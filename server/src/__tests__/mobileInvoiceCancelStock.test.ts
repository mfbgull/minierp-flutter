/**
 * TASK 17 — mobile invoice cancellation must restore stock.
 *
 * Audit finding: the mobile submit path keyed its SALE stock movements to
 * the invoice ID while the shared cancellation/reversal primitive resolves
 * them by invoice NUMBER, so `reverseStockForItems` found no SALE movements,
 * skipped the ADJUSTMENT restore, and left stock permanently reduced on
 * every cancelled mobile invoice (the GL void and the CANCELLATION ledger
 * credit had already run, so only the physical/batch leg was lost).
 *
 * Required regression, run end-to-end through the mobile submit endpoint:
 *   1. create a mobile invoice for 10 units → stock = original − 10
 *   2. cancel it                     → stock returns exactly to original
 *   3. GL reversal (INVOICE group voided) and ledger reversal (net 0)
 *   4. repeat the cancellation       → rejected, no double restoration
 *   5. invoices with similar identifiers: cancelling one leaves the
 *      other's stock, movements and GL byte-for-byte intact
 *
 * The second describe pins the one-time backfill that repairs databases
 * populated before the convention was normalized.
 */
import request from 'supertest';
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer,
  glTotalsFor, customerLedgerNet,
} from './helpers/invoiceReturnSpec';
import { runBackfillMobileInvoiceStockReference } from '../migrations/backfillMobileInvoiceStockReference';

