// End-to-end runs of Main.js against fake Google services and a fake
// Shopify Admin API. Run from shopify_code_delivery/: node --test
// Apps Script cannot run locally, so these fakes model only the behaviour
// Main.js relies on. Codes are synthetic.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SRC = path.join(__dirname, '..', 'apps_script');
const ROBOT = 'kai.robot@gmail.com';
const SET = 'gid://shopify/ProductVariant/111';
const L = { GID: 0, NAME: 1, SET: 2, CODE: 3, ISSUED: 4, MF: 5, TAG: 6, EMAIL_TO: 7, EMAIL_AT: 8, RESEND: 9, NOTE: 10 };

// ── fake Sheets ──────────────────────────────────────────────────────────
class Sheet {
  constructor(name) { this.name = name; this.rows = []; this.maxRows = 1000; }
  cell(r, c) { return (this.rows[r - 1] || [])[c - 1]; }
  put(r, c, v) { (this.rows[r - 1] = this.rows[r - 1] || [])[c - 1] = v; }
  getLastRow() {
    for (let r = this.rows.length; r > 0; r--) {
      if ((this.rows[r - 1] || []).some((v) => v !== '' && v !== undefined && v !== null)) return r;
    }
    return 0;
  }
  getLastColumn() { return Math.max(0, ...this.rows.map((r) => (r || []).length)); }
  getDataRange() { return this.getRange(1, 1, Math.max(this.getLastRow(), 1), Math.max(this.getLastColumn(), 1)); }
  getRange(r, c, nr = 1, nc = 1) {
    const s = this;
    const grid = () => Array.from({ length: nr }, (_, i) => Array.from({ length: nc }, (_, j) => {
      const v = s.cell(r + i, c + j); return v === undefined ? '' : v;
    }));
    return {
      getValues: () => (s.getLastRow() === 0 && r === 1 ? [] : grid()),
      getValue: () => grid()[0][0],
      setValue: (v) => { s.put(r, c, v); },
      setValues: (vals) => vals.forEach((row, i) => row.forEach((v, j) => s.put(r + i, c + j, v))),
      clearContent: () => { for (let i = 0; i < nr; i++) for (let j = 0; j < nc; j++) s.put(r + i, c + j, ''); },
      insertCheckboxes: () => { if (s.cell(r, c) === '' || s.cell(r, c) === undefined) s.put(r, c, false); },
    };
  }
  appendRow(v) { const r = this.getLastRow() + 1; v.forEach((x, j) => this.put(r, j + 1, x)); }
  deleteRow(r) { this.rows.splice(r - 1, 1); }
  getMaxRows() { return this.maxRows; }
  setFrozenRows() {}
}
class Book {
  constructor(names) { this.sheets = {}; names.forEach((n) => { this.sheets[n] = new Sheet(n); }); }
  getSheetByName(n) { return this.sheets[n] || null; }
}

// ── fake Shopify ─────────────────────────────────────────────────────────
function makeShop() {
  const shop = { orders: {}, down: false, forgetOlderThan60Days: new Set(), calls: [] };
  shop.add = (o) => {
    shop.orders[o.id] = {
      email: 'buyer@example.com', displayFinancialStatus: 'PAID', cancelledAt: null, test: false,
      createdAt: '2026-10-01T01:00:00Z', tags: [], mf: null, mfDigest: null,
      risk: { recommendation: 'ACCEPT', assessments: [{ riskLevel: 'LOW' }] },
      lineItems: { nodes: [{ currentQuantity: 1, variant: { id: SET } }] },
      ...o,
    };
    return shop.orders[o.id];
  };
  const matches = (o, q) => {
    if (q.includes('(financial_status:paid OR financial_status:partially_refunded)') &&
      !['PAID', 'PARTIALLY_REFUNDED'].includes(o.displayFinancialStatus)) return false;
    if (q.includes('financial_status:expired') && o.displayFinancialStatus !== 'EXPIRED') return false;
    for (const m of q.matchAll(/(?:^| )tag_not:(\S+)/g)) if (o.tags.includes(m[1])) return false;
    for (const m of q.matchAll(/(?:^| )tag:(\S+)/g)) if (!o.tags.includes(m[1])) return false;
    for (const m of q.matchAll(/created_at:>=('?)([^' ]+)\1/g)) if (o.createdAt < m[2]) return false;
    for (const m of q.matchAll(/created_at:<=('?)([^' ]+)\1/g)) if (o.createdAt > m[2]) return false;
    return true;
  };
  const view = (o) => o && ({
    ...o, metafield: o.mf === null ? null : { value: o.mf, compareDigest: o.mfDigest },
  });
  shop.handle = (query, v) => {
    shop.calls.push(query);
    if (query.includes('metafieldsSet')) {
      const m = v.m[0]; const o = shop.orders[m.ownerId];
      const okCas = m.compareDigest === null ? o.mf === null : m.compareDigest === o.mfDigest;
      if (!okCas) return { metafieldsSet: { metafields: [], userErrors: [{ message: 'stale', code: 'STALE_OBJECT' }] } };
      o.mf = m.value; o.mfDigest = 'd' + Math.random();
      return { metafieldsSet: { metafields: [{ id: 'm' }], userErrors: [] } };
    }
    if (query.includes('tagsAdd')) {
      const o = shop.orders[v.id]; v.t.forEach((t) => { if (!o.tags.includes(t)) o.tags.push(t); });
      return { tagsAdd: { userErrors: [] } };
    }
    if (query.includes('orders(')) {
      return { orders: { nodes: Object.values(shop.orders).filter((o) => matches(o, v.q || ''))
        .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1)).map(view) } };
    }
    if (query.includes('order(id:')) {
      return { order: shop.forgetOlderThan60Days.has(v.id) ? null : view(shop.orders[v.id]) };
    }
    throw new Error('fake Shopify: unhandled query ' + query);
  };
  return shop;
}

