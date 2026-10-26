'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '../..');
const run = fs.mkdtempSync(path.join(root, 'accounting-audit/evidence/payable-cash-run-'));
const serverRequire = createRequire(path.join(root, 'server/package.json'));
Object.assign(process.env, { NODE_ENV: 'test', DATABASE_PATH: run, LOG_DIR: path.join(run, 'logs'), JWT_SECRET: 'isolated-payable-cash-audit-secret', DEFAULT_ADMIN_PASSWORD: 'Isolated-audit-2026!' });
const opened = [];
const sqlitePath = serverRequire.resolve('better-sqlite3');
const NativeSqlite = serverRequire(sqlitePath);
serverRequire.cache[sqlitePath].exports = new Proxy(NativeSqlite, { construct(Target, args) {
  assert.equal(typeof args[0], 'string');
  const filename = path.resolve(args[0]);
  assert(filename.startsWith(run + path.sep), 'SQLite outside isolated fixture refused');
  opened.push(filename);
  return Reflect.construct(Target, args);
} });
serverRequire('ts-node').register({ project: path.join(root, 'server/tsconfig.json'), transpileOnly: true });
const config = serverRequire('./src/config/database');
const db = config.default;
serverRequire.cache[serverRequire.resolve('@jest/globals')] = { exports: { expect: serverRequire('expect').expect } };
const invariants = serverRequire('./src/__tests__/helpers/accountingInvariants');
const result = { run, invocation: 'node accounting-audit/tests/payable-cash-extension.cjs', opened, checks: [], requests: [], scenarios: [], gaps: ['Dedicated supplier-advance refund endpoint not found in mounted supplierPrepayments router; unused advance void exercised instead.', 'Cash-to-bank transfer and reversal not executed: dedicated route not found by bounded graph and source discovery.'] };
const write = (name, value) => fs.writeFileSync(path.join(run, name), JSON.stringify(value, null, 2));
let app, request, cookie;
const codes = ['1000', '1010', '1200', '1320', '1330', '2000', '2115', '3000', '3200', '6000'];
const collectors = ['customerArImbalances', 'supplierApImbalances', 'stockImbalances', 'arImbalances', 'apImbalances', 'inventoryImbalances', 'cashImbalances', 'orphanSourceBatches', 'unappliedLiabilityImbalances', 'creditSourceConsumptionImbalances', 'creditSourceBoundsImbalances', 'receiptAllocationImbalances', 'supplierAdvanceImbalances', 'expensePayableImbalances', 'inputTaxImbalances'];
const tables = ['settings', 'opening_balances', 'idempotency_keys', 'accounting_periods', 'journal_entries', 'journal_lines', 'suppliers', 'supplier_ledger', 'supplier_bills', 'supplier_bill_allocations', 'supplier_prepayments', 'supplier_prepayment_applications', 'payments', 'purchase_allocations', 'po_allocations', 'purchases', 'items', 'stock_movements', 'stock_batches', 'stock_balances', 'expenses', 'expense_payments', 'cash_reconciliations'];
function check(label, actual, expected) { const pass = JSON.stringify(actual) === JSON.stringify(expected); result.checks.push({ label, actual, expected, pass }); if (!pass) console.log('MISMATCH', label, JSON.stringify(actual), JSON.stringify(expected)); }
function gl(code) { return Math.round(db.prepare('SELECT COALESCE(SUM(j.debit-j.credit),0)*100 n FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE j.voided=0 AND a.code=?').get(code).n); }
function state() { const data = { accountsPaise: Object.fromEntries(codes.map(code => [code, gl(code)])) }; for (const table of tables) data[table] = db.prepare('SELECT * FROM ' + table + ' ORDER BY rowid').all(); return data; }
function hash(data) { return crypto.createHash('sha256').update(JSON.stringify(data)).digest('hex'); }
function checkpoint(label) {
  const data = state(); write(label + '.json', data);
  const observed = {}; for (const name of collectors) { observed[name] = invariants[name](db); check(label + ' ' + name, observed[name], []); }
  observed.gl = invariants.glImbalances(db); check(label + ' balanced reference groups', observed.gl.groups, []); check(label + ' aggregate balance paise', Math.round(observed.gl.totalDiff * 100), 0);
  observed.eachJournal = db.prepare('SELECT journal_entry_id,SUM(ROUND(debit*100)-ROUND(credit*100)) delta FROM journal_lines GROUP BY journal_entry_id HAVING SUM(ROUND(debit*100)-ROUND(credit*100)) != 0').all(); check(label + ' every retained journal balanced', observed.eachJournal, []);
  observed.headers = db.prepare('SELECT j.id FROM journal_lines j LEFT JOIN journal_entries h ON h.id=j.journal_entry_id WHERE h.id IS NULL OR h.voided!=j.voided').all(); check(label + ' canonical and header void status agree', observed.headers, []);
  observed.voidedSourceGl = db.prepare("SELECT j.id FROM journal_lines j WHERE j.voided=0 AND ((j.reference_type='SUPPLIER_PREPAYMENT' AND EXISTS(SELECT 1 FROM supplier_prepayments s WHERE s.id=j.reference_id AND s.voided_at IS NOT NULL)) OR (j.reference_type='EXPENSE_PAYMENT' AND EXISTS(SELECT 1 FROM expense_payments p WHERE p.id=j.reference_id AND p.voided_at IS NOT NULL)) OR (j.reference_type='EXPENSE' AND EXISTS(SELECT 1 FROM expenses e WHERE e.id=j.reference_id AND e.status='Cancelled')))").all(); check(label + ' voided sources have no active GL', observed.voidedSourceGl, []);
  observed.orphanAllocations = db.prepare('SELECT a.id FROM supplier_bill_allocations a JOIN payments p ON p.id=a.payment_id JOIN supplier_bills b ON b.id=a.bill_id WHERE a.voided_at IS NULL AND (p.voided_at IS NOT NULL OR b.voided_at IS NOT NULL) UNION ALL SELECT a.id FROM purchase_allocations a JOIN payments p ON p.id=a.payment_id JOIN purchases b ON b.id=a.purchase_id WHERE a.voided_at IS NULL AND (p.voided_at IS NOT NULL OR b.voided_at IS NOT NULL)').all(); check(label + ' active allocations retain active sources', observed.orphanAllocations, []);
  const supplierNet = db.prepare('SELECT COALESCE(SUM(current_balance),0)*100 n FROM suppliers').get().n; check(label + ' signed supplier balance matches AP', Math.round(supplierNet), -gl('2000'));
  try { invariants.expectAllInvariantsHold(label, db); observed.fullAssertion = 'PASS'; } catch (error) { observed.fullAssertion = error.message; check(label + ' A-J and extensions', error.message, 'PASS'); }
  write(label + '-invariants.json', observed); return data;
}
async function api(method, url, body, key) {
  const id = String(result.requests.length + 1).padStart(3, '0'); const before = state(); write(id + '-before.json', before);
  let req = request(app)[method](url).set('Cookie', cookie); if (key) req = req.set('Idempotency-Key', key); if (body !== undefined) req = req.send(body);
  const response = await req; const after = state(); write(id + '-after.json', after);
  result.requests.push({ id, method, url, body, key, status: response.status, response: response.body, before: id + '-before.json', after: id + '-after.json', beforeHash: hash(before), afterHash: hash(after) }); write('api-events.json', result.requests);
  if (response.status >= 400) check(id + ' rejection preserves economic and source rows', hash(after), hash(before));
  return response;
}
async function ok(method, url, body, key) { const response = await api(method, url, body, key); assert(response.status >= 200 && response.status < 300, method + ' ' + url + ' ' + response.status + ' ' + JSON.stringify(response.body)); return response.body.data ?? response.body; }
async function reject(method, url, body) { const response = await api(method, url, body); check(method + ' ' + url + ' rejected 4xx', response.status >= 400 && response.status < 500, true); }
async function scenario(name, fn) { const first = result.checks.length; const startRequest = result.requests.length + 1; try { await fn(); result.scenarios.push({ name, startRequest, endRequest: result.requests.length, status: result.checks.slice(first).every(c => c.pass) ? 'PASS' : 'FAIL' }); } catch (error) { result.scenarios.push({ name, startRequest, endRequest: result.requests.length, status: 'BLOCKED', error: error.message }); } write('results.json', result); }
async function main() {
  config.applyPendingMigrations(); await config.dbSeedReady;
  write('schema.json', db.prepare("SELECT name,sql FROM sqlite_master WHERE type='table'").all());
  app = serverRequire('./src/app').default; request = serverRequire('supertest');
  const login = await request(app).post('/api/auth/login').send({ username: 'admin', password: process.env.DEFAULT_ADMIN_PASSWORD }); assert.equal(login.status, 200); cookie = login.headers['set-cookie'].map(v => v.split(';')[0]).join('; ');
  await ok('post', '/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 1000, payment_method: 'Cash' });
  await ok('post', '/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 1000, payment_method: 'Bank' });
  await scenario('advance bill and purchase application, exact bill settlement, guards, reversal', async () => {
    const supplier = await ok('post', '/api/suppliers', { supplier_code: 'PC-SUP', supplier_name: 'Payable cash fixture' });
    const bill = await ok('post', '/api/supplier-bills', { supplier_id: supplier.id, bill_no: 'PC-BILL', bill_date: '2026-09-03', description: 'Fixture services', net_amount: 100.25, input_tax_amount: 15.04 });
    const item = await ok('post', '/api/inventory/items', { item_code: 'PC-ITEM', item_name: 'Fixture item', unit_of_measure: 'pcs' });
    const warehouse = db.prepare("SELECT id FROM warehouses WHERE warehouse_code NOT IN ('DAMAGED','EXPIRED') ORDER BY id LIMIT 1").get().id;
    const purchase = await ok('post', '/api/purchases', { item_id: item.id, supplier_id: supplier.id, warehouse_id: warehouse, purchase_date: '2026-09-03', quantity: 4, unit_cost: 12.34 });
    const baseline = checkpoint('advance-01-liabilities'); check('bill plus purchase AP paise', gl('2000'), -16465); check('bill expense paise', gl('6000'), 10025); check('bill input tax paise', gl('1320'), 1504); check('purchase stock paise', gl('1200'), 4936);
    const body = { supplier_id: supplier.id, prepay_date: '2026-09-02', amount: 200.75, payment_method: 'Cash' };
    const advance = await ok('post', '/api/supplier-prepayments', body, 'pc-create'); const replay = await ok('post', '/api/supplier-prepayments', body, 'pc-create'); check('advance replay retains id', replay.id, advance.id);
    check('advance cash debit only once paise', gl('1000'), 79925); check('advance asset paise', gl('1330'), 20075); check('advance does not net supplier AP', gl('2000'), -16465); checkpoint('advance-02-created');
    const allocation = { applied_at: '2026-09-04', allocations: [{ kind: 'supplier_bill', id: bill.id, amount: 60.13 }, { kind: 'purchase', id: purchase.id, amount: 20.11 }] };
    const applied = await ok('post', `/api/supplier-prepayments/${advance.id}/apply`, allocation, 'pc-apply'); const appliedReplay = await ok('post', `/api/supplier-prepayments/${advance.id}/apply`, allocation, 'pc-apply'); check('application replay retains id', appliedReplay.id, applied.id);
    check('application cash unchanged', gl('1000'), 79925); check('application asset remainder', gl('1330'), 12051); check('application AP remainder', gl('2000'), -8441); checkpoint('advance-03-part-applied');
    const remainingBill = await ok('post', `/api/supplier-prepayments/${advance.id}/apply`, { applied_at: '2026-09-04', allocations: [{ kind: 'supplier_bill', id: bill.id, amount: 55.16 }] });
    const billView = await ok('get', `/api/supplier-bills/${bill.id}`); check('exact bill has zero payable', billView.balance_amount, 0); check('exact bill paid paise', Math.round(billView.paid_amount * 100), 11529); check('exact bill leaves purchase AP', gl('2000'), -2925); check('advance remaining after exact bill', gl('1330'), 6535); checkpoint('advance-04-bill-settled');
    await reject('post', `/api/supplier-prepayments/${advance.id}/void`, { reason: 'Consumed advance guard' }); await reject('post', `/api/supplier-bills/${bill.id}/void`, { reason: 'Paid bill guard' });
    await reject('post', `/api/supplier-prepayments/${advance.id}/apply`, { applied_at: '2026-09-04', allocations: [{ kind: 'purchase', id: purchase.id, amount: 65.36 }] });
    await reject('post', `/api/supplier-prepayments/${advance.id}/apply`, { applied_at: '2026-09-04', allocations: [{ kind: 'supplier_bill', id: bill.id, amount: 0.01 }] }); checkpoint('advance-05-guards');
    await ok('delete', `/api/payments/${remainingBill.id}`); await ok('delete', `/api/payments/${applied.id}`); check('application reversals restore advance', gl('1330'), 20075); check('application reversals do not move cash', gl('1000'), 79925); check('application reversals restore AP', gl('2000'), -16465); checkpoint('advance-06-applications-reversed');
    await ok('post', `/api/supplier-prepayments/${advance.id}/void`, { reason: 'Unused after reversal' }); check('advance void restores baseline GL', state().accountsPaise, baseline.accountsPaise); const reversed = hash(state()); const repeat = await api('post', `/api/supplier-prepayments/${advance.id}/void`, { reason: 'Duplicate void' }); check('repeat advance void has no economic effect', hash(state()), reversed); result.scenarios.push({ name: 'advance repeat void HTTP contract', observedStatus: repeat.status, note: '200 replay observed; economic neutrality checked, no 4xx claim' }); checkpoint('advance-07-voided');
    const unused = await ok('post', '/api/supplier-prepayments', { supplier_id: supplier.id, prepay_date: '2026-09-05', amount: 25.25, payment_method: 'Bank' }); check('unused bank advance bank credit', gl('1010'), 97475); await ok('post', `/api/supplier-prepayments/${unused.id}/void`, { reason: 'Unused correction' }); check('unused bank advance restored', gl('1010'), 100000); checkpoint('advance-08-unused-bank-void');
    db.exec("CREATE TEMP TRIGGER pc_fail_gl BEFORE INSERT ON journal_lines BEGIN SELECT RAISE(ABORT,'audit intentional posting failure'); END");
    try { const failure = await api('post', '/api/supplier-prepayments', body, 'pc-failed-create'); check('injected advance GL failure rejected', failure.status >= 400, true); } finally { db.exec('DROP TRIGGER pc_fail_gl'); }
    checkpoint('advance-09-atomic-failure');
  });
  await scenario('credit expense partial and exact settlement, overpay guard, reverse and cancel', async () => {
    const baseline = checkpoint('expense-01-before'); const category = db.prepare('SELECT category_name FROM expense_categories ORDER BY id LIMIT 1').get().category_name;
    const expense = await ok('post', '/api/expenses', { expense_category: category, expense_date: '2026-09-06', amount: 120.37, payment_method: 'Credit' }); check('draft expense creates no GL', state().accountsPaise, baseline.accountsPaise);
    await ok('put', `/api/expenses/${expense.id}`, { status: 'Recorded' }); check('credit expense accrues expense paise', gl('6000') - baseline.accountsPaise['6000'], 12037); check('credit expense liability paise', gl('2115'), -12037); check('credit expense cash unchanged', gl('1000'), baseline.accountsPaise['1000']); checkpoint('expense-02-recorded');
    const partial = await ok('post', `/api/expenses/${expense.id}/payments`, { payment_date: '2026-09-07', amount: 40.12, payment_method: 'Cash' }, 'pc-expense-part'); check('partial expense cash credit', gl('1000') - baseline.accountsPaise['1000'], -4012); check('partial expense payable', gl('2115'), -8025); checkpoint('expense-03-part-paid');
    await reject('put', `/api/expenses/${expense.id}`, { status: 'Cancelled' });
    const exactBody = { payment_date: '2026-09-08', amount: 80.25, payment_method: 'Bank' }; const exact = await ok('post', `/api/expenses/${expense.id}/payments`, exactBody, 'pc-expense-exact'); const replay = await ok('post', `/api/expenses/${expense.id}/payments`, exactBody, 'pc-expense-exact'); check('expense payment replay same id', replay.id, exact.id); check('exact expense bank credit', gl('1010') - baseline.accountsPaise['1010'], -8025); check('exact expense payable zero', gl('2115'), 0); checkpoint('expense-04-settled');
    await reject('post', `/api/expenses/${expense.id}/payments`, { ...exactBody, amount: 0.01 }); await ok('post', `/api/expenses/${expense.id}/payments/${exact.id}/void`, { reason: 'Reverse bank settlement' }); check('bank settlement reversal restores payable', gl('2115'), -8025); check('bank settlement reversal restores bank', gl('1010'), baseline.accountsPaise['1010']); checkpoint('expense-05-payment-voided');
    const beforeRepeat = hash(state()); const repeat = await api('post', `/api/expenses/${expense.id}/payments/${exact.id}/void`, { reason: 'Duplicate payment void' }); check('repeat expense payment void has no effect', hash(state()), beforeRepeat); result.scenarios.push({ name: 'expense payment repeat void HTTP contract', observedStatus: repeat.status, note: '200 replay observed; economic neutrality checked, no 4xx claim' });
    db.exec("CREATE TEMP TRIGGER pc_fail_gl BEFORE INSERT ON journal_lines BEGIN SELECT RAISE(ABORT,'audit intentional posting failure'); END");
    try { const failure = await api('post', `/api/expenses/${expense.id}/payments`, exactBody, 'pc-expense-failed'); check('injected expense GL failure rejected', failure.status >= 400, true); } finally { db.exec('DROP TRIGGER pc_fail_gl'); } checkpoint('expense-06-atomic-failure');
    await ok('post', `/api/expenses/${expense.id}/payments/${partial.id}/void`, { reason: 'Reverse cash settlement' }); await ok('put', `/api/expenses/${expense.id}`, { status: 'Cancelled' }); check('cancelled expense returns all GL to baseline', state().accountsPaise, baseline.accountsPaise); check('cancelled expense preserved source', db.prepare('SELECT status FROM expenses WHERE id=?').get(expense.id).status, 'Cancelled'); checkpoint('expense-07-cancelled');
    await reject('post', `/api/expenses/${expense.id}/payments`, { ...exactBody, amount: 1 }); checkpoint('expense-08-cancelled-payment-guard');
  });
  await scenario('opening seed replacement and reconciliation count atomicity', async () => {
    const before = state().accountsPaise; await ok('put', '/api/dashboard/cash-opening-balances', { accounts: [{ key: 'cash', amount: 100.10 }, { key: 'bank', amount: 50.20 }] }); check('opening adds cash', gl('1000') - before['1000'], 10010); check('opening adds bank', gl('1010') - before['1010'], 5020); check('opening capital credit', gl('3000') - before['3000'], -15030); checkpoint('cash-01-opening');
    await ok('put', '/api/dashboard/cash-opening-balances', { accounts: [{ key: 'cash', amount: 100.10 }, { key: 'bank', amount: 50.20 }] }); check('opening rewrite no double cash', gl('1000') - before['1000'], 10010); check('opening rewrite no double bank', gl('1010') - before['1010'], 5020); checkpoint('cash-02-opening-replaced');
    const cash = gl('1000'), bank = gl('1010'); const journalBefore = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const count = await ok('post', '/api/reports/cash-reconciliation', { date: '2026-09-09', accounts: [{ key: 'cash', counted_balance: cash / 100 - 0.15, notes: 'Fixture count shortage' }, { key: 'bank', counted_balance: bank / 100 }] }); const counted = count.accounts.find(a => a.key === 'cash'); check('reconciliation independently known shortage', Math.round(counted.variance * 100), -15); check('reconciliation expected cash agrees with GL', Math.round(counted.expected_balance * 100), cash); check('reconciliation no automatic journal', db.prepare('SELECT * FROM journal_lines ORDER BY id').all(), journalBefore); checkpoint('cash-03-counted');
    await reject('post', '/api/reports/cash-reconciliation', { date: '2026-09-09', accounts: [{ key: 'cash', counted_balance: 1 }, { key: 'unknown', counted_balance: 2 }] }); checkpoint('cash-04-invalid-count-atomic');
    await ok('put', '/api/dashboard/cash-opening-balances', { accounts: [{ key: 'cash', amount: 0 }, { key: 'bank', amount: 0 }] }); check('opening zero restores GL baseline', state().accountsPaise, before); checkpoint('cash-05-opening-zeroed');
  });
  result.integrity = db.pragma('integrity_check'); result.foreignKeys = db.pragma('foreign_key_check'); check('SQLite integrity', result.integrity, [{ integrity_check: 'ok' }]); check('foreign key integrity', result.foreignKeys, []);
}
main().catch(error => { result.error = { message: error.message, stack: error.stack }; }).finally(() => {
  result.completed = !result.error && result.scenarios.every(s => !s.status || s.status === 'PASS') && result.checks.every(c => c.pass); result.failedChecks = result.checks.filter(c => !c.pass); write('results.json', result); fs.writeFileSync(path.join(root, 'accounting-audit/evidence/payable-cash-latest-run.txt'), run + '\n');
  db.close(); serverRequire('./src/middleware/rateLimiter').shutdownRateLimiters(); serverRequire('./src/utils/logger').default.close(); console.log(JSON.stringify({ run, completed: result.completed, requests: result.requests.length, checks: result.checks.length, scenarios: result.scenarios, failedChecks: result.failedChecks, error: result.error }, null, 2)); process.exitCode = result.completed ? 0 : 1;
});
