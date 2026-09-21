/**
 * H8 — payment date/method edits must keep the books in step
 * (payment-edit-gl-integrity).
 *
 * PaymentModel.update used to change only the payments row and leave the
 * books behind:
 *   - a date edit moved the payment but kept the journal entry AND the
 *     subledger row on the old date,
 *   - a customer method change reposted the GL, but a supplier method
 *     change did not (the GL kept crediting the old cash account), and
 *   - only the OLD date was checked against closed periods, so a payment
 *     could be dragged into a closed period.
 *
 * Every case the audit called out is pinned here.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, createCustomer, createInvoice, purchaseStock, EPSILON,
  processReturn, settlementsFor,
} from './helpers/invoiceReturnSpec';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import AccountingService from '../services/accountingService';
import { getCashAccountTotals } from '../services/cashService';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

// Cash / bank GL account chosen for a payment method
// (AccountingService._cashOrBankAccountCode).
const AR_CODE = '1100';
const AP_CODE = '2000';

let token: string;
let warehouseId: number;
let itemId: number;

beforeAll(async () => {
  token = await getAuthCookie();
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseId = wh.id;
  itemId = await createItem('H8 Payment Edit Item', token);
  // sellable stock for the customer invoices (bought on credit — cash is
  // left untouched so the seeded capital is what the tests see)
  await purchaseStock(itemId, warehouseId, 200, 20, token);

  // Seed operating cash in Cash AND Bank so supplier payments clear the
  // funds guard and every bucket starts above zero. (The repost an edit
  // performs does not re-run the funds check, so only the initial create
  // needs the balance.)
  const seed = (method: string, amount: number, date: string) =>
    OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, date),
      capital_date: date,
      amount,
      payment_method: method,
      note: 'H8 test seed',
      created_by: 1,
    });
  seed('Cash', 100000, '2026-01-02');
  seed('Bank', 100000, '2026-01-03');
});

// ────────────────────────────────────────────────────────────────────
// helpers
// ────────────────────────────────────────────────────────────────────

function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: Record<string, unknown>) {
  return request(app)[method](url).set('Cookie', token).send(body);
}

type GlLine = {
  id: number;
  entry_date: string;
  line_date: string;
  account_code: string;
  debit: number;
  credit: number;
  voided: number;
};

function paymentGlLines(paymentId: number): GlLine[] {
  return db.prepare(`
    SELECT jl.id, je.entry_date, jl.line_date, a.code AS account_code,
           jl.debit, jl.credit, jl.voided
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE jl.reference_type = 'PAYMENT' AND jl.reference_id = ?
    ORDER BY jl.id
  `).all(paymentId) as GlLine[];
}

function glBalance(code: string, asOf: string): number {
  const acct = AccountingService.getAccountByCode(db, code);
  if (!acct) throw new Error(`account ${code} missing`);
  return AccountingService.getAccountBalance(db, acct.id, asOf).balance;
}

function paymentRow(paymentId: number) {
  return db.prepare(
    'SELECT id, payment_no, customer_id, supplier_id, payment_date, payment_method, amount, reference_no, notes FROM payments WHERE id = ?'
  ).get(paymentId) as {
    id: number; payment_no: string; customer_id: number | null;
    supplier_id: number | null; payment_date: string; payment_method: string;
    amount: number; reference_no: string | null; notes: string | null;
  };
}

function activeLedger(table: string, referenceNo: string) {
  return db.prepare(
    `SELECT id, transaction_type, transaction_date, debit, credit, voided, reversed_by
     FROM ${table} WHERE reference_no = ? AND voided = 0 ORDER BY id`
  ).all(referenceNo) as Array<{
    id: number; transaction_type: string; transaction_date: string;
    debit: number; credit: number; voided: number; reversed_by: number | null;
  }>;
}

function voidedLedger(table: string, referenceNo: string) {
  return db.prepare(
    `SELECT id, transaction_type, transaction_date, debit, credit, voided FROM ${table}
     WHERE reference_no = ? AND voided = 1 ORDER BY id`
  ).all(referenceNo) as Array<{
    id: number; transaction_type: string; transaction_date: string;
    debit: number; credit: number; voided: number;
  }>;
}

async function recordCustomerPayment(customerId: number, invoiceId: number, amount: number, date: string, method: string): Promise<number> {
  const res = await api('post', '/api/payments', {
    customer_id: customerId,
    amount,
    payment_date: date,
    payment_method: method,
    invoice_allocations: [{ invoice_id: invoiceId, amount }],
  });
  expect(res.status).toBe(201);
  return res.body.data.id as number;
}

async function createSupplier(name: string, code: string): Promise<number> {
  const res = await api('post', '/api/suppliers', { supplier_code: code, supplier_name: name });
  expect(res.status).toBe(201);
  return res.body.data.id as number;
}

async function purchaseFromSupplier(supplierId: number, quantity: number, unitCost: number, date: string): Promise<number> {
  const res = await api('post', '/api/purchases', {
    item_id: itemId,
    warehouse_id: warehouseId,
    quantity,
    unit_cost: unitCost,
    purchase_date: date,
    supplier_id: supplierId,
  });
  expect([200, 201]).toContain(res.status);
  const row = db.prepare('SELECT id FROM purchases WHERE supplier_id = ? ORDER BY id DESC LIMIT 1').get(supplierId) as { id: number };
  return row.id;
}

async function recordSupplierPayment(supplierId: number, purchaseId: number, amount: number, date: string, method: string): Promise<number> {
  const res = await api('post', '/api/payments', {
    supplier_id: supplierId,
    amount,
    payment_date: date,
    payment_method: method,
    purchase_allocations: [{ purchase_id: purchaseId, amount }],
  });
  expect(res.status).toBe(201);
  return res.body.data.id as number;
}

function closePeriodFor(date: string, name: string) {
  const start = `${date.slice(0, 7)}-01`;
  const end = `${date.slice(0, 7)}-31`;
  db.prepare(`
    INSERT INTO accounting_periods (period_name, start_date, end_date, status)
    VALUES (?, ?, ?, 'open')
    ON CONFLICT(period_name) DO NOTHING
  `).run(name, start, end);
  db.prepare(`UPDATE accounting_periods SET status = 'closed' WHERE period_name = ?`).run(name);
}

function reopenPeriod(name: string) {
  db.prepare(`DELETE FROM accounting_periods WHERE period_name = ?`).run(name);
}

// ────────────────────────────────────────────────────────────────────
// H8: customer payment date edit
// ────────────────────────────────────────────────────────────────────

describe('H8 payment date/method edit reposting', () => {
  it('customer payment date edit moves the GL entry and ledger row to the new date', async () => {
    const customerId = await createCustomer('H8 Cust Date', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-11-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-11-05', 'Cash');
    const paymentNo = paymentRow(paymentId).payment_no;

    // the books start on the original date
    expect(paymentGlLines(paymentId).filter((l) => !l.voided).map((l) => l.line_date)).toEqual(['2026-11-05', '2026-11-05']);
    expect(activeLedger('customer_ledger', paymentNo).filter((r) => r.transaction_type === 'PAYMENT').map((r) => r.transaction_date)).toEqual(['2026-11-05']);

    const arBefore = glBalance(AR_CODE, '2026-11-30');
    const cashBefore = glBalance('1000', '2026-11-30');
    const custBalanceBefore = (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance;

    const res = await api('put', `/api/payments/${paymentId}`, { payment_date: '2026-11-15' });
    expect(res.status).toBe(200);

    // payment row moved
    expect(paymentRow(paymentId).payment_date).toBe('2026-11-15');

    // exactly one active GL entry, entirely on the new date, same legs
    const active = paymentGlLines(paymentId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.every((l) => l.line_date === '2026-11-15' && l.entry_date === '2026-11-15')).toBe(true);
    const legs = active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort();
    expect(legs).toEqual(['1000:200-0', '1100:0-200']);

    // the original posting was voided, not edited in place
    const voided = paymentGlLines(paymentId).filter((l) => l.voided);
    expect(voided).toHaveLength(2);

    // the ledger row moved with it — append-only, one active PAYMENT row
    const ledgerActive = activeLedger('customer_ledger', paymentNo);
    const paymentRows = ledgerActive.filter((r) => r.transaction_type === 'PAYMENT');
    expect(paymentRows).toHaveLength(1);
    expect(paymentRows[0].transaction_date).toBe('2026-11-15');
    expect(paymentRows[0].credit).toBe(200);
    const originalRows = voidedLedger('customer_ledger', paymentNo);
    expect(originalRows).toHaveLength(1);
    const reversalRows = ledgerActive.filter((r) => r.transaction_type === 'REVERSAL:PAYMENT');
    expect(reversalRows).toHaveLength(1);
    expect(reversalRows[0].debit).toBe(200);

    // no money moved — only the date — so balances are unchanged
    expect(glBalance(AR_CODE, '2026-11-30')).toBeCloseTo(arBefore, 2);
    expect(glBalance('1000', '2026-11-30')).toBeCloseTo(cashBefore, 2);
    const custBalanceAfter = (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance;
    expect(custBalanceAfter).toBeCloseTo(custBalanceBefore, 2);

    // the receipt keys on the latest non-voided PAYMENT ledger row — after
    // the reissue that is the new-dated row, so it must still resolve
    const receipt = await api('get', `/api/payments/${paymentId}/receipt`);
    expect(receipt.status).toBe(200);
    expect(receipt.body.data.payment.payment_date).toBe('2026-11-15');
    expect(receipt.body.data.balance.payment_amount).toBe(200);
  });

  it('customer payment method edit reposts the GL onto the new cash account', async () => {
    const customerId = await createCustomer('H8 Cust Method', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-12-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-12-05', 'Cash');

    const cashBefore = glBalance('1000', '2026-12-31');
    const bankBefore = glBalance('1010', '2026-12-31');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_method: 'Bank' });
    expect(res.status).toBe(200);
    expect(paymentRow(paymentId).payment_method).toBe('Bank');

    // the cash leg now sits on Bank, and Cash has been put back
    const active = paymentGlLines(paymentId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(['1010:200-0', '1100:0-200']);
    expect(active.map((l) => l.account_code)).not.toContain('1000');

    // a customer payment DEBITS cash, so the leg leaving Cash restores it
    // and lands on Bank instead
    expect(glBalance('1000', '2026-12-31')).toBeCloseTo(cashBefore - 200, 2);
    expect(glBalance('1010', '2026-12-31')).toBeCloseTo(bankBefore + 200, 2);

    // cash-by-method reconciliation still ties: the day's flow for Bank is
    // the payment and Cash is flat, with no GL/flow variance either way
    const totals = getCashAccountTotals(db, '2026-12-05');
    const bank = totals.find((t) => t.key === 'bank');
    const cash = totals.find((t) => t.key === 'cash');
    expect(bank?.inflow).toBeCloseTo(200, 2);
    expect(cash?.inflow).toBeCloseTo(0, 2);
    expect(bank?.flow_variance).toBeLessThanOrEqual(EPSILON);
    expect(cash?.flow_variance).toBeLessThanOrEqual(EPSILON);

    // the subledger is untouched by a method change (amount/date fixed)
    const paymentNo = paymentRow(paymentId).payment_no;
    const paymentRows = activeLedger('customer_ledger', paymentNo).filter((r) => r.transaction_type === 'PAYMENT');
    expect(paymentRows).toHaveLength(1);
    expect(paymentRows[0].credit).toBe(200);
    expect(paymentRows[0].transaction_date).toBe('2026-12-05');
  });

  it('supplier payment method edit reposts the GL onto the new cash account (regression: used to be skipped)', async () => {
    const supplierId = await createSupplier('H8 Sup Method', 'H8-SUP-METHOD');
    const purchaseId = await purchaseFromSupplier(supplierId, 25, 20, '2026-10-01');
    const paymentId = await recordSupplierPayment(supplierId, purchaseId, 500, '2026-10-05', 'Cash');
    const paymentNo = paymentRow(paymentId).payment_no;

    const cashBefore = glBalance('1000', '2026-10-31');
    const bankBefore = glBalance('1010', '2026-10-31');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_method: 'Bank' });
    expect(res.status).toBe(200);
    expect(paymentRow(paymentId).payment_method).toBe('Bank');

    // AP is debited, the cash leg moved from Cash to Bank
    const active = paymentGlLines(paymentId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(['1010:0-500', '2000:500-0']);
    expect(active.map((l) => l.account_code)).not.toContain('1000');

    expect(glBalance('1000', '2026-10-31')).toBeCloseTo(cashBefore + 500, 2);
    expect(glBalance('1010', '2026-10-31')).toBeCloseTo(bankBefore - 500, 2);

    const totals = getCashAccountTotals(db, '2026-10-05');
    const bank = totals.find((t) => t.key === 'bank');
    const cash = totals.find((t) => t.key === 'cash');
    expect(bank?.outflow).toBeCloseTo(500, 2);
    expect(cash?.outflow).toBeCloseTo(0, 2);
    expect(bank?.flow_variance).toBeLessThanOrEqual(EPSILON);
    expect(cash?.flow_variance).toBeLessThanOrEqual(EPSILON);

    // the supplier's own balance is preserved by the method change
    const supBalanceBefore = (db.prepare('SELECT current_balance FROM suppliers WHERE id = ?').get(supplierId) as { current_balance: number }).current_balance;
    // the supplier ledger row is untouched by a method change
    const paymentRows = activeLedger('supplier_ledger', paymentNo).filter((r) => r.transaction_type === 'PAYMENT');
    expect(paymentRows).toHaveLength(1);
    expect(paymentRows[0].credit).toBe(500);
    expect(paymentRows[0].transaction_date).toBe('2026-10-05');

    const supBalanceAfter = (db.prepare('SELECT current_balance FROM suppliers WHERE id = ?').get(supplierId) as { current_balance: number }).current_balance;
    expect(supBalanceAfter).toBeCloseTo(supBalanceBefore, 2);
  });

  it('supplier payment date edit moves the GL entry and ledger row to the new date', async () => {
    const supplierId = await createSupplier('H8 Sup Date', 'H8-SUP-DATE');
    const purchaseId = await purchaseFromSupplier(supplierId, 25, 20, '2026-08-01');
    const paymentId = await recordSupplierPayment(supplierId, purchaseId, 500, '2026-08-05', 'Bank');
    const paymentNo = paymentRow(paymentId).payment_no;

    expect(paymentGlLines(paymentId).filter((l) => !l.voided).map((l) => l.line_date)).toEqual(['2026-08-05', '2026-08-05']);
    expect(activeLedger('supplier_ledger', paymentNo).filter((r) => r.transaction_type === 'PAYMENT').map((r) => r.transaction_date)).toEqual(['2026-08-05']);

    const apBefore = glBalance(AP_CODE, '2026-08-31');
    const bankBefore = glBalance('1010', '2026-08-31');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_date: '2026-08-15' });
    expect(res.status).toBe(200);
    expect(paymentRow(paymentId).payment_date).toBe('2026-08-15');

    const active = paymentGlLines(paymentId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.every((l) => l.line_date === '2026-08-15' && l.entry_date === '2026-08-15')).toBe(true);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(['1010:0-500', '2000:500-0']);
    expect(paymentGlLines(paymentId).filter((l) => l.voided)).toHaveLength(2);

    const ledgerActive = activeLedger('supplier_ledger', paymentNo);
    const paymentRows = ledgerActive.filter((r) => r.transaction_type === 'PAYMENT');
    expect(paymentRows).toHaveLength(1);
    expect(paymentRows[0].transaction_date).toBe('2026-08-15');
    expect(paymentRows[0].credit).toBe(500);
    expect(voidedLedger('supplier_ledger', paymentNo)).toHaveLength(1);
    const reversalRows = ledgerActive.filter((r) => r.transaction_type === 'REVERSAL:PAYMENT');
    expect(reversalRows).toHaveLength(1);
    expect(reversalRows[0].debit).toBe(500);

    expect(glBalance(AP_CODE, '2026-08-31')).toBeCloseTo(apBefore, 2);
    expect(glBalance('1010', '2026-08-31')).toBeCloseTo(bankBefore, 2);
  });

  it('a date edit and a method edit together repost on the new date and account', async () => {
    const customerId = await createCustomer('H8 Cust Both', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-05-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-05-05', 'Cash');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_date: '2026-05-18', payment_method: 'JazzCash' });
    expect(res.status).toBe(200);

    const active = paymentGlLines(paymentId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.every((l) => l.line_date === '2026-05-18' && l.entry_date === '2026-05-18')).toBe(true);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(['1030:200-0', '1100:0-200']);

    const paymentNo = paymentRow(paymentId).payment_no;
    const paymentRows = activeLedger('customer_ledger', paymentNo).filter((r) => r.transaction_type === 'PAYMENT');
    expect(paymentRows).toHaveLength(1);
    expect(paymentRows[0].transaction_date).toBe('2026-05-18');
  });

  it('moving a payment INTO a closed period is rejected and nothing is rewritten', async () => {
    const customerId = await createCustomer('H8 Cust Closed', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-06-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-06-05', 'Cash');
    const paymentNo = paymentRow(paymentId).payment_no;
    const glBefore = paymentGlLines(paymentId);
    const ledgerBefore = activeLedger('customer_ledger', paymentNo);

    // May is closed; the payment sits in open June
    closePeriodFor('2026-05-10', '2026-05-closed-for-h8');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_date: '2026-05-10' });
    expect(res.status).toBe(409);
    expect(/closed|period/i.test(res.body.error ?? ''));

    // untouched
    expect(paymentRow(paymentId).payment_date).toBe('2026-06-05');
    expect(paymentGlLines(paymentId).map((l) => `${l.voided}:${l.line_date}`).sort()).toEqual(glBefore.map((l) => `${l.voided}:${l.line_date}`).sort());
    expect(activeLedger('customer_ledger', paymentNo)).toEqual(ledgerBefore);

    reopenPeriod('2026-05-closed-for-h8');
  });

  it('editing a payment that sits inside a closed period is rejected', async () => {
    const customerId = await createCustomer('H8 Cust Closed Own', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-07-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-07-05', 'Cash');
    const paymentNo = paymentRow(paymentId).payment_no;
    const glBefore = paymentGlLines(paymentId);
    const ledgerBefore = activeLedger('customer_ledger', paymentNo);

    closePeriodFor('2026-07-05', '2026-07-closed-for-h8');

    const res = await api('put', `/api/payments/${paymentId}`, { payment_date: '2026-07-15', payment_method: 'Bank' });
    expect(res.status).toBe(409);
    expect(/closed|period/i.test(res.body.error ?? ''));

    expect(paymentRow(paymentId).payment_date).toBe('2026-07-05');
    expect(paymentRow(paymentId).payment_method).toBe('Cash');
    expect(paymentGlLines(paymentId).map((l) => `${l.voided}:${l.account_code}`).sort()).toEqual(glBefore.map((l) => `${l.voided}:${l.account_code}`).sort());
    expect(activeLedger('customer_ledger', paymentNo)).toEqual(ledgerBefore);

    reopenPeriod('2026-07-closed-for-h8');
  });

  it('a metadata-only edit (reference / notes) leaves the books untouched', async () => {
    const customerId = await createCustomer('H8 Cust Meta', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-04-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-04-05', 'Cash');
    const paymentNo = paymentRow(paymentId).payment_no;
    const glBefore = paymentGlLines(paymentId);
    const ledgerBefore = activeLedger('customer_ledger', paymentNo);

    const res = await api('put', `/api/payments/${paymentId}`, { reference_no: 'H8-REF-42', notes: 'cleared' });
    expect(res.status).toBe(200);

    const row = paymentRow(paymentId);
    expect(row.reference_no ?? '').toContain('H8-REF-42');
    expect(row.payment_date).toBe('2026-04-05');
    expect(row.payment_method).toBe('Cash');
    expect(paymentGlLines(paymentId)).toEqual(glBefore);
    expect(activeLedger('customer_ledger', paymentNo)).toEqual(ledgerBefore);
  });

  it('still rejects an amount edit with void-and-reissue', async () => {
    const customerId = await createCustomer('H8 Cust Amount', token);
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-03-05', payment: null },
      token,
    );
    const paymentId = await recordCustomerPayment(customerId, inv.invoiceId, 200, '2026-03-05', 'Cash');

    const res = await api('put', `/api/payments/${paymentId}`, { amount: 250 });
    expect(res.status).toBe(400);
    expect(/void|re-?record|amount/i.test(res.body.error ?? ''));
    expect(paymentRow(paymentId).amount).toBe(200);
  });

  // A refund settlement creates a NEGATIVE payments row whose GL is keyed
  // PAYMENT/refundPaymentId but posted by postRefundEntry (Dr AR / Cr
  // Cash). postPaymentEntry ignores amounts ≤ 0, so an edit that voids and
  // then reposts through the wrong primitive silently deletes the refund
  // from the books.
  async function createRefundPayment(customerId: number, amount: number): Promise<number> {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 10, unitPrice: 20 }], invoiceDate: '2026-02-05', payment: 'full' },
      token,
    );
    const ret = await processReturn(inv.invoiceId, {
      invoiceItemIds: inv.invoiceItemIds,
      quantities: [10],
      settlements: [{ type: 'refund', amount, method: 'Cash' }],
    }, token);
    expect([200, 201]).toContain(ret.status);
    const settlement = settlementsFor(ret.returnId!).find((s) => s.type === 'refund');
    if (!settlement?.payment_id) throw new Error('refund settlement missing payment_id');
    return settlement.payment_id;
  }

  const REFUND_LEGS = ['1000:0-200', '1100:200-0'];

  it('refund payment date edit reposts the refund GL and moves the REFUND ledger row', async () => {
    const customerId = await createCustomer('H8 Refund Date', token);
    const refundId = await createRefundPayment(customerId, 200);
    const row = paymentRow(refundId);
    expect(row.amount).toBe(-200);

    const activeBefore = paymentGlLines(refundId).filter((l) => !l.voided);
    expect(activeBefore.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(REFUND_LEGS);

    const originalDate = row.payment_date;
    const newDate = `${originalDate.slice(0, 8)}${String(Math.min(28, Number(originalDate.slice(8, 10)) + 3)).padStart(2, '0')}`;
    expect(newDate).not.toBe(originalDate);

    const custBalanceBefore = (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance;
    const arBefore = glBalance(AR_CODE, '2026-09-30');
    const cashBefore = glBalance('1000', '2026-09-30');

    const res = await api('put', `/api/payments/${refundId}`, { payment_date: newDate });
    expect(res.status).toBe(200);

    // the refund's cash exit survives, on the new date
    const active = paymentGlLines(refundId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.every((l) => l.line_date === newDate && l.entry_date === newDate)).toBe(true);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(REFUND_LEGS);
    expect(paymentGlLines(refundId).filter((l) => l.voided)).toHaveLength(2);

    // the ledger REFUND row moved with it — one active debit row at the new date
    const refundLedger = activeLedger('customer_ledger', row.payment_no).filter((r) => r.transaction_type === 'REFUND');
    expect(refundLedger).toHaveLength(1);
    expect(refundLedger[0].transaction_date).toBe(newDate);
    expect(refundLedger[0].debit).toBe(200);

    // same-month move: nothing changed in the balances
    expect(glBalance(AR_CODE, '2026-09-30')).toBeCloseTo(arBefore, 2);
    expect(glBalance('1000', '2026-09-30')).toBeCloseTo(cashBefore, 2);
    const custBalanceAfter = (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance;
    expect(custBalanceAfter).toBeCloseTo(custBalanceBefore, 2);
  });

  it('refund payment method edit reposts the cash exit onto the new account', async () => {
    const customerId = await createCustomer('H8 Refund Method', token);
    const refundId = await createRefundPayment(customerId, 200);

    const cashBefore = glBalance('1000', '2026-09-30');
    const bankBefore = glBalance('1010', '2026-09-30');

    const res = await api('put', `/api/payments/${refundId}`, { payment_method: 'Bank' });
    expect(res.status).toBe(200);
    expect(paymentRow(refundId).payment_method).toBe('Bank');

    const active = paymentGlLines(refundId).filter((l) => !l.voided);
    expect(active).toHaveLength(2);
    expect(active.map((l) => `${l.account_code}:${l.debit}-${l.credit}`).sort()).toEqual(['1010:0-200', '1100:200-0']);

    // the exit left Cash and lands on Bank instead
    expect(glBalance('1000', '2026-09-30')).toBeCloseTo(cashBefore + 200, 2);
    expect(glBalance('1010', '2026-09-30')).toBeCloseTo(bankBefore - 200, 2);
  });
});
