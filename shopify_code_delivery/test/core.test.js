// Unit tests for the decision logic. Run from shopify_code_delivery/: node --test
// Codes here are synthetic, signed with a throwaway key; no issued code ever
// enters this repository.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const C = require('../apps_script/Core.js');

// The layout of tool/generate_codes.py: purchase_id (4 bytes BE) +
// key_version (1 byte) + 5 bytes of HMAC, base32, XXXX-XXXX-XXXX-XXXX.
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function makeCode(purchaseId, keyVersion = 2) {
  const payload = Buffer.alloc(5);
  payload.writeUInt32BE(purchaseId);
  payload[4] = keyVersion;
  const mac = crypto.createHmac('sha256', 'test-only-key').update(payload).digest().subarray(0, 5);
  let bits = '';
  for (const b of Buffer.concat([payload, mac])) bits += b.toString(2).padStart(8, '0');
  let s = '';
  for (let i = 0; i < bits.length; i += 5) s += B32[parseInt(bits.slice(i, i + 5), 2)];
  return s.match(/.{4}/g).join('-');
}

const SET = 'gid://shopify/ProductVariant/111';
const NOW = Date.parse('2026-10-01T03:00:00Z');
const order = (over = {}) => ({
  id: 'gid://shopify/Order/1', name: '#1001', email: 'buyer@example.com',
  displayFinancialStatus: 'PAID', cancelledAt: null, test: false,
  createdAt: '2026-10-01T02:00:00Z',
  risk: { recommendation: 'ACCEPT', assessments: [{ riskLevel: 'LOW' }] },
  lineItems: { nodes: [{ currentQuantity: 1, variant: { id: SET } }] },
  ...over,
});
const opts = { setVariantIds: [SET], live: true, now: NOW };

test('codes: the generator format is accepted and normalised', () => {
  assert.equal(C.normalizeCode(' aaaa-abcd-2345-7zzz '), 'AAAA-ABCD-2345-7ZZZ');
  assert.equal(C.normalizeCode('AAAAABCD23457ZZZ'), 'AAAA-ABCD-2345-7ZZZ');
  assert.equal(C.normalizeCode('AAAA－ABCD－2345－7ZZZ'), 'AAAA-ABCD-2345-7ZZZ'); // full-width dashes from Excel
  assert.ok(C.isValidCode('AAAA-ABCD-2345-7ZZZ'));
  // 0, 1, 8 and 9 are not in the base32 alphabet
  assert.ok(!C.isValidCode('AAAA-ABCD-0189-ZZZZ'));
  assert.ok(!C.isValidCode('AAAA-ABCD-2345'));
});

test('codes: purchase id and key version are read back as the generator packed them', () => {
  assert.deepEqual(C.decodeCode(makeCode(12)), { purchaseId: 12, keyVersion: 2 });
  assert.deepEqual(C.decodeCode(makeCode(1000000)), { purchaseId: 1000000, keyVersion: 2 });
  assert.deepEqual(C.decodeCode(makeCode(4294967295, 1)), { purchaseId: 4294967295, keyVersion: 1 });
});

test('import: header skipped, junk, duplicates, wrong series and old key rejected with reasons', () => {
  const [a, b, c, d] = [makeCode(12), makeCode(13), makeCode(14), makeCode(15)];
  const rows = [
    ['code', 'purchase_id'],
    [a + ',12,2026-09-25T01:55:11+00:00,2'], // a whole CSV line pasted into one cell
    ['not a code'],
    [a],                                     // duplicate within the import
    [b.toLowerCase()],                       // already known
    [c],                                     // handed out by hand
    [''],
    [makeCode(1000001)],                     // standalone series
    [makeCode(16, 1)],                       // the retired v1 key
    [d],
  ];
  const r = C.parseCodeRows(rows, [b], [c]);
  assert.deepEqual(r.accepted, [a, d]);
  assert.deepEqual(r.rejected.map((x) => x.reason), [
    'not a XXXX-XXXX-XXXX-XXXX code',
    'duplicate within this import',
    'already in pool or ledger',
    'handed out before launch',
    'standalone series (--standalone), not a set code',
    'key version 1 (the app accepts 2)',
  ]);
});

