// Unlock-code delivery for the KAI Shopify store — Google Apps Script.
//
// Every 5 minutes poll() asks the Shopify Admin API for paid orders that
// have not been handled, re-reads each one, and for every study set in it:
//   1. takes the next unused code from the private pool sheet,
//   2. records (order, set no., code) in the ledger sheet and flushes,
//   3. writes the code(s) onto the order (metafield custom.unlock_code),
//      which the packing slip prints and staff see on the order page,
//   4. emails the buyer,
//   5. tags the order `code-issued`, which removes it from the next query.
// Each step is recorded; a run that fails part-way is finished by the next
// run with the SAME code. Only the ledger decides "already issued".
//
// Pull, not push: the system has no inbound URL in normal operation. The
// one-time doGet() below exists only for the OAuth install and is archived
// afterwards. See ../README.md for setup and operations.
//
// Everything that sends mail runs as the robot account (ROBOT_EMAIL): mail
// goes out from whoever runs the function.

var API_VERSION = '2026-07';
var MF_NAMESPACE = 'custom';
var MF_KEY = 'unlock_code';
var TAG_ISSUED = 'code-issued';
var TAG_SKIP = 'code-skip';
var TAG_FLAGGED = 'code-flagged'; // needs a person; remove the tag to re-process
var MAX_RUN_MS = 4 * 60 * 1000; // an execution is capped at 6 minutes
var MAX_FAILURES_IN_A_ROW = 3; // then the cause is probably not the order
var LEDGER_ROWS = 10000; // pre-sized so the resend column stays editable

// Pool sheet 'pool': code | batch_id | imported_at | status | used_at | order_name
var P = { CODE: 0, BATCH: 1, IMPORTED: 2, STATUS: 3, USED_AT: 4, ORDER: 5 };
var POOL_HEADERS = ['code', 'batch_id', 'imported_at', 'status', 'used_at', 'order_name'];
// Ledger sheet 'ledger'
var L = { GID: 0, NAME: 1, SET: 2, CODE: 3, ISSUED: 4, MF: 5, TAG: 6, EMAIL_TO: 7, EMAIL_AT: 8, RESEND: 9, NOTE: 10 };
var LEDGER_HEADERS = ['order_gid', 'order_name', 'set_no', 'code', 'issued_at', 'metafield',
  'tag', 'email_to', 'email_sent_at', 'resend', 'note'];
var FLAG_HEADERS = ['order_gid', 'order_name', 'reason', 'first_seen', 'last_seen'];

// ── entry points ─────────────────────────────────────────────────────────

/** Scheduled every 5 minutes by installTriggers(). */
function poll() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('PAUSED') === 'true') return;
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return; // the previous run is still working
  var started = Date.now();
  var errors = [];
  try {
    assertRobot_();
    var cfg = config_();
    var ctx = openContext_(cfg);
    processResends_(cfg, ctx, errors);
    if (errors.length) ctx = openContext_(cfg);
    var nodes = gql_(cfg,
      'query($q:String!){orders(first:50,sortKey:CREATED_AT,query:$q){nodes{id name}}}',
      { q: buildOrdersQuery(cfg.launchDate, cfg.live) }).orders.nodes;
    props.setProperty('LAST_POLL_OK', new Date().toISOString());
    var failures = 0;
    for (var i = 0; i < nodes.length; i++) {
      if (Date.now() - started > MAX_RUN_MS) break; // the next run continues
      try {
        processOrder_(cfg, ctx, nodes[i].id);
        failures = 0;
      } catch (e) {
        errors.push(nodes[i].name + ': ' + errText_(e));
        if (e.stopRun || ++failures >= MAX_FAILURES_IN_A_ROW) break;
        ctx = openContext_(cfg); // the cached rows may no longer match the sheets
      }
    }
  } catch (e) {
    errors.push(errText_(e));
  } finally {
    lock.releaseLock();
  }
  if (errors.length) {
    props.setProperty('LAST_POLL_ERROR', new Date().toISOString() + ' ' + errors.join(' | ').slice(0, 1500));
    // Rethrow so Apps Script's own failure email reaches the robot account.
    throw new Error('poll finished with errors:\n' + errors.join('\n'));
  }
}

/**
 * Scheduled daily. A report to KAI, so nothing fails silently: every part
 * that cannot be checked says so in the report instead of stopping it.
 */