// ── the Apps Script world ────────────────────────────────────────────────
function world(opts = {}) {
  const props = {
    ROBOT_EMAIL: ROBOT, SHOP_DOMAIN: 'kai-test.myshopify.com', SET_VARIANT_IDS: '111',
    LAUNCH_DATE: '2026-10-01', LIVE: 'true', POOL_SHEET_ID: 'pool', LEDGER_SHEET_ID: 'ledger',
    SHOPIFY_TOKEN: 'shpat_fake', ...opts.props,
  };
  const books = { pool: new Book(['pool', 'import', 'exclude']), ledger: new Book(['ledger', 'flags']) };
  books.pool.sheets.pool.appendRow(['code', 'batch_id', 'imported_at', 'status', 'used_at', 'order_name']);
  books.pool.sheets.import.appendRow(['paste here']);
  books.pool.sheets.exclude.appendRow(['handed out']);
  books.ledger.sheets.ledger.appendRow(['order_gid', 'order_name', 'set_no', 'code', 'issued_at', 'metafield',
    'tag', 'email_to', 'email_sent_at', 'resend', 'note']);
  books.ledger.sheets.flags.appendRow(['order_gid', 'order_name', 'reason', 'first_seen', 'last_seen']);
  const shop = makeShop();
  const mail = [];
  const w = { props, books, shop, mail, user: ROBOT, quota: 100, failMailOnce: false };
  const ctx = {
    console,
    PropertiesService: { getScriptProperties: () => ({
      getProperty: (k) => (k in props ? props[k] : null),
      setProperty: (k, v) => { props[k] = String(v); },
      deleteProperty: (k) => { delete props[k]; },
    }) },
    LockService: { getScriptLock: () => ({ tryLock: () => true, waitLock: () => {}, releaseLock: () => {} }) },
    Session: { getEffectiveUser: () => ({ getEmail: () => w.user }) },
    SpreadsheetApp: { openById: (id) => books[id], flush: () => {} },
    MailApp: {
      getRemainingDailyQuota: () => w.quota,
      sendEmail: (m) => {
        if (w.failMailOnce) { w.failMailOnce = false; throw new Error('Service invoked too many times'); }
        mail.push(m); w.quota--;
      },
    },
    UrlFetchApp: { fetch: (url, o) => {
      if (shop.down) throw new Error('Address unavailable');
      const body = JSON.parse(o.payload);
      const data = shop.handle(body.query, body.variables);
      return { getResponseCode: () => 200, getContentText: () => JSON.stringify({ data }) };
    } },
    Utilities: { formatDate: (d) => new Date(d).toISOString(), getUuid: () => 'uuid' },
    Logger: { log: () => {} },
  };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(SRC, 'Core.js'), 'utf8'), ctx);
  vm.runInContext(fs.readFileSync(path.join(SRC, 'Main.js'), 'utf8'), ctx);
  w.run = (fn) => ctx[fn]();
  w.ctx = ctx;
  w.loadCodes = (codes) => {
    const imp = books.pool.sheets.import;
    codes.forEach((c, i) => imp.put(i + 2, 1, c));
    return ctx.importCodes();
  };
  w.ledger = () => books.ledger.sheets.ledger.rows.slice(1).filter((r) => r && r[0]);
  w.flags = () => books.ledger.sheets.flags.rows.slice(1).filter((r) => r && r[0]);
  w.available = () => books.pool.sheets.pool.rows.slice(1).filter((r) => r && r[3] === 'available').length;
  return w;
}

