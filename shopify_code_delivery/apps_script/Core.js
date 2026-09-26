// Pure decision logic for unlock-code delivery. No Google or Shopify calls
// here, so every rule can be unit-tested with Node (test/core.test.js).
//
// The rules this file encodes, all of which exist because a code, once
// issued, can never be revoked:
//   * a code goes only to an order Shopify reports as PAID (fully captured);
//   * never to a cancelled order, never to a test order in live mode, never
//     to an order Shopify's fraud analysis says to cancel;
//   * one code per study set, keyed (order, set number), so a repeat run can
//     only finish missing steps, never draw a second code;
//   * a code is accepted into the pool only if it is well-formed, unseen, from
//     the set series and signed with the current key;
//   * a paid order that cannot be handled is flagged for a person, never
//     dropped without a trace.

/** Base32 alphabet used by tool/generate_codes.py (RFC 4648, no padding). */
var CODE_RE = /^[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$/;
var B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
/** Must equal STANDALONE_FIRST_ID in tool/generate_codes.py. */
var STANDALONE_FIRST_ID = 1000000;
/** The key version the shipping app verifies. */
var KEY_VERSION = 2;
/** How long to wait for Shopify's fraud analysis before issuing anyway. */
var RISK_PENDING_MAX_MIN = 30;

var REASON_POOL_EMPTY = 'コードの在庫がありません（補充が必要です）';

/** Upper-case, trim, and turn common separators into the canonical dash form. */
function normalizeCode(raw) {
  if (raw === null || raw === undefined) return '';
  var s = String(raw).toUpperCase().replace(/[\s　]/g, '').replace(/[‐‑‒–—―ー－]/g, '-');
  if (/^[A-Z2-7]{16}$/.test(s)) {
    s = s.slice(0, 4) + '-' + s.slice(4, 8) + '-' + s.slice(8, 12) + '-' + s.slice(12);
  }
  return s;
}

function isValidCode(raw) {
  return CODE_RE.test(normalizeCode(raw));
}

/**
 * The plain-text part of a code: generate_codes.py packs
 * purchase_id (4 bytes, big-endian) + key_version (1 byte) + a 5-byte MAC.
 * Returns { purchaseId, keyVersion }. The MAC is not checked here (the key
 * never leaves the contractor's machine); the app checks it.
 */
function decodeCode(code) {
  var chars = normalizeCode(code).replace(/-/g, '');
  var bits = '';
  for (var i = 0; i < chars.length; i++) {
    var v = B32.indexOf(chars.charAt(i));
    bits += ('0000' + v.toString(2)).slice(-5);
  }
  return {
    purchaseId: parseInt(bits.slice(0, 32), 2),
    keyVersion: parseInt(bits.slice(32, 40), 2),
  };
}

/**
 * Validate pasted generator rows before they enter the pool.
 * rows: array of arrays (first cell = code; a whole CSV line pasted into
 * one cell is cut at the first comma). A header row is skipped.
 * known: codes already in the pool or the ledger (any casing).
 * excluded: codes handed out by hand before launch, which must never be
 * issued again.
 * Returns { accepted: [code], rejected: [{ row, value, reason }] }.
 */
function parseCodeRows(rows, known, excluded) {
  var seen = {};
  (known || []).forEach(function (c) { seen[normalizeCode(c)] = 'already in pool or ledger'; });
  (excluded || []).forEach(function (c) { seen[normalizeCode(c)] = 'handed out before launch'; });
  var accepted = [];
  var rejected = [];
  (rows || []).forEach(function (row, i) {
    var value = row && row.length ? row[0] : '';
    var text = String(value === undefined || value === null ? '' : value).split(',')[0].trim();
    if (text === '') return;
    var code = normalizeCode(text);
    // The generator CSV header. A row counts as a header only if it is not a
    // valid code, so a real code containing the letters CODE is never skipped.
    if (i === 0 && !CODE_RE.test(code) && /code/i.test(text)) return;
    if (!CODE_RE.test(code)) {
      rejected.push({ row: i + 1, value: text, reason: 'not a XXXX-XXXX-XXXX-XXXX code' });
      return;
    }
    var parts = decodeCode(code);
    if (parts.purchaseId >= STANDALONE_FIRST_ID) {
      rejected.push({ row: i + 1, value: code, reason: 'standalone series (--standalone), not a set code' });
      return;
    }
    if (parts.keyVersion !== KEY_VERSION) {
      rejected.push({ row: i + 1, value: code, reason: 'key version ' + parts.keyVersion + ' (the app accepts ' + KEY_VERSION + ')' });
      return;
    }
    if (seen[code]) {
      rejected.push({ row: i + 1, value: code, reason: seen[code] });
      return;
    }
    seen[code] = 'duplicate within this import';
    accepted.push(code);
  });
  return { accepted: accepted, rejected: rejected };
}

/**
 * A variant id as the Admin API returns it. The number from the admin URL is
 * accepted too. Returns null for anything else.
 */
function normalizeVariantId(raw) {
  var s = String(raw === null || raw === undefined ? '' : raw).trim();
  if (/^\d+$/.test(s)) return 'gid://shopify/ProductVariant/' + s;
  return /^gid:\/\/shopify\/ProductVariant\/\d+$/.test(s) ? s : null;
}

/** Number of study sets in an order: the current quantity of set variants. */
function countSets(order, setVariantIds) {
  var ids = {};
  (setVariantIds || []).forEach(function (id) { ids[String(id).trim()] = true; });
  var nodes = (order && order.lineItems && order.lineItems.nodes) || [];
  var n = 0;
  nodes.forEach(function (li) {
    var vid = li && li.variant && li.variant.id;
    if (vid && ids[vid]) n += Math.max(0, Number(li.currentQuantity) || 0);
  });
  return n;
}

/** A line still in the order whose variant was deleted (variant is null). */
function hasOrphanLine(order) {
  var nodes = (order && order.lineItems && order.lineItems.nodes) || [];
  return nodes.some(function (li) { return li && !li.variant && Number(li.currentQuantity) > 0; });
}

/**
 * What to do with an order re-read from the Admin API.
 * opts: { setVariantIds: [gid], live: bool, now: epoch ms }
 * Returns one of
 *   { action: 'wait' }                   not ready yet: leave it, check later
 *   { action: 'skip', reason }           nothing to issue (tag it and move on)
 *   { action: 'flag', reason }           a human must look (never auto-issue)
 *   { action: 'issue', sets, noEmail }   issue `sets` codes
 * Reasons are Japanese: they go straight into KAI's daily report.
 */
function decideOrder(order, opts) {
  opts = opts || {};
  if (!order) return { action: 'flag', reason: '注文が見つかりません' };
  var status = order.displayFinancialStatus;
  if (status !== 'PAID') {
    if (status === 'PARTIALLY_REFUNDED' || status === 'REFUNDED' || status === 'VOIDED') {
      return { action: 'flag', reason: '返金または取消のある注文です（' + status + '）' };
    }
    return { action: 'wait' };
  }
  if (order.cancelledAt) return { action: 'flag', reason: 'キャンセル済みの注文です' };
  if (order.test && opts.live) return { action: 'flag', reason: 'テスト注文です（本番稼働中）' };

  var risk = order.risk || {};
  if (risk.recommendation === 'CANCEL') {
    return { action: 'flag', reason: 'Shopifyの不正注文分析が「キャンセル推奨」としています' };
  }
  var pending = (risk.assessments || []).some(function (a) { return a && a.riskLevel === 'PENDING'; });
  if (pending && opts.now && order.createdAt) {
    var ageMin = (opts.now - Date.parse(order.createdAt)) / 60000;
    if (ageMin < RISK_PENDING_MAX_MIN) return { action: 'wait' };
  }

  var sets = countSets(order, opts.setVariantIds);
  if (sets === 0) {
    if (hasOrphanLine(order)) {
      return { action: 'flag', reason: '削除された商品の明細があります（セットの注文か確認してください）' };
    }
    return { action: 'skip', reason: 'コード対象の商品がありません' };
  }
  return { action: 'issue', sets: sets, noEmail: !order.email };
}

/** Ledger key: one row per (order, set number). */
function ledgerKey(orderGid, setNo) {
  return String(orderGid) + '#' + String(setNo);
}

/** Codes as written onto the order metafield and printed on the slip. */
function joinCodes(codes) {
  return (codes || []).join(' / ');
}

function splitCodes(value) {
  return String(value || '').split('/').map(function (s) { return s.trim(); }).filter(String);
}

/**
 * The Admin API search for orders that may need a code.
 * launchDate: 'YYYY-MM-DD' — nothing older is ever considered. Required: with
 * no date the search would reach back over every earlier paid order.
 * live: false during the dry run, when only orders tagged code-dryrun are
 * touched.
 */
function buildOrdersQuery(launchDate, live) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(launchDate || ''))) {
    throw new Error('LAUNCH_DATE must be YYYY-MM-DD');
  }
  // partially_refunded is included so it reaches decideOrder and is flagged.
  // code-flagged: a person must act; left in the queue, flagged orders would
  // pile up at the front (oldest first) and starve new paid orders.
  var q = '(financial_status:paid OR financial_status:partially_refunded)' +
    ' tag_not:code-issued tag_not:code-skip tag_not:code-flagged' +
    ' created_at:>=' + launchDate;
  if (!live) q += ' tag:code-dryrun';
  return q;
}