function dailySummary() {
  assertRobot_();
  var props = PropertiesService.getScriptProperties();
  var cfg = config_();
  var now = Date.now();
  var problems = [];
  var ctx = null;
  try { ctx = openContext_(cfg); } catch (e) { problems.push('管理表を開けません：' + errText_(e)); }
  var ask = function (label, q) {
    try {
      return gql_(cfg, 'query($q:String!){orders(first:50,sortKey:CREATED_AT,query:$q){nodes{name createdAt}}}',
        { q: q }).orders.nodes;
    } catch (e) {
      problems.push(label + '：Shopifyに接続できません（' + errText_(e) + '）');
      return [];
    }
  };
  var launch = ' created_at:>=' + cfg.launchDate;
  var stalePaid = ask('未発行の注文の確認',
    buildOrdersQuery(cfg.launchDate, cfg.live) + ' created_at:<=' + searchTime(now - 30 * 60000));
  var expired = ask('期限切れの注文の確認',
    'financial_status:expired created_at:>=' + searchTime(now - 14 * 86400000) + launch);
  var skipped = ask('対象外の注文の確認',
    'tag:' + TAG_SKIP + ' updated_at:>=' + searchTime(now - 86400000) + launch);

  var paused = props.getProperty('PAUSED') === 'true';
  var lastOk = props.getProperty('LAST_POLL_OK');
  var lastErr = props.getProperty('LAST_POLL_ERROR') || '';
  var lines = [];
  lines.push('快単パーフェクト アンロックコード自動送付 — 日次レポート（' + fmt_(new Date(now)) + '）');
  lines.push('');
  if (paused) lines.push('★現在、自動送付を一時停止しています。再開するまでコードは送られません。');
  if (!cfg.live) lines.push('※試験運用中です（code-dryrun タグの注文のみ処理しています）。');
  problems.forEach(function (p) { lines.push('★' + p); });
  if (!paused) {
    if (!lastOk) {
      lines.push('★自動送付がまだ一度も正常に動いていません。');
    } else if (now - Date.parse(lastOk) > 30 * 60000) {
      lines.push('★自動送付が ' + fmt_(new Date(lastOk)) + ' から止まっています。至急ご確認ください。');
    }
  }
  var errAt = Date.parse(lastErr.split(' ')[0]);
  if (lastErr && now - errAt < 86400000) {
    lines.push('直近のエラー（' + fmt_(new Date(errAt)) + '）：' + lastErr.slice(lastErr.indexOf(' ') + 1, 400));
  }
  if (lines[lines.length - 1] !== '') lines.push('');

  if (ctx) {
    var dayAgo = now - 86400000;
    var issued = ctx.ledger.rows.filter(function (r) { return r[L.ISSUED] && new Date(r[L.ISSUED]).getTime() >= dayAgo; });
    var available = ctx.pool.availableCount();
    lines.push('過去24時間に発行したコード：' + issued.length + ' 件');
    lines.push('在庫（未使用のコード）：' + available + ' 件' +
      (available < cfg.lowPool ? '　★残りわずかです。補充をご依頼ください。' : ''));
    if (ctx.ledger.rows.length > LEDGER_ROWS - 1000) {
      lines.push('★発行台帳の行が残り少なくなっています。setupSheets() を実行してください。');
    }
    lines.push('');
    var flags = ctx.flags.rows;
    lines.push('要確認の注文：' + flags.length + ' 件');
    flags.forEach(function (f) {
      var old = f[3] && now - new Date(f[3]).getTime() > 45 * 86400000;
      lines.push('　' + f[1] + '：' + f[2] + (old ? '　★60日を過ぎると自動では処理できなくなります' : ''));
    });
    var halfway = {};
    ctx.ledger.rows.forEach(function (r) {
      if (r[L.TAG] !== 'ok' && r[L.ISSUED] && now - new Date(r[L.ISSUED]).getTime() > 3600000) halfway[r[L.NAME]] = true;
    });
    var halfwayNames = Object.keys(halfway);
    lines.push('');
    lines.push('発行の途中で止まっている注文：' + halfwayNames.length + ' 件');
    halfwayNames.forEach(function (n) { lines.push('　' + n); });
  }
  lines.push('');
  lines.push('お支払い済みで、30分以上コードが未発行の注文：' + stalePaid.length + ' 件');
  stalePaid.forEach(function (o) { lines.push('　' + o.name); });
  lines.push('');
  lines.push('お支払い期限が切れた注文（過去14日）：' + expired.length + ' 件');
  if (expired.length) lines.push('　コンビニで期限後に入金されていないか、KOMOJUの管理画面でご確認ください。');
  expired.forEach(function (o) { lines.push('　' + o.name); });
  lines.push('');
  lines.push('コード対象外とした注文（過去24時間）：' + skipped.length + ' 件');
  if (skipped.length) lines.push('　セット商品の注文が含まれていないかご確認ください。');
  skipped.forEach(function (o) { lines.push('　' + o.name); });
  sendMail_(cfg, cfg.summaryTo, '【快単】コード自動送付 日次レポート', lines.join('\n'));
}

// ── one order ────────────────────────────────────────────────────────────

