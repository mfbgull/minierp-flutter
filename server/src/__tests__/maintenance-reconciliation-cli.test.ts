import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

class ReconciliationExit extends Error {
  constructor(readonly code: number | undefined) { super(`exit ${code}`); }
}

describe('read-only reconciliation CLI', () => {
  const originalPath = process.env.DATABASE_PATH;
  let directory: string;
  let db: Database.Database;
  let output: jest.SpyInstance;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(__dirname, '../../.tmp-test/maintenance-reconciliation-'));
    process.env.DATABASE_PATH = directory;
    db = new Database(path.join(directory, 'erp.db'));
    output = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(process, 'exit').mockImplementation(code => { throw new ReconciliationExit(Number(code)); });
    db.exec(`
      CREATE TABLE items(id INTEGER PRIMARY KEY,item_code TEXT,item_name TEXT);
      CREATE TABLE warehouses(id INTEGER PRIMARY KEY,warehouse_name TEXT);
      CREATE TABLE stock_balances(item_id INTEGER,warehouse_id INTEGER,quantity REAL);
      CREATE TABLE stock_batches(item_id INTEGER,warehouse_id INTEGER,quantity_remaining REAL);
      CREATE TABLE stock_movements(id INTEGER PRIMARY KEY,item_id INTEGER,movement_no TEXT,movement_type TEXT,
        quantity REAL,unit_cost REAL,batch_id INTEGER,reference_doctype TEXT,reference_docno TEXT,movement_date TEXT);
      CREATE TABLE suppliers(id INTEGER PRIMARY KEY,supplier_name TEXT);
      CREATE TABLE purchase_orders(id INTEGER PRIMARY KEY,po_no TEXT,po_date TEXT,supplier_id INTEGER,status TEXT);
      CREATE TABLE purchase_order_items(id INTEGER PRIMARY KEY,po_id INTEGER,item_id INTEGER,quantity REAL,unit_price REAL);
      CREATE TABLE goods_receipt_items(po_item_id INTEGER,received_quantity REAL);
      CREATE TABLE purchases(id INTEGER PRIMARY KEY,purchase_no TEXT,purchase_date TEXT,item_id INTEGER,
        warehouse_id INTEGER,quantity REAL,unit_cost REAL,total_cost REAL,supplier_name TEXT);
      CREATE TABLE po_allocations(po_id INTEGER,amount REAL);
      CREATE TABLE payments(supplier_id INTEGER,amount REAL);
      INSERT INTO items VALUES(1,'ITEM-1','Test'),(2,'ITEM-2','Other');
      INSERT INTO warehouses VALUES(1,'Main');
      INSERT INTO suppliers VALUES(1,'Supplier');
      INSERT INTO stock_balances VALUES(1,1,5),(2,1,1);
      INSERT INTO stock_batches VALUES(1,1,5),(2,1,1);
      INSERT INTO purchase_orders VALUES(1,'PO-1','2026-01-01',1,'Received'),(2,'PO-2','2026-01-01',1,'Sent');
      INSERT INTO purchase_order_items VALUES(1,1,1,5,2),(2,2,1,5,2);
      INSERT INTO goods_receipt_items VALUES(1,5);
    `);
  });

  afterEach(() => {
    db.close();
    fs.rmSync(directory, { recursive: true, force: true });
    process.env.DATABASE_PATH = originalPath;
    jest.restoreAllMocks();
  });

  function run(code: number): void {
    const before = fs.readFileSync(path.join(directory, 'erp.db'));
    expect(() => jest.isolateModules(() => { jest.requireActual<Record<string, never>>('../scripts/reconcile-stock-cash'); }))
      .toThrow(new ReconciliationExit(code));
    expect(fs.readFileSync(path.join(directory, 'erp.db'))).toEqual(before);
  }

  test('returns zero for covered stock and ignores near-matches in item, quantity, cost and date', () => {
    db.exec(`INSERT INTO purchases VALUES
      (1,'PUR-1','2026-01-01',2,1,5,2,10,NULL),
      (2,'PUR-2','2026-01-01',1,1,4,2,8,NULL),
      (3,'PUR-3','2026-01-01',1,1,5,3,15,NULL),
      (4,'PUR-4','2026-01-02',1,1,5,2,10,NULL);`);
    run(0);
    expect(output).toHaveBeenLastCalledWith('  RESULT: no issues found.');
  });

  test('reports uncovered quantities, weighted costs, inbound sources and paid/unpaid duplicate matches', () => {
    db.exec(`
      DELETE FROM stock_batches;
      INSERT INTO stock_movements VALUES(1,1,'MOV-1','PURCHASE',2,3,NULL,'PURCHASE','PUR-1','2026-01-01'),
        (2,1,'MOV-2','PURCHASE',3,8,NULL,'PURCHASE','PUR-2','2026-01-02');
      INSERT INTO purchases VALUES(1,'PUR-1','2026-01-01',1,1,5,2,10,'Supplier'),
        (2,'PUR-2','2026-01-01',1,1,5,2,10,NULL);
      INSERT INTO po_allocations VALUES(1,10);
      INSERT INTO payments VALUES(1,10),(NULL,500),(1,-5);
    `);
    run(1);
    expect(output).toHaveBeenCalledWith(expect.stringContaining('5.000 UNCOVERED (~Rs 30.00 @ 6.00)'));
    expect(output).toHaveBeenCalledWith(expect.stringContaining('PO payment: paid Rs 10'));
    expect(output).toHaveBeenLastCalledWith(expect.stringContaining('4 issue(s) flagged'));
    db.exec('DELETE FROM po_allocations');
    run(1);
    expect(output).toHaveBeenCalledWith(expect.stringContaining('PO payment: not paid'));
  });
});
