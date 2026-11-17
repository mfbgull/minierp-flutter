import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { SupplierPaymentService } from '../services/SupplierPaymentService';

/**
 * F-3: voiding a supplier refund receipt must date its GL and supplier-ledger
 * reversal on the ORIGINAL receipt date.
 *
 * A refund receipt is the cash the supplier pays back. Voiding it means "this
 * receipt was entered in error", so both accounting stores must reverse on the
 * receipt's own date. The GL reversal already marks the original journal lines
 * voided (so it keeps the original date); the supplier-ledger counter-entry
 * must do the same. Posting it on "today" splits the two stores and makes the
 * supplier balance disagree between two as-of dates for no business reason.
 */

let cookie: string;

beforeAll(async () => { cookie = await getAuthCookie(); });
beforeEach(() => { db.exec('SAVEPOINT f3_void_case'); });
afterEach(() => { db.exec('ROLLBACK TO f3_void_case; RELEASE f3_void_case'); });

const RECEIPT_DATE = '2026-03-15';
const RETURN_DATE = '2026-03-10';
/** Between the purchase and the receipt — a date a caller may ask about. */
const INTERMEDIATE_DATE = '2026-03-12';

/** Scoped GL AP (account 2000) balance attributable to ONE supplier's
 *  documents, read as-of a date. Liability increases on credit, so the AP
 *  balance is credit - debit. Voided lines are excluded, matching the
 *  unvoided supplier ledger. Scope = the reference set this supplier owns.
 *
 *  Scoping matters: a global account-2000 total also counts other suppliers'
 *  rows, so it cannot prove THIS supplier's two stores agree. */
function glApScopedAsOf(refs: Array<{ type: string; id: number }>, asOf: string): number {
  const acct = db.prepare<[string], { id: number }>('SELECT id FROM chart_of_accounts WHERE code = ?').get('2000');
  if (!acct) throw new Error('Missing account 2000');
  let total = 0;
  for (const r of refs) {
    const row = db.prepare<[number, string, number, string], { total: number }>(`
      SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS total
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE jl.account_id = ? AND jl.voided = 0 AND jl.reference_type = ? AND jl.reference_id = ?
        AND je.entry_date <= ?
    `).get(acct.id, r.type, r.id, asOf);
    total += row?.total ?? 0;
  }
  return total;
}

/** This supplier's dated, unvoided ledger net (debit - credit) as-of a date. */
function ledgerNetAsOf(supplierId: number, asOf: string): number {
  const row = db.prepare<[number, string], { total: number }>(`
    SELECT COALESCE(SUM(debit - credit), 0) AS total
    FROM supplier_ledger
    WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL AND transaction_date <= ?
  `).get(supplierId, asOf);
  return row?.total ?? 0;
}

