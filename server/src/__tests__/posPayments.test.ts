/**
 * POS payment legs, discounts, tax and the closed-period guard
 * (audit-3 task 07, `server/docs/pos-payments-design.md`).
 *
 * The POS used to be a hand-rolled GL path that hardcoded account codes,
 * computed its own total, and never checked the accounting period. It is
 * now a thin adapter over `InvoiceCreationService`, so every row below is
 * really a statement that the shared service's guarantees reach the till.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { createCustomer, createItem, purchaseStock } from './helpers/invoiceReturnSpec';

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

type SaleRow = { id: number; total_amount: number; paid_amount: number; balance_amount: number; status: string };

describe('POS sale — payment legs, discount, tax, closed period', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  let customerId: number;
  let openDate: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('POS Leg Item', authCookie);
    await purchaseStock(itemId, warehouseId, 500, 10, authCookie);
    customerId = await createCustomer('POS Leg Customer', authCookie);

    const open = db.prepare(
      "SELECT period_name FROM accounting_periods WHERE status = 'open' ORDER BY start_date DESC LIMIT 1",
    ).get() as { period_name: string } | undefined;
    openDate = open ? `${open.period_name}-15` : '2026-06-15';
  });

  function sale(invoiceNo: string): SaleRow {
    return db.prepare(
      'SELECT id, total_amount, paid_amount, balance_amount, status FROM invoices WHERE invoice_no = ?',
    ).get(invoiceNo) as SaleRow;
  }

  function legsOf(invoiceId: number): Array<{ payment_method: string; amount: number }> {
    return db.prepare(`
      SELECT p.payment_method, p.amount
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      WHERE pa.invoice_id = ? AND p.voided_at IS NULL
      ORDER BY p.id
    `).all(invoiceId) as Array<{ payment_method: string; amount: number }>;
  }

  /**
   * Debit posted to `accountCode` by this invoice's payment legs, keyed off
   * the payment rows themselves. Payment GL descriptions carry the payment
   * number, not the invoice number, so matching on the invoice would miss.
   */
  function glLegDebit(accountCode: string, invoiceId: number): number {
    const row = db.prepare(`
      SELECT COALESCE(SUM(jl.debit), 0) AS total
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE coa.code = ? AND je.voided = 0 AND jl.voided = 0
        AND je.reference_type = 'PAYMENT'
        AND je.reference_id IN (
          SELECT pa.payment_id FROM payment_allocations pa WHERE pa.invoice_id = ?
        )
    `).get(accountCode, invoiceId) as { total: number };
    return Number(row.total);
  }

  function glInvoiceLine(accountCode: string, invoiceId: number): number {
    const row = db.prepare(`
      SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN chart_of_accounts coa ON coa.id = jl.account_id
      WHERE coa.code = ? AND je.voided = 0 AND jl.voided = 0
        AND je.reference_type = 'INVOICE' AND je.reference_id = ?
    `).get(accountCode, invoiceId) as { net: number };
    return Number(row.net);
  }

  async function postSale(payload: Record<string, unknown>) {
    return request(app).post('/api/pos/sale').set('Cookie', authCookie).send(payload);
  }

  function basePayload(overrides: Record<string, unknown> = {}) {
    return {
      warehouse_id: warehouseId,
      sale_date: openDate,
      customer_id: customerId,
      items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
      ...overrides,
    };
  }

  describe('R1/R2 — legacy payload is unchanged', () => {
    it('full cash sale with no new fields posts one Cash leg and marks it Paid', async () => {
      const res = await postSale(basePayload({ cash_received: 100 }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.total_amount).toBeCloseTo(100, 2);
      expect(row.paid_amount).toBeCloseTo(100, 2);
      expect(row.balance_amount).toBeCloseTo(0, 2);
      expect(row.status).toBe('Paid');
      expect(legsOf(row.id)).toHaveLength(1);
      expect(legsOf(row.id)[0].payment_method).toBe('Cash');
    });

    it('still refuses cash below the total on the legacy payload', async () => {
      const res = await postSale(basePayload({ cash_received: 40 }));
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/Insufficient cash/i);
    });
  });

  describe('R3/R4 — single leg by method', () => {
    it('accepts an Easypaisa leg and debits the mobile-wallet account', async () => {
      const res = await postSale(basePayload({ payments: [{ amount: 100, payment_method: 'Easypaisa' }] }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.status).toBe('Paid');
      expect(legsOf(row.id)[0].payment_method).toBe('Easypaisa');
      expect(glLegDebit('1020', row.id)).toBeCloseTo(100, 2);
      expect(glLegDebit('1100', row.id)).toBeCloseTo(0, 2);
    });
  });

  describe('R5/R6 — split legs', () => {
    it('records one GL entry per leg and leaves AR at zero', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 110 }],
        payments: [
          { amount: 60, payment_method: 'Cash' },
          { amount: 50, payment_method: 'Easypaisa' },
        ],
      }));
      expect(res.status).toBe(201);
      const no = res.body.data.transaction_no;
      const row = sale(no);

      expect(row.total_amount).toBeCloseTo(110, 2);
      expect(row.paid_amount).toBeCloseTo(110, 2);
      expect(row.balance_amount).toBeCloseTo(0, 2);
      expect(row.status).toBe('Paid');

      const legs = legsOf(row.id);
      expect(legs).toHaveLength(2);
      expect(glLegDebit('1000', row.id)).toBeCloseTo(60, 2);
      expect(glLegDebit('1020', row.id)).toBeCloseTo(50, 2);
      expect(glLegDebit('1100', row.id)).toBeCloseTo(0, 2);
      expect(glInvoiceLine('1100', row.id)).toBeCloseTo(110, 2);
    });

    it('handles three legs summing to the total', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 90 }],
        payments: [
          { amount: 30, payment_method: 'Cash' },
          { amount: 30, payment_method: 'Bank' },
          { amount: 30, payment_method: 'JazzCash' },
        ],
      }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(legsOf(row.id)).toHaveLength(3);
      expect(row.status).toBe('Paid');
      expect(row.balance_amount).toBeCloseTo(0, 2);
    });
  });

  describe('R7/R8 — overpayment and bad legs are refused before any write', () => {
    it('rejects legs summing above the total and writes nothing', async () => {
      const before = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      const res = await postSale(basePayload({
        payments: [
          { amount: 60, payment_method: 'Cash' },
          { amount: 60, payment_method: 'Cash' },
        ],
      }));
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/exceeds invoice total/i);
      const after = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      expect(after).toBe(before);
    });

    it('rejects an unknown payment method', async () => {
      const res = await postSale(basePayload({
        payments: [{ amount: 100, payment_method: 'Bitcoin' }],
      }));
      expect(res.status).toBe(400);
    });
  });

  describe('R9/R10 — credit and partial sales', () => {
    it('records a credit sale with payments: [] as Unpaid, AR untouched by cash', async () => {
      const res = await postSale(basePayload({ payments: [] }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.total_amount).toBeCloseTo(100, 2);
      expect(row.paid_amount).toBeCloseTo(0, 2);
      expect(row.balance_amount).toBeCloseTo(100, 2);
      expect(row.status).toBe('Unpaid');
      expect(legsOf(row.id)).toHaveLength(0);
    });

    it('records a partial settlement with the remainder outstanding', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 200 }],
        payments: [{ amount: 50, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.paid_amount).toBeCloseTo(50, 2);
      expect(row.balance_amount).toBeCloseTo(150, 2);
      expect(legsOf(row.id)).toHaveLength(1);
      // POS sets due_date = sale_date, so a dated sale is overdue once its
      // day has passed. The settlement split is what matters here; the
      // exact status word is the overdue rule's business, not this test's.
      expect(['Partially Paid', 'Overdue']).toContain(row.status);
    });
  });

  describe('R11/R12 — header discount', () => {
    it('applies an invoice-scope percentage discount without a total mismatch', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 2, unit_price: 100 }],
        discount_scope: 'invoice',
        discount_type: 'percentage',
        discount_value: 10,
        payments: [{ amount: 180, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.total_amount).toBeCloseTo(180, 2);
      expect(row.paid_amount).toBeCloseTo(180, 2);
    });

    it('clamps a discount larger than the line grosses', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 50 }],
        discount_scope: 'invoice',
        discount_type: 'flat',
        discount_value: 500,
        payments: [],
      }));
      expect(res.status).toBe(201);
      const row = sale(res.body.data.transaction_no);
      expect(row.total_amount).toBeCloseTo(0, 2);
    });
  });

  describe('R13 — tax', () => {
    it('posts tax to 2100 and revenue net of tax to 4000', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 15 }],
        payments: [{ amount: 115, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(201);
      const no = res.body.data.transaction_no;
      const row = sale(no);
      expect(row.total_amount).toBeCloseTo(115, 2);

      const tax = db.prepare(`
        SELECT COALESCE(SUM(jl.credit), 0) AS total FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN chart_of_accounts coa ON coa.id = jl.account_id
        WHERE coa.code = '2100' AND je.reference_type = 'INVOICE'
          AND je.reference_id = ? AND je.voided = 0 AND jl.voided = 0
      `).get(row.id) as { total: number };
      expect(Number(tax.total)).toBeCloseTo(15, 2);
      // Revenue is net of tax, so the two must add back to the total.
      const revenue = db.prepare(`
        SELECT COALESCE(SUM(jl.credit), 0) AS total FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN chart_of_accounts coa ON coa.id = jl.account_id
        WHERE coa.code = '4000' AND je.reference_type = 'INVOICE'
          AND je.reference_id = ? AND je.voided = 0 AND jl.voided = 0
      `).get(row.id) as { total: number };
      expect(Number(revenue.total)).toBeCloseTo(100, 2);
    });
  });

  describe('R17 — closed period (H6)', () => {
    it('refuses a sale dated inside a closed period with 409 and writes nothing', async () => {
      const period = ((): { period_name: string; start_date: string } => {
        const existing = db.prepare(
          "SELECT period_name, start_date FROM accounting_periods WHERE status = 'closed' ORDER BY end_date DESC LIMIT 1",
        ).get() as { period_name: string; start_date: string } | undefined;
        if (existing) return existing;
        const created = db.prepare(
          "INSERT INTO accounting_periods (period_name, start_date, end_date, status) VALUES ('2019-01', '2019-01-01', '2019-01-31', 'closed')",
        ).run();
        expect(created.changes).toBe(1);
        return { period_name: '2019-01', start_date: '2019-01-01' };
      })();

      const before = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      const res = await postSale(basePayload({
        sale_date: period.start_date,
        payments: [{ amount: 100, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(409);
      expect(res.body.error).toMatch(new RegExp(period.period_name));
      const after = (db.prepare('SELECT COUNT(*) AS n FROM journal_entries').get() as { n: number }).n;
      expect(after).toBe(before);
    });

    it('refuses a credit sale in a closed period too', async () => {
      const period = db.prepare(
        "SELECT start_date FROM accounting_periods WHERE status = 'closed' ORDER BY end_date DESC LIMIT 1",
      ).get() as { start_date: string };
      const res = await postSale(basePayload({ sale_date: period.start_date, payments: [] }));
      expect(res.status).toBe(409);
    });

    it('names the closed period the way assertPeriodNotClosed does', async () => {
      const period = db.prepare(
        "SELECT start_date FROM accounting_periods WHERE status = 'closed' ORDER BY end_date DESC LIMIT 1",
      ).get() as { start_date: string };
      const covering = AccountingService.getClosedPeriodCovering(db, period.start_date);
      expect(covering).toBeDefined();
    });
  });

  describe('R19/R20 — idempotent replay', () => {
    it('replays a split discounted sale with the same legs and line totals', async () => {
      const payload = basePayload({
        items: [{ item_id: itemId, quantity: 1, unit_price: 110, tax_rate: 10 }],
        discount_scope: 'invoice',
        discount_type: 'flat',
        discount_value: 10,
        payments: [
          { amount: 60, payment_method: 'Cash' },
          { amount: 49, payment_method: 'Easypaisa' },
        ],
      });
      const key = `pos-replay-${Date.now()}`;
      const first = await request(app).post('/api/pos/sale')
        .set('Cookie', authCookie)
        .set('Idempotency-Key', key)
        .send(payload);
      expect(first.status).toBe(201);
      expect(first.headers['x-idempotent-replay']).toBeUndefined();

      const second = await request(app).post('/api/pos/sale')
        .set('Cookie', authCookie)
        .set('Idempotency-Key', key)
        .send(payload);
      const third = await request(app).post('/api/pos/sale')
        .set('Cookie', authCookie)
        .set('Idempotency-Key', key)
        .send(payload);

      expect(second.status).toBe(201);
      expect(third.body.data).toEqual(first.body.data);
      expect(third.headers['x-idempotent-replay']).toBe('true');
      expect(legsOf(sale(first.body.data.transaction_no).id)).toHaveLength(2);
    });

    it('reports line_total from the stored amount, not quantity times price', async () => {
      const res = await postSale(basePayload({
        items: [{ item_id: itemId, quantity: 2, unit_price: 100, tax_rate: 10 }],
        payments: [{ amount: 220, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(201);
      const item = res.body.data.items[0];
      expect(Number(item.line_total)).toBeCloseTo(220, 2);
    });
  });

  describe('R16 — walk-in customer', () => {
    it('reuses a single WALK-IN row when no customer is sent', async () => {
      // The row is created lazily on first use, so make one sale to create
      // it, then assert the second sale reuses rather than duplicates it.
      const first = await postSale({
        warehouse_id: warehouseId,
        sale_date: openDate,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
        payments: [{ amount: 100, payment_method: 'Cash' }],
      });
      expect(first.status).toBe(201);
      const before = (db.prepare("SELECT COUNT(*) AS n FROM customers WHERE customer_code = 'WALK-IN'").get() as { n: number }).n;
      expect(before).toBe(1);

      const second = await postSale({
        warehouse_id: warehouseId,
        sale_date: openDate,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
        payments: [{ amount: 100, payment_method: 'Cash' }],
      });
      expect(second.status).toBe(201);
      const after = (db.prepare("SELECT COUNT(*) AS n FROM customers WHERE customer_code = 'WALK-IN'").get() as { n: number }).n;
      expect(after).toBe(1);
    });
  });

  describe('R21 — client total disagreement', () => {
    it('rejects a wrong total_amount with 400', async () => {
      const res = await postSale(basePayload({
        total_amount: 999,
        payments: [{ amount: 100, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/total_amount/i);
    });
  });

  describe('R25 — status is server-derived', () => {
    it('ignores a client-sent status and derives its own', async () => {
      const res = await postSale(basePayload({
        status: 'Cancelled',
        payments: [{ amount: 100, payment_method: 'Cash' }],
      }));
      expect(res.status).toBe(201);
      expect(sale(res.body.data.transaction_no).status).toBe('Paid');
    });
  });
});