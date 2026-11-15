/**
 * Regression proofs for the money-path gaps found in the audit review pass
 * (task 4). GAP 2 is RED against the unfixed code; GAP 1 was RED until the
 * claim moved inside the settle transaction, and now guards that it stays
 * there.
 *
 * GAP 1 — settle-return idempotency claim must run INSIDE the settle txn.
 *   invoiceReturnController.settleReturn() must claim the Idempotency-Key in
 *   the same transaction as InvoiceReturnService.settleReturn(). Claiming
 *   afterwards left a crash window with no key row, so a retry paid twice.
 *   Same shape as expenseController's EXPENSE_CREATE claim.
 *
 * GAP 2 — salary / loan disbursement skip assertCashTimeline.
 *   Both call only assertSufficientFunds, a cumulative balance as of the
 *   payment date. That balance is right at ITS date, but the check ignores
 *   every other day, so a backdated outflow can post when a later day is
 *   already overdrawn.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createItem, purchaseStock } from './helpers/invoiceReturnSpec';
import { IDEMPOTENCY_SCOPES } from '../utils/idempotency';

let cookie = '';
let itemId = 0;
let customerId = 0;
let warehouseId = 0;

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

beforeAll(async () => {
  cookie = await getLoginCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  itemId = await createItem('Review Gap Widget', cookie);
  customerId = await createCustomer('Review Gap Customer', cookie);
  // Opening cash first, so the account has a real balance to overdraw.
  const capital = await request(app)
    .post('/api/owner-equity/capital')
    .set('Cookie', cookie)
    .set('Idempotency-Key', `gap-cap-${Date.now()}`)
    .send({ amount: 50_000, capital_date: '2026-08-01', payment_method: 'Cash' });
  expect([200, 201]).toContain(capital.status);
  await purchaseStock(itemId, warehouseId, 100, 50, cookie, '2026-09-01');
});

beforeEach(() => { db.exec('SAVEPOINT review_gap'); });
afterEach(() => { db.exec('ROLLBACK TO review_gap; RELEASE review_gap'); });

describe('GAP 1: settle-return idempotency claim vs transaction boundary', () => {
  /**
   * STRUCTURAL PROOF (no request instrumentation needed). The controller
   * `invoiceReturnController.settleReturn` destructures `claimIdempotencyKey`
   * at import, so a module-property patch cannot intercept the call. Instead,
   * assert the invariant at the source level: the claim call must appear
   * BEFORE the service call's transaction commits — i.e. inside the same
   * db.transaction. The safe pattern (expenseController) is contrasted in the
   * same test so the rule is documented, not just asserted.
   */
  it('claims the key inside a transaction (source invariant, like expenseController)', async () => {
    const fs = await import('fs');
    const path = await import('path');
    const routeSrc = fs.readFileSync(
      path.resolve(__dirname, '..', 'controllers', 'invoiceReturnController.ts'),
      'utf8',
    );
    const safeSrc = fs.readFileSync(
      path.resolve(__dirname, '..', 'controllers', 'expenseController.ts'),
      'utf8',
    );

    // The safe pattern wraps the write and the claim in one db.transaction.
    const safeBlock = safeSrc.slice(safeSrc.indexOf('db.transaction('));
    const safeTxnEnd = safeBlock.indexOf('})()');
    const safeTxnBody = safeBlock.slice(0, safeTxnEnd + 3);
    expect(safeTxnBody).toContain('claimIdempotencyKey');

    // The settle path must do the same. Today it does not: the claim follows
    // the service call, which has already committed its own transaction.
    const settleFn = routeSrc.slice(
      routeSrc.indexOf('function settleReturn('),
      routeSrc.indexOf('function voidReturn('),
    );

    // The claim must sit INSIDE the controller's own transaction. Asserting
    // only that 'db.transaction(' appears is too weak: the broken shape could
    // return by simply wrapping an unrelated statement.
    const txnStart = settleFn.indexOf('db.transaction(');
    expect(txnStart).toBeGreaterThan(-1);
    const txnEnd = settleFn.indexOf('})()', txnStart);
    expect(txnEnd).toBeGreaterThan(txnStart);
    const txnBody = settleFn.slice(txnStart, txnEnd + 3);
    expect(txnBody).toContain('claimIdempotencyKey');
    expect(txnBody).toContain('settleReturn(');

    // And the service call must not sit outside the transaction, which is
    // what made the claim a separate, non-atomic step before the fix.
    const beforeTxn = settleFn.slice(0, txnStart);
    expect(beforeTxn).not.toContain('InvoiceReturnService.settleReturn(');
  });

  it('does not settle twice when the same key is retried after a committed settle', async () => {
    const inv = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', `gap2-inv-${Date.now()}`)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-11',
        due_date: '2027-12-31',
        items: [{ item_id: itemId, quantity: 2, unit_price: 100 }],
        record_payment: true,
        payment: { payment_date: '2026-09-11', amount: 200, payment_method: 'Cash' },
      });
    const invItems = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').all(inv.body.id) as Array<{ id: number }>;
    const ret = await request(app)
      .post(`/api/invoices/${inv.body.id}/return`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', `gap2-ret-${Date.now()}`)
      .send({
        items: [{ invoice_item_id: invItems[0].id, return_quantity: 1 }],
        fee_type: 'none', fee_value: 0, return_date: '2026-09-13',
        warehouse_id: warehouseId, reason: 'gap2 review', disposition: 'credit',
      });
    const returnId = ret.body?.data?.returnId ?? ret.body?.data?.id;

    const key = `gap2-settle-${Date.now()}`;
    const body = { allocations: [{ type: 'refund', amount: 100, method: 'Cash' }] };
    const first = await request(app).post(`/api/invoice-returns/${returnId}/settle`)
      .set('Cookie', cookie).set('Idempotency-Key', key).send(body);
    expect([200, 201]).toContain(first.status);

    // Simulate the crash window: delete the key row the claim wrote, then
    // retry the SAME key. If the claim were inside the settle transaction,
    // the settle and the key would be one atomic unit and this state could
    // not exist. Deleting it models "settle committed, claim never landed".
    db.prepare('DELETE FROM idempotency_keys WHERE scope = ? AND key = ?')
      .run(IDEMPOTENCY_SCOPES.INVOICE_RETURN_SETTLE, key);

    const refundsBefore = db
      .prepare("SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = 'RETURN_SETTLEMENT' AND voided = 0")
      .get() as { c: number };

    await request(app).post(`/api/invoice-returns/${returnId}/settle`)
      .set('Cookie', cookie).set('Idempotency-Key', key).send(body);

    const refundsAfter = db
      .prepare("SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = 'RETURN_SETTLEMENT' AND voided = 0")
      .get() as { c: number };

    // The settled return cannot be settled again, so no new money moves.
    // This passes today (the return status is the second line of defense) —
    // it pins the behavior so a future unwrapping of the guard is caught.
    expect(refundsAfter.c).toBe(refundsBefore.c);
  });
});