async function makeRefundReceipt(supplierName: string, itemName: string): Promise<{
  refundId: number; supplierId: number; refundNo: string; purchaseId: number;
}> {
  // Seed opening cash so the cash-out supplier payment passes the timeline guard.
  const capital = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
    .set('Idempotency-Key', `f3-cap-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ amount: 1000, capital_date: '2026-02-01', payment_method: 'Cash' });
  expect(capital.status).toBe(201);

  const itemId = await createItem(itemName, cookie);
  const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
  if (!warehouse) throw new Error('Missing fixture warehouse');

  const purchase = await purchaseWithNamedSupplier(supplierName, {
    item_id: itemId, warehouse_id: warehouse.id, quantity: 10, unit_cost: 10,
    purchase_date: '2026-03-01',
  }, cookie);
  expect(purchase.status).toBe(201);
  const purchaseId = purchase.body.data?.id ?? purchase.body.id;
  const supplierIdForPay = db.prepare<[number], { supplier_id: number }>(
    'SELECT supplier_id FROM purchases WHERE id = ?'
  ).get(purchaseId)!.supplier_id;
  // Pay the purchase in full first: REVERSAL-RULES 1.12 caps a refund at the
  // refundable credit, and an unpaid purchase leaves nothing refundable.
  new SupplierPaymentService(db).recordSupplierPayment({
    supplierId: supplierIdForPay, paymentDate: '2026-03-01', amount: 100, paymentMethod: 'Cash',
    allocations: [{ kind: 'purchase', id: purchaseId, amount: 100 }],
  });

  const returned = await request(app).post('/api/purchase-returns')
    .set('Cookie', cookie)
    .set('Idempotency-Key', `f3-pr-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({
      return_date: '2026-03-10', source_type: 'PURCHASE', source_id: purchaseId,
      warehouse_id: warehouse.id, disposition: 'credit_on_account',
      items: [{ source_item_id: purchaseId, quantity: 10 }],
    });
  expect(returned.status).toBe(201);

  const note = db.prepare<[number], { id: number }>(
    'SELECT id FROM credit_notes WHERE source_id = ? ORDER BY id DESC'
  ).get(returned.body.data?.id ?? returned.body.id);
  if (!note) throw new Error('Missing fixture credit note');

  // Real HTTP receipt: this is the cash the supplier pays back.
  const receipt = await request(app).post('/api/supplier-refunds')
    .set('Cookie', cookie)
    .set('Idempotency-Key', `f3-sr-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ credit_note_id: note.id, refund_date: RECEIPT_DATE, amount: 100, payment_method: 'cash' });
  expect(receipt.status).toBe(201);
  const refundId = receipt.body.data?.id ?? receipt.body.id;
  const refundNo: string = receipt.body.data?.refund_no ?? receipt.body.refund_no;

  const supplierId = db.prepare<[number], { supplier_id: number }>(
    'SELECT supplier_id FROM supplier_refunds WHERE id = ?'
  ).get(refundId)!.supplier_id;

  return { refundId, supplierId, refundNo, purchaseId };
}

describe('F-3: supplier refund void dates both stores on the original receipt date', () => {
  it('posts the supplier-ledger reversal on the receipt date, not today', async () => {
    const { refundId, supplierId } = await makeRefundReceipt('F3 supplier A', 'F3 item A');

    // Receipt posted: supplier ledger carries a debit on the receipt date.
    const rowsBefore = db.prepare<[number], { transaction_type: string; transaction_date: string }>(
      'SELECT transaction_type, transaction_date FROM supplier_ledger WHERE supplier_id = ? ORDER BY id'
    ).all(supplierId);
    expect(rowsBefore.some((r) => r.transaction_type === 'REFUND_RECEIPT' && r.transaction_date === RECEIPT_DATE)).toBe(true);

    const voidRes = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'entered in error' });
    expect(voidRes.status).toBe(200);

    const reversal = db.prepare<[number], { transaction_date: string; transaction_type: string }>(`
      SELECT transaction_date, transaction_type FROM supplier_ledger
      WHERE supplier_id = ? AND transaction_type = 'REFUND_RECEIPT_VOID' ORDER BY id DESC LIMIT 1
    `).get(supplierId);
    expect(reversal).toBeDefined();
    // THE F-3 ASSERTION: original receipt date, not the wall-clock date.
    expect(reversal!.transaction_date).toBe(RECEIPT_DATE);
  });

  it('keeps the scoped GL AP and the dated supplier ledger in agreement at every as-of date', async () => {
    const { refundId, supplierId, purchaseId } = await makeRefundReceipt('F3 supplier B', 'F3 item B');

    // Baseline before the void: the receipt is posted, so the supplier's
    // ledger sits at (allocation-only net + receipt).
    const baselineAtReceipt = ledgerNetAsOf(supplierId, RECEIPT_DATE);

    const voidRes = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'entered in error' });
    expect(voidRes.status).toBe(200);

    // Every document reference this supplier owns and that touches AP 2000.
    const refs = [
      { type: 'PURCHASE', id: purchaseId },
      { type: 'PAYMENT', id: db.prepare<[number], { id: number }>(
        'SELECT payment_id AS id FROM purchase_allocations WHERE purchase_id = ? LIMIT 1'
      ).get(purchaseId)!.id },
      { type: 'PURCHASE_RETURN', id: db.prepare<[number], { id: number }>(
        'SELECT id FROM purchase_returns WHERE source_id = ? LIMIT 1'
      ).get(purchaseId)!.id },
      { type: 'REFUND_RECEIPT', id: refundId },
    ];

    // before receipt -> on receipt -> between receipt and "today" -> today/after.
    // At each date the scoped GL AP must equal the dated supplier ledger.
    for (const asOf of [RETURN_DATE, RECEIPT_DATE, INTERMEDIATE_DATE, '2099-12-31']) {
      expect({ asOf, gl: glApScopedAsOf(refs, asOf) }).toEqual({ asOf, gl: ledgerNetAsOf(supplierId, asOf) });
    }

    // Receipt and reversal cancel on the receipt date: after the void the
    // receipt-date balance falls back to the pre-receipt baseline, and every
    // later date equals that same baseline too.
    const preReceiptBaseline = ledgerNetAsOf(supplierId, RETURN_DATE);
    expect(ledgerNetAsOf(supplierId, RECEIPT_DATE)).toBe(preReceiptBaseline);
    expect(ledgerNetAsOf(supplierId, INTERMEDIATE_DATE)).toBe(preReceiptBaseline);
    expect(ledgerNetAsOf(supplierId, '2099-12-31')).toBe(preReceiptBaseline);
    expect(baselineAtReceipt).not.toBe(preReceiptBaseline);
    expectAllInvariantsHold('after F-3 void');
  });

  it('refuses to void a receipt in a closed period and changes nothing', async () => {
    const { refundId, supplierId, refundNo } = await makeRefundReceipt('F3 supplier C', 'F3 item C');

    // Close the month of the receipt, then attempt the void. The receipt is
    // already posted, so the period starts open and is then closed.
    const month = RECEIPT_DATE.slice(0, 7);
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, ?, ?, 'open') ON CONFLICT(period_name) DO NOTHING
    `).run(`F3-${month}`, `${month}-01`, `${month}-31`);
    const periodId = db.prepare<[string], { id: number }>(
      'SELECT id FROM accounting_periods WHERE period_name = ?'
    ).get(`F3-${month}`)!.id;
    const close = await request(app).post(`/api/accounting/periods/${periodId}/close`).set('Cookie', cookie);
    expect([200, 201]).toContain(close.status);

    const linesBefore = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const ledgerBefore = db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all();

    const voidRes = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'late void' });
    // Exact existing contract: 409 with the closed-period message.
    expect(voidRes.status).toBe(409);
    expect(voidRes.body.error).toContain(`Supplier refund ${refundNo} is dated ${RECEIPT_DATE} inside closed accounting period`);
    expect(voidRes.body.error).toContain('edit/delete blocked');
    expect(db.prepare('SELECT status FROM supplier_refunds WHERE id = ?').get(refundId)).toEqual({ status: 'POSTED' });
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(linesBefore);
    expect(db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all()).toEqual(ledgerBefore);
    expect(supplierId).toBeGreaterThan(0);
  });

  it('voids once and makes a second void a no-op', async () => {
    const { refundId, purchaseId } = await makeRefundReceipt('F3 supplier D', 'F3 item D');

    const first = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'once' });
    expect(first.status).toBe(200);
    const linesAfterFirst = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();
    const ledgerAfterFirst = db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all();
    const allocAfterFirst = db.prepare('SELECT * FROM purchase_allocations ORDER BY id').all();

    const second = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'twice' });
    // Exact existing state-guard contract: 400 "Only POSTED refunds can be voided".
    expect(second.status).toBe(400);
    expect(second.body.error).toBe('Only POSTED refunds can be voided');
    // No store moved: the state guard fires before any write.
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(linesAfterFirst);
    expect(db.prepare('SELECT * FROM supplier_ledger ORDER BY id').all()).toEqual(ledgerAfterFirst);
    expect(db.prepare('SELECT * FROM purchase_allocations ORDER BY id').all()).toEqual(allocAfterFirst);
    expect(purchaseId).toBeGreaterThan(0);
  });
});