// ── shared fixtures ────────────────────────────────────────────────────
describe('TASK 17: mobile invoice cancellation restores stock', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  function mobileBody(qty: number) {
    return {
      customer_id: customerId,
      invoice_date: '2026-09-10',
      due_date: '2026-09-24',
      items: [{
        item_id: itemId,
        quantity: qty,
        unit_price: 100,
        tax_rate: 0,
        discount_type: 'percentage',
        discount_value: 0,
      }],
    };
  }

  async function submitMobile(qty: number): Promise<{ invoiceId: number; invoiceNo: string }> {
    const res = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send(mobileBody(qty));
    if (res.status !== 201) throw new Error(`mobile submit failed: ${res.status} ${JSON.stringify(res.body)}`);
    return { invoiceId: res.body.data.id, invoiceNo: res.body.data.invoice_no };
  }

  function batchQty(): number {
    return (db.prepare(
      'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ?'
    ).get(itemId) as { q: number }).q;
  }

  function balanceQty(): number {
    return (db.prepare(
      'SELECT COALESCE(SUM(quantity), 0) AS q FROM stock_balances WHERE item_id = ?'
    ).get(itemId) as { q: number }).q;
  }

  function saleMovementCount(invoiceNo: string): number {
    return (db.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements
       WHERE reference_doctype = 'INVOICE' AND movement_type = 'SALE' AND reference_docno = ?`
    ).get(invoiceNo) as { c: number }).c;
  }

  function cancelMovementCount(invoiceNo: string): number {
    return (db.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements
       WHERE reference_doctype = 'INVOICE_CANCEL' AND movement_type = 'ADJUSTMENT' AND reference_docno = ?`
    ).get(invoiceNo) as { c: number }).c;
  }

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Widget T17 Mobile Cancel', authCookie);
    await purchaseStock(itemId, warehouseId, 100, 100, authCookie);
    customerId = await createCustomer('T17 Mobile Cancel Customer', authCookie);
  });

  it('consumes the sold quantity and keys the SALE movement to invoice_no', async () => {
    const baseline = batchQty();
    const { invoiceId, invoiceNo } = await submitMobile(10);

    // Requirement 1: stock = original − 10.
    expect(batchQty()).toBeCloseTo(baseline - 10, 6);
    // The convention the fix normalizes: the reversal resolves SALE
    // movements by invoice_no, so the write must key to invoice_no.
    expect(saleMovementCount(invoiceNo)).toBe(1);
    expect((db.prepare('SELECT reference_docno FROM stock_movements WHERE reference_doctype = ? AND movement_type = ? AND reference_docno = ?')
      .get('INVOICE', 'SALE', invoiceNo) as { reference_docno: string }).reference_docno).toBe(invoiceNo);
    expect(Number(glTotalsFor('INVOICE', invoiceId).debit)).toBeGreaterThan(0);
  });

  it('cancelling restores stock exactly, voids the GL and nets the ledger', async () => {
    const baseline = batchQty();
    const ledgerBefore = customerLedgerNet(customerId);
    const { invoiceId, invoiceNo } = await submitMobile(10);
    expect(batchQty()).toBeCloseTo(baseline - 10, 6);

    const res = await request(app)
      .put(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', authCookie)
      .send({});
    expect(res.status).toBe(200);

    // Requirement 2: stock returns exactly to the original level — on both
    // the batch ledger and the balance summary the UI reads.
    expect(batchQty()).toBeCloseTo(baseline, 6);
    expect(balanceQty()).toBeCloseTo(baseline, 6);

    // Requirement 3: GL reversal — the whole INVOICE group (revenue + COGS)
    // is voided, and exactly one stock-restoration movement was written.
    expect(glTotalsFor('INVOICE', invoiceId)).toEqual({ debit: 0, credit: 0 });
    expect(cancelMovementCount(invoiceNo)).toBe(1);

    // Requirement 3: ledger reversal — the INVOICE debit is nettied by the
    // append-only CANCELLATION credit, so the customer's net position is
    // back where it started.
    expect(customerLedgerNet(customerId)).toBeCloseTo(ledgerBefore, 2);

    const row = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(row.status).toBe('Cancelled');
  });

  it('repeating the cancellation is rejected and restores nothing twice', async () => {
    const baseline = batchQty();
    const { invoiceId, invoiceNo } = await submitMobile(10);
    expect(batchQty()).toBeCloseTo(baseline - 10, 6);

    const first = await request(app).put(`/api/invoices/${invoiceId}/cancel`).set('Cookie', authCookie).send({});
    expect(first.status).toBe(200);
    expect(batchQty()).toBeCloseTo(baseline, 6);

    // Requirement 4: the second attempt is a 4xx, and stock does not move
    // a second time (no second ADJUSTMENT restore, quantity unchanged).
    const second = await request(app).put(`/api/invoices/${invoiceId}/cancel`).set('Cookie', authCookie).send({});
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expect(second.body.error).toMatch(/already cancelled/i);

    expect(batchQty()).toBeCloseTo(baseline, 6);
    expect(balanceQty()).toBeCloseTo(baseline, 6);
    expect(cancelMovementCount(invoiceNo)).toBe(1);
  });

  it('invoices with similar identifiers: cancelling one leaves the other intact', async () => {
    // Requirement 5: consecutive submissions take consecutive document
    // numbers (INV-…-000N / INV-…-000N+1) while their invoice IDs are also
    // adjacent — the exact neighbourhood where an id/number confusion
    // would cross-wire two invoices.
    const baseline = batchQty();
    const a = await submitMobile(10);
    const b = await submitMobile(5);
    const aNum = parseInt(a.invoiceNo.split('-').pop() as string, 10);
    const bNum = parseInt(b.invoiceNo.split('-').pop() as string, 10);
    expect(bNum - aNum).toBe(1);
    expect(a.invoiceId).not.toBe(b.invoiceId);
    expect(batchQty()).toBeCloseTo(baseline - 15, 6); // A took 10, B took 5

    const res = await request(app).put(`/api/invoices/${a.invoiceId}/cancel`).set('Cookie', authCookie).send({});
    expect(res.status).toBe(200);

    // Invoice A's own stock is restored…
    expect(batchQty()).toBeCloseTo(baseline - 5, 6);
    expect(cancelMovementCount(a.invoiceNo)).toBe(1);
    expect(glTotalsFor('INVOICE', a.invoiceId)).toEqual({ debit: 0, credit: 0 });

    // …and Invoice B is untouched: stock still consumed, SALE movements
    // still keyed to ITS number, GL still active, status still live, and
    // no restoration movement written against it.
    expect(batchQty()).not.toBeCloseTo(baseline, 6);
    expect(saleMovementCount(b.invoiceNo)).toBe(1);
    expect(Number(glTotalsFor('INVOICE', b.invoiceId).debit)).toBeGreaterThan(0);
    expect(cancelMovementCount(b.invoiceNo)).toBe(0);
    const bRow = db.prepare('SELECT status FROM invoices WHERE id = ?').get(b.invoiceId) as { status: string };
    expect(bRow.status).not.toBe('Cancelled');

    // B can still be cancelled on its own terms — the neighbour's cancel
    // consumed nothing of B's reversal.
    const bCancel = await request(app).put(`/api/invoices/${b.invoiceId}/cancel`).set('Cookie', authCookie).send({});
    expect(bCancel.status).toBe(200);
    expect(batchQty()).toBeCloseTo(baseline, 6);
    expect(cancelMovementCount(b.invoiceNo)).toBe(1);
  });
});

