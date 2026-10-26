import Database from 'better-sqlite3';
import { spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import db from '../config/database';
import PurchaseModel from '../models/Purchase';
import SupplierModel from '../models/Supplier';

describe('duplicate-purchase repair CLI on current-schema copies', () => {
  const serverRoot = path.resolve(__dirname, '../..');
  let directory: string;
  let fixture: Database.Database;
  let purchaseId: number;
  let itemId: number;
  let warehouseId: number;
  let supplierId: number;

  beforeAll(() => {
    supplierId = SupplierModel.create({ supplier_code: 'DUP-CLI-SUP', supplier_name: 'Repair fixture' }, db);
    itemId = Number(db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,standard_cost) VALUES('DUP-CLI','Repair fixture','pcs',500)").run().lastInsertRowid);
    warehouseId = Number(db.prepare("INSERT INTO warehouses(warehouse_code,warehouse_name) VALUES('DUP-CLI-WH','Second warehouse')").run().lastInsertRowid);
    const number = jest.spyOn(PurchaseModel, 'generatePurchaseNo').mockReturnValue('PURCH-2026-0004');
    try {
      purchaseId = PurchaseModel.recordPurchase({ item_id: itemId, warehouse_id: warehouseId,
        supplier_id: supplierId, quantity: 5, unit_cost: 500, purchase_date: '2026-08-01' }, 1, db).id;
    } finally { number.mockRestore(); }
    PurchaseModel.recordPurchase({ item_id: itemId, warehouse_id: 1, supplier_id: supplierId,
      quantity: 10, unit_cost: 500, purchase_date: '2026-08-01' }, 1, db);
  });

  beforeEach(async () => {
    directory = fs.mkdtempSync(path.join(serverRoot, '.tmp-test/duplicate-cli-'));
    await db.backup(path.join(directory, 'erp.db'));
    fixture = new Database(path.join(directory, 'erp.db'));
  });

  afterEach(() => {
    fixture.close();
    fs.rmSync(directory, { recursive: true, force: true });
  });

  function run(apply = true, databasePath = directory) {
    return spawnSync(process.execPath, [path.join(serverRoot, 'node_modules/ts-node/dist/bin.js'),
      '--transpile-only', 'src/scripts/fix-duplicate-purchase.ts', ...(apply ? ['--apply'] : [])], {
      cwd: serverRoot, env: { ...process.env, DATABASE_PATH: databasePath, TS_NODE_PROJECT: 'tsconfig.test.json' },
      encoding: 'utf8', timeout: 60_000,
    });
  }

  test('voids in the purchase warehouse and preserves row, batch, GL and attribution', () => {
    expect(warehouseId).not.toBe(1);
    expect(fixture.prepare("SELECT COUNT(*) n FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=? AND voided=0").get(purchaseId))
      .toEqual({ n: 2 });
    const result = run();
    expect({ status: result.status, stderr: result.stderr }).toEqual({ status: 0, stderr: '' });
    expect(fixture.prepare('SELECT warehouse_id,quantity FROM stock_balances WHERE item_id=? ORDER BY warehouse_id').all(itemId))
      .toEqual([{ warehouse_id: 1, quantity: 10 }, { warehouse_id: warehouseId, quantity: 0 }]);
    expect(fixture.prepare('SELECT voided_at,voided_by FROM purchases WHERE id=?').get(purchaseId))
      .toEqual({ voided_at: expect.any(String), voided_by: 1 });
    expect(fixture.prepare("SELECT quantity_remaining FROM stock_batches WHERE source_type='PURCHASE' AND source_id=?").get(purchaseId))
      .toEqual({ quantity_remaining: 0 });
    expect(fixture.prepare("SELECT COUNT(*) n FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=? AND voided=0").get(purchaseId))
      .toEqual({ n: 0 });
    expect(fixture.prepare("SELECT voided FROM journal_entries WHERE reference_type='PURCHASE' AND reference_id=?").all(purchaseId))
      .toEqual([{ voided: 1 }]);
    expect(fixture.prepare(`SELECT SUM(jl.debit-jl.credit) balance FROM journal_lines jl
      JOIN chart_of_accounts coa ON coa.id=jl.account_id WHERE jl.voided=0 AND coa.code='1200'`).get())
      .toEqual({ balance: 5000 });
    expect(fixture.prepare(`SELECT transaction_type,voided FROM supplier_ledger
      WHERE reference_no='PURCH-2026-0004' ORDER BY id`).all())
      .toEqual([{ transaction_type: 'PURCHASE', voided: 1 }, { transaction_type: 'REVERSAL:PURCHASE', voided: 0 }]);
    expect(fixture.prepare("SELECT quantity,warehouse_id FROM stock_movements WHERE reference_doctype='PURCHASE_VOID' AND reference_docno='PURCH-2026-0004'").get())
      .toEqual({ quantity: -5, warehouse_id: warehouseId });
    expect(fixture.prepare("SELECT action FROM activity_log WHERE entity_type='Purchase' AND entity_id=? AND action='VOID'").get(purchaseId))
      .toEqual({ action: 'VOID' });
    expect(fixture.prepare('SELECT current_balance FROM suppliers WHERE id=?').get(supplierId)).toEqual({ current_balance: 5000 });
    const backups = fs.readdirSync(directory).filter(name => /\.backup-\d+-\d+$/.test(name));
    expect(backups).toHaveLength(1);
    const snapshot = new Database(path.join(directory, backups[0]), { readonly: true });
    try {
      expect(snapshot.prepare('SELECT voided_at FROM purchases WHERE id=?').get(purchaseId)).toEqual({ voided_at: null });
    } finally { snapshot.close(); }
    expect(run().status).toBe(0);
    expect(fixture.prepare("SELECT COUNT(*) n FROM stock_movements WHERE reference_doctype='PURCHASE_VOID'").get()).toEqual({ n: 1 });
    expect(fs.readdirSync(directory).filter(name => /\.backup-\d+-\d+$/.test(name))).toHaveLength(1);
  }, 130_000);

  test('defaults to a read-only preview without a backup or database changes', () => {
    const before = fixture.serialize();
    const result = run(false);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain('Read-only preview');
    expect(fixture.serialize()).toEqual(before);
    expect(fs.readdirSync(directory).filter(name => /\.backup-\d+-\d+$/.test(name))).toHaveLength(0);
  }, 70_000);

  test.each([
    ['', 'Set DATABASE_PATH'],
    [path.join(serverRoot, 'database'), 'Refusing the canonical live database'],
  ])('refuses unsafe database selection %s before opening it', (databasePath, message) => {
    const result = run(true, databasePath);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain(message);
  }, 70_000);

  test('rejects a linked active payment without changing purchase economics', () => {
    const payment = fixture.prepare(`INSERT INTO payments(payment_no,supplier_id,payment_date,amount,payment_method)
      VALUES('DUP-CLI-PAY',?,'2026-08-01',500,'Cash')`).run(supplierId);
    fixture.prepare('INSERT INTO purchase_allocations(payment_id,purchase_id,amount) VALUES(?,?,500)')
      .run(payment.lastInsertRowid, purchaseId);
    const before = fixture.serialize();
    const result = run();
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('recorded payments');
    expect(fixture.serialize()).toEqual(before);
  }, 70_000);

  test('rejects a consumed batch without modifying the remaining stock or GL', () => {
    fixture.prepare("UPDATE stock_batches SET quantity_remaining=4 WHERE source_type='PURCHASE' AND source_id=?").run(purchaseId);
    const before = fixture.serialize();
    const result = run();
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('already sold/consumed');
    expect(fixture.serialize()).toEqual(before);
  }, 70_000);

  test('missing target is a no-op without schema initialization or a backup', () => {
    fixture.prepare("UPDATE purchases SET purchase_no='OTHER-PURCHASE' WHERE id=?").run(purchaseId);
    const before = fixture.serialize();
    const result = run();
    expect(result.status).toBe(0);
    expect(result.stdout).toContain('nothing to fix');
    expect(fixture.serialize()).toEqual(before);
    expect(fs.readdirSync(directory).filter(name => /\.backup-\d+-\d+$/.test(name))).toHaveLength(0);
  }, 70_000);
});