var ORDER_QUERY =
  'query($id:ID!){order(id:$id){id name email displayFinancialStatus cancelledAt test createdAt ' +
  'risk{recommendation assessments{riskLevel}} ' +
  'lineItems(first:50){nodes{currentQuantity variant{id}}} ' +
  'metafield(namespace:"' + MF_NAMESPACE + '",key:"' + MF_KEY + '"){value}}}';

function processOrder_(cfg, ctx, gid) {
  var order = gql_(cfg, ORDER_QUERY, { id: gid }).order;
  var d = decideOrder(order, { setVariantIds: cfg.setVariantIds, live: cfg.live, now: Date.now() });
  if (d.action === 'wait') return;
  if (d.action === 'skip') { tagsAdd_(cfg, gid, [TAG_SKIP]); return; }
  if (d.action === 'flag') {
    ctx.flags.raise(gid, order && order.name, d.reason);
    if (order) tagsAdd_(cfg, gid, [TAG_FLAGGED]);
    return;
  }

  // A code typed onto the order by hand: never draw a second one for it.
  if (order.metafield && order.metafield.value && !ctx.ledger.find(ledgerKey(gid, 1))) {
    ctx.flags.raise(gid, order.name, '注文のコード欄に、台帳にないコードが入っています（手動で確認してください）');
    tagsAdd_(cfg, gid, [TAG_FLAGGED]);
    return;
  }

  // 1-2. Reserve one code per set in the ledger, before touching Shopify.
  var rows = [];
  for (var n = 1; n <= d.sets; n++) {
    var row = ctx.ledger.find(ledgerKey(gid, n));
    if (!row) {
      var code = ctx.pool.take(order.name);
      while (code && ctx.ledger.hasCode(code)) {
        // Marked available in the pool but already issued: never reuse it.
        ctx.flags.raise(gid, order.name, 'コード在庫に発行済みのコードが残っていました（在庫表を確認してください）');
        code = ctx.pool.take(order.name);
      }
      if (!code) {
        ctx.flags.raise(gid, order.name, REASON_POOL_EMPTY);
        SpreadsheetApp.flush();
        throw stopRun_('pool empty'); // every later order would fail the same way
      }
      row = ctx.ledger.append(gid, order.name, n, code);
      SpreadsheetApp.flush();
    }
    rows.push(row);
  }
  var codes = rows.map(function (r) { return r.values[L.CODE]; });
  var value = joinCodes(codes);

  // 3. The order metafield (packing slip + order page). Compare-and-set.
  if (!rows.every(function (r) { return r.values[L.MF] === 'ok'; })) {
    var outcome = writeCodeMetafield_(cfg, gid, value);
    if (outcome === 'conflict') {
      ctx.flags.raise(gid, order.name, '注文のコード欄に別のコードが入っています（手動で確認してください）');
      tagsAdd_(cfg, gid, [TAG_FLAGGED]);
      return;
    }
    if (outcome !== 'ok') throw new Error('metafield write failed');
    rows.forEach(function (r) { ctx.ledger.set(r, L.MF, 'ok'); });
    SpreadsheetApp.flush();
  }

  // 4. The email.
  if (!rows.every(function (r) { return !!r.values[L.EMAIL_AT]; })) {
    if (!order.email) {
      ctx.flags.raise(gid, order.name,
        'メールアドレスがありません。コードは納品書に印刷されます。メールでも送る場合は、' +
        'Shopifyで注文のメールアドレスを入力し、発行台帳の resend 欄に✓を入れてください');
      rows.forEach(function (r) { ctx.ledger.set(r, L.NOTE, 'no email'); });
    } else {
      if (!mailQuotaLeft_(cfg)) throw stopRun_('mail quota exhausted; will retry');
      var mail = buildCodeEmail(order.name, codes);
      sendMail_(cfg, order.email, mail.subject, mail.body);
      var at = new Date();
      rows.forEach(function (r) {
        ctx.ledger.set(r, L.EMAIL_TO, order.email);
        ctx.ledger.set(r, L.EMAIL_AT, at);
      });
    }
    SpreadsheetApp.flush();
  }

  // 5. Tag last: it takes the order out of the next query.
  tagsAdd_(cfg, gid, [TAG_ISSUED]);
  rows.forEach(function (r) { ctx.ledger.set(r, L.TAG, 'ok'); });
  ctx.flags.clear(gid, REASON_POOL_EMPTY);
  SpreadsheetApp.flush();
}

/**
 * Staff tick `resend` in the ledger; the robot's trigger sends the SAME
 * code(s) again. Orders older than 60 days cannot be read from Shopify, so
 * the address the codes first went to is used instead.
 */