/** A point in time for a search query: quoted, whole seconds, UTC. */
function searchTime(ms) {
  return "'" + new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z') + "'";
}

/**
 * The email that carries the code(s). Plain text: it renders everywhere and
 * never trips an HTML filter.
 */
function buildCodeEmail(orderName, codes) {
  var many = codes.length > 1;
  var lines = [];
  lines.push('このたびは「快単パーフェクト［2級〜準1級］」をお買い求めいただき、');
  lines.push('誠にありがとうございます。');
  lines.push('');
  lines.push('ご注文（' + orderName + '）のお支払いを確認いたしましたので、');
  lines.push('アプリのアンロックコードをお送りいたします。');
  lines.push('');
  codes.forEach(function (c, i) {
    lines.push('　アンロックコード' + (many ? '（' + (i + 1) + '）' : '') + '：' + c);
  });
  lines.push('');
  lines.push('■ ご利用方法');
  lines.push('1. アプリ「快単パーフェクト」を App Store または Google Play からダウンロードしてください。');
  lines.push('2. スタート画面の「アンロックコードをお持ちの方」をタップしてください。');
  lines.push('　（iPhone では「全機能を解放する（購入・コード入力）」と表示されます）');
  lines.push('3. 上記のコードを入力し、「アンロック」をタップしてください。');
  lines.push('');
  lines.push('■ ご注意');
  lines.push('・同じコードを、お届けする書籍の納品書にも記載しております。');
  if (many) {
    lines.push('・コードは1セットにつき1つです。各セットをお使いになる方に、1つずつお渡しください。');
  } else {
    lines.push('・コードは本セットをご購入のお客様専用です。第三者への譲渡・共有はご遠慮ください。');
  }
  lines.push('・学習の記録は端末内に保存されます。機種変更の際は、新しい端末で再度コードを入力してください。');
  lines.push('');
  lines.push('ご不明な点は、info@kai.or.jp までお問い合わせください（このメールへのご返信でも承ります）。');
  lines.push('');
  lines.push('一般社団法人ＫＡＩ');
  return {
    subject: '【快単パーフェクト】アプリのアンロックコードのお知らせ（ご注文 ' + orderName + '）',
    body: lines.join('\n'),
  };
}

