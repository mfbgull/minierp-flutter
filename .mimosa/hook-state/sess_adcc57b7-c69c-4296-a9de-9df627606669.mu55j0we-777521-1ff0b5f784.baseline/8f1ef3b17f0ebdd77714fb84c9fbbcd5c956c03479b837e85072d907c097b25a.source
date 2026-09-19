/**
 * Ledger integrity + reconciliation tests (gl-posting-completeness §4-§8).
 *
 * 4.4  Append-only ledgers: reversal row pairs, no reachable DELETE,
 *      counterparty-scoped reference operations.
 * 5.5  Backdated insert lands in (transaction_date, id) position; stored
 *      balance column equals the statement footing.
 * 6.3  current_balance always equals the ledger-derived figure.
 * 7.5  Inflated client total → 400 with nothing written; legit totals pass;
 *      discount/tax reflected in stored amounts.
 * 8.2  Reconciliation: clean fixture reconciles within 0.01; drift shows.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import ledgerUtils from '../utils/ledgerUtils';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

function ledgerRows(table: 'customer_ledger' | 'supplier_ledger', where: string, ...params: unknown[]) {
  return db.prepare(`SELECT * FROM ${table} WHERE ${where}`).all(...params) as Array<Record<string, unknown>>;
}

describe('ledger integrity and reconciliation', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let customerId2: number;
  let warehouseId: number;
  let counter = Date.now() % 100000;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get() as { id: number }).id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `LGR-${Date.now()}`, item_name: 'Ledger Integrity Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const supplierRes = await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 500,
        unit_cost: 10,
        purchase_date: '2026-05-01',
        supplier_name: 'Ledger Integrity Supplier',
      });
    expect(supplierRes.status).toBe(201);

    for (const name of ['Ledger Customer One', 'Ledger Customer Two']) {
      const c = await request(app).post('/api/customers')
        .set('Cookie', authCookie)
        .send({ customer_name: name, phone: `555-${counter}` });
      expect(c.status).toBe(201);
      if (!customerId) {
        customerId = c.body.data?.id ?? c.body.id;
      } else {
        customerId2 = c.body.data?.id ?? c.body.id;
      }
    }
  });
  async function createInvoice(customerIdArg: number, totalAmount: number, date: string): Promise<{ invoiceId: number; invoiceNo: string }> {
    counter += 1;
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-LGR-${counter}`,
        customer_id: customerIdArg,
        invoice_date: date,
        due_date: date,
        status: 'Unpaid',
        items: [{ item_id: itemId, quantity: totalAmount / 100, unit_price: 100, warehouse_id: warehouseId }],
      });
    expect(res.status).toBe(201);
    return { invoiceId: res.body.id as number, invoiceNo: res.body.invoice_no as string };
  }

  // ------------------------------------------------------------------
  // 4.4 Append-only ledger
  // ------------------------------------------------------------------

  it('invoice delete leaves voided original plus REVERSAL rows — no DELETE', async () => {
    const { invoiceId, invoiceNo } = await createInvoice(customerId, 200, '2026-07-01');

    const beforeCount = ledgerRows(
      'customer_ledger',
      'customer_id = ? AND reference_no = ? AND transaction_type = ?',
      customerId, invoiceNo, 'INVOICE'
    ).length;
    expect(beforeCount).toBe(1);

    const del = await request(app).delete(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie);
    expect(del.status).toBe(200);

    // Original row survives, voided; a REVERSAL pair exists.
    const original = db.prepare(
      `SELECT voided FROM customer_ledger WHERE customer_id = ? AND reference_no = ? AND transaction_type = 'INVOICE'`
    ).get(customerId, invoiceNo) as { voided: number };
    expect(Number(original.voided)).toBe(1);

    const reversal = db.prepare(
      `SELECT id, reversed_by FROM customer_ledger WHERE customer_id = ? AND transaction_type LIKE 'REVERSAL:%' AND reference_no = ?`
    ).get(customerId, invoiceNo) as { id: number; reversed_by: number } | undefined;
    expect(reversal).toBeDefined();
  });

  it('a colliding reference across customers affects only the owning party', async () => {
    // Seed two ledger rows with the same reference_no but different customers.
    const collisionRef = `COLLIDE-${counter}`;
    const seed = (custId: number): number => {
      const r = db.prepare(`
        INSERT INTO customer_ledger (customer_id, transaction_date, transaction_type, reference_no, debit, credit, balance)
        VALUES (?, ?, 'INVOICE', ?, 50, 0, 50)
      `).run(custId, '2026-07-02', collisionRef);
      return r.lastInsertRowid as number;
    };
    const ownRowId = seed(customerId);
    const otherRowId = seed(customerId2);

    // Reversal scoped by counterparty touches only the owner's row.
    const InvoiceModel = (await import('../models/Invoice')).default;
    InvoiceModel.deleteLedgerEntryByReference(db, collisionRef, customerId);

    const ownVoided = (db.prepare('SELECT voided FROM customer_ledger WHERE id = ?').get(ownRowId) as { voided: number }).voided;
    const otherVoided = (db.prepare('SELECT voided FROM customer_ledger WHERE id = ?').get(otherRowId) as { voided: number }).voided;
    expect(Number(ownVoided)).toBe(1);
    expect(Number(otherVoided)).toBe(0);

    // Cleanup the untouched decoy so later tests see a clean chain.
    db.prepare('DELETE FROM customer_ledger WHERE id = ?').run(otherRowId);
    db.prepare('DELETE FROM customer_ledger WHERE reversed_by = ?').run(ownRowId);
  });

  // ------------------------------------------------------------------
  // 5.5 Ledger chain truth
  // ------------------------------------------------------------------

  it('backdated insert lands in date position and footing equals stored balances', async () => {
    // Chain: invoice on 2026-06-10 (300), payment on 2026-06-20 (100).
    const invA = await createInvoice(customerId2, 300, '2026-06-10');
    expect(invA.invoiceId).toBeGreaterThan(0);
    const pay = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId2,
        payment_date: '2026-06-20',
        amount: 100,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invA.invoiceId, amount: 100 }],
      });
    expect([200, 201]).toContain(pay.status);

    // Backdated invoice between them (150 on 2026-06-15).
    const invB = await createInvoice(customerId2, 150, '2026-06-15');

    const rows = ledgerRows(
      'customer_ledger',
      'customer_id = ? AND voided = 0 ORDER BY transaction_date ASC, id ASC',
      customerId2
    ) as Array<{ transaction_date: string; debit: number; credit: number; balance: number }>;

    const dates = rows.map(r => r.transaction_date);
    expect(dates.indexOf('2026-06-15')).toBeGreaterThan(-1);
    expect(dates.indexOf('2026-06-20')).toBeGreaterThan(dates.indexOf('2026-06-15'));

    // Statement footing: running sum over non-voided rows in date order
    // must equal every stored balance value, including the backdated one.
    let running = 0;
    for (const row of rows) {
      running += Number(row.debit) - Number(row.credit);
      expect(Number(row.balance)).toBeCloseTo(running, 2);
    }
    // The final stored balance is also what recalc derives.
    const derived = ledgerUtils.recalcCustomerBalanceFromLedger(customerId2);
    expect(derived).toBeCloseTo(running, 2);
  });

  // ------------------------------------------------------------------
  // 6.3 Single balance writer
  // ------------------------------------------------------------------

  it('current_balance equals the ledger-derived figure after mutations', async () => {
    const preExistingBalance = ledgerUtils.recalcCustomerBalanceFromLedger(customerId);

    const inv = await createInvoice(customerId, 400, '2026-05-01');

    const pay = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        payment_date: '2026-05-05',
        amount: 250,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 250 }],
      });
    expect([200, 201]).toContain(pay.status);

    const stored = (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance;
    // Contract (6.3): whatever mutations happened before, current_balance
    // must equal the ledger-derived figure exactly.
    const derived = ledgerUtils.recalcCustomerBalanceFromLedger(customerId);
    expect(Number(stored)).toBeCloseTo(derived, 2);

    // Sanity: this test's own two rows net to 400 − 250 = 150 against the
    // pre-existing chain position captured above.
    expect(derived).toBeCloseTo(preExistingBalance + 150, 2);
  });

  // ------------------------------------------------------------------
  // 7.5 Server-authoritative totals
  // ------------------------------------------------------------------

  it('inflated client total is rejected with nothing written', async () => {
    const invoicesBefore = (db.prepare('SELECT COUNT(*) AS c FROM invoices').get() as { c: number }).c;
    const movementsBefore = (db.prepare('SELECT COUNT(*) AS c FROM stock_movements').get() as { c: number }).c;
    const linesBefore = (db.prepare('SELECT COUNT(*) AS c FROM journal_lines').get() as { c: number }).c;

    counter += 1;
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-LGR-BAD-${counter}`,
        customer_id: customerId,
        invoice_date: '2026-07-10',
        due_date: '2026-07-10',
        total_amount: 100000, // line items sum to 100
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toContain('total_amount disagrees with line items');

    expect((db.prepare('SELECT COUNT(*) AS c FROM invoices').get() as { c: number }).c).toBe(invoicesBefore);
    expect((db.prepare('SELECT COUNT(*) AS c FROM stock_movements').get() as { c: number }).c).toBe(movementsBefore);
    expect((db.prepare('SELECT COUNT(*) AS c FROM journal_lines').get() as { c: number }).c).toBe(linesBefore);
  });

  it('discount and tax are reflected in the stored line amount and header', async () => {
    counter += 1;
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-LGR-DISC-${counter}`,
        customer_id: customerId,
        invoice_date: '2026-07-12',
        due_date: '2026-07-12',
        // Flutter-shaped legitimate total: qty×price=200, 10% discount → 180, 5% tax → 189
        total_amount: 189,
        items: [{
          item_id: itemId,
          quantity: 2,
          unit_price: 100,
          discount_type: 'percentage',
          discount_value: 10,
          tax_rate: 5,
          warehouse_id: warehouseId,
        }],
      });
    expect(res.status).toBe(201);

    const line = db.prepare(
      'SELECT amount FROM invoice_items WHERE invoice_id = ?'
    ).get(res.body.id) as { amount: number };
    expect(Number(line.amount)).toBeCloseTo(189, 2);

    const header = db.prepare(
      'SELECT total_amount FROM invoices WHERE id = ?'
    ).get(res.body.id) as { total_amount: number };
    expect(Number(header.total_amount)).toBeCloseTo(189, 2);
  });

  it('invoice-scope header discount nets into the accepted/stored total', async () => {
    counter += 1;
    // Form contract: gross 200, invoice-scope flat discount 50 → grand
    // total 150. Before computeInvoiceGrandTotal this was rejected as a
    // mismatch because the header discount was ignored.
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-LGR-INVDC-${counter}`,
        customer_id: customerId,
        invoice_date: '2026-07-13',
        due_date: '2026-07-13',
        status: 'Unpaid',
        discount_scope: 'invoice',
        discount_type: 'flat',
        discount_value: 50,
        total_amount: 150,
        items: [{
          item_id: itemId,
          quantity: 2,
          unit_price: 100,
          warehouse_id: warehouseId,
        }],
      });
    expect(res.status).toBe(201);

    const header = db.prepare(
      'SELECT total_amount FROM invoices WHERE id = ?'
    ).get(res.body.id) as { total_amount: number };
    expect(Number(header.total_amount)).toBeCloseTo(150, 2);
  });

  it('loose amount-driven line bills the entered amount, not qty × price', async () => {
    counter += 1;
    // Flip-model loose line (§5.2): the user billed a flat 60 for
    // 1.75 units — qty × price would disagree by design.
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        invoice_no: `INV-LGR-LOOSE-${counter}`,
        customer_id: customerId,
        invoice_date: '2026-07-14',
        due_date: '2026-07-14',
        status: 'Unpaid',
        total_amount: 60,
        items: [{
          item_id: itemId,
          quantity: 1.75,
          unit_price: 33.333,
          amount: 60,
          warehouse_id: warehouseId,
        }],
      });
    expect(res.status).toBe(201);

    const line = db.prepare(
      'SELECT amount FROM invoice_items WHERE invoice_id = ?'
    ).get(res.body.id) as { amount: number };
    expect(Number(line.amount)).toBeCloseTo(60, 2);
  });

  // ------------------------------------------------------------------
  // 8.2 Reconciliation report
  // ------------------------------------------------------------------

  it('reconciliation endpoint returns GL vs operational pairs', async () => {
    const res = await request(app).get('/api/accounting/reconciliation')
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);

    const pairings = res.body.data.pairings as Array<{ pairing: string; account_code: string; gl_balance: number; operational_balance: number; delta: number }>;
    expect(pairings.length).toBeGreaterThanOrEqual(4);

    const inventory = pairings.find(p => p.account_code === '1200');
    expect(inventory).toBeDefined();
    expect(typeof inventory!.gl_balance).toBe('number');
    expect(typeof inventory!.operational_balance).toBe('number');

    // Clean seeded fixture: purchases post to the GL now, sales consume
    // FIFO cost — inventory delta must reconcile within tolerance.
    expect(Math.abs(inventory!.delta)).toBeLessThanOrEqual(0.01);
  });
});
