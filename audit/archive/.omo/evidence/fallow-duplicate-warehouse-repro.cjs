const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const server = path.resolve(__dirname, '../../server');
const Database = require(path.join(server, 'node_modules/better-sqlite3'));
const ts = require(path.join(server, 'node_modules/typescript'));
const directory = fs.mkdtempSync(path.join(server, '.tmp-test/maintenance-warehouse-repro-'));
const db = new Database(path.join(directory, 'erp.db'));
try {
  db.exec(`
    CREATE TABLE purchases(id INTEGER PRIMARY KEY,purchase_no TEXT,item_id INTEGER,quantity REAL,unit_cost REAL,total_cost REAL,warehouse_id INTEGER);
    CREATE TABLE stock_movements(movement_no TEXT,item_id INTEGER,warehouse_id INTEGER,movement_type TEXT,quantity REAL,unit_cost REAL,reference_doctype TEXT,reference_docno TEXT,remarks TEXT,movement_date TEXT,created_by INTEGER);
    CREATE TABLE stock_batches(id INTEGER PRIMARY KEY,source_type TEXT,source_id INTEGER,quantity_remaining REAL);
    CREATE TABLE stock_balances(id INTEGER PRIMARY KEY,item_id INTEGER,warehouse_id INTEGER,quantity REAL);
    CREATE TABLE items(id INTEGER PRIMARY KEY,current_stock REAL);
    CREATE TABLE payments(supplier_id INTEGER,amount REAL);
    INSERT INTO purchases VALUES(1,'PURCH-2026-0004',1,5,500,2500,2);
    INSERT INTO stock_batches VALUES(1,'PURCHASE',1,5);
    INSERT INTO stock_balances VALUES(1,1,1,10),(2,1,2,5);
    INSERT INTO items VALUES(1,15);
  `);
  const source = fs.readFileSync(path.join(server, 'src/scripts/fix-duplicate-purchase.ts'), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true } }).outputText;
  const localRequire = name => {
    if (name === 'better-sqlite3') return Database;
    if (name === '../models/StockMovement') return { generateMovementNo: () => 'MOV-TEST-1' };
    if (name === '../utils/serverRoot') return { defaultDbDir: () => directory };
    return require(name);
  };
  vm.runInNewContext(compiled, { require: localRequire, exports: {}, console,
    process: { env: { DATABASE_PATH: directory }, exit: code => { throw new Error(`exit ${code}`); } } });
  const movement = db.prepare('SELECT warehouse_id,quantity FROM stock_movements').get();
  console.log('Fixture purchase warehouse: 2; actual reversal:', movement);
  console.log('Actual balances:', db.prepare('SELECT warehouse_id,quantity FROM stock_balances ORDER BY warehouse_id').all());
  assert.equal(movement.warehouse_id, 2, 'Reversal must target purchase warehouse 2');
} finally {
  db.close();
  fs.rmSync(directory, { recursive: true, force: true });
}