function processResends_(cfg, ctx, errors) {
  var byOrder = {};
  ctx.ledger.rows.forEach(function (values, i) {
    if (values[L.RESEND] === true) {
      var gid = values[L.GID];
      (byOrder[gid] = byOrder[gid] || []).push(ctx.ledger.row(i));
    }
  });
  var gids = Object.keys(byOrder);
  for (var k = 0; k < gids.length; k++) {
    var gid = gids[k];
    var rows = byOrder[gid].sort(function (a, b) { return a.values[L.SET] - b.values[L.SET]; });
    var name = rows[0].values[L.NAME];
    try {
      if (!rows.every(function (r) { return r.values[L.MF] === 'ok'; })) {
        ctx.flags.raise(gid, name, '発行が完了していないため再送できません（自動で処理が続きます）');
        rows.forEach(function (r) { ctx.ledger.set(r, L.RESEND, false); });
        continue;
      }
      var order = gql_(cfg, 'query($id:ID!){order(id:$id){name email}}', { id: gid }).order;
      var to = order ? order.email : rows[0].values[L.EMAIL_TO];
      if (!to) {
        ctx.flags.raise(gid, name, order
          ? '再送できません：注文にメールアドレスがありません'
          : '再送できません：60日より前の注文でメールアドレスの記録もありません。台帳のコードを手動でお送りください');
        rows.forEach(function (r) { ctx.ledger.set(r, L.RESEND, false); });
        continue;
      }
      if (!mailQuotaLeft_(cfg)) { errors.push('resend: mail quota exhausted; will retry'); break; }
      var mail = buildCodeEmail(order ? order.name : name, rows.map(function (r) { return r.values[L.CODE]; }));
      sendMail_(cfg, String(to), mail.subject, mail.body);
      var at = new Date();
      rows.forEach(function (r) {
        ctx.ledger.set(r, L.EMAIL_TO, String(to));
        ctx.ledger.set(r, L.EMAIL_AT, at);
        ctx.ledger.set(r, L.RESEND, false);
        ctx.ledger.set(r, L.NOTE, 'resent ' + fmt_(at));
      });
    } catch (e) {
      errors.push('resend ' + name + ': ' + errText_(e));
    }
    SpreadsheetApp.flush();
  }
}

// ── Shopify ──────────────────────────────────────────────────────────────

function gql_(cfg, query, variables) {
  var res = UrlFetchApp.fetch('https://' + cfg.shop + '/admin/api/' + API_VERSION + '/graphql.json', {
    method: 'post',
    contentType: 'application/json',
    headers: { 'X-Shopify-Access-Token': token_(cfg) },
    payload: JSON.stringify({ query: query, variables: variables || {} }),
    muteHttpExceptions: true,
  });
  var status = res.getResponseCode();
  var text = res.getContentText();
  if (status !== 200) throw new Error('Shopify API HTTP ' + status + ': ' + text.slice(0, 300));
  var json = JSON.parse(text);
  if (json.errors) throw new Error('Shopify API: ' + JSON.stringify(json.errors).slice(0, 500));
  return json.data;
}

/** Returns 'ok' | 'conflict' | 'error' (see metafieldOutcome in Core.js). */
function writeCodeMetafield_(cfg, gid, value) {
  var errs = setMetafield_(cfg, gid, value, null);
  if (!errs.length) return 'ok';
  var o = gql_(cfg, 'query($id:ID!){order(id:$id){metafield(namespace:"' + MF_NAMESPACE +
    '",key:"' + MF_KEY + '"){value compareDigest}}}', { id: gid }).order;
  var mf = o && o.metafield;
  var outcome = metafieldOutcome(errs, mf ? mf.value : null, value);
  if (outcome !== 'extend') return outcome;
  // The order carries only codes we issued to it: a set was added later.
  return setMetafield_(cfg, gid, value, mf.compareDigest).length ? 'error' : 'ok';
}

/** compareDigest null: write only if the order has no value yet. */
function setMetafield_(cfg, gid, value, compareDigest) {
  var data = gql_(cfg,
    'mutation($m:[MetafieldsSetInput!]!){metafieldsSet(metafields:$m){' +
    'metafields{id} userErrors{field message code}}}',
    { m: [{ ownerId: gid, namespace: MF_NAMESPACE, key: MF_KEY,
      type: 'single_line_text_field', value: value, compareDigest: compareDigest }] });
  return data.metafieldsSet.userErrors || [];
}

function tagsAdd_(cfg, gid, tags) {
  var data = gql_(cfg,
    'mutation($id:ID!,$t:[String!]!){tagsAdd(id:$id,tags:$t){userErrors{field message}}}',
    { id: gid, t: tags });
  var errs = data.tagsAdd.userErrors;
  if (errs && errs.length) throw new Error('tagsAdd: ' + JSON.stringify(errs));
}

