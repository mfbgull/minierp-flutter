const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const server = path.join(root, 'server');
const Database = require(path.join(server, 'node_modules/better-sqlite3'));

function fingerprint(filename) {
  return fs.existsSync(filename) ? crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex') : null;
}

function exerciseSnapshot() {
  require(path.join(server, 'node_modules/ts-node/register/transpile-only'));
  const { protectDatabaseConstructor } = require(path.join(server, 'src/__tests__/helpers/liveDbGuard'));
  require.cache[require.resolve(path.join(server, 'node_modules/better-sqlite3'))].exports = protectDatabaseConstructor(Database);
  const database = require(path.join(server, 'src/config/database'));
  const db = database.default;
  const accounting = require(path.join(server, 'src/services/accountingService')).default;
  const ledger = require(path.join(server, 'src/utils/ledgerUtils')).default;
  const { UnappliedCashService } = require(path.join(server, 'src/services/unappliedCashService'));
  const checks = require(path.join(server, 'src/__tests__/helpers/accountingInvariants'));
  const names = ['glImbalances', 'customerArImbalances', 'supplierApImbalances', 'stockImbalances', 'arImbalances', 'apImbalances', 'inventoryImbalances', 'cashImbalances', 'orphanSourceBatches'];
  const capture = () => Object.fromEntries(names.map(name => {
    const result = checks[name](db);
    return [name, Array.isArray(result) ? result.map(({ label, diff }) => ({ label, diff })).sort((left, right) => left.label.localeCompare(right.label)) : result];
  }));
  const baseline = capture();
  assert.equal(baseline.arImbalances[0].diff, 1800);
  database.applyPendingMigrations();
  assert.deepEqual(capture(), baseline);
  const historical = checks.historicalCreditSourceBaseline(db);
  assert.equal(historical.length, 13);
  const service = new UnappliedCashService(db);
  const customerId = Number(db.prepare(`INSERT INTO customers (customer_code,customer_name,current_balance,credit_balance)
    VALUES ('STAGE-D-VERIFY','Stage D verification',0,0)`).run().lastInsertRowid);
  const verify = () => {
    assert.deepEqual(capture(), baseline);
    for (const name of ['unappliedLiabilityImbalances', 'creditSourceConsumptionImbalances', 'creditSourceBoundsImbalances', 'receiptAllocationImbalances']) {
      assert.deepEqual(checks[name](db), []);
    }
    assert.deepEqual(checks.historicalCreditSourceBaseline(db), historical);
    assert.deepEqual(db.pragma('foreign_key_check'), []);
  };
  const receipt = service.receive({ customerId, amount: 500, date: '2026-11-01', paymentMethod: 'Cash' });
  verify();
  const invoiceId = Number(db.prepare(`INSERT INTO invoices (invoice_no,customer_id,invoice_date,total_amount,balance_amount,paid_amount)
    VALUES ('STAGE-D-INVOICE',?,'2026-11-01',499.80,499.80,0)`).run(customerId).lastInsertRowid);
  ledger.createLedgerEntry(customerId, '2026-11-01', 'INVOICE', 'STAGE-D-INVOICE', 499.80, 0, 'Verification invoice', db);
  db.prepare('UPDATE customers SET current_balance=499.80 WHERE id=?').run(customerId);
  accounting.postEntry(db, { entry_date: '2026-11-01', description: 'Verification invoice', reference_type: 'INVOICE', reference_id: invoiceId,
    lines: [{ account_id: accounting.getAccountByCode(db, '1100').id, debit: 499.80 }, { account_id: accounting.getAccountByCode(db, '4000').id, credit: 499.80 }] });
  verify();
  service.apply({ customerId, date: '2026-11-02', applicationKey: 'stage-d-apply', allocations: [{ invoiceId, amount: 400 }] });
  assert.equal(db.prepare('SELECT current_balance FROM customers WHERE id=?').get(customerId).current_balance, 99.80);
  verify();
  service.refund({ customerId, date: '2026-11-03', amount: 100, paymentMethod: 'Cash', applicationKey: 'stage-d-refund' });
  verify();
  assert.throws(() => service.reverse(receipt.paymentId));
  const unused = service.receive({ customerId, date: '2026-11-04', amount: 50, paymentMethod: 'Cash' });
  verify();
  service.reverse(unused.paymentId, { voidReason: 'Verification reversal' });
  verify();
  const sources = db.prepare('SELECT * FROM customer_credit_sources ORDER BY id').all();
  const draws = db.prepare('SELECT * FROM credit_source_consumptions ORDER BY id').all();
  database.applyPendingMigrations();
  assert.deepEqual(db.prepare('SELECT * FROM customer_credit_sources ORDER BY id').all(), sources);
  assert.deepEqual(db.prepare('SELECT * FROM credit_source_consumptions ORDER BY id').all(), draws);
  verify();
  console.log(JSON.stringify({ stage: 'D', historicalGap: 1800, historicalSources: historical.length, baseline, checkpoints: 7, migrationReplay: true, passed: true }));
}

async function main() {
  if (process.argv[2] === '--snapshot') {
    exerciseSnapshot();
    return;
  }
  const sourcePath = process.argv[2];
  if (!sourcePath) throw new Error('Usage: node unapplied-cash-stage-d.cjs <source-db>');
  const files = [sourcePath, `${sourcePath}-wal`, `${sourcePath}-shm`];
  const before = files.map(fingerprint);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-stage-d-'));
  try {
    const source = new Database(sourcePath, { readonly: true, fileMustExist: true });
    try { await source.backup(path.join(temporary, 'erp.db')); }
    finally { source.close(); }
    const snapshotHash = fingerprint(path.join(temporary, 'erp.db'));
    const child = spawnSync(process.execPath, [__filename, '--snapshot'], {
      cwd: server, env: { ...process.env, DATABASE_PATH: temporary, NODE_ENV: 'test' }, encoding: 'utf8', timeout: 120000,
    });
    if (child.status !== 0) throw new Error(child.stderr || child.stdout || String(child.error));
    process.stdout.write(child.stdout);
    assert.deepEqual(files.map(fingerprint), before);
    console.log(JSON.stringify({ sourceFingerprintsUnchanged: true, sourceHash: before[0], snapshotHash }));
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