describe('GAP 2: a backdated cash outflow is checked only at its own date', () => {
  /**
   * PROVEN BEHAVIOUR (probe, 2026-11-15). `postSalaryEntry` and
   * `postLoanDisbursement` call only `assertSufficientFunds`, a CUMULATIVE
   * balance as of the payment date. They never call `assertCashTimeline`,
   * the running check that every other outflow path uses.
   *
   * The cumulative balance is correct at the payment date, so the guard is
   * not wrong about the day it checks. The gap is the days it does NOT check.
   * Sequence that breaks the books:
   *
   *   1. cash +30,000 on 2026-09-20
   *   2. loan 25,000 dated 2026-09-25   -> posts (30,000 at 09-25)
   *   3. loan 28,000 dated 2026-09-22   -> posts (30,000 at 09-22)
   *
   * Step 3 sees only 09-22, where 30,000 is available, and ignores the
   * 25,000 already spent on 09-25. The book then holds -23,000 on 09-25.
   * `assertCashTimeline` detects exactly this and is the guard that must run.
   *
   * This test is RED until steps 2 and 3 are wrapped so the timeline holds.
   */
  it('keeps the running cash timeline non-negative when an outflow is backdated', async () => {
    const emp = await request(app)
      .post('/api/employees')
      .set('Cookie', cookie)
      .send({ first_name: 'Gap', last_name: 'Employee', salary: 1000, hire_date: '2026-01-01' });
    expect([200, 201]).toContain(emp.status);
    const employeeId = emp.body?.data?.id ?? emp.body?.id;
    expect(employeeId).toBeTruthy();

    // 1. Opening cash in a FRESH account. The suite's opening 50,000 sits in
    // Cash (1000); using JazzCash (1030) keeps this scenario's arithmetic
    // isolated, so a real deficit cannot be masked by unrelated cash.
    const capital = await request(app)
      .post('/api/owner-equity/capital')
      .set('Cookie', cookie)
      .set('Idempotency-Key', `gap-cap-${Date.now()}`)
      .send({ amount: 30_000, capital_date: '2026-09-20', payment_method: 'JazzCash' });
    expect([200, 201]).toContain(capital.status);

    // 2. The LATER outflow first: 25,000 on 09-25.
    const late = await request(app)
      .post(`/api/employees/${employeeId}/loans`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', `gap-late-${Date.now()}`)
      .send({ amount: 25_000, disbursement_date: '2026-09-25', payment_method: 'JazzCash', description: 'late' });
    expect([200, 201]).toContain(late.status);

    // 3. The BACKDATED outflow: 28,000 on 09-22. Its own date has 30,000, so
    // the point-in-time check passes — but 09-25 already spent 25,000.
    // Before the fix this posted (201); now it must be refused.
    const early = await request(app)
      .post(`/api/employees/${employeeId}/loans`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', `gap-early-${Date.now()}`)
      .send({ amount: 28_000, disbursement_date: '2026-09-22', payment_method: 'JazzCash', description: 'early' });
    expect(early.status).toBeGreaterThanOrEqual(400);

    // The invariant: no cash day may go negative. `assertCashTimeline` cannot
    // be scoped to a window
    // dates, starting from the 2026-09-20 capital. JazzCash keeps it isolated.
    const days = db.prepare(`
      WITH daily AS (
        SELECT line_date, SUM(ROUND(debit * 100) - ROUND(credit * 100)) AS movement
        FROM journal_lines
        WHERE account_id = (SELECT id FROM chart_of_accounts WHERE code = '1030') AND voided = 0
        GROUP BY line_date
      )
      SELECT line_date, SUM(movement) OVER (ORDER BY line_date) AS balance FROM daily
      WHERE line_date >= '2026-09-20'
    `).all() as Array<{ line_date: string; balance: number }>;

    const negative = days.filter((d) => d.balance < 0);
    expect(negative).toEqual([]);
  });
});