// ── one-time repair of databases populated before the fix ─────────────
describe('TASK 17 backfill: re-keys legacy mobile movements and restores cancelled stock', () => {
  const MIGRATIONS = [
    'init.sql',
    'add-batch-costing.sql',
    'add-stock-adjustment-financial.sql',
    'add-gl-foundation.sql',
  ];

  function makeDb(): Database.Database {
    const fixture = new Database(':memory:');
    fixture.pragma('foreign_keys = ON');
    for (const f of MIGRATIONS) {
      fixture.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
    }
    // Columns the boot migration adds programmatically (guarded by
    // pragma_table_info in config/database.ts), so the fixture has to add
    // them itself — reverseStockForItems writes batch_id on the restore.
    fixture.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
    fixture.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
                     VALUES ('u','e@x.c','h','U','admin',1)`).run();
    fixture.prepare(`INSERT INTO customers (customer_code,customer_name,is_active)
                     VALUES ('C1','Legacy Cust',1)`).run();
    fixture.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active)
                     VALUES ('WH-001','Main',1)`).run();
    fixture.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
                     VALUES ('T17','T17 Item','Nos',50,1,1)`).run();
    return fixture;
  }

  // Reproduce the buggy write: a mobile invoice whose SALE movement is keyed
  // to the invoice ID, plus a desktop invoice keyed to its number.
  function seedLegacy(fixture: Database.Database): void {
    fixture.prepare(`INSERT INTO invoices (id, invoice_no, customer_id, invoice_date, due_date, status,
                                            total_amount, paid_amount, balance_amount, created_by)
                     VALUES (7, 'INV-0926-00007', 1, '2026-09-08', '2026-09-08', 'Cancelled', 500, 0, 500, 1),
                            (8, 'INV-0926-00008', 1, '2026-09-09', '2026-09-09', 'Unpaid',   600, 0, 600, 1)`).run();
    fixture.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
                     VALUES (7, 1, 10, 50, 500), (8, 1, 12, 50, 600)`).run();
    fixture.prepare(`INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
                                                 quantity_original, quantity_remaining, unit_cost, received_date)
                     VALUES ('B1', 1, 1, 'PURCHASE', 1, 100, 90, 50, '2026-09-01')`).run(); // 10 consumed by invoice 7
    fixture.prepare(`INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (1, 1, 90)`).run();
    // Mobile path: StockMovementModel.recordBatchMovement prefixes the
    // remarks with the batch-consumption line and links batch_id — the sale
    // was keyed to the numeric invoice id '7' instead of its number.
    fixture.prepare(`INSERT INTO stock_movements (movement_no, item_id, warehouse_id, movement_type, quantity,
                                                   unit_cost, reference_doctype, reference_docno, remarks,
                                                   movement_date, created_by, batch_id)
                     VALUES ('STK-1', 1, 1, 'SALE', -10, 50, 'INVOICE', '7',
                             'Batch: 1 - 10 @ 50 | Sold via Invoice 7', '2026-09-08', 1, 1),
                            ('STK-2', 1, 1, 'SALE', -12, 50, 'INVOICE', 'INV-0926-00008',
                             'Sold via Invoice INV-0926-00008 (batch 1)', '2026-09-09', 1, 1)`).run();
  }
  it('re-keys the mobile reference and restores the cancelled invoice stock', () => {
    const fixture = makeDb();
    seedLegacy(fixture);

    runBackfillMobileInvoiceStockReference(fixture);

    // Step 1: the mobile SALE movement now carries the invoice NUMBER —
    // the key the (fixed) reversal path resolves.
    const mobileRef = fixture.prepare(
      `SELECT reference_docno FROM stock_movements WHERE movement_no = 'STK-1'`
    ).get() as { reference_docno: string };
    expect(mobileRef.reference_docno).toBe('INV-0926-00007');

    // Step 2: the stock the cancelled sale took comes back — batch and
    // balance ledgers, plus the INVOICE_CANCEL movement the fixed cancel
    // would have written.
    const batch = fixture.prepare(
      'SELECT quantity_remaining AS q FROM stock_batches WHERE batch_no = ?'
    ).get('B1') as { q: number };
    expect(batch.q).toBe(100);
    const bal = fixture.prepare(
      'SELECT quantity AS q FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1'
    ).get() as { q: number };
    expect(bal.q).toBe(100);
    const cancelMov = fixture.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements
       WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = 'INV-0926-00007'`
    ).get() as { c: number };
    expect(cancelMov.c).toBe(1);
  });

  it('leaves desktop-keyed movements and live invoices untouched', () => {
    const fixture = makeDb();
    seedLegacy(fixture);

    runBackfillMobileInvoiceStockReference(fixture);

    const desktopRef = fixture.prepare(
      `SELECT reference_docno FROM stock_movements WHERE movement_no = 'STK-2'`
    ).get() as { reference_docno: string };
    expect(desktopRef.reference_docno).toBe('INV-0926-00008');

    // The live (non-cancelled) invoice gained no phantom restoration and
    // no stock was added on its behalf.
    const liveCancel = fixture.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements
       WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = 'INV-0926-00008'`
    ).get() as { c: number };
    expect(liveCancel.c).toBe(0);
    const bal = fixture.prepare(
      'SELECT quantity AS q FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1'
    ).get() as { q: number };
    expect(bal.q).toBe(100); // only invoice 7's 10 units restored
  });

  it('is idempotent: a second run changes nothing', () => {
    const fixture = makeDb();
    seedLegacy(fixture);

    runBackfillMobileInvoiceStockReference(fixture);
    const afterFirst = fixture.prepare(
      `SELECT reference_docno, quantity FROM stock_movements
       JOIN (SELECT 1) AS x ON 1=1 ORDER BY id`
    ).all();
    const batchAfterFirst = (fixture.prepare(
      'SELECT quantity_remaining AS q FROM stock_batches WHERE batch_no = ?'
    ).get('B1') as { q: number }).q;

    runBackfillMobileInvoiceStockReference(fixture);

    const afterSecond = fixture.prepare(
      `SELECT reference_docno, quantity FROM stock_movements ORDER BY id`
    ).all();
    expect(afterSecond).toEqual(afterFirst);
    const batchAfterSecond = (fixture.prepare(
      'SELECT quantity_remaining AS q FROM stock_batches WHERE batch_no = ?'
    ).get('B1') as { q: number }).q;
    expect(batchAfterSecond).toBe(batchAfterFirst);
    const cancelCount = (fixture.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL'`
    ).get() as { c: number }).c;
    expect(cancelCount).toBe(1);
  });

  it('is a no-op on a database already written with the fixed convention', () => {
    const fixture = makeDb();
    // Fixed write path: SALE movement keyed to invoice_no from the start.
    fixture.prepare(`INSERT INTO invoices (id, invoice_no, customer_id, invoice_date, due_date, status,
                                            total_amount, paid_amount, balance_amount, created_by)
                     VALUES (9, 'INV-0926-00009', 1, '2026-09-08', '2026-09-08', 'Unpaid', 500, 0, 500, 1)`).run();
    fixture.prepare(`INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
                     VALUES (9, 1, 10, 50, 500)`).run();
    fixture.prepare(`INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
                                                 quantity_original, quantity_remaining, unit_cost, received_date)
                     VALUES ('B2', 1, 1, 'PURCHASE', 1, 100, 90, 50, '2026-09-01')`).run();
    fixture.prepare(`INSERT INTO stock_movements (movement_no, item_id, warehouse_id, movement_type, quantity,
                                                   unit_cost, reference_doctype, reference_docno, remarks,
                                                   movement_date, created_by)
                     VALUES ('STK-3', 1, 1, 'SALE', -10, 50, 'INVOICE', 'INV-0926-00009',
                             'Batch: 1 - 10 @ 50 | Sold via Invoice INV-0926-00009', '2026-09-08', 1)`).run();

    runBackfillMobileInvoiceStockReference(fixture);

    const ref = fixture.prepare(`SELECT reference_docno FROM stock_movements WHERE movement_no = 'STK-3'`)
      .get() as { reference_docno: string };
    expect(ref.reference_docno).toBe('INV-0926-00009');
    const cancelCount = (fixture.prepare(
      `SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL'`
    ).get() as { c: number }).c;
    expect(cancelCount).toBe(0);
  });
});