test('import: a code in the first row is taken, never mistaken for a header', () => {
  const a = makeCode(20);
  assert.deepEqual(C.parseCodeRows([[a]], [], []).accepted, [a]);
  // A code-shaped value containing CODE is judged as a code, not skipped as a header.
  const r = C.parseCodeRows([['AAAA-CODE-2345-7ZZZ']], [], []);
  assert.equal(r.accepted.length + r.rejected.length, 1);
});

test('variant ids: the admin number and the GID are both accepted, nothing else', () => {
  assert.equal(C.normalizeVariantId('4567'), 'gid://shopify/ProductVariant/4567');
  assert.equal(C.normalizeVariantId(' gid://shopify/ProductVariant/4567 '), 'gid://shopify/ProductVariant/4567');
  assert.equal(C.normalizeVariantId('gid://shopify/Product/4567'), null);
  assert.equal(C.normalizeVariantId('set-a'), null);
});

test('orders: only PAID issues; pending and authorised wait', () => {
  assert.deepEqual(C.decideOrder(order(), opts), { action: 'issue', sets: 1, noEmail: false });
  for (const s of ['PENDING', 'AUTHORIZED', 'EXPIRED', 'PARTIALLY_PAID']) {
    assert.equal(C.decideOrder(order({ displayFinancialStatus: s }), opts).action, 'wait', s);
  }
});

test('orders: refunds, cancellations and live-mode test orders go to a person', () => {
  for (const s of ['PARTIALLY_REFUNDED', 'REFUNDED', 'VOIDED']) {
    assert.equal(C.decideOrder(order({ displayFinancialStatus: s }), opts).action, 'flag', s);
  }
  assert.equal(C.decideOrder(order({ cancelledAt: '2026-10-01T00:00:00Z' }), opts).action, 'flag');
  assert.equal(C.decideOrder(order({ test: true }), opts).action, 'flag');
  // before launch, test orders are how the system is tried out
  assert.equal(C.decideOrder(order({ test: true }), { ...opts, live: false }).action, 'issue');
  assert.equal(C.decideOrder(null, opts).action, 'flag');
});

test('orders: Shopify fraud analysis — cancel is flagged, pending waits up to 30 minutes', () => {
  const cancel = order({ risk: { recommendation: 'CANCEL', assessments: [{ riskLevel: 'HIGH' }] } });
  assert.equal(C.decideOrder(cancel, opts).action, 'flag');
  const pending = { recommendation: 'NONE', assessments: [{ riskLevel: 'PENDING' }] };
  assert.equal(C.decideOrder(order({ risk: pending, createdAt: '2026-10-01T02:45:00Z' }), opts).action, 'wait');
  assert.equal(C.decideOrder(order({ risk: pending, createdAt: '2026-10-01T02:00:00Z' }), opts).action, 'issue');
  assert.equal(C.decideOrder(order({ risk: { recommendation: 'INVESTIGATE', assessments: [] } }), opts).action, 'issue');
});

test('orders: one code per set, other products skipped, deleted variants flagged', () => {
  const two = order({ lineItems: { nodes: [
    { currentQuantity: 2, variant: { id: SET } },
    { currentQuantity: 5, variant: { id: 'gid://shopify/ProductVariant/999' } },
  ] } });
  assert.equal(C.decideOrder(two, opts).sets, 2);
  const other = order({ lineItems: { nodes: [{ currentQuantity: 1, variant: { id: 'gid://shopify/ProductVariant/999' } }] } });
  assert.equal(C.decideOrder(other, opts).action, 'skip');
  // a removed line (current quantity 0) does not count
  const removed = order({ lineItems: { nodes: [{ currentQuantity: 0, variant: { id: SET } }] } });
  assert.equal(C.decideOrder(removed, opts).action, 'skip');
  // the variant was deleted after the order: it may have been the set
  const orphan = order({ lineItems: { nodes: [{ currentQuantity: 1, variant: null }] } });
  assert.equal(C.decideOrder(orphan, opts).action, 'flag');
});

test('orders: missing email still issues (the slip carries the code) but says so', () => {
  assert.deepEqual(C.decideOrder(order({ email: null }), opts), { action: 'issue', sets: 1, noEmail: true });
});

