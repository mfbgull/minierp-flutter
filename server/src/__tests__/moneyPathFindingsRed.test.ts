/**
 * Findings from audit/GLM-REVIEW.md (2026-11-16): F-2 and F-3.
 *
 * - F-2 (Medium) — FIXED in 7a96e6d8. Cancelling a written-off claim,
 *   directly or through a purchase-return void, used to orphan the write-off's
 *   Dr 7300 / Cr AP posting and silently drop the uncollected remainder. The
 *   guard (SupplierRefundClaimModel.cancel) now refuses while
 *   written_off_amount > 0. The F-2 case below is a normal regression guard:
 *   it passes today and fails if that guard is removed or weakened.
 *
 * - F-3 (Medium) — parked, pending Gull's dating decision. SupplierRefundModel
 *   .void appends its supplier-ledger reversal dated "today"
 *   (new Date().toISOString(), UTC) while the GL lines are voided
 *   retroactively, so for any as-of date between the receipt and the void, GL
 *   AP and the supplier subledger disagree. The codebase's own rule
 *   (ledgerUtils.reverseLedgerEntry) is same-date reversal. The F-3 case below
 *   is wrapped in `it.failing` so the suite stays green while the defect is
 *   visible; remove the wrapper when the dating decision is implemented.
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
  it('F-2: voiding a return whose claim carries a write-off is refused with 409', async () => {
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

    // Void the return. No receipts exist, so the receipts guard passes; the
    // write-off guard must still refuse. Exact 409 — a bare >= 400 would also
    // accept an unrelated 500 or an auth failure and prove nothing.
    const voided = await request(app)
      .post(`/api/purchase-returns/${returnId}/void`)
      .set('Cookie', cookie)
      .send({ reason: 'goods never left stock' });
    expect(voided.status).toBe(409);
    // The refusal names the business rule, not a generic crash.
    expect(String(voided.body.error)).toMatch(/write-off/i);
    expect(String(voided.body.error)).toMatch(/cannot be cancelled/i);

    // Unchanged state: the claim is still open with the write-off posted, the
    // remainder is still reported as due, and the write-off lines are active.
    const claim = db.prepare(
      'SELECT status, written_off_amount, amount, received_amount FROM supplier_refund_claims WHERE id = ?'
    ).get(claimId) as {
      status: string; written_off_amount: number; amount: number; received_amount: number;
    };
    expect(claim.status).not.toBe('CANCELLED');
    expect(claim.written_off_amount).toBeCloseTo(2000, 2);

    const activeWriteOff = db.prepare(
      `SELECT COUNT(*) AS n FROM journal_lines
       WHERE reference_type = 'REFUND_CLAIM_WRITE_OFF' AND voided = 0`
    ).get() as { n: number };
    expect(activeWriteOff.n).toBeGreaterThan(0);

    const due = await request(app)
      .get('/api/supplier-refunds/claims/due')
      .set('Cookie', cookie);
    expect(due.status).toBe(200);
    // The claim is still reported due with the remainder intact:
    // 5000 claim − 0 received − 2000 written off = 3000.
    const claimDue = (due.body.data as Array<{
      id: number; amount: number; received_amount: number; written_off_amount: number;
    }>).find((row) => row.id === claimId);
    expect(claimDue).toBeDefined();
    expect(claimDue!.amount - claimDue!.received_amount - claimDue!.written_off_amount)
      .toBeCloseTo(3000, 2);
  });

  // Scoped control: the guard keys on the standing write-off, not on every
  // claim. Without a write-off the return void still cancels the claim — so a
  // regression that over-broadens the guard (refusing every void) is caught.
  it('F-2 control: a claim with no write-off still cancels on return void', async () => {
    await seedOpeningCash(6000);
    const info = await paidPurchase(5000);
    const { returnId, claimId } = await returnAgainstPurchase(info);

    const voided = await request(app)
      .post(`/api/purchase-returns/${returnId}/void`)
      .set('Cookie', cookie)
      .send({ reason: 'goods never left stock' });
    expect(voided.status).toBe(200);

    const claim = db.prepare(
      'SELECT status FROM supplier_refund_claims WHERE id = ?'
    ).get(claimId) as { status: string };
    expect(claim.status).toBe('CANCELLED');
  });

  // it.failing: parked pending Gull's F-3 dating decision. It flips to a real
  // failure the moment F-3 is fixed; remove the wrapper then.
  //
  // Verified 2026-11-16 (isolated test-only worktree, glm-f3-probe): the void
  // request below needs NO Idempotency-Key. `POST /api/supplier-refunds/:id/void`
  // (routes/supplierRefunds.ts:34) calls no idempotency helper — there is no
  // SUPPLIER_REFUND_VOID scope, and voidSupplierRefund
  // (controllers/supplierRefundController.ts:162) only reaches
  // startRequiredIdempotentRequest's siblings CREATE / CLAIM_CREATE /
  // CLAIM_WRITE_OFF. Run unwrapped, the void returned HTTP 200 with no header,
  // and the FIRST failing assertion is the as-of GL/subledger comparison
  // (Expected 0, Received 3000) — not a masked HTTP 400. The earlier claim
  // that 653dfe43 proves this route key-mandatory was wrong (that commit is
  // Flutter-only and its message is inaccurate about the server).
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
    // reversal is appended dated today. No Idempotency-Key: this route does
    // not require one (verified — see the header comment above).
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
