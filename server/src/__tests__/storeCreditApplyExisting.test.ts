/**
 * Store credit applied to EXISTING invoices from the customer screen.
 *
 * Lifecycle: sale → return settled as store credit → separate open unpaid
 * invoice → POST /api/customers/:id/store-credit/apply with per-invoice
 * allocations. The pool drains FIFO through return settlements, the invoice
 * credit_offset grows, and GL, customer ledger and invoice status stay
 * consistent. Rejections write nothing. Repeats of the same Idempotency-Key
 * replay without a second draw.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, customerLedgerNet, glTotalsFor, assertGlBalanced,
} from './helpers/invoiceReturnSpec';
import { arImbalances } from './helpers/accountingInvariants';

interface CustomerRow { current_balance: number; credit_balance: number }
interface InvoiceRow { status: string; paid_amount: number; balance_amount: number; credit_offset: number }

const customerRow = (id: number): CustomerRow => db.prepare(
  'SELECT current_balance, COALESCE(credit_balance, 0) AS credit_balance FROM customers WHERE id = ?'
).get(id) as CustomerRow;

const invoiceRow = (id: number): InvoiceRow => db.prepare(
  'SELECT status, paid_amount, balance_amount, credit_offset FROM invoices WHERE id = ?'
).get(id) as InvoiceRow;

const drawsFor = (invoiceId: number): { count: number; minor: number } => db.prepare(
  'SELECT COUNT(*) AS count, COALESCE(SUM(amount_minor), 0) AS minor FROM store_credit_draws WHERE invoice_id = ?'
).get(invoiceId) as { count: number; minor: number };

function apply(
  customerId: number, key: string, operationDate: string,
  allocations: { invoice_id: number; amount: number }[],
) {
  return request(app)
    .post(`/api/customers/${customerId}/store-credit/apply`)
    .set('Cookie', authCookie!)
    .set('Idempotency-Key', key)
    .send({ operation_date: operationDate, allocations });
}

let authCookie: string;
let itemId: number;
let customerId: number;
let otherCustomerId: number;
let warehouseId: number;
let openInvoiceId: number;
let openInvoiceNo: string;

describe('store credit applied to existing invoices', () => {
  beforeAll(async () => {
    authCookie = await getAuthCookie();
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Widget ApplySC', authCookie);
    await purchaseStock(itemId, warehouseId, 40, 10, authCookie);
    customerId = await createCustomer('Apply Credit Customer', authCookie);
    otherCustomerId = await createCustomer('Other Credit Customer', authCookie);

    // Seed the pool: sell 2 × 100, paid in full, return both as store credit.
    const paid = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], payment: 'full' }, authCookie);
    const ret = await processReturn(paid.invoiceId, {
      invoiceItemIds: paid.invoiceItemIds, quantities: [2], warehouseId,
      settlements: [{ type: 'credit', amount: 200 }],
    }, authCookie);
    expect(ret.status).toBe(200);
    expect(customerRow(customerId).credit_balance).toBeCloseTo(200, 2);

    // An open, wholly unpaid invoice to receive the credit later.
    const open = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 100 }] }, authCookie);
    openInvoiceId = open.invoiceId;
    openInvoiceNo = open.invoiceNo;
  });

  it('rejects an allocation to another customer\'s invoice and writes nothing', async () => {
    const foreign = await createInvoice(
      { customerId: otherCustomerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }] }, authCookie);
    const res = await apply(customerId, 'sca-foreign-000001', '2026-09-20',
      [{ invoice_id: foreign.invoiceId, amount: 50 }]);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_ALLOCATION');
    expect(customerRow(customerId).credit_balance).toBeCloseTo(200, 2);
    expect(drawsFor(foreign.invoiceId).count).toBe(0);
  });

  it('rejects an operation date before the invoice date', async () => {
    const res = await apply(customerId, 'sca-earlydate-0001', '2000-01-01',
      [{ invoice_id: openInvoiceId, amount: 10 }]);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_INVOICE');
  });

  it('applies a partial amount: pool, invoice, GL and subledger all move together', async () => {
    const res = await apply(customerId, 'sca-partial-000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 150 }]);
    expect(res.status).toBe(200);
    const applicationId = res.body.data.applicationId as number;
    expect(applicationId).toBeGreaterThan(0);

    const cust = customerRow(customerId);
    expect(cust.credit_balance).toBeCloseTo(50, 2);
    expect(cust.current_balance).toBeCloseTo(150, 2);

    const inv = invoiceRow(openInvoiceId);
    expect(inv.credit_offset).toBeCloseTo(150, 2);
    expect(inv.balance_amount).toBeCloseTo(150, 2);
    expect(inv.status).toBe('Partially Paid');

    const draws = drawsFor(openInvoiceId);
    expect(draws.minor).toBe(15000);

    assertGlBalanced('CREDIT_OFFSET', openInvoiceId);
    expect(glTotalsFor('CREDIT_OFFSET', openInvoiceId).debit).toBeGreaterThanOrEqual(150);
    expect(customerLedgerNet(customerId)).toBeCloseTo(cust.current_balance, 2);

    // The consumption ledger row follows the CREDIT-<invoice_no> reference
    // pattern the return-reversal guard scans for.
    const ledgerRef = db.prepare(
      "SELECT COALESCE(SUM(credit), 0) AS c FROM customer_ledger WHERE customer_id=? AND transaction_type='CREDIT' AND reference_no=? AND voided=0"
    ).get(customerId, `CREDIT-${openInvoiceNo}`) as { c: number };
    expect(ledgerRef.c).toBeCloseTo(150, 2);

    // The draw must be attributable to this application.
    const linked = db.prepare(
      'SELECT COUNT(*) AS n FROM store_credit_draws WHERE invoice_id=? AND application_id=?'
    ).get(openInvoiceId, applicationId) as { n: number };
    expect(linked.n).toBeGreaterThan(0);
  });

  it('replays the same Idempotency-Key and payload without a second draw', async () => {
    const res = await apply(customerId, 'sca-partial-000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 150 }]);
    expect(res.status).toBe(200);
    expect(customerRow(customerId).credit_balance).toBeCloseTo(50, 2);
    expect(invoiceRow(openInvoiceId).credit_offset).toBeCloseTo(150, 2);
  });

  it('rejects the same key reused for a different payload', async () => {
    const res = await apply(customerId, 'sca-partial-000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 10 }]);
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('IDEMPOTENCY_CONFLICT');
  });

  it('rejects an allocation above the invoice balance', async () => {
    const res = await apply(customerId, 'sca-overbal-0000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 200 }]);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVOICE_OVERALLOCATION');
  });

  it('rejects an application above the remaining pool', async () => {
    const res = await apply(customerId, 'sca-overpool-000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 60 }]);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INSUFFICIENT_STORE_CREDIT');
  });

  it('applies the last of the pool and leaves the invoice remainder open', async () => {
    const res = await apply(customerId, 'sca-final-00000001', '2026-09-20',
      [{ invoice_id: openInvoiceId, amount: 50 }]);
    expect(res.status).toBe(200);
    expect(customerRow(customerId).credit_balance).toBeCloseTo(0, 2);
    const inv = invoiceRow(openInvoiceId);
    expect(inv.credit_offset).toBeCloseTo(200, 2);
    expect(inv.balance_amount).toBeCloseTo(100, 2);
    expect(inv.status).toBe('Partially Paid');
    expect(customerLedgerNet(customerId)).toBeCloseTo(customerRow(customerId).current_balance, 2);
    expect(arImbalances()).toEqual([]);
  });
});
