/**
 * Customer credit offset — GL vs subledger consistency.
 *
 * A credit offset settles an invoice with credit the customer already holds, so
 * it moves NO cash. That credit can come from two places, recorded differently on
 * purpose:
 *
 *   1. Ledger credit from a return. The return wrote a `RETURN` credit row and
 *      left `current_balance` negative. The offset extinguishes it as the new
 *      invoice's own `INVOICE` row nets out. No extra ledger row is correct —
 *      invoiceReturnService: "Legacy 'credit' posts no settlement: the RETURN
 *      ledger row already carries the credit (credit_offset consumes it)".
 *
 *   2. The store-credit POOL (`customers.credit_balance`). Here the credit lives
 *      OFF the ledger, so consuming it must write one `CREDIT` ledger row on the
 *      credit side and decrement the pool (InvoiceCreationService).
 *
 * An audit finding claimed every offset needed its own subledger event. That is
 * wrong: under case 1 it would credit each invoice twice. These tests pin the
 * real contract — whichever source the credit came from, the customer lands at
 * the right balance, exactly one economic credit event exists per credit, and no
 * cash moves.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app).post('/api/auth/login').send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

const R2 = (n: number): number => Math.round(n * 100) / 100;

interface LedgerRow {
  id: number;
  transaction_type: string;
  debit: number;
  credit: number;
  voided: number;
}

describe('customer credit offset accounting', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `COA-${Date.now()}`, item_name: 'Credit Offset Accounting Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const supplierId = await resolveSupplierByName('Credit Offset Supplier', authCookie);
    await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId, warehouse_id: warehouseId, quantity: 60, unit_cost: 10,
        purchase_date: '2026-08-01', supplier_id: supplierId,
      });
  });

  function newCustomer(): Promise<number> {
    return request(app).post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: `Offset Acct ${Date.now()}-${Math.floor(Math.random() * 1e6)}`, phone: '555-0700' })
      .then((res) => {
        expect(res.status).toBe(201);
        return res.body.data?.id ?? res.body.id;
      });
  }

  /** Sell on account, collect in full, then return the goods as ledger credit. */
  async function seedLedgerCredit(customerId: number, qty: number, date: string): Promise<number> {
    const inv = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: date, due_date: date,
        items: [{ item_id: itemId, description: 'item', quantity: qty, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: qty * 100,
        record_payment: true,
        payment: { payment_date: date, amount: qty * 100, payment_method: 'Cash' },
      });
    expect(inv.status).toBe(201);

    const invItem = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(inv.body.id) as { id: number };
    const ret = await request(app).post(`/api/invoices/${inv.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'seed ledger credit', disposition: 'credit', warehouse_id: warehouseId,
        items: [{ invoice_item_id: invItem.id, return_quantity: qty }],
      });
    expect(ret.status).toBe(200);
    return qty * 100;
  }

  /** Sell on account, collect in full, then settle the return into the pool. */
  async function seedPoolCredit(customerId: number, qty: number, date: string): Promise<number> {
    const inv = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId, invoice_date: date, due_date: date,
        items: [{ item_id: itemId, description: 'item', quantity: qty, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: qty * 100,
        record_payment: true,
        payment: { payment_date: date, amount: qty * 100, payment_method: 'Cash' },
      });
    expect(inv.status).toBe(201);

    const invItem = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(inv.body.id) as { id: number };
    const ret = await request(app).post(`/api/invoices/${inv.body.id}/return`)
      .set('Cookie', authCookie)
      .send({
        reason: 'seed pool credit', warehouse_id: warehouseId,
        items: [{ invoice_item_id: invItem.id, return_quantity: qty }],
        settlements: [{ type: 'credit', amount: qty * 100 }],
      });
    expect(ret.status).toBe(200);
    return qty * 100;
  }

  function ledgerRows(customerId: number): LedgerRow[] {
    return db.prepare(
      'SELECT id, transaction_type, debit, credit, voided FROM customer_ledger WHERE customer_id = ? ORDER BY id'
    ).all(customerId) as LedgerRow[];
  }

  function ledgerNet(customerId: number): number {
    return R2((db.prepare(
      'SELECT COALESCE(SUM(debit - credit),0) AS n FROM customer_ledger WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL'
    ).get(customerId) as { n: number }).n);
  }

  function position(customerId: number): { current_balance: number; credit_balance: number } {
    return db.prepare('SELECT current_balance, COALESCE(credit_balance,0) AS credit_balance FROM customers WHERE id = ?')
      .get(customerId) as { current_balance: number; credit_balance: number };
  }

  describe('offset drawn from ledger credit (negative current_balance)', () => {
    let customerId: number;
    let offsetInvoiceId: number;

    beforeAll(async () => {
      customerId = await newCustomer();
      await seedLedgerCredit(customerId, 2, '2026-09-01');

      // The credit sits on the ledger; the pool is untouched.
      expect(R2(position(customerId).current_balance)).toBe(-200);
      expect(R2(position(customerId).credit_balance)).toBe(0);

      const inv = await request(app).post('/api/invoices')
        .set('Cookie', authCookie)
        .send({
          customer_id: customerId, invoice_date: '2026-09-10', due_date: '2026-09-24',
          items: [{ item_id: itemId, description: 'item', quantity: 2, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
          total_amount: 200, credit_offset: 200,
        });
      expect(inv.status).toBe(201);
      offsetInvoiceId = inv.body.id;
    });

    it('posts Dr 1110 / Cr 1100 and moves no cash', () => {
      const lines = db.prepare(`
        SELECT c.code, jl.debit, jl.credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN chart_of_accounts c ON c.id = jl.account_id
        WHERE je.reference_type = 'CREDIT_OFFSET' AND je.reference_id = ? AND jl.voided = 0`).all(offsetInvoiceId) as
        Array<{ code: string; debit: number; credit: number }>;

      expect(R2(lines.reduce((s, l) => s + l.debit, 0))).toBe(200);
      expect(R2(lines.reduce((s, l) => s + l.credit, 0))).toBe(200);
      expect(lines.find((l) => l.debit > 0)?.code).toBe('1110');
      expect(lines.find((l) => l.credit > 0)?.code).toBe('1100');

      // No cash account may be touched by a credit-offset entry.
      const cashTouched = db.prepare(`
        SELECT COUNT(*) AS n
        FROM journal_lines jl JOIN chart_of_accounts c ON c.id = jl.account_id
        WHERE c.code IN ('1000','1010','1020') AND jl.voided = 0
          AND jl.journal_entry_id IN (
            SELECT je.id FROM journal_entries je WHERE je.reference_type = 'CREDIT_OFFSET')`).get() as { n: number };
      expect(cashTouched.n).toBe(0);
    });

    it('settles the invoice to zero with exactly ONE economic credit event', () => {
      const inv = db.prepare('SELECT total_amount, paid_amount, balance_amount, credit_offset FROM invoices WHERE id = ?')
        .get(offsetInvoiceId) as { total_amount: number; paid_amount: number; balance_amount: number; credit_offset: number };

      expect(inv.credit_offset).toBe(200);
      expect(R2(inv.balance_amount)).toBe(0);

      // The seed invoice was collected in cash and then returned, so it leaves a
      // PAYMENT credit and a RETURN credit. The offset must add NO further credit:
      // no CREDIT row (the pool was empty) and no CREDIT_OFFSET row.
      const credits = ledgerRows(customerId).filter((r) => !r.voided && r.credit > 0);
      expect(credits.map((r) => r.transaction_type).sort()).toEqual(['PAYMENT', 'RETURN']);
      expect(R2(credits.filter((r) => r.transaction_type === 'RETURN')[0].credit)).toBe(200);
      expect(ledgerRows(customerId).filter((r) => r.transaction_type === 'CREDIT' && !r.voided)).toHaveLength(0);
      expect(ledgerRows(customerId).filter((r) => r.transaction_type === 'CREDIT_OFFSET' && !r.voided)).toHaveLength(0);

      const pos = position(customerId);
      expect(R2(pos.current_balance)).toBe(0);
      expect(R2(pos.credit_balance)).toBe(0);
      expect(ledgerNet(customerId)).toBe(R2(pos.current_balance));
    });
  });

  describe('offset drawn from the store-credit pool', () => {
    let customerId: number;
    let offsetInvoiceId: number;

    beforeAll(async () => {
      customerId = await newCustomer();
      await seedPoolCredit(customerId, 2, '2026-10-01');

      // The credit now sits in the pool, off the ledger.
      expect(R2(position(customerId).credit_balance)).toBe(200);
      expect(R2(position(customerId).current_balance)).toBe(0);

      const inv = await request(app).post('/api/invoices')
        .set('Cookie', authCookie)
        .send({
          customer_id: customerId, invoice_date: '2026-10-10', due_date: '2026-10-24',
          items: [{ item_id: itemId, description: 'item', quantity: 2, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
          total_amount: 200, credit_offset: 200,
        });
      expect(inv.status).toBe(201);
      offsetInvoiceId = inv.body.id;
    });

    it('writes exactly one CREDIT ledger row and draws the pool down', () => {
      const rows = ledgerRows(customerId).filter((r) => !r.voided);

      // Two CREDIT rows, opposite legs: the conversion debit (ledger -> pool) and
      // the consumption credit (pool -> ledger). Only the latter settles the invoice.
      const creditRows = rows.filter((r) => r.transaction_type === 'CREDIT');
      expect(creditRows).toHaveLength(2);
      const consumption = creditRows.filter((r) => r.credit > 0);
      expect(consumption).toHaveLength(1);
      expect(R2(consumption[0].credit)).toBe(200);
      expect(R2(consumption[0].debit)).toBe(0);

      const pos = position(customerId);
      expect(R2(pos.credit_balance)).toBe(0);
      expect(ledgerNet(customerId)).toBe(R2(pos.current_balance));

      const inv = db.prepare('SELECT balance_amount FROM invoices WHERE id = ?').get(offsetInvoiceId) as { balance_amount: number };
      expect(R2(inv.balance_amount)).toBe(0);

      // No CREDIT_OFFSET row: pool consumption already moved the ledger.
      expect(rows.filter((r) => r.transaction_type === 'CREDIT_OFFSET')).toHaveLength(0);
    });
  });

  it('holds GL AR (1100+1110) equal to customer balances, with the ledger as subledger authority', () => {
    const customers = db.prepare('SELECT id, current_balance FROM customers').all() as Array<{ id: number; current_balance: number }>;
    for (const c of customers) {
      expect(ledgerNet(c.id)).toBe(R2(c.current_balance));
    }

    const gl = db.prepare(`
      SELECT COALESCE(SUM(jl.debit - jl.credit),0) AS bal
      FROM journal_lines jl JOIN chart_of_accounts c ON c.id = jl.account_id
      WHERE c.code IN ('1100','1110') AND jl.voided = 0`).get() as { bal: number };
    const agg = db.prepare(
      'SELECT COALESCE(SUM(current_balance),0) AS rec, COALESCE(SUM(credit_balance),0) AS sc FROM customers'
    ).get() as { rec: number; sc: number };

    expect(R2(Math.abs(gl.bal))).toBe(R2(Math.abs(R2(agg.rec) - R2(agg.sc))));
  });
});
