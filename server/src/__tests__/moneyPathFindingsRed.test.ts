/**
 * RED tests for audit/GLM-REVIEW.md findings F-2 and F-3 (2026-11-16).
 *
 * These tests deliberately FAIL against the current code. They document the
 * failing scenarios so the fix work can go red → green. Do not merge as-is
 * without either fixing the findings or consciously deleting the tests:
 *
 * - F-2 (Medium): cancelling a written-off claim — directly or through a
 *   purchase-return void — orphans the write-off's Dr 7300 / Cr AP posting
 *   and silently drops the uncollected remainder. The guard
 *   (SupplierRefundClaimModel.cancel) only refuses while LIVE RECEIPTS are
 *   allocated. Fix options per the review: refuse cancel/void while
 *   written_off_amount > 0, or reverse the write-off with the cancel.
 *   NOTE: the void path lives in PurchaseReturn.ts (currently another
 *   agent's file) — the fix must be coordinated there.
 *
 * - F-3 (Medium): SupplierRefundModel.void appends its supplier-ledger
 *   reversal dated "today" (new Date().toISOString(), UTC) while the GL
 *   lines are voided retroactively — for any as-of date between the receipt
 *   and the void, GL AP and the supplier subledger disagree. The codebase's
 *   own rule (ledgerUtils.reverseLedgerEntry) is same-date reversal.
 */
import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import { SupplierPaymentService } from '../services/SupplierPaymentService';

let cookie: string;

beforeAll(async () => { cookie = await getLoginCookie(); });
beforeEach(() => { db.exec('SAVEPOINT findings_red_case'); });
afterEach(() => { db.exec('ROLLBACK TO findings_red_case; RELEASE findings_red_case'); });

async function getLoginCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

function uniqueKey(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

/** Opening cash through the house channel (owner capital). */
async function seedOpeningCash(amount: number, date = '2026-10-01'): Promise<void> {
  const r = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
    .set('Idempotency-Key', uniqueKey('red-capital'))
    .send({ amount, capital_date: date, payment_method: 'Cash' });
  expect(r.status).toBe(201);
}

interface PurchaseInfo { purchaseId: number; supplierId: number; warehouseId: number; itemId: number; }

/** Paid purchase through the real payment service (fresh named supplier). */
async function paidPurchase(total: number): Promise<PurchaseInfo> {
  const itemId = await createItem(`Red-test item ${Math.random()}`, cookie);
  const warehouse = db.prepare<[], { id: number }>(
    'SELECT id FROM warehouses ORDER BY id LIMIT 1'
  ).get();
  if (!warehouse) throw new Error('Missing fixture warehouse');
  const purchase = await purchaseWithNamedSupplier(`Red-test supplier ${Math.random()}`, {
    item_id: itemId, warehouse_id: warehouse.id, quantity: 10, unit_cost: total / 10,
    purchase_date: '2026-10-02',
  }, cookie);
  expect(purchase.status).toBe(201);
  const purchaseId = purchase.body.data?.id ?? purchase.body.id;
  const row = db.prepare<[number], { supplier_id: number }>(
    'SELECT supplier_id FROM purchases WHERE id = ?'
  ).get(purchaseId);
  if (!row) throw new Error('Missing fixture supplier');
  new SupplierPaymentService(db).recordSupplierPayment({
    supplierId: row.supplier_id, paymentDate: '2026-10-02', amount: total,
    paymentMethod: 'Cash', allocations: [{ kind: 'purchase', id: purchaseId, amount: total }],
  });
  return { purchaseId, supplierId: row.supplier_id, warehouseId: warehouse.id, itemId };
}

/** refund_expected return against a purchase, with its claim id. */
async function returnAgainstPurchase(info: PurchaseInfo): Promise<{ returnId: number; claimId: number }> {
  const returned = await request(app).post('/api/purchase-returns')
      .set('Idempotency-Key', uniqueKey('red-pr')).set('Cookie', cookie).send({
    return_date: '2026-10-03', source_type: 'PURCHASE', source_id: info.purchaseId,
    warehouse_id: info.warehouseId, disposition: 'refund_expected',
    items: [{ source_item_id: info.purchaseId, quantity: 10 }],
  });
  expect(returned.status).toBe(201);
  const returnId = returned.body.data?.id ?? returned.body.id;
  const claim = db.prepare<[number], { id: number }>(
    'SELECT id FROM supplier_refund_claims WHERE return_id = ?'
  ).get(returnId);
  if (!claim) throw new Error('Missing auto-opened refund claim');
  return { returnId, claimId: claim.id };
}

/** GL AP (account 2000) balance as of a date, active lines only. */
function glApAsOf(date: string): number {
  return (db.prepare(`
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS v
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = '2000' AND jl.voided = 0 AND jl.line_date <= ?
  `).get(date) as { v: number }).v;
}

/** Supplier subledger balance as of a date, live rows only — same
 * debit-minus-credit orientation as invariant D. */
function supplierLedgerAsOf(supplierId: number, date: string): number {
  return (db.prepare(`
    SELECT COALESCE(SUM(debit - credit), 0) AS v
    FROM supplier_ledger
    WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL
      AND transaction_date <= ?
  `).get(supplierId, date) as { v: number }).v;
}

describe('GLM-REVIEW findings (F-2 fixed, F-3 parked)', () => {
  // F-2 is fixed (7a96e6d8 refused cancel of a written-off claim) — this is
  // now a normal regression guard for that fix.
  it('F-2: voiding a return whose claim carries a write-off is refused, not silently orphaned', async () => {
    await seedOpeningCash(6000);
    const info = await paidPurchase(5000);
    const { returnId, claimId } = await returnAgainstPurchase(info);

    // First write-off is permitted: 2000 of the 5000, at the claim's date.
    const writeOff = await request(app)
      .post(`/api/supplier-refunds/claims/${claimId}/write-off`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', uniqueKey('red-wo'))
      .send({ amount: 2000, reason: 'supplier unreachable' });
    expect(writeOff.status).toBe(200);

    // Void the return. No receipts exist, so cancel's only guard passes.
    // Expected: refusal (the write-off posting must not be orphaned and the
    // remaining 3000 must not vanish from refundsDue unaccounted).
    const voided = await request(app)
      .post(`/api/purchase-returns/${returnId}/void`)
      .set('Cookie', cookie)
      .send({ reason: 'goods never left stock' });
    expect(voided.status).toBeGreaterThanOrEqual(400);
  });

  // it.failing: known defect (audit/GLM-REVIEW.md F-3) — parked pending the
  // dating decision. It flips to a real failure the moment F-3 is fixed;
  // delete the wrapper then.
  it.failing('F-3: a voided receipt keeps GL AP and the supplier ledger in agreement at every as-of date', async () => {
    await seedOpeningCash(10000);
    const info = await paidPurchase(100);

    // Standalone claim on the purchase's (fresh) supplier.
    const claim = await request(app).post('/api/supplier-refunds/claims')
      .set('Cookie', cookie)
      .set('Idempotency-Key', uniqueKey('red-claim'))
      .send({
        supplier_id: info.supplierId,
        claim_date: '2026-11-01',
        amount: 3000,
        reason: 'price compensation',
      });
    expect(claim.status).toBe(201);
    const claimId = claim.body.data?.id ?? claim.body.id;

    // Receipt 3000 on 2026-11-01 (cash).
    const receipt = await request(app).post('/api/supplier-refunds')
      .set('Cookie', cookie)
      .set('Idempotency-Key', uniqueKey('red-receipt'))
      .send({
        claim_id: claimId,
        refund_date: '2026-11-01',
        amount: 3000,
        payment_method: 'Cash',
      });
    expect(receipt.status).toBe(201);
    const receiptId = receipt.body.data?.id ?? receipt.body.id;

    // Void "today" (2026-11-16): GL lines void retroactively; the ledger
    // reversal is appended dated today.
    const voided = await request(app)
      .post(`/api/supplier-refunds/${receiptId}/void`)
      .set('Cookie', cookie)
      .send({ reason: 'wrong claim' });
    expect(voided.status).toBe(200);

    // As-of 2026-11-05 (inside the window) the two ledgers must agree.
    // RED today: the ledger still shows the receipt applied while GL AP
    // already shows it undone — off by exactly 3000.
    const asOf = '2026-11-05';
    expect(supplierLedgerAsOf(info.supplierId, asOf))
      .toBeCloseTo(glApAsOf(asOf), 2);

    // Sanity: at end-of-chain (today) the two agree again — the defect is
    // confined to the window between receipt and void. This half passes
    // today and must keep passing after the same-date fix.
    const today = '2026-12-31';
    expect(supplierLedgerAsOf(info.supplierId, today))
      .toBeCloseTo(glApAsOf(today), 2);
  });
});
