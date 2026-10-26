import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

describe('ledger maintenance CLI on disposable databases', () => {
  const originalPath = process.env.DATABASE_PATH;
  const originalArgv = process.argv;
  let directory: string;
  let db: Database.Database;
  let output: jest.SpyInstance;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(__dirname, '../../.tmp-test/maintenance-ledger-'));
    process.env.DATABASE_PATH = directory;
    db = new Database(path.join(directory, 'erp.db'));
    output = jest.spyOn(console, 'log').mockImplementation(() => undefined);
  });

  afterEach(() => {
    db.close();
    fs.rmSync(directory, { recursive: true, force: true });
    process.env.DATABASE_PATH = originalPath;
    process.argv = originalArgv;
    output.mockRestore();
  });

  function run(script: string, apply = false): void {
    process.argv = ['node', script, ...(apply ? ['--apply'] : [])];
    jest.isolateModules(() => { jest.requireActual<Record<string, never>>(`../../scripts/${script}.js`); });
  }

  test('date backfill preserves dry run, source-less rows, voided balances, and idempotency', () => {
    db.exec(`
      CREATE TABLE customers(id INTEGER PRIMARY KEY,current_balance REAL);
      CREATE TABLE invoices(invoice_no TEXT,invoice_date TEXT);
      CREATE TABLE payments(payment_no TEXT,payment_date TEXT);
      CREATE TABLE customer_ledger(id INTEGER PRIMARY KEY,customer_id INTEGER,transaction_type TEXT,
        reference_no TEXT,transaction_date TEXT,debit REAL,credit REAL,balance REAL,voided INTEGER);
      INSERT INTO customers VALUES(1,999);
      INSERT INTO invoices VALUES('INV-1','2026-01-02');
      INSERT INTO payments VALUES('PAY-1','2026-01-03');
      INSERT INTO customer_ledger VALUES
        (1,1,'INVOICE','INV-1','2026-02-01',100,0,999,0),
        (2,1,'PAYMENT','PAY-1','2026-01-01',0,30,999,0),
        (3,1,'OPENING_BALANCE','OPEN','2026-01-01',20,0,999,0),
        (4,1,'RETURN','MISSING','2026-01-04',0,10,999,1);
    `);
    const initial = db.prepare('SELECT * FROM customer_ledger').all();
    run('backfill-ledger-dates');
    expect(db.prepare('SELECT * FROM customer_ledger').all()).toEqual(initial);
    run('backfill-ledger-dates', true);
    expect(db.prepare('SELECT id,transaction_date,balance FROM customer_ledger ORDER BY id').all()).toEqual([
      { id: 1, transaction_date: '2026-01-02', balance: 120 },
      { id: 2, transaction_date: '2026-01-03', balance: 90 },
      { id: 3, transaction_date: '2026-01-01', balance: 20 },
      { id: 4, transaction_date: '2026-01-04', balance: 999 },
    ]);
    expect(db.prepare('SELECT current_balance FROM customers').get()).toEqual({ current_balance: 90 });
    run('backfill-ledger-dates', true);
    expect(output).toHaveBeenLastCalledWith(expect.stringContaining('nothing to do'));
  });

  test('PO dedupe appends attributed reversals once and rebuilds active balances', () => {
    db.exec(`
      CREATE TABLE suppliers(id INTEGER PRIMARY KEY,current_balance REAL);
      CREATE TABLE supplier_ledger(id INTEGER PRIMARY KEY,supplier_id INTEGER,transaction_date TEXT,
        transaction_type TEXT,reference_no TEXT,debit REAL,credit REAL,balance REAL,
        description TEXT,reversed_by INTEGER,voided INTEGER DEFAULT 0);
      INSERT INTO suppliers VALUES(1,999),(2,40);
      INSERT INTO supplier_ledger VALUES
        (1,1,'2026-01-01','PURCHASE_ORDER','PO-1',100,0,100,NULL,NULL,0),
        (2,1,'2026-01-02','PURCHASE','PUR-1',100,0,200,NULL,NULL,0),
        (3,2,'2026-01-01','PURCHASE_ORDER','PO-2',40,0,40,NULL,NULL,0);
    `);
    run('dedupe-po');
    expect(db.prepare('SELECT count(*) n FROM supplier_ledger').get()).toEqual({ n: 3 });
    run('dedupe-po', true);
    expect(db.prepare('SELECT voided FROM supplier_ledger WHERE id=1').get()).toEqual({ voided: 1 });
    expect(db.prepare('SELECT debit,credit,reversed_by,description FROM supplier_ledger WHERE id=4').get())
      .toEqual({ debit: 0, credit: 100, reversed_by: 1, description: 'PO commitment reversal (backfill)' });
    expect(db.prepare('SELECT current_balance FROM suppliers WHERE id=1').get()).toEqual({ current_balance: 0 });
    run('dedupe-po', true);
    expect(db.prepare('SELECT count(*) n FROM supplier_ledger').get()).toEqual({ n: 4 });
    expect(output).toHaveBeenLastCalledWith(expect.stringContaining('nothing to do'));
  });

  test('line recomputation handles flat/percent/tax and never changes divergent headers', () => {
    db.exec(`
      CREATE TABLE invoices(id INTEGER PRIMARY KEY,invoice_no TEXT,total_amount REAL);
      CREATE TABLE invoice_items(id INTEGER PRIMARY KEY,invoice_id INTEGER,quantity REAL,
        unit_price REAL,amount REAL,tax_rate,discount_type TEXT,discount_value);
      INSERT INTO invoices VALUES(1,'INV-1',999);
      INSERT INTO invoice_items VALUES
        (1,1,2,10,0,10,'flat',5),
        (2,1,2,10,0,'10','percent','25'),
        (3,1,2,10,0,0,'flat',100),
        (4,1,2,10,0,'bad','flat','bad'),
        (5,1,2,10,20,NULL,NULL,NULL);
    `);
    run('recompute-item-amounts');
    expect(db.prepare('SELECT amount FROM invoice_items WHERE id=1').get()).toEqual({ amount: 0 });
    run('recompute-item-amounts', true);
    expect(db.prepare('SELECT amount FROM invoice_items ORDER BY id').all())
      .toEqual([16.5,16.5,0,20,20].map(amount => ({ amount })));
    expect(db.prepare('SELECT total_amount FROM invoices').get()).toEqual({ total_amount: 999 });
    run('recompute-item-amounts', true);
    expect(output).toHaveBeenCalledWith(expect.stringContaining('5 line(s) scanned, 0 need recomputation'));
  });
});