// Synthetic set codes in the generator's layout (see core.test.js).
const crypto = require('node:crypto');
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function makeCode(pid) {
  const p = Buffer.alloc(5); p.writeUInt32BE(pid); p[4] = 2;
  const mac = crypto.createHmac('sha256', 'test-only-key').update(p).digest().subarray(0, 5);
  let bits = ''; for (const b of Buffer.concat([p, mac])) bits += b.toString(2).padStart(8, '0');
  let s = ''; for (let i = 0; i < 80; i += 5) s += B32[parseInt(bits.slice(i, i + 5), 2)];
  return s.match(/.{4}/g).join('-');
}
const CODES = Array.from({ length: 10 }, (_, i) => makeCode(100 + i));
const pollQuietly = (w) => { try { w.run('poll'); return null; } catch (e) { return e; } };

test('a paid order with two sets gets two codes, one email, the metafield and the tag', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 5));
  const o = w.shop.add({ id: 'gid://shopify/Order/1', name: '#1001',
    lineItems: { nodes: [{ currentQuantity: 2, variant: { id: SET } }] } });
  assert.equal(pollQuietly(w), null);
  assert.equal(w.ledger().length, 2);
  assert.deepEqual(w.ledger().map((r) => r[L.CODE]), [CODES[0], CODES[1]]);
  assert.equal(o.mf, CODES[0] + ' / ' + CODES[1]);
  assert.ok(o.tags.includes('code-issued'));
  assert.equal(w.mail.length, 1);
  assert.ok(w.mail[0].body.includes(CODES[0]) && w.mail[0].body.includes(CODES[1]));
  assert.equal(w.mail[0].replyTo, 'info@kai.or.jp');
  assert.equal(w.available(), 3);
  // the next run does nothing more
  assert.equal(pollQuietly(w), null);
  assert.equal(w.ledger().length, 2);
  assert.equal(w.mail.length, 1);
  assert.ok(w.props.LAST_POLL_OK);
});

test('a crash after the code is reserved is finished next run with the SAME code', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  const o = w.shop.add({ id: 'gid://shopify/Order/2', name: '#1002' });
  w.failMailOnce = true;
  assert.ok(pollQuietly(w)); // the run reports the failure
  assert.equal(w.ledger().length, 1);
  assert.equal(o.mf, CODES[0]);
  assert.ok(!o.tags.includes('code-issued'));
  assert.ok(w.props.LAST_POLL_ERROR.includes('#1002'));
  assert.equal(pollQuietly(w), null);
  assert.equal(w.ledger().length, 1);
  assert.equal(w.mail.length, 1);
  assert.ok(w.mail[0].body.includes(CODES[0]));
  assert.ok(o.tags.includes('code-issued'));
  assert.equal(w.available(), 2);
});

test('konbini: nothing while pending, the code once Shopify says PAID', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  const o = w.shop.add({ id: 'gid://shopify/Order/3', name: '#1003', displayFinancialStatus: 'PENDING' });
  pollQuietly(w);
  assert.equal(w.ledger().length, 0);
  o.displayFinancialStatus = 'PAID';
  pollQuietly(w);
  assert.equal(w.ledger().length, 1);
  assert.equal(w.mail.length, 1);
});

test('an empty pool flags the order, stops the run, and clears the flag after the refill', () => {
  const w = world();
  const o = w.shop.add({ id: 'gid://shopify/Order/4', name: '#1004' });
  w.shop.add({ id: 'gid://shopify/Order/5', name: '#1005', createdAt: '2026-10-01T02:00:00Z' });
  const err = pollQuietly(w);
  assert.ok(err && /pool empty/.test(err.message));
  assert.equal(w.flags().length, 1); // the run stopped at the first order
  assert.ok(!o.tags.includes('code-flagged')); // stays in the queue
  w.loadCodes(CODES.slice(0, 2));
  assert.equal(pollQuietly(w), null);
  assert.equal(w.ledger().length, 2);
  assert.equal(w.flags().length, 0);
});