test('query: launch date required; issued, skipped and flagged orders never re-read', () => {
  const q = C.buildOrdersQuery('2026-10-01', true);
  for (const part of ['(financial_status:paid OR financial_status:partially_refunded)',
    'tag_not:code-issued', 'tag_not:code-skip', 'tag_not:code-flagged', 'created_at:>=2026-10-01']) {
    assert.ok(q.includes(part), part);
  }
  assert.ok(!q.includes('code-dryrun'));
  assert.throws(() => C.buildOrdersQuery('', true));
  assert.throws(() => C.buildOrdersQuery('2026/10/01', true));
});

test('query: during the dry run only orders tagged code-dryrun are touched', () => {
  assert.ok(C.buildOrdersQuery('2026-10-01', false).endsWith(' tag:code-dryrun'));
});

test('search times are quoted, in whole seconds, UTC', () => {
  assert.equal(C.searchTime(Date.parse('2026-09-25T23:30:00.123Z')), "'2026-09-25T23:30:00Z'");
});

test('ledger key and metafield value', () => {
  assert.equal(C.ledgerKey('gid://shopify/Order/1', 2), 'gid://shopify/Order/1#2');
  assert.equal(C.joinCodes(['A', 'B']), 'A / B');
  assert.deepEqual(C.splitCodes('A / B'), ['A', 'B']);
});

test('metafield compare-and-set: accepted only when the order carries nothing but OUR codes', () => {
  assert.equal(C.metafieldOutcome([], null, 'X'), 'ok');
  assert.equal(C.metafieldOutcome([{ message: 'stale' }], 'X', 'X'), 'ok');
  assert.equal(C.metafieldOutcome([{ message: 'stale' }], 'X', 'X / Y'), 'extend'); // a set added later
  assert.equal(C.metafieldOutcome([{ message: 'stale' }], 'Z', 'X / Y'), 'conflict');
  assert.equal(C.metafieldOutcome([{ message: 'stale' }], 'X / Z', 'X / Y'), 'conflict');
  assert.equal(C.metafieldOutcome([{ message: 'boom' }], null, 'X'), 'error');
});

test('email: carries every code, the order, and no link or price', () => {
  const [a, d] = [makeCode(30), makeCode(31)];
  const m = C.buildCodeEmail('#1002', [a, d]);
  assert.ok(m.subject.includes('#1002'));
  assert.ok(m.body.includes(a) && m.body.includes(d));
  assert.ok(m.body.includes('（1）') && m.body.includes('（2）'));
  assert.ok(m.body.includes('1つずつお渡しください')); // extra sets are meant for other people
  assert.ok(!/https?:\/\//.test(m.body));
  assert.ok(!/円/.test(m.body));
  const one = C.buildCodeEmail('#1003', [a]);
  assert.ok(!one.body.includes('（1）'));
});

test('OAuth callback: Shopify HMAC verified exactly; tampering and a missing secret fail', () => {
  const secret = 'shpss_test_secret';
  const params = { code: 'abc', host: 'YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUva2Fp', shop: 'kai-test.myshopify.com',
    state: 'nonce-1', timestamp: '1758860000' };
  const hmacHex = (msg, key) => crypto.createHmac('sha256', key).update(msg).digest('hex');
  assert.equal(C.shopifyHmacMessage(params),
    'code=abc&host=YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUva2Fp&shop=kai-test.myshopify.com&state=nonce-1&timestamp=1758860000');
  const signed = { ...params, hmac: hmacHex(C.shopifyHmacMessage(params), secret) };
  assert.ok(C.verifyShopifyHmac(signed, secret, hmacHex));
  assert.ok(!C.verifyShopifyHmac({ ...signed, shop: 'evil.myshopify.com' }, secret, hmacHex));
  assert.ok(!C.verifyShopifyHmac(signed, 'wrong', hmacHex));
  assert.ok(!C.verifyShopifyHmac(signed, '', hmacHex));
  assert.ok(!C.verifyShopifyHmac(params, secret, hmacHex)); // no hmac at all
});

test('only a myshopify.com host may receive the client secret', () => {
  assert.ok(C.isShopDomain('kai-test.myshopify.com'));
  assert.ok(!C.isShopDomain('kai-test.myshopify.com.evil.com'));
  assert.ok(!C.isShopDomain('evil.com'));
  assert.ok(!C.isShopDomain(''));
});