function token_(cfg) {
  var props = PropertiesService.getScriptProperties();
  var t = props.getProperty('SHOPIFY_TOKEN');
  if (t) return t;
  // Fallback route: a client-credentials app in KAI's own organization.
  // Tokens last 24 h; keep one with its expiry in Script Properties.
  if (props.getProperty('TOKEN_MODE') !== 'client_credentials') {
    throw new Error('No Shopify token. Run beginOAuth() and complete the install.');
  }
  var cached = props.getProperty('CC_TOKEN');
  var exp = Number(props.getProperty('CC_TOKEN_EXPIRES') || 0);
  if (cached && Date.now() < exp - 60 * 1000) return cached;
  var res = UrlFetchApp.fetch('https://' + cfg.shop + '/admin/oauth/access_token', {
    method: 'post',
    payload: { grant_type: 'client_credentials',
      client_id: props.getProperty('CLIENT_ID'), client_secret: props.getProperty('CLIENT_SECRET') },
    muteHttpExceptions: true,
  });
  var j = JSON.parse(res.getContentText());
  if (!j.access_token) throw new Error('client credentials failed: ' + res.getContentText().slice(0, 200));
  props.setProperty('CC_TOKEN', j.access_token);
  props.setProperty('CC_TOKEN_EXPIRES', String(Date.now() + Number(j.expires_in || 86399) * 1000));
  return j.access_token;
}

// ── one-time install (authorization code grant) ──────────────────────────

/**
 * Run from the editor after deploying this project as a web app and setting
 * SHOP_DOMAIN, CLIENT_ID, CLIENT_SECRET and REDIRECT_URI. REDIRECT_URI is the
 * /exec URL copied from the deployment, exactly as registered in the Dev
 * Dashboard (ScriptApp.getService().getUrl() does not return it reliably
 * from the editor). Logs the install URL to open.
 */
function beginOAuth() {
  var props = PropertiesService.getScriptProperties();
  var shop = props.getProperty('SHOP_DOMAIN');
  if (!isShopDomain(shop)) throw new Error('SHOP_DOMAIN must be xxx.myshopify.com');
  var redirect = props.getProperty('REDIRECT_URI') || '';
  if (!/^https:\/\/script\.google\.com\/macros\/s\/[^\/]+\/exec$/.test(redirect)) {
    throw new Error('REDIRECT_URI must be the web app /exec URL from Deploy > Manage deployments');
  }
  var state = Utilities.getUuid();
  props.setProperty('OAUTH_STATE', state);
  var url = 'https://' + shop + '/admin/oauth/authorize?client_id=' +
    encodeURIComponent(props.getProperty('CLIENT_ID')) +
    '&scope=read_orders,write_orders&redirect_uri=' + encodeURIComponent(redirect) +
    '&state=' + state;
  Logger.log(url);
  return url;
}

/** The OAuth redirect target. Archive the web-app deployment once connected. */
function doGet(e) {
  var p = (e && e.parameter) || {};
  var props = PropertiesService.getScriptProperties();
  var page = function (msg) { return HtmlService.createHtmlOutput('<p>' + msg + '</p>'); };
  if (!isShopDomain(p.shop) || p.shop !== props.getProperty('SHOP_DOMAIN')) return page('Nothing to do.');
  var secret = props.getProperty('CLIENT_SECRET');
  if (!verifyShopifyHmac(p, secret, hmacHex_)) return page('Signature mismatch.');
  if (!p.code) {
    // Opened from the custom-distribution install link (the app URL): start the grant.
    return HtmlService.createHtmlOutput('<p><a href="' + beginOAuth() + '" target="_top">' +
      'Continue: authorise KAI Unlock Codes</a></p>');
  }
  var state = props.getProperty('OAUTH_STATE');
  if (!state || p.state !== state) return page('State mismatch. Run beginOAuth() again.');
  var res = UrlFetchApp.fetch('https://' + p.shop + '/admin/oauth/access_token', {
    method: 'post',
    payload: { client_id: props.getProperty('CLIENT_ID'), client_secret: secret, code: p.code },
    muteHttpExceptions: true,
  });
  var j = JSON.parse(res.getContentText() || '{}');
  if (!j.access_token) return page('Token exchange failed.');
  props.setProperty('SHOPIFY_TOKEN', j.access_token);
  props.deleteProperty('OAUTH_STATE');
  props.deleteProperty('CLIENT_SECRET'); // not needed again; do not leave it here
  return page('Connected. Now archive this web-app deployment.');
}

function hmacHex_(message, secret) {
  var bytes = Utilities.computeHmacSha256Signature(message, secret);
  return bytes.map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); }).join('');
}

/**
 * Go/no-go gate before launch: can this app read the buyer's email on the
 * store's plan? Official docs disagree for Basic. Also logs the variant id
 * of each line, for SET_VARIANT_IDS. Needs only SHOP_DOMAIN and the token.
 */