test('resend sends the same code; for an order Shopify no longer returns, to the recorded address', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  w.shop.add({ id: 'gid://shopify/Order/6', name: '#1006' });
  pollQuietly(w);
  const sheet = w.books.ledger.sheets.ledger;
  sheet.put(2, L.RESEND + 1, true);
  w.shop.forgetOlderThan60Days.add('gid://shopify/Order/6');
  assert.equal(pollQuietly(w), null);
  assert.equal(w.mail.length, 2);
  assert.equal(w.mail[1].to, 'buyer@example.com');
  assert.ok(w.mail[1].body.includes(CODES[0]));
  assert.equal(sheet.cell(2, L.RESEND + 1), false);
  assert.equal(w.ledger().length, 1);
});

test('a code already typed onto the order: flagged, no code drawn', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  const o = w.shop.add({ id: 'gid://shopify/Order/7', name: '#1007', mf: 'HAND-TYPE-DCOD-E222', mfDigest: 'x' });
  pollQuietly(w);
  assert.equal(w.ledger().length, 0);
  assert.equal(w.available(), 3);
  assert.ok(o.tags.includes('code-flagged'));
  assert.equal(w.mail.length, 0);
});

test('paused, or run from the wrong account: nothing is issued or sent', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  w.shop.add({ id: 'gid://shopify/Order/8', name: '#1008' });
  w.run('pause');
  pollQuietly(w);
  assert.equal(w.ledger().length, 0);
  w.run('resume');
  w.user = 'contractor@example.com';
  assert.ok(/robot account/.test(pollQuietly(w).message));
  assert.equal(w.ledger().length, 0);
  assert.equal(w.mail.length, 0);
});

test('dry run: only orders tagged code-dryrun are touched; LAUNCH_DATE is mandatory', () => {
  const w = world({ props: { LIVE: 'false' } });
  w.loadCodes(CODES.slice(0, 3));
  const real = w.shop.add({ id: 'gid://shopify/Order/9', name: '#1009' });
  const trial = w.shop.add({ id: 'gid://shopify/Order/10', name: '#1010', test: true, tags: ['code-dryrun'] });
  pollQuietly(w);
  assert.deepEqual(w.ledger().map((r) => r[L.NAME]), ['#1010']);
  assert.ok(!real.tags.length);
  assert.ok(trial.tags.includes('code-issued'));
  const w2 = world({ props: { LAUNCH_DATE: '' } });
  w2.loadCodes(CODES.slice(0, 3));
  w2.shop.add({ id: 'gid://shopify/Order/11', name: '#1011' });
  assert.ok(/LAUNCH_DATE/.test(pollQuietly(w2).message));
  assert.equal(w2.ledger().length, 0);
});

test('a set added to an order after issue: tag removed, the extra code is added and both are emailed', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  const o = w.shop.add({ id: 'gid://shopify/Order/12', name: '#1012' });
  pollQuietly(w);
  o.lineItems.nodes[0].currentQuantity = 2;
  o.tags = o.tags.filter((t) => t !== 'code-issued');
  assert.equal(pollQuietly(w), null);
  assert.equal(o.mf, CODES[0] + ' / ' + CODES[1]);
  assert.equal(w.ledger().length, 2);
  assert.equal(w.mail.length, 2);
  assert.ok(w.mail[1].body.includes(CODES[0]) && w.mail[1].body.includes(CODES[1]));
});

test('the daily report still arrives when Shopify is unreachable, and says so', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  w.shop.down = true;
  w.run('dailySummary');
  assert.equal(w.mail.length, 1);
  assert.equal(w.mail[0].to, 'info@kai.or.jp');
  assert.ok(w.mail[0].body.includes('Shopifyに接続できません'));
  assert.ok(w.mail[0].body.includes('一度も正常に動いていません'));
  assert.ok(w.mail[0].body.includes('在庫（未使用のコード）：3 件'));
});

test('the last recipient of the daily mail quota is kept for the report', () => {
  const w = world();
  w.loadCodes(CODES.slice(0, 3));
  w.shop.add({ id: 'gid://shopify/Order/13', name: '#1013' });
  w.quota = 1;
  const err = pollQuietly(w);
  assert.ok(/mail quota/.test(err.message));
  assert.equal(w.mail.length, 0);
  w.run('dailySummary');
  assert.equal(w.mail.length, 1);
});

test('import refuses codes handed out by hand, found in any column of the member list', () => {
  const w = world();
  w.books.pool.sheets.exclude.appendRow([1, CODES[0], 12, '会員A', '#900', '2026-09-30']);
  const r = w.loadCodes(CODES.slice(0, 3));
  assert.equal(r.accepted.length, 2);
  assert.equal(r.rejected[0].reason, 'handed out before launch');
});
