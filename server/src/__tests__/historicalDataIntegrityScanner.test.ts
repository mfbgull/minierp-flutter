import Database from 'better-sqlite3';
import { scanHistoricalDataIntegrity, type HistoricalIntegrityReport } from '../../scripts/historical-data-integrity';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY,
      invoice_no TEXT NOT NULL
    );
    CREATE TABLE invoice_returns (
      id INTEGER PRIMARY KEY,
      return_no TEXT NOT NULL,
      invoice_id INTEGER NOT NULL,
      returned_amount REAL NOT NULL DEFAULT 0,
      fee_amount REAL NOT NULL DEFAULT 0,
      net_amount REAL NOT NULL DEFAULT 0,
      settled_amount REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'Settled',
      voided_at TEXT
    );
    CREATE TABLE invoice_return_items (
      id INTEGER PRIMARY KEY,
      return_id INTEGER NOT NULL,
      invoice_item_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      quantity REAL NOT NULL,
      stock_movement_id INTEGER
    );
    CREATE TABLE journal_lines (
      id INTEGER PRIMARY KEY,
      reference_type TEXT,
      reference_id INTEGER,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      voided INTEGER NOT NULL DEFAULT 0,
      void_reason TEXT
    );
    CREATE TABLE items (
      id INTEGER PRIMARY KEY,
      item_code TEXT NOT NULL,
      item_name TEXT NOT NULL,
      standard_cost REAL NOT NULL DEFAULT 0
    );
    CREATE TABLE stock_movements (
      id INTEGER PRIMARY KEY,
      movement_no TEXT NOT NULL,
      item_id INTEGER NOT NULL,
      warehouse_id INTEGER NOT NULL,
      movement_type TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      batch_id INTEGER,
      reference_doctype TEXT,
      reference_docno TEXT
    );
    CREATE TABLE stock_balances (
      item_id INTEGER NOT NULL,
      warehouse_id INTEGER NOT NULL,
      quantity REAL NOT NULL DEFAULT 0
    );
    CREATE TABLE stock_batches (
      id INTEGER PRIMARY KEY,
      batch_no TEXT NOT NULL,
      item_id INTEGER NOT NULL,
      warehouse_id INTEGER NOT NULL,
      source_type TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      quantity_original REAL NOT NULL,
      quantity_remaining REAL NOT NULL,
      unit_cost REAL NOT NULL
    );
    CREATE TABLE goods_receipts (
      id INTEGER PRIMARY KEY,
      receipt_no TEXT NOT NULL,
      po_id INTEGER NOT NULL,
      receipt_date TEXT NOT NULL,
      warehouse_id INTEGER NOT NULL,
      voided_at TEXT
    );
    CREATE TABLE goods_receipt_items (
      id INTEGER PRIMARY KEY,
      receipt_id INTEGER NOT NULL,
      po_item_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      received_quantity REAL NOT NULL
    );
    CREATE TABLE purchase_order_items (
      id INTEGER PRIMARY KEY,
      po_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      unit_price REAL NOT NULL
    );
  `);
  return db;
}

function seedCorruptedFixture(db: Database.Database): void {
  const insertItem = db.prepare(
    'INSERT INTO items (id, item_code, item_name, standard_cost) VALUES (?, ?, ?, ?)',
  );
  insertItem.run(1, 'C1-A', 'C1 item A', 10);
  insertItem.run(2, 'C1-B', 'C1 item B', 10);
  insertItem.run(3, 'C2-ITEM', 'C2 item', 10);
  insertItem.run(4, 'C3-ITEM', 'C3 item', 25);
  insertItem.run(5, 'H10-ITEM', 'H10 item', 7);

  const insertInvoice = db.prepare('INSERT INTO invoices (id, invoice_no) VALUES (?, ?)');
  insertInvoice.run(1, 'INV-A');
  insertInvoice.run(2, 'INV-B');
  insertInvoice.run(3, 'INV-C');

  const insertReturn = db.prepare(`
    INSERT INTO invoice_returns
      (id, return_no, invoice_id, returned_amount, fee_amount, net_amount, settled_amount, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  insertReturn.run(1, 'RET-B', 2, 100, 0, 100, 100, 'Settled');
  insertReturn.run(2, 'RET-A', 1, 50, 0, 50, 50, 'Settled');
  insertReturn.run(3, 'RET-C', 3, 20, 0, 20, 20, 'Settled');

  const insertJournalLine = db.prepare(`
    INSERT INTO journal_lines
      (id, reference_type, reference_id, debit, credit, voided, void_reason)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  // C1 collision: Invoice A cancellation voided Invoice B's return group.
  insertJournalLine.run(1, 'INVOICE_RETURN', 1, 100, 0, 1, 'Invoice INV-A cancelled');
  insertJournalLine.run(2, 'INVOICE_RETURN', 1, 0, 100, 1, 'Invoice INV-A cancelled');
  // Same cancellation reason, but this is the return belonging to Invoice A.
  insertJournalLine.run(3, 'INVOICE_RETURN', 2, 50, 0, 1, 'Invoice INV-A cancelled');
  insertJournalLine.run(4, 'INVOICE_RETURN', 2, 0, 50, 1, 'Invoice INV-A cancelled');
  // C1 orphan: an old return GL group no longer resolves to a return document.
  insertJournalLine.run(5, 'RETURN_FEE', 99, 10, 0, 0, null);
  insertJournalLine.run(6, 'RETURN_FEE', 99, 0, 10, 0, null);

  // C2: the return says two units were restocked, but its attributed
  // movement contains only one.
  db.prepare(`
    INSERT INTO invoice_return_items
      (id, return_id, invoice_item_id, item_id, quantity, stock_movement_id)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(3, 3, 30, 3, 2, 3);
  db.prepare(`
    INSERT INTO stock_movements
      (id, movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost, batch_id, reference_doctype, reference_docno)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(3, 'STK-C2-3', 3, 1, 'RETURN', 1, 10, 10, 'RETURN', 'INV-C');

  // C3: a received PO line has stock but no active GOODS_RECEIPT GL group.
  db.prepare(`
    INSERT INTO purchase_order_items (id, po_id, item_id, unit_price)
    VALUES (?, ?, ?, ?)
  `).run(4, 4, 4, 25);
  db.prepare(`
    INSERT INTO goods_receipts
      (id, receipt_no, po_id, receipt_date, warehouse_id, voided_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(4, 'GR-C3-4', 4, '2026-01-01', 1, null);
  db.prepare(`
    INSERT INTO goods_receipt_items
      (id, receipt_id, po_item_id, item_id, received_quantity)
    VALUES (?, ?, ?, ?, ?)
  `).run(4, 4, 4, 4, 4);

  // H10: on-hand stock has no covering batch, and its inbound adjustment
  // movement is itself unbatched.
  db.prepare('INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)').run(5, 1, 5);
  db.prepare(`
    INSERT INTO stock_movements
      (id, movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost, batch_id, reference_doctype, reference_docno)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(5, 'STK-H10-5', 5, 1, 'ADJUSTMENT', 5, 7, null, 'ADJUSTMENT', 'ADJ-H10-5');
}

function snapshot(db: Database.Database): Record<string, unknown[]> {
  return {
    invoices: db.prepare('SELECT * FROM invoices ORDER BY id').all(),
    returns: db.prepare('SELECT * FROM invoice_returns ORDER BY id').all(),
    returnItems: db.prepare('SELECT * FROM invoice_return_items ORDER BY id').all(),
    journalLines: db.prepare('SELECT * FROM journal_lines ORDER BY id').all(),
    movements: db.prepare('SELECT * FROM stock_movements ORDER BY id').all(),
    balances: db.prepare('SELECT * FROM stock_balances ORDER BY item_id, warehouse_id').all(),
    batches: db.prepare('SELECT * FROM stock_batches ORDER BY id').all(),
    receipts: db.prepare('SELECT * FROM goods_receipts ORDER BY id').all(),
    receiptItems: db.prepare('SELECT * FROM goods_receipt_items ORDER BY id').all(),
  };
}

describe('historical data-integrity scanner', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = createFixture();
    seedCorruptedFixture(db);
  });

  afterEach(() => {
    db.close();
  });

  it('reports C1/C2/C3/H10 findings with document-level expected and actual values', () => {
    const report: HistoricalIntegrityReport = scanHistoricalDataIntegrity(db);
    const byCode = (code: HistoricalIntegrityReport['findings'][number]['code']): HistoricalIntegrityReport['findings'] =>
      report.findings.filter((finding) => finding.code === code);

    expect(report.mode).toBe('report-only');
    expect(report.dryRun).toBe(true);
    expect(report.backupRecommended).toBe(true);

    const c1Findings = byCode('C1');
    expect(c1Findings).toHaveLength(2);
    expect(c1Findings).toEqual(expect.arrayContaining([
      expect.objectContaining({
        check: 'return_reference_collision',
        document: 'INVOICE_RETURN',
        reference: 'RET-B',
        affectedAmount: 100,
        expected: expect.stringContaining('INV-B'),
        actual: expect.stringContaining('Invoice INV-A cancelled'),
      }),
      expect.objectContaining({
        check: 'return_reference_orphan',
        document: 'RETURN_FEE',
        reference: '99',
        affectedAmount: 10,
      }),
    ]));

    expect(byCode('C2')).toEqual([
      expect.objectContaining({
        document: 'INVOICE_RETURN',
        reference: 'RET-C',
        affectedQuantity: 1,
        affectedAmount: 10,
        expected: expect.stringContaining('2'),
        actual: expect.stringContaining('1'),
      }),
    ]);

    expect(byCode('C3')).toEqual([
      expect.objectContaining({
        document: 'GOODS_RECEIPT',
        reference: 'GR-C3-4',
        affectedQuantity: 4,
        affectedAmount: 100,
        expected: expect.stringContaining('1200'),
        actual: expect.stringContaining('0 active'),
      }),
    ]);

    const h10Findings = byCode('H10');
    expect(h10Findings.length).toBeGreaterThanOrEqual(1);
    expect(h10Findings).toEqual(expect.arrayContaining([
      expect.objectContaining({
        check: 'unbatched_stock_balance',
        document: 'STOCK_BALANCE',
        reference: '5/1',
        affectedQuantity: 5,
        affectedAmount: 35,
      }),
    ]));
  });

  it('runs against a query-only connection without changing any fixture rows', () => {
    db.pragma('query_only = 1');
    const before = JSON.stringify(snapshot(db));

    const report = scanHistoricalDataIntegrity(db);

    expect(report.findings.length).toBeGreaterThan(0);
    expect(JSON.stringify(snapshot(db))).toBe(before);
    expect(db.pragma('query_only', { simple: true })).toBe(1);
  });
});
