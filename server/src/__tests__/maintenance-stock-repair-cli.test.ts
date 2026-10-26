import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

describe('explicit stock repair commands on fresh SQLite fixtures', () => {
  const originalPath = process.env.DATABASE_PATH;
  const originalArgv = process.argv;
  let directory: string;
  let db: Database.Database;
  let output: jest.SpyInstance;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(__dirname, '../../.tmp-test/maintenance-repair-'));
    process.env.DATABASE_PATH = path.join(directory, 'erp.db');
    db = new Database(process.env.DATABASE_PATH);
    output = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    db.exec(`
      CREATE TABLE items(id INTEGER PRIMARY KEY,standard_cost REAL);
      CREATE TABLE stock_balances(item_id INTEGER,warehouse_id INTEGER,quantity REAL);
      CREATE TABLE goods_receipt_items(id INTEGER PRIMARY KEY);
      CREATE TABLE purchases(id INTEGER PRIMARY KEY);
      CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT,updated_at TEXT);
      CREATE TABLE stock_movements(id INTEGER PRIMARY KEY,item_id INTEGER,warehouse_id INTEGER,
        movement_type TEXT,quantity REAL,unit_cost REAL,batch_id INTEGER);
      CREATE TABLE stock_batches(id INTEGER PRIMARY KEY,batch_no TEXT,item_id INTEGER,warehouse_id INTEGER,
        source_type TEXT,source_id INTEGER,quantity_original REAL,quantity_remaining REAL,unit_cost REAL,received_date TEXT);
      CREATE TABLE journal_entries(id INTEGER PRIMARY KEY,reference_type TEXT,reference_id INTEGER,entry_date TEXT,
        description TEXT,debit_account TEXT,credit_account TEXT,amount REAL,voided INTEGER);
      CREATE TABLE chart_of_accounts(id INTEGER PRIMARY KEY,code TEXT);
      CREATE TABLE journal_lines(journal_entry_id INTEGER,account_id INTEGER,debit REAL,credit REAL,description TEXT,line_date TEXT);
      INSERT INTO chart_of_accounts VALUES(1,'1200'),(2,'4999');
    `);
    jest.doMock('../config/database', () => ({ __esModule: true, default: db, applyPendingMigrations: jest.fn() }));
  });

  afterEach(() => {
    jest.dontMock('../config/database');
    db.close();
    fs.rmSync(directory, { recursive: true, force: true });
    process.env.DATABASE_PATH = originalPath;
    process.argv = originalArgv;
    output.mockRestore();
  });

  function run(command: string): void {
    process.argv = ['node', 'repair-stock', command];
    jest.isolateModules(() => { jest.requireActual<Record<string, never>>('../../scripts/repair-stock'); });
    const backups = fs.readdirSync(directory).filter(name => name.startsWith('pre-repair-'));
    expect(backups.length).toBeGreaterThan(0);
    for (const backup of backups) fs.unlinkSync(path.join(directory, backup));
  }

  test('orphan cleanup preserves quantities, invalid costs and historical links', () => {
    db.exec(`
      INSERT INTO stock_batches VALUES
        (1,'EMPTY',1,1,'PURCHASE',100,5,0,2,'2026-01-01'),
        (2,'LINKED',1,1,'PURCHASE',101,5,0.0001,2,'2026-01-01'),
        (3,'LIVE',1,1,'PURCHASE',102,5,3,2,'2026-01-01'),
        (4,'ZERO-COST',1,1,'PURCHASE',103,5,0,0,'2026-01-01'),
        (5,'ZERO-ORIGINAL',1,1,'PURCHASE',104,0,0,2,'2026-01-01');
      INSERT INTO stock_movements VALUES(1,1,1,'PURCHASE',5,2,2);
    `);
    run('orphaned-batches');
    expect(db.prepare('SELECT id,quantity_remaining FROM stock_batches ORDER BY id').all()).toEqual([
      { id: 2, quantity_remaining: 0 }, { id: 3, quantity_remaining: 3 },
      { id: 4, quantity_remaining: 0 }, { id: 5, quantity_remaining: 0 },
    ]);
    expect(db.prepare('SELECT batch_id FROM stock_movements').get()).toEqual({ batch_id: 2 });
    expect(output).toHaveBeenCalledWith(expect.stringContaining('3 flagged for manual review'));
  });

  test('empty orphan cleanup leaves all tables unchanged', () => {
    run('orphaned-batches');
    expect(db.prepare('SELECT COUNT(*) n FROM stock_batches').get()).toEqual({ n: 0 });
    expect(output).toHaveBeenLastCalledWith(expect.stringContaining('no orphaned/invalid batches'));
  });

  test('unbatched repair scopes inbound costs, balances GL, advances sequence and is idempotent', () => {
    db.exec(`
      INSERT INTO items VALUES(1,99),(2,3),(3,0);
      INSERT INTO stock_balances VALUES(1,1,5),(2,1,2),(3,1,1);
      INSERT INTO stock_movements VALUES(1,1,1,'PURCHASE',2,4,NULL),(2,1,1,'PRODUCTION',3,6,NULL),
        (3,1,2,'PURCHASE',100,999,NULL),(4,1,1,'ADJUSTMENT',100,999,NULL);
    `);
    run('unbatched-stock');
    expect(db.prepare('SELECT item_id,quantity_remaining,unit_cost FROM stock_batches ORDER BY id').all()).toEqual([
      { item_id: 1, quantity_remaining: 5, unit_cost: 5.2 },
      { item_id: 2, quantity_remaining: 2, unit_cost: 3 },
      { item_id: 3, quantity_remaining: 1, unit_cost: 0 },
    ]);
    expect(db.prepare('SELECT SUM(debit) debit,SUM(credit) credit FROM journal_lines').get())
      .toEqual({ debit: 32, credit: 32 });
    expect(db.prepare("SELECT value FROM settings WHERE key='BATCH_RECON_last_no'").get()).toEqual({ value: '3' });
    run('unbatched-stock');
    expect(db.prepare('SELECT count(*) n FROM stock_batches').get()).toEqual({ n: 3 });
    expect(db.prepare('SELECT count(*) n FROM journal_entries').get()).toEqual({ n: 2 });
  });
});
