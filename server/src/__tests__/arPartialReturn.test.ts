/**
 * H4 — AR reports must not hide partially-returned debt.
 *
 * Every AR surface used to include only statuses
 * ('Unpaid','Partially Paid','Overdue'[, 'Sent']), so the moment an
 * invoice was partially returned its still-owed balance vanished from AR
 * aging / top debtors / receivables summary / dashboard while the GL and
 * the customer ledger kept carrying it. The fix (AR_OUTSTANDING in
 * utils/reportSql) decides inclusion by balance_amount > 0 and excludes
 * only Cancelled / Draft — payment state and return state stay separate.
 *
 * Pinned here:
 *  1. unpaid invoice + partial return → still in AR aging, at the
 *     remaining balance; ledger / invoice / aging / GL AR reconcile.
 *  2. fully returned (settled by the return itself) → balance 0, gone.
 *  3. partially paid + partially returned → aging row equals the
 *     remaining balance of the kept goods.
 *  4. cancelled invoice with balance > 0 → stays out of AR.
 *  5. dashboard AR summary moves with the outstanding, not the status.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, createCustomer, createInvoice, purchaseStock,
  processReturn, customerLedgerNet, getInvoiceRow,
} from './helpers/invoiceReturnSpec';
import Reports from '../models/Reports';
import Dashboard from '../models/Dashboard';
import AccountingService from '../services/accountingService';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

const AS_OF = '2026-09-30';          // covers all fixture dates incl. today's returns
const INVOICE_DATE = '2026-06-10';  // helper pins due_date to 2026-09-30

let token: string;
let warehouseId: number;
let itemId: number;

beforeAll(async () => {
  token = await getAuthCookie();
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseId = wh.id;
  itemId = await createItem('H4 AR Return Item', token);
  await purchaseStock(itemId, warehouseId, 200, 50, token);
});

type AgingRow = {
  customer_name: string; customer_code: string; total_outstanding: number;
  current_amount: number; days_1_30: number; days_31_60: number;
  days_61_90: number; days_over_90: number;
};

function agingRow(customerName: string, asOf = AS_OF): AgingRow | undefined {
  const report = Reports.getARAgingReport(asOf, db) as { agingBuckets: AgingRow[] };
  return report.agingBuckets.find((b) => b.customer_name === customerName);
}

async function seedInvoice(customerId: number): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
  return createInvoice(
    { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], invoiceDate: INVOICE_DATE, payment: null },
    token,
  );
}

function glAR(asOf = AS_OF): number {
  const acct = AccountingService.getAccountByCode(db, '1100');
  if (!acct) throw new Error('AR account 1100 missing');
  return AccountingService.getAccountBalance(db, acct.id, asOf).balance;
}

async function payAmount(invoiceId: number, amount: number, date: string): Promise<void> {
  const res = await request(app).post('/api/payments')
    .set('Cookie', token)
    .send({
      customer_id: (db.prepare('SELECT customer_id FROM invoices WHERE id = ?').get(invoiceId) as { customer_id: number }).customer_id,
      amount, payment_date: date, payment_method: 'Cash',
      invoice_allocations: [{ invoice_id: invoiceId, amount }],
    });
  expect(res.status).toBe(201);
}

describe('H4 AR surfaces keep partially-returned debt', () => {
  it('unpaid invoice with a partial return stays in AR aging at the remaining balance and reconciles', async () => {
    const customerId = await createCustomer('H4 Partial Return', token);
    const { invoiceId, invoiceItemIds } = await seedInvoice(customerId);

    // 1800 owed; the GL and ledger both carry it before any return
    expect(getInvoiceRow(invoiceId).balance_amount).toBeCloseTo(1800, 2);
    expect(customerLedgerNet(customerId)).toBeCloseTo(1800, 2);

    const arBefore = glAR();
    const ret = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [2], warehouseId,
    }, token);
    expect(ret.status).toBe(200);

    // status moved to the returned vocabulary, balance moved to 600
    const row = getInvoiceRow(invoiceId);
    expect(row.status).toBe('Partially Returned');
    expect(row.balance_amount).toBeCloseTo(600, 2);

    // H4: the debt is still in AR aging, at exactly the remaining balance
    const mine = agingRow('H4 Partial Return');
    expect(mine).toBeTruthy();
    expect(mine?.total_outstanding).toBeCloseTo(600, 2);

    // top debtors agrees, ledger agrees, GL AR dropped by exactly the
    // returned amount — all four surfaces foot
    const debtors = Reports.getTopDebtors(db, 500) as Array<{ customer_name: string; total_outstanding: number }>;
    expect((debtors.find((d) => d.customer_name === 'H4 Partial Return'))?.total_outstanding).toBeCloseTo(600, 2);
    expect(customerLedgerNet(customerId)).toBeCloseTo(600, 2);
    expect(glAR()).toBeCloseTo(arBefore - 1200, 2);

    // receivables summary: the returned-status bucket carries it
    const summary = Reports.getReceivablesSummary(db, AS_OF);
    expect(summary.statusBreakdown.partiallyReturned.amount).toBeGreaterThanOrEqual(600);
    expect(summary.statusBreakdown.partiallyReturned.count).toBeGreaterThanOrEqual(1);
    // breakdown foots to the total (modulo rows outside this file's data
    // is impossible only if every AR row maps to exactly one bucket —
    // assert the global identity instead of a fixed value)
    const parts = summary.statusBreakdown;
    const sum = parts.unpaid.amount + parts.partiallyPaid.amount + parts.overdue.amount
      + parts.sent.amount + parts.partiallyReturned.amount + parts.returned.amount;
    expect(sum).toBeCloseTo(summary.total_outstanding, 2);
  });

  it('fully returned unpaid invoice leaves AR only when its balance reaches zero', async () => {
    const customerId = await createCustomer('H4 Full Return', token);
    const { invoiceId, invoiceItemIds } = await seedInvoice(customerId);

    const ret = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [3], warehouseId,
    }, token);
    expect(ret.status).toBe(200);

    const row = getInvoiceRow(invoiceId);
    expect(row.status).toBe('Returned');
    expect(row.balance_amount).toBeCloseTo(0, 2);

    // Genuinely settled by the return itself → gone from aging, on the
    // balance, not on the status label.
    expect(agingRow('H4 Full Return')).toBeUndefined();
    expect(customerLedgerNet(customerId)).toBeCloseTo(0, 2);
  });

  it('partially paid + partially returned invoice appears at the kept-goods balance', async () => {
    const customerId = await createCustomer('H4 Paid Returned', token);
    const { invoiceId, invoiceItemIds } = await seedInvoice(customerId);

    await payAmount(invoiceId, 600, '2026-06-20');
    const ret = await processReturn(invoiceId, {
      invoiceItemIds, quantities: [1], warehouseId,
    }, token);
    expect(ret.status).toBe(200);

    const row = getInvoiceRow(invoiceId);
    expect(row.status).toBe('Partially Returned');
    // (1800 − 600 returned) − 600 paid = 600 still owed
    expect(row.balance_amount).toBeCloseTo(600, 2);

    const mine = agingRow('H4 Paid Returned');
    expect(mine).toBeTruthy();
    expect(mine?.total_outstanding).toBeCloseTo(600, 2);
    expect(customerLedgerNet(customerId)).toBeCloseTo(600, 2);
  });

  it('cancelled invoice with balance > 0 stays out of AR', async () => {
    const customerId = await createCustomer('H4 Cancelled', token);
    const { invoiceId } = await seedInvoice(customerId);

    const res = await request(app).put(`/api/invoices/${invoiceId}/cancel`).set('Cookie', token);
    expect([200, 204]).toContain(res.status);

    const row = getInvoiceRow(invoiceId);
    expect(row.status).toBe('Cancelled');
    expect(agingRow('H4 Cancelled')).toBeUndefined();
  });

  it('dashboard AR summary counts returned debt (status-blind)', async () => {
    const before = Dashboard.getARSummary(db).total_ar;
    const customerId = await createCustomer('H4 Dash Return', token);
    const { invoiceId, invoiceItemIds } = await seedInvoice(customerId);
    const mid = Dashboard.getARSummary(db).total_ar;
    expect(mid - before).toBeCloseTo(1800, 2);

    await processReturn(invoiceId, { invoiceItemIds, quantities: [2], warehouseId }, token);

    const after = Dashboard.getARSummary(db).total_ar;
    expect(after).toBeCloseTo(mid - 1200, 2);
    expect(Dashboard.getARSummary(db).customer_count).toBeGreaterThanOrEqual(1);
  });
});
