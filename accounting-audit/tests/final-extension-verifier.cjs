'use strict';

// Read-only verification of retained synthetic fixtures; never imports app/DB boot.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const Database = require('../../server/node_modules/better-sqlite3');
const root = path.resolve(__dirname, '../..');
const evidence = path.join(root, 'accounting-audit/evidence');
const sales = path.join(evidence, 'sales-channel-run-AFjr5O');
const payable = path.join(evidence, 'payable-cash-run-GIxBh2');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const snap = name => read(path.join(sales, name));
const events = read(path.join(sales, 'api-events.json'));
const output = { verifiedAt: new Date().toISOString(), scope: 'Retained synthetic DBs only; no application boot or financial writes', findings: {} };

const before = snap('19-pos-zero-before.json');
const after = snap('20-pos-zero-after.json');
const zero = events.find(event => event.url === '/api/pos/sale' && event.body?.cash_received === 0);
assert.equal(zero.status, 201);
assert.equal(zero.headers['Idempotency-Key'], 'SC-zero-cash-valid');
assert.equal(after.balances['1000'] - before.balances['1000'], 1735);
assert.equal(after.balances['1100'] - before.balances['1100'], 0);
assert.equal(after.balances['1200'] - before.balances['1200'], -925);
const newPayments = after.state.payments.filter(row => !before.state.payments.some(old => old.id === row.id));
assert.equal(newPayments.length, 1);
assert.equal(Math.round(newPayments[0].amount * 100), 1735);
output.findings.F073 = { request: zero, expectedCashDeltaPaise: 0, actualCashDeltaPaise: 1735,
  actualArDeltaPaise: 0, actualInventoryDeltaPaise: -925, fabricatedPayment: newPayments[0] };

const replay = snap('22-reservation-replayed.json');
const released = snap('23-reservation-released.json');
assert.equal(replay.state.stock_reservations.length, 1);
assert.equal(replay.state.stock_reservations[0].quantity_reserved, 3);
assert.equal(replay.state.batch_stock_by_location[0].quantity_reserved, 6);
assert.equal(released.state.stock_reservations[0].status, 'RELEASED');
assert.equal(released.state.batch_stock_by_location[0].quantity_reserved, 3);
assert.equal(released.state.batch_stock_by_location[0].quantity_available, 7);
output.findings.F071 = { replayRow: replay.state.stock_reservations[0],
  replayLocation: replay.state.batch_stock_by_location[0], releasedLocation: released.state.batch_stock_by_location[0],
  expectedFinalReserved: 0, expectedFinalAvailable: 10 };

const control = snap('26-reservation-control-released.json');
assert.equal(control.state.stock_reservations.find(row => row.id === 2).status, 'RELEASED');
assert.equal(control.state.batch_stock_by_location.find(row => row.batch_id === 8).quantity_available, 10);
const nullLine = snap('28-reservation-noline-after.json').state.stock_reservations.find(row => row.id === 3);
const nullRelease = events.find(event => event.url === '/api/inventory/reservations/3/release');
assert.equal(nullLine.reference_line_id, null);
assert.equal(nullLine.status, 'ACTIVE');
assert.equal(nullRelease.status, 400);
assert.equal(nullRelease.before, nullRelease.after);
output.findings.F072 = { retainedReservation: nullLine, release: nullRelease, nonNullLinePositiveControl: '200 and availability restored10' };

const repeat = events.find(event => event.url === '/api/sales-orders/1/cancel' && event.status === 500);
assert.ok(repeat);
assert.equal(repeat.before, repeat.after);
output.findings.F070 = { repeat, expectedStatus: '4xx', secondMutation: false };

const db = new Database(path.join(payable, 'erp.db'), { readonly: true, fileMustExist: true });
const staleHeaders = db.prepare(`
  SELECT e.id, e.reference_type, e.reference_id, e.voided,
         COUNT(l.id) AS line_count, SUM(CASE WHEN l.voided = 0 THEN 1 ELSE 0 END) AS active_lines
  FROM journal_entries e JOIN journal_lines l ON l.journal_entry_id = e.id
  WHERE e.voided = 0 GROUP BY e.id
  HAVING COUNT(l.id) > 0 AND SUM(CASE WHEN l.voided = 0 THEN 1 ELSE 0 END) = 0
`).all();
assert.ok(staleHeaders.length > 0);
const imbalanced = db.prepare(`SELECT journal_entry_id, SUM(debit-credit) AS difference
  FROM journal_lines WHERE voided = 0 GROUP BY journal_entry_id HAVING ABS(SUM(debit-credit)) > 0.005`).all();
assert.equal(imbalanced.length, 0);
output.findings.F060 = { staleHeaders, canonicalUnbalancedEntries: imbalanced,
  economicEffectClaim: 'None demonstrated; canonical active-line accounting remains balanced' };
output.payable = { checks: read(path.join(payable, 'results.json')).checks.length,
  integrity: db.pragma('integrity_check'), foreignKeys: db.pragma('foreign_key_check') };
db.close();

const baseline = read(path.join(evidence, 'source-baseline.json'));
const changed = Object.entries(baseline.sourceHashes).flatMap(([file, hash]) => {
  const filename = path.join(root, file);
  const current = fs.existsSync(filename) ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex') : null;
  return current === hash ? [] : [{ file, baseline: hash, current }];
});
output.source = { baselineRevision: baseline.revision, protectedFiles: Object.keys(baseline.sourceHashes).length,
  changed, interpretation: 'Later shared-workspace changes are preserved and are not attributed to this audit; original fixture executions are snapshot evidence' };
fs.writeFileSync(path.join(evidence, 'final-extension-verification.json'), JSON.stringify(output, null, 2));
console.log(JSON.stringify({ status: 'VERIFIED', findings: Object.keys(output.findings), staleHeaders: staleHeaders.length,
  sourceFilesChangedSinceSnapshot: changed.length }));
