/**
 * Money-path regression: partial payment allocation, invoice edit after
 * payment, and parallel invoice numbering (tasks 9.2–9.4).
 *
 * The previous version of this file skipped every assertion (`if (!itemId
 * || !customerId) return;`) because no item/customer was seeded — three
 * real money paths appeared green while being completely uncovered.
 * Everything is now seeded explicitly and asserted against DB state.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, createCustomer, createInvoice, purchaseStock,
} from './helpers/invoiceReturnSpec';
import AccountingService from '../services/accountingService';

jest.setTimeout(60000);

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD must be set');

let authCookie: string;
let warehouseId: number;
let itemId: number;
let customerId: number;

beforeAll(async () => {
  authCookie = await getAuthCookie();
  expect(authCookie).not.toBe('');

  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseId = wh.id;
  itemId = await createItem('MoneyPaths Item', authCookie);
  customerId = await createCustomer('MoneyPaths Customer', authCookie);
  // Sellable stock for the invoice creates (bought on credit — cash stays
  // untouched so the payment POSTs never trip the funds guard).
  await purchaseStock(itemId, warehouseId, 100, 10, authCookie);
});

function glBalance(code: string, asOf: string): number {
  const acct = AccountingService.getAccountByCode(db, code);
  if (!acct) throw new Error(`account ${code} missing`);
  return AccountingService.getAccountBalance(db, acct.id, asOf).balance;
}

function invoiceRow(invoiceId: number) {
  return db.prepare(
    'SELECT id, invoice_no, total_amount, paid_amount, balance_amount, status FROM invoices WHERE id = ?'
  ).get(invoiceId) as {
    id: number; invoice_no: string; total_amount: number;
    paid_amount: number; balance_amount: number; status: string;
  };
}

describe('money-path suites (tasks 9.2–9.4)', () => {
  it('9.2 partial customer payment: allocations + paid/balance/status correct', async () => {
    const today = new Date().toISOString().split('T')[0];
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], invoiceDate: today, payment: null },
      authCookie,
    );
    expect(invoiceRow(inv.invoiceId).total_amount).toBeCloseTo(200, 2);

    const cashBefore = glBalance('1000', today);

    // Partial payment of 100 against a 200 invoice — via the allocation
    // API the production client uses.
    const pay = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        amount: 100,
        payment_date: today,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 100 }],
      });
    expect([200, 201]).toContain(pay.status);
    const paymentId = pay.body.data?.id ?? pay.body.id;
    expect(paymentId).toBeTruthy();

    // Allocation row exists, keyed to the right invoice, right amount
    const allocs = db.prepare(
      'SELECT payment_id, invoice_id, amount FROM payment_allocations WHERE invoice_id = ?'
    ).all(inv.invoiceId) as Array<{ payment_id: number; invoice_id: number; amount: number }>;
    expect(allocs).toHaveLength(1);
    expect(allocs[0].payment_id).toBe(paymentId);
    expect(allocs[0].amount).toBeCloseTo(100, 2);

    // Invoice header fields moved by exactly the allocation
    const row = invoiceRow(inv.invoiceId);
    expect(row.paid_amount).toBeCloseTo(100, 2);
    expect(row.balance_amount).toBeCloseTo(row.total_amount - 100, 2);
    expect(row.status).toBe('Partially Paid');

    // GL: cash moved in by exactly the payment (delta-based — the suite
    // shares one DB, so absolute AR balances include other tests' data)
    expect(glBalance('1000', today)).toBeCloseTo(cashBefore + 100, 2);

    // overpaying past the balance is refused
    const over = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        amount: 500,
        payment_date: today,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 500 }],
      });
    expect([400, 409]).toContain(over.status);
    // and the header is untouched by the refused payment
    expect(invoiceRow(inv.invoiceId).paid_amount).toBeCloseTo(100, 2);
  });

  it('9.3 invoice edit after payment keeps totals/stock/GL consistent', async () => {
    const today = new Date().toISOString().split('T')[0];
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 50 }], invoiceDate: today, payment: null },
      authCookie,
    );
    const totalBefore = invoiceRow(inv.invoiceId).total_amount;
    expect(totalBefore).toBeCloseTo(150, 2);

    // pay in full first
    const pay = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        amount: 150,
        payment_date: today,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 150 }],
      });
    expect([200, 201]).toContain(pay.status);
    const paidRow = invoiceRow(inv.invoiceId);
    expect(paidRow.status).toBe('Paid');
    expect(paidRow.paid_amount).toBeCloseTo(150, 2);
    expect(paidRow.balance_amount).toBeCloseTo(0, 2);

    const cashAtFull = glBalance('1000', today);
    const stockAtFull = (db.prepare('SELECT current_stock AS quantity FROM items WHERE id = ?').get(itemId) as { quantity: number }).quantity;

    // edit: drop one unit → new total 100. The controller allows the edit
    // and does a full void+repost (ACC-08): the invoice's INVOICE + COGS
    // lines are voided and re-posted at the new amounts, stock is reversed
    // and re-relieved, and paid_amount recomputes from the untouched
    // payment (150 paid vs 100 total → balance 0, still 'Paid').
    const edit = await request(app).put(`/api/invoices/${inv.invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: today,
        items: [{
          item_id: itemId,
          quantity: 2,
          unit_price: 50,
          discount_type: 'none',
          discount_value: 0,
        }],
      });
    expect(edit.status).toBe(200);

    const row = invoiceRow(inv.invoiceId);
    expect(row.total_amount).toBeCloseTo(100, 2);
    expect(row.paid_amount).toBeCloseTo(150, 2); // payment untouched
    expect(row.balance_amount).toBeCloseTo(0, 2); // max(0, 100 − 150)
    expect(row.status).toBe('Paid');

    // the customer's cash is not disturbed by the invoice edit
    expect(glBalance('1000', today)).toBeCloseTo(cashAtFull, 2);

    // stock: the old 3-unit sale was reversed, a 2-unit sale re-posted →
    // one more unit on the shelf than before the edit
    expect((db.prepare('SELECT current_stock AS quantity FROM items WHERE id = ?').get(itemId) as { quantity: number }).quantity)
      .toBe(stockAtFull + 1);

    // the same edit on an UNPAID invoice is allowed and re-posts cleanly:
    // totals move, stock re-relieved, GL stays balanced.
    const inv2 = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 4, unitPrice: 50 }], invoiceDate: today, payment: null },
      authCookie,
    );
    const arBeforeEdit = glBalance('1100', today);
    const edit2 = await request(app).put(`/api/invoices/${inv2.invoiceId}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: today,
        items: [{
          item_id: itemId,
          quantity: 1,
          unit_price: 50,
          discount_type: 'none',
          discount_value: 0,
        }],
      });
    expect([200, 201]).toContain(edit2.status);
    const row2 = invoiceRow(inv2.invoiceId);
    expect(row2.total_amount).toBeCloseTo(50, 2);
    expect(row2.status).toBe('Unpaid');
    // the AR re-post moved by exactly the total delta (200 → 50)
    expect(glBalance('1100', today)).toBeCloseTo(arBeforeEdit - 150, 2);

    // whole-GL balance invariant after both edits
    const imbalanced = db.prepare(`
      SELECT COUNT(*) AS n FROM (
        SELECT je.id FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        WHERE jl.voided = 0
        GROUP BY je.id
        HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.005
      )
    `).get() as { n: number };
    expect(imbalanced.n).toBe(0);
  });

  it('9.4 parallel invoice creates → unique numbers and correct stock deduction', async () => {
    const today = new Date().toISOString().split('T')[0];
    const before = db.prepare(
      `SELECT COUNT(DISTINCT invoice_no) AS d, COUNT(*) AS n FROM invoices`
    ).get() as { d: number; n: number };
    const stockBefore = (db.prepare('SELECT current_stock AS quantity FROM items WHERE id = ?').get(itemId) as { quantity: number }).quantity;

    // SQLite serializes writes, so a true deadlock race is not reachable
    // here — what IS reachable is the doc-number collision: two creates
    // generating the same invoice_no must not both succeed (the UNIQUE
    // constraint plus server-side retry/guard must keep numbers unique).
    const results = await Promise.all(Array.from({ length: 5 }, () =>
      request(app).post('/api/invoices')
        .set('Cookie', authCookie)
        .send({
          customer_id: customerId,
          invoice_date: today,
          status: 'Unpaid',
          items: [{ item_id: itemId, quantity: 1, unit_price: 10 }],
        })
    ));
    const ok = results.filter((r) => [200, 201].includes(r.status));
    expect(ok).toHaveLength(5);

    const after = db.prepare(
      `SELECT COUNT(DISTINCT invoice_no) AS d, COUNT(*) AS n FROM invoices`
    ).get() as { d: number; n: number };
    expect(after.d).toBe(after.n); // no duplicate numbers
    expect(after.n - before.n).toBe(5);

    // stock moved by exactly 5
    const stockAfter = (db.prepare('SELECT current_stock AS quantity FROM items WHERE id = ?').get(itemId) as { quantity: number }).quantity;
    expect(stockAfter).toBeCloseTo(stockBefore - 5, 2);
  });
});