function goNoGoCheck() {
  var cfg = shopConfig_();
  var o = gql_(cfg, '{orders(first:1,sortKey:CREATED_AT,reverse:true){nodes{name email displayFinancialStatus ' +
    'lineItems(first:10){nodes{name variant{id}}}}}}', {}).orders.nodes[0];
  if (!o) { Logger.log('No orders yet: place a test order first.'); return; }
  Logger.log(o.name + ' status=' + o.displayFinancialStatus + ' email=' +
    (o.email ? 'READABLE (go)' : 'NOT READABLE (use the fallback in README)'));
  o.lineItems.nodes.forEach(function (li) {
    Logger.log('  ' + li.name + '  variant=' + (li.variant ? li.variant.id : '(deleted)'));
  });
}

// ── Google side ──────────────────────────────────────────────────────────

function sendMail_(cfg, to, subject, body) {
  if (cfg.mailProvider === 'resend') {
    // ¥0 alternative that sends as info@kai.or.jp once kai.or.jp's DNS
    // carries the provider's records. Free tier: 100/day, 3,000/month.
    var res = UrlFetchApp.fetch('https://api.resend.com/emails', {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + PropertiesService.getScriptProperties().getProperty('RESEND_API_KEY') },
      payload: JSON.stringify({ from: cfg.mailFrom, to: [to], subject: subject, text: body, reply_to: cfg.replyTo }),
      muteHttpExceptions: true,
    });
    if (res.getResponseCode() >= 300) throw new Error('mail provider: ' + res.getContentText().slice(0, 200));
    return;
  }
  MailApp.sendEmail({ to: to, subject: subject, body: body, name: cfg.senderName, replyTo: cfg.replyTo });
}

/** Keeps one recipient of the daily quota for the daily report. */
function mailQuotaLeft_(cfg) {
  if (cfg.mailProvider === 'resend') return true; // the provider enforces its own limit
  return MailApp.getRemainingDailyQuota() > 1;
}

/** Mail goes out from whoever runs the code: only the robot may. */
function assertRobot_() {
  var robot = String(PropertiesService.getScriptProperties().getProperty('ROBOT_EMAIL') || '').toLowerCase();
  var me = String(Session.getEffectiveUser().getEmail() || '').toLowerCase();
  if (!robot || me !== robot) {
    throw new Error('Run this as the robot account (Script Property ROBOT_EMAIL). Current account: ' + (me || 'unknown'));
  }
}

function shopConfig_() {
  var shop = PropertiesService.getScriptProperties().getProperty('SHOP_DOMAIN');
  if (!isShopDomain(shop)) throw new Error('Script property SHOP_DOMAIN must be xxx.myshopify.com');
  return { shop: shop };
}

function config_() {
  var p = PropertiesService.getScriptProperties();
  var cfg = shopConfig_();
  var raw = (p.getProperty('SET_VARIANT_IDS') || '').split(',')
    .map(function (s) { return s.trim(); }).filter(String);
  var variants = raw.map(normalizeVariantId);
  if (!variants.length || variants.some(function (v) { return !v; })) {
    throw new Error('Script property SET_VARIANT_IDS must list variant ids (gid://shopify/ProductVariant/… or the number), comma-separated');
  }
  var launchDate = p.getProperty('LAUNCH_DATE') || '';
  if (!/^\d{4}-\d{2}-\d{2}$/.test(launchDate)) {
    // Without it the search would reach back over every earlier paid order.
    throw new Error('Script property LAUNCH_DATE must be set (YYYY-MM-DD) before anything runs');
  }
  var ids = sheetIds_();
  cfg.setVariantIds = variants;
  cfg.launchDate = launchDate;
  cfg.live = p.getProperty('LIVE') === 'true';
  cfg.poolSheetId = ids.pool;
  cfg.ledgerSheetId = ids.ledger;
  cfg.summaryTo = p.getProperty('SUMMARY_TO') || 'info@kai.or.jp';
  cfg.lowPool = Number(p.getProperty('LOW_POOL') || 30);
  cfg.mailProvider = p.getProperty('MAIL_PROVIDER') || 'mailapp';
  cfg.mailFrom = p.getProperty('MAIL_FROM') || '一般社団法人ＫＡＩ <info@kai.or.jp>';
  cfg.senderName = '一般社団法人ＫＡＩ';
  cfg.replyTo = 'info@kai.or.jp';
  return cfg;
}

function sheetIds_() {
  var p = PropertiesService.getScriptProperties();
  var ids = { pool: p.getProperty('POOL_SHEET_ID'), ledger: p.getProperty('LEDGER_SHEET_ID') };
  if (!ids.pool || !ids.ledger) throw new Error('Set POOL_SHEET_ID and LEDGER_SHEET_ID');
  return ids;
}

function openContext_(cfg) {
  var poolSheet = SpreadsheetApp.openById(cfg.poolSheetId).getSheetByName('pool');
  var ledgerBook = SpreadsheetApp.openById(cfg.ledgerSheetId);
  return {
    pool: poolTable_(poolSheet),
    ledger: ledgerTable_(ledgerBook.getSheetByName('ledger')),
    flags: flagTable_(ledgerBook.getSheetByName('flags')),
  };
}