/**
 * Shopify OAuth callback check. The message is every query parameter except
 * `hmac` (and `signature`), sorted by key, joined as key=value with '&'.
 * hmacHex(message, secret) must return the lower-case hex HMAC-SHA256.
 */
function shopifyHmacMessage(params) {
  return Object.keys(params)
    .filter(function (k) { return k !== 'hmac' && k !== 'signature'; })
    .sort()
    .map(function (k) { return k + '=' + params[k]; })
    .join('&');
}

function verifyShopifyHmac(params, secret, hmacHex) {
  if (!params || !params.hmac || !secret) return false;
  var expected = hmacHex(shopifyHmacMessage(params), secret);
  return constantTimeEqual(String(expected).toLowerCase(), String(params.hmac).toLowerCase());
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Only a *.myshopify.com host may receive our client secret. */
function isShopDomain(shop) {
  return /^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(String(shop || ''));
}

/**
 * Interpret the result of a compare-and-set metafield write.
 * We first write with compareDigest: null, which Shopify refuses when the
 * order already has a value. The refusal is expected after a crash between
 * the write and our bookkeeping, so read the current value and compare.
 * Returns
 *   'ok'        written, or the order already carries exactly our value;
 *   'extend'    the order carries some of OUR codes only (a set was added to
 *               the order later): overwrite it using the current digest;
 *   'conflict'  the order carries a code we did not issue to it;
 *   'error'     refused for another reason.
 */
function metafieldOutcome(userErrors, currentValue, ourValue) {
  if (!userErrors || userErrors.length === 0) return 'ok';
  if (currentValue === null || currentValue === undefined) return 'error';
  if (currentValue === ourValue) return 'ok';
  var ours = splitCodes(ourValue);
  var current = splitCodes(currentValue);
  var allOurs = current.length > 0 && current.every(function (c) { return ours.indexOf(c) >= 0; });
  return allOurs ? 'extend' : 'conflict';
}

if (typeof module !== 'undefined') {
  module.exports = {
    CODE_RE: CODE_RE, STANDALONE_FIRST_ID: STANDALONE_FIRST_ID, KEY_VERSION: KEY_VERSION,
    REASON_POOL_EMPTY: REASON_POOL_EMPTY,
    normalizeCode: normalizeCode, isValidCode: isValidCode, decodeCode: decodeCode,
    parseCodeRows: parseCodeRows, normalizeVariantId: normalizeVariantId,
    countSets: countSets, hasOrphanLine: hasOrphanLine, decideOrder: decideOrder,
    ledgerKey: ledgerKey, joinCodes: joinCodes, splitCodes: splitCodes,
    buildOrdersQuery: buildOrdersQuery, searchTime: searchTime,
    buildCodeEmail: buildCodeEmail, shopifyHmacMessage: shopifyHmacMessage,
    verifyShopifyHmac: verifyShopifyHmac, constantTimeEqual: constantTimeEqual,
    isShopDomain: isShopDomain, metafieldOutcome: metafieldOutcome,
  };
}
