/**
 * PRET-002 — supplier refund claims: the expected → received lifecycle.
 *
 * Core invariant (D19): cash and bank change ONLY on REFUND_RECEIPT.
 * A claim (auto-opened by a refund_expected return, or standalone) posts
 * no GL. Receipts post Dr cash/bank / Cr AP with reference_type
 * REFUND_RECEIPT and advance the claim EXPECTED → PARTIAL → RECEIVED.
 * Write-offs settle short-paid claims through Dr 7300 / Cr AP with a
 * mandatory reason; above Rs 1,000 they are owner (admin) only.
 */
import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import bcrypt from 'bcrypt';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import { SupplierPaymentService } from '../services/SupplierPaymentService';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

let cookie: string;

beforeAll(async () => { cookie = await getLoginCookie(); });
beforeEach(() => { db.exec('SAVEPOINT claim_case'); });
afterEach(() => { db.exec('ROLLBACK TO claim_case; RELEASE claim_case'); });

async function getLoginCookie(username = 'admin', password?: string): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username, password: password ?? process.env.TEST_ADMIN_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

/** Opening cash through the house channel: owner capital posts Dr 1000 /
 * Cr 3000 and the operational flow counts the same inflow. */
async function seedOpeningCash(amount: number, date = '2026-08-01'): Promise<void> {
  const r = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
    .set('Idempotency-Key', `patch-supplierRefund-43-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ amount, capital_date: date, payment_method: 'Cash' });
  expect(r.status).toBe(201);
}

interface PurchaseInfo { purchaseId: number; supplierId: number; warehouseId: number; itemId: number; }

/** Paid purchase through the real payment service. */
async function paidPurchase(total: number): Promise<PurchaseInfo> {
  const itemId = await createItem(`Claim item ${Math.random()}`, cookie);
  const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
  if (!warehouse) throw new Error('Missing fixture warehouse');
  const purchase = await purchaseWithNamedSupplier(`Claim supplier ${Math.random()}`, {
    item_id: itemId, warehouse_id: warehouse.id, quantity: 10, unit_cost: total / 10,
    purchase_date: '2026-08-02',
  }, cookie);
  expect(purchase.status).toBe(201);
  const purchaseId = purchase.body.data?.id ?? purchase.body.id;
  const row = db.prepare<[number], { supplier_id: number }>(
    'SELECT supplier_id FROM purchases WHERE id = ?'
  ).get(purchaseId);
  if (!row) throw new Error('Missing fixture supplier');
  new SupplierPaymentService(db).recordSupplierPayment({
    supplierId: row.supplier_id, paymentDate: '2026-08-02', amount: total,
    paymentMethod: 'Cash', allocations: [{ kind: 'purchase', id: purchaseId, amount: total }],
  });
  return { purchaseId, supplierId: row.supplier_id, warehouseId: warehouse.id, itemId };
}

/** refund_expected return against a purchase, with its credit note + claim ids. */
async function returnAgainstPurchase(info: PurchaseInfo, opts: {
  returnQty?: number; disposition?: string;
} = {}): Promise<{ returnId: number; creditNoteId: number; claimId: number }> {
  const returned = await request(app).post('/api/purchase-returns').set('Cookie', cookie).send({
    return_date: '2026-08-03', source_type: 'PURCHASE', source_id: info.purchaseId,
    warehouse_id: info.warehouseId, disposition: opts.disposition ?? 'refund_expected',
    items: [{ source_item_id: info.purchaseId, quantity: opts.returnQty ?? 10 }],
  });
  expect(returned.status).toBe(201);
  const returnId = returned.body.data?.id ?? returned.body.id;
  const note = db.prepare<[number], { id: number }>(
    'SELECT id FROM credit_notes WHERE source_id = ?'
  ).get(returnId);
  if (!note) throw new Error('Missing credit note');
  const claim = db.prepare<[number], { id: number }>(
    'SELECT id FROM supplier_refund_claims WHERE return_id = ?'
  ).get(returnId);
  if (!claim) throw new Error('Missing auto-opened refund claim');
  return { returnId, creditNoteId: note.id, claimId: claim.id };
}

/** Paid purchase + a refund_expected return against it, via the real API. */
async function paidPurchaseWithReturn(opts: {
  total?: number; returnQty?: number; disposition?: string;
} = {}): Promise<PurchaseInfo & { returnId: number; creditNoteId: number; claimId: number; total: number }> {
  const total = opts.total ?? 100;
  const info = await paidPurchase(total);
  const rest = await returnAgainstPurchase(info, { returnQty: opts.returnQty, disposition: opts.disposition });
  return { ...info, ...rest, total };
}

function cashBankBalance(): number {
  return (db.prepare(`
    SELECT COALESCE(SUM(j.debit - j.credit), 0) AS amount
    FROM journal_lines j JOIN chart_of_accounts a ON a.id = j.account_id
    WHERE a.code IN ('1000', '1010') AND j.voided = 0
  `).get() as { amount: number }).amount;
}

async function receipt(body: Record<string, unknown>, key?: string) {
  const req = request(app).post('/api/supplier-refunds').set('Cookie', cookie).send(body);
  if (key !== undefined) req.set('Idempotency-Key', key);
  return req;
}

describe('PRET-002 supplier refund claims', () => {
  it('a refund_expected return opens a claim and moves no cash', async () => {
    await seedOpeningCash(500);

    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier
    // payment the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();
    expect(before).toBeCloseTo(400, 2);

    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?')
      .get(info.claimId) as {
        claim_no: string; supplier_id: number; status: string;
        amount: number; received_amount: number; written_off_amount: number;
        return_id: number; credit_note_id: number;
      };
    expect(claim.claim_no).toMatch(/^SRC-\d{4}-\d+$/);
    expect(claim.status).toBe('EXPECTED');
    expect(claim.amount).toBe(100);
    expect(claim.received_amount).toBe(0);
    expect(claim.return_id).toBe(info.returnId);
    expect(claim.credit_note_id).toBe(info.creditNoteId);

    // The invariant: expected money is NOT cash. No REFUND_RECEIPT (or any
    // cash-affecting claim) line may exist, and cash/bank are untouched.
    const receiptLines = db.prepare(
      `SELECT COUNT(*) AS n FROM journal_lines WHERE reference_type IN ('REFUND_RECEIPT', 'REFUND_CLAIM_WRITE_OFF')`
    ).get() as { n: number };
    expect(receiptLines.n).toBe(0);
    expect(cashBankBalance()).toBeCloseTo(before, 2);

    // Refunds due is a memo total, not a cash movement.
    const due = await request(app).get('/api/supplier-refunds/claims/due').set('Cookie', cookie);
    expect(due.status).toBe(200);
    expect(due.body.total_due).toBeCloseTo(100, 2);

    expectAllInvariantsHold('claim opened');
  });

  it('a receipt posts REFUND_RECEIPT (Dr cash / Cr AP) and walks the claim to RECEIVED', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier payment
    // the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();

    const first = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId,
      amount: 40, payment_method: 'cash',
    }, '11111111-1111-4111-8111-111111111111');
    expect(first.status).toBe(201);

    let claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; received_amount: number;
    };
    expect(claim.status).toBe('PARTIAL');
    expect(claim.received_amount).toBeCloseTo(40, 2);

    // The receipt carries the cash: Dr 1000 / Cr 2000, typed REFUND_RECEIPT.
    const lines = db.prepare(`
      SELECT a.code, j.debit, j.credit FROM journal_lines j
      JOIN chart_of_accounts a ON a.id = j.account_id
      WHERE j.reference_type = 'REFUND_RECEIPT' AND j.voided = 0
    `).all() as Array<{ code: string; debit: number; credit: number }>;
    expect(lines).toEqual([
      { code: '1000', debit: 40, credit: 0 },
      { code: '2000', debit: 0, credit: 40 },
    ]);
    expect(cashBankBalance()).toBeCloseTo(before + 40, 2);

    // Settling the rest completes the claim.
    const second = await receipt({
      refund_date: '2026-08-06', credit_note_id: info.creditNoteId,
      amount: 60, payment_method: 'bank',
    }, '22222222-2222-4222-8222-222222222222');
    expect(second.status).toBe(201);
    claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; received_amount: number;
    };
    expect(claim.status).toBe('RECEIVED');
    expect(claim.received_amount).toBeCloseTo(100, 2);
    expect(cashBankBalance()).toBeCloseTo(before + 100, 2);
    expectAllInvariantsHold('claim received');
  });

  it('rejects a receipt above the claim remaining by default and routes the excess to an advance on the explicit action', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier payment
    // the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();

    const rejected = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 120,
    }, '33333333-3333-4333-8333-333333333333');
    expect(rejected.status).toBe(400);
    expect(rejected.body.error).toContain('exceeds the remaining balance');
    expect(db.prepare('SELECT COUNT(*) AS n FROM supplier_refunds').get()).toEqual({ n: 0 });

    const accepted = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 120,
      treat_excess_as_advance: true,
    }, '44444444-4444-4444-8444-444444444444');
    expect(accepted.status).toBe(201);
    expect(accepted.body.message).toContain('credit on account');

    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; received_amount: number;
    };
    expect(claim.status).toBe('RECEIVED');
    expect(claim.received_amount).toBeCloseTo(100, 2);

    // One physical cash event: the full 120 arrived. The claim absorbs 100;
    // the 20 overage is supplier credit on account (Cr AP), NOT a 1330
    // advance — a prepayment models cash WE paid out.
    const advance = db.prepare(`
      SELECT COALESCE(SUM(j.debit - j.credit), 0) AS amount
      FROM journal_lines j JOIN chart_of_accounts a ON a.id = j.account_id
      WHERE a.code = '1330' AND j.voided = 0
    `).get() as { amount: number };
    expect(advance.amount).toBe(0);
    expect(cashBankBalance()).toBeCloseTo(before + 120, 2);
    expect(accepted.body.data.amount).toBeCloseTo(120, 2);
    expectAllInvariantsHold('excess as supplier credit');
  });

  it('a standalone claim settles money owed with no return behind it', async () => {
    await seedOpeningCash(500);
    await paidPurchaseWithReturn({ total: 100 }); // context: supplier exists through the API path
    const before = cashBankBalance();

    const supplier = db.prepare<[], { id: number }>('SELECT id FROM suppliers WHERE is_active = 1 LIMIT 1').get();
    if (!supplier) throw new Error('Missing supplier fixture');

    const created = await request(app).post('/api/supplier-refunds/claims')
      .set('Cookie', cookie)
      .set('Idempotency-Key', '55555555-5555-4555-8555-555555555555')
      .send({ supplier_id: supplier.id, claim_date: '2026-08-04', amount: 50, reason: 'Price correction owed' });
    expect(created.status).toBe(201);
    const claimId = created.body.data.id;
    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(claimId) as {
      claim_no: string; status: string; amount: number; credit_note_id: number | null; return_id: number | null;
    };
    expect(claim.status).toBe('EXPECTED');
    expect(claim.amount).toBe(50);
    expect(claim.credit_note_id).toBeNull();
    expect(claim.return_id).toBeNull();
    expect(cashBankBalance()).toBeCloseTo(before, 2);

    const settled = await receipt({
      refund_date: '2026-08-06', claim_id: claimId, amount: 50, payment_method: 'bank',
    }, '66666666-6666-4666-8666-666666666666');
    expect(settled.status).toBe(201);
    expect(settled.body.data.credit_note_id).toBeNull();

    const after = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(claimId) as {
      status: string; received_amount: number;
    };
    expect(after.status).toBe('RECEIVED');
    expect(after.received_amount).toBeCloseTo(50, 2);
    expect(cashBankBalance()).toBeCloseTo(before + 50, 2);
    expectAllInvariantsHold('standalone claim settled');
  });

  it('write-offs require a reason, use 7300 vs AP, and above Rs 1,000 need the owner', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier payment
    // the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();

    const part = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 30,
    }, '77777777-7777-4777-8777-777777777777');
    expect(part.status).toBe(201);

    // Missing reason is refused.
    const noReason = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/write-off`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', '88888888-8888-4888-8888-888888888888')
      .send({});
    expect(noReason.status).toBe(400);

    // Owner writes off the remaining 70 — Dr 7300 / Cr AP.
    const written = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/write-off`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', '99999999-9999-4999-8999-999999999999')
      .send({ reason: 'Supplier went out of business' });
    expect(written.status).toBe(200);
    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; written_off_amount: number;
    };
    expect(claim.status).toBe('RECEIVED');
    expect(claim.written_off_amount).toBeCloseTo(70, 2);
    const lines = db.prepare(`
      SELECT a.code, j.debit, j.credit FROM journal_lines j
      JOIN chart_of_accounts a ON a.id = j.account_id
      WHERE j.reference_type = 'REFUND_CLAIM_WRITE_OFF' AND j.voided = 0
    `).all() as Array<{ code: string; debit: number; credit: number }>;
    expect(lines).toEqual([
      { code: '7300', debit: 70, credit: 0 },
      { code: '2000', debit: 0, credit: 70 },
    ]);
    expect(cashBankBalance()).toBeCloseTo(before + 30, 2);
    expectAllInvariantsHold('write-off posted');
  });

  it('write-offs above Rs 1,000 are refused to a non-owner even with write-off permission', async () => {
    await seedOpeningCash(1500);
    const info = await paidPurchaseWithReturn({ total: 1200 });

    // A non-owner (user role) granted refund + write-off permissions.
    const role = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };
    db.prepare(`
      INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
      SELECT ?, id FROM permissions WHERE permission_name IN
        ('supplier_refunds:read', 'supplier_refunds:create', 'supplier_refunds:write_off')
    `).run(role.id);
    db.prepare(`
      INSERT OR IGNORE INTO users (username, email, password_hash, full_name, role, is_active, role_id)
      VALUES ('claimuser', 'claimuser@x.io', ?, 'Claim User', 'user', 1, ?)
    `).run(bcrypt.hashSync('claim-pass-2026', 10), role.id);
    const userCookie = await getLoginCookie('claimuser', 'claim-pass-2026');
    expect(userCookie).not.toBe('');

    const big = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/write-off`)
      .set('Cookie', userCookie)
      .set('Idempotency-Key', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
      .send({ reason: 'Short paid by supplier' });
    expect(big.status).toBe(403);
    expect(big.body.error).toContain('Rs 1000');

    const small = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/write-off`)
      .set('Cookie', userCookie)
      .set('Idempotency-Key', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
      .send({ amount: 500, reason: 'Minor short pay' });
    expect(small.status).toBe(200);
  });

  it('voiding a receipt releases the claim and unwinds its cash', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier payment
    // the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();

    const posted = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 100,
    }, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    expect(posted.status).toBe(201);
    expect(cashBankBalance()).toBeCloseTo(before + 100, 2);
    const refundId = posted.body.data.id;

    const voided = await request(app).post(`/api/supplier-refunds/${refundId}/void`)
      .set('Cookie', cookie).send({ reason: 'Receipt recorded twice' });
    expect(voided.status).toBe(200);

    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; received_amount: number;
    };
    expect(claim.status).toBe('EXPECTED');
    expect(claim.received_amount).toBe(0);
    expect(cashBankBalance()).toBeCloseTo(before, 2);

    const liveReceipts = db.prepare(
      `SELECT COUNT(*) AS n FROM refund_receipt_allocations WHERE claim_id = ?`
    ).get(info.claimId) as { n: number };
    expect(liveReceipts.n).toBe(0);
    expectAllInvariantsHold('receipt voided');
  });

  it('a return with receipted claims cannot void until the receipts are reversed', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });

    const posted = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 60,
    }, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    expect(posted.status).toBe(201);

    const blocked = await request(app).post(`/api/purchase-returns/${info.returnId}/void`)
      .set('Cookie', cookie).send({ reason: 'Wrong supplier' });
    expect(blocked.status).toBe(409);
    expect(blocked.body.error).toContain('refund claim');
    expect(blocked.body.error).toContain('receipt');

    // Reversing the receipt unblocks the return.
    const unvoid = await request(app).post(`/api/supplier-refunds/${posted.body.data.id}/void`)
      .set('Cookie', cookie).send({ reason: 'Reversing first' });
    expect(unvoid.status).toBe(200);

    const voided = await request(app).post(`/api/purchase-returns/${info.returnId}/void`)
      .set('Cookie', cookie).send({ reason: 'Wrong supplier' });
    expect(voided.status).toBe(200);

    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      status: string; cancelled_reason: string | null;
    };
    expect(claim.status).toBe('CANCELLED');
    expectAllInvariantsHold('return voided after receipt reversal');
  });

  it('refund receipts require an Idempotency-Key and replay instead of double-posting', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    // Baseline after the fixture: opening 500 minus the 100 supplier payment
    // the setup itself posted (Dr AP / Cr cash).
    const before = cashBankBalance();

    const missingKey = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 50,
    });
    expect(missingKey.status).toBe(400);
    expect(missingKey.body.error).toContain('Idempotency-Key');

    const standaloneMissing = await request(app).post('/api/supplier-refunds/claims')
      .set('Cookie', cookie)
      .send({ supplier_id: 1, claim_date: '2026-08-04', amount: 10 });
    expect(standaloneMissing.status).toBe(400);

    const key = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    const first = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 50,
    }, key);
    expect(first.status).toBe(201);
    const replay = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 50,
    }, key);
    expect(replay.status).toBe(201);
    expect(replay.body.idempotentReplay).toBe(true);
    expect(replay.body.data.id).toBe(first.body.data.id);

    expect(cashBankBalance()).toBeCloseTo(before + 50, 2);
    const claim = db.prepare('SELECT * FROM supplier_refund_claims WHERE id = ?').get(info.claimId) as {
      received_amount: number;
    };
    expect(claim.received_amount).toBeCloseTo(50, 2);
  });

  it('receipts accept only cash or bank transfer', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });

    const refused = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId,
      amount: 50, payment_method: 'easypaisa',
    }, 'ffff0f0f-ffff-4fff-8fff-ffffffffffff');
    expect(refused.status).toBe(400);
    expect(refused.body.error).toContain('Cash or Bank transfer only');
  });

  it('lists claims with filters and cancels a live claim with no receipts', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });

    // List: the auto-opened claim is visible, and the status filter finds it.
    const listed = await request(app).get('/api/supplier-refunds/claims')
      .set('Cookie', cookie);
    expect(listed.status).toBe(200);
    const rows = listed.body.data as Array<{ id: number; status: string }>;
    expect(rows.some((row) => row.id === info.claimId && row.status === 'EXPECTED')).toBe(true);

    const filtered = await request(app)
      .get('/api/supplier-refunds/claims?status=EXPECTED&supplier_id=' + info.supplierId)
      .set('Cookie', cookie);
    expect(filtered.status).toBe(200);
    expect((filtered.body.data as Array<{ id: number }>)
      .some((row) => row.id === info.claimId)).toBe(true);

    // Refunds due is a memo total, not a cash figure.
    const due = await request(app).get('/api/supplier-refunds/claims/due')
      .set('Cookie', cookie);
    expect(due.status).toBe(200);
    expect(due.body.data.some((row: { id: number }) => row.id === info.claimId)).toBe(true);

    // Cancel without receipts succeeds and frees the claim.
    const cancelled = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/cancel`)
      .set('Cookie', cookie)
      .send({ reason: 'Supplier rejected the return' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.data.status).toBe('CANCELLED');

    const after = await request(app)
      .get('/api/supplier-refunds/claims?status=CANCELLED')
      .set('Cookie', cookie);
    expect((after.body.data as Array<{ id: number }>)
      .some((row) => row.id === info.claimId)).toBe(true);
  });

  it('cancelling a claim that holds receipts is refused', async () => {
    await seedOpeningCash(500);
    const info = await paidPurchaseWithReturn({ total: 100 });
    const rec = await receipt({
      refund_date: '2026-08-05', credit_note_id: info.creditNoteId, amount: 40,
    }, 'aaa0a0a0-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(rec.status).toBe(201);

    const cancelled = await request(app)
      .post(`/api/supplier-refunds/claims/${info.claimId}/cancel`)
      .set('Cookie', cookie)
      .send({ reason: 'Attempt over a receipted claim' });
    expect(cancelled.status).toBe(400);
    expect(cancelled.body.error).toMatch(/recorded receipt/i);
    const claim = db.prepare('SELECT status FROM supplier_refund_claims WHERE id = ?')
      .get(info.claimId) as { status: string };
    expect(claim.status).toBe('PARTIAL');
  });
});