// The tables below cache the sheet at the start of a run. Every write first
// checks that the row still holds what the cache says, so a sheet sorted or
// edited during a run makes the run stop and retry instead of writing to the
// wrong row.

function poolTable_(sheet) {
  var values = sheet.getDataRange().getValues();
  var next = 1; // row 0 is the header
  return {
    availableCount: function () {
      return values.slice(1).filter(function (r) { return r[P.STATUS] === 'available'; }).length;
    },
    /** Marks the next available code used and returns it, or null. */
    take: function (orderName) {
      for (; next < values.length; next++) {
        if (values[next][P.STATUS] !== 'available') continue;
        var code = String(values[next][P.CODE]);
        var live = sheet.getRange(next + 1, 1, 1, P.STATUS + 1).getValues()[0];
        if (String(live[P.CODE]) !== code || live[P.STATUS] !== 'available') {
          throw new Error('pool sheet changed during the run; will retry');
        }
        var now = new Date();
        values[next][P.STATUS] = 'used';
        values[next][P.USED_AT] = now;
        values[next][P.ORDER] = orderName;
        sheet.getRange(next + 1, P.STATUS + 1, 1, 3).setValues([['used', now, orderName]]);
        next++;
        return code;
      }
      return null;
    },
  };
}

function ledgerTable_(sheet) {
  var rows = sheet.getDataRange().getValues().slice(1);
  var sheetRows = rows.map(function (v, i) { return i + 2; });
  var index = {};
  var codes = {};
  rows.forEach(function (v, i) {
    index[ledgerKey(v[L.GID], v[L.SET])] = i;
    codes[String(v[L.CODE])] = true;
  });
  var row = function (i) { return { index: i, sheetRow: sheetRows[i], values: rows[i] }; };
  return {
    rows: rows,
    row: row,
    find: function (key) {
      var i = index[key];
      return i === undefined ? null : row(i);
    },
    hasCode: function (code) { return !!codes[String(code)]; },
    append: function (gid, name, setNo, code) {
      var v = [gid, name, setNo, code, new Date(), '', '', '', '', false, ''];
      sheet.appendRow(v);
      // Record the row before any other call can fail.
      rows.push(v);
      sheetRows.push(sheet.getLastRow());
      index[ledgerKey(gid, setNo)] = rows.length - 1;
      codes[String(code)] = true;
      var r = row(rows.length - 1);
      sheet.getRange(r.sheetRow, L.RESEND + 1).insertCheckboxes();
      return r;
    },
    set: function (r, col, value) {
      var code = sheet.getRange(r.sheetRow, L.CODE + 1).getValue();
      if (String(code) !== String(r.values[L.CODE])) {
        throw new Error('ledger sheet changed during the run (row ' + r.sheetRow + '); will retry');
      }
      r.values[col] = value;
      sheet.getRange(r.sheetRow, col + 1).setValue(value);
    },
  };
}

function flagTable_(sheet) {
  var rows = sheet.getDataRange().getValues().slice(1);
  return {
    rows: rows,
    raise: function (gid, name, reason) {
      var now = new Date();
      for (var i = 0; i < rows.length; i++) {
        if (rows[i][0] === gid && rows[i][2] === reason) {
          sheet.getRange(i + 2, 5).setValue(now);
          return;
        }
      }
      var v = [gid, name || '', reason, now, now];
      sheet.appendRow(v);
      rows.push(v);
    },
    /** Removes this order's rows with this reason (checked against the sheet first). */
    clear: function (gid, reason) {
      for (var i = rows.length - 1; i >= 0; i--) {
        if (rows[i][0] !== gid || rows[i][2] !== reason) continue;
        var live = sheet.getRange(i + 2, 1, 1, 3).getValues()[0];
        if (live[0] === gid && live[2] === reason) sheet.deleteRow(i + 2);
        rows.splice(i, 1);
      }
    },
  };
}

function stopRun_(message) {
  var e = new Error(message);
  e.stopRun = true;
  return e;
}

function errText_(e) {
  return e && e.message ? e.message : String(e);
}

function fmt_(d) {
  return Utilities.formatDate(d, 'Asia/Tokyo', 'yyyy-MM-dd HH:mm');
}

// ── setup and operations (run from the editor as the robot account) ──────

/** Creates the sheets and protects the ledger. Safe to run more than once. */
function setupSheets() {
  assertRobot_();
  var ids = sheetIds_();
  var pool = SpreadsheetApp.openById(ids.pool);
  var ledger = SpreadsheetApp.openById(ids.ledger);
  ensureSheet_(pool, 'pool', POOL_HEADERS);
  ensureSheet_(pool, 'import', ['paste or import the generator CSV here (column A = code)']);
  ensureSheet_(pool, 'exclude', ['codes already handed out by hand (never issue); any column']);
  var sh = ensureSheet_(ledger, 'ledger', LEDGER_HEADERS);
  ensureSheet_(ledger, 'flags', FLAG_HEADERS);
  if (sh.getMaxRows() < LEDGER_ROWS) sh.insertRowsAfter(sh.getMaxRows(), LEDGER_ROWS - sh.getMaxRows());
  // Staff may tick `resend` and nothing else; the robot (owner) edits freely.
  var pr = sh.getProtections(SpreadsheetApp.ProtectionType.SHEET)[0] || sh.protect();
  pr.setDescription('発行台帳：resend 欄以外は編集・並べ替えをしないでください');
  pr.setUnprotectedRanges([sh.getRange(2, L.RESEND + 1, sh.getMaxRows() - 1, 1)]);
  pr.addEditor(Session.getEffectiveUser());
  pr.removeEditors(pr.getEditors());
  if (pr.canDomainEdit()) pr.setDomainEdit(false);
}

function ensureSheet_(book, name, headers) {
  var sh = book.getSheetByName(name) || book.insertSheet(name);
  if (sh.getLastRow() === 0) sh.appendRow(headers);
  sh.setFrozenRows(1);
  return sh;
}

/**
 * Moves pasted codes from 'import' into the pool after validation. Codes in
 * 'exclude' (handed out before launch), codes already known, standalone-series
 * codes and codes signed with an old key are refused.
 */
function importCodes() {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var ids = sheetIds_();
    var book = SpreadsheetApp.openById(ids.pool);
    var pool = book.getSheetByName('pool');
    var imp = book.getSheetByName('import');
    var exc = book.getSheetByName('exclude');
    var known = pool.getDataRange().getValues().slice(1).map(function (r) { return r[P.CODE]; })
      .concat(SpreadsheetApp.openById(ids.ledger).getSheetByName('ledger')
        .getDataRange().getValues().slice(1).map(function (r) { return r[L.CODE]; }));
    // Any cell may hold a handed-out code: KAI's member list keeps it in column B.
    var excluded = [];
    exc.getDataRange().getValues().slice(1).forEach(function (r) {
      r.forEach(function (cell) { if (isValidCode(cell)) excluded.push(cell); });
    });
    var rows = imp.getDataRange().getValues().slice(1);
    var result = parseCodeRows(rows, known, excluded);
    var batch = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyyMMdd-HHmm');
    var now = new Date();
    if (result.accepted.length) {
      pool.getRange(pool.getLastRow() + 1, 1, result.accepted.length, POOL_HEADERS.length)
        .setValues(result.accepted.map(function (c) { return [c, batch, now, 'available', '', '']; }));
    }
    if (imp.getLastRow() > 1) imp.getRange(2, 1, imp.getLastRow() - 1, imp.getLastColumn()).clearContent();
    Logger.log('imported ' + result.accepted.length + ' codes (batch ' + batch + ')');
    // r.row counts from the first pasted row; +1 for the sheet's header row.
    result.rejected.forEach(function (r) { Logger.log('rejected row ' + (r.row + 1) + ' ' + r.value + ': ' + r.reason); });
    return result;
  } finally {
    lock.releaseLock();
  }
}

/** Creates the 5-minute poll and the daily report, as the robot account. */
function installTriggers() {
  assertRobot_();
  config_(); // refuse to start with an incomplete configuration
  ScriptApp.getProjectTriggers().forEach(function (t) {
    var f = t.getHandlerFunction();
    if (f === 'poll' || f === 'dailySummary') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('poll').timeBased().everyMinutes(5).create();
  ScriptApp.newTrigger('dailySummary').timeBased().everyDays(1).atHour(9).inTimezone('Asia/Tokyo').create();
  PropertiesService.getScriptProperties().deleteProperty('PAUSED');
}

/**
 * Stops issuing at once, whoever runs it: triggers belong to the account
 * that made them, but this property is shared. The daily report continues
 * and says that issuing is paused.
 */
function pause() {
  PropertiesService.getScriptProperties().setProperty('PAUSED', 'true');
  Logger.log('Paused. Run resume() to continue.');
}

function resume() {
  PropertiesService.getScriptProperties().deleteProperty('PAUSED');
  Logger.log('Resumed. Orders paid meanwhile are handled on the next run.');
}

/** Removes this account's triggers (decommissioning). To stop issuing, use pause(). */
function removeTriggers() {
  var n = 0;
  ScriptApp.getProjectTriggers().forEach(function (t) { ScriptApp.deleteTrigger(t); n++; });
  Logger.log(n + ' trigger(s) removed for ' + Session.getEffectiveUser().getEmail() +
    (n ? '' : ' — none belong to this account; triggers run as the account that made them'));
}
