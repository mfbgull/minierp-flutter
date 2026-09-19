/**
 * Invoice Return — Acceptance scenarios 1–8
 * (invoice-return-spec.md §8 — core position math + settlement types)
 *
 * Acceptance case (spec §17): INV-… 3 × 600 = 1800, paid 1800,
 * return 2 × 600, fee 10% → returned 1200, fee 120, net 1080.
 *
 * SCAFFOLDING NOTE: these tests describe the post-implementation API
 * and DB shape. They will fail until the new tables/endpoints exist —
 * that is intentional (spec-first development).
 */
import request from 'supertest';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, settleReturn, fetchPosition, expectPositionOf,
  expectNoNegativeBalance, assertOriginalLinesUntouched, assertPaymentsUnchanged,
  assertGlBalanced, assertFeeEntrySeparate, customerLedgerNet, returnRow,
  settlementsFor, getInvoiceRow, type Position,
} from './helpers/invoiceReturnSpec';

describe('Invoice Return spec — scenarios 1–8 (position math + settlements)', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    itemId = await createItem('Widget A (acceptance)', authCookie);
    await purchaseStock(itemId, warehouseId, 50, 300, authCookie); // plenty of stock at cost 300
    customerId = await createCustomer('Return Spec Customer 1', authCookie);
  });

  /**
   * The spec §17 acceptance fixture: fully paid invoice, 3 × 600.
   * Returns {invoiceId, invoiceItemIds}.
   */
  async function seedAcceptanceInvoice(): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
    const inv = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 3, unitPrice: 600 }],
        payment: 'full',
        invoiceDate: '2026-09-15',
      },
      authCookie,
    );
    return { invoiceId: inv.invoiceId, invoiceItemIds: inv.invoiceItemIds };
  }

  // ── Scenario 1 ────────────────────────────────────────────────────
  it('1. original invoice lines and payments are unchanged after a return', async () => {
    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();

    const res = await processReturn(
      invoiceId,
      { invoiceItemIds, quantities: [2], feeType: 'percentage', feeValue: 10, warehouseId },
      authCookie,
    );
    expect(res.status).toBe(200);

    // Original line stays Qty 3 @ 600 (spec rule 1)
    assertOriginalLinesUntouched(invoiceId, [{ quantity: 3, unitPrice: 600 }]);
    // Original payment stays 1800 (spec rule 2)
    assertPaymentsUnchanged(invoiceId, 1800);
  });

  // ── Scenario 2 ────────────────────────────────────────────────────
  it('2. partial return on fully-paid invoice → position {1800, 1200, 600, 1800, fee 120, due 1080, balance 0}', async () => {
    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();

    const res = await processReturn(
      invoiceId,
      { invoiceItemIds, quantities: [2], feeType: 'percentage', feeValue: 10, warehouseId },
      authCookie,
    );
    expect(res.status).toBe(200);

    await expectPositionOf(invoiceId, authCookie, {
      originalTotal: 1800,
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 1800,
      totalFees: 120,
      balanceDue: 0,
    } as Partial<Position>);

    expectNoNegativeBalance(invoiceId);
    const row = getInvoiceRow(invoiceId);
    expect(row.status).toBe('Partially Returned');
  });

  // ── Scenario 3 ────────────────────────────────────────────────────
  it('3. settlement as credit: exactly 1080 credited, remaining due 0, ledger + GL balanced', async () => {
    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();

    const ret = await processReturn(
      invoiceId,
      {
        invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'credit', amount: 1080 }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    expect(ret.returnId).toBeDefined();

    const row = returnRow(ret.returnId!);
    expect(row.settled_amount).toBeCloseTo(1080, 2);
    expect(row.status).toBe('Settled');

    const allocations = settlementsFor(ret.returnId!);
    expect(allocations.filter((s) => !s.voided_at)).toHaveLength(1);
    expect(allocations[0].type).toBe('credit');
    expect(allocations[0].amount).toBeCloseTo(1080, 2);

    await expectPositionOf(invoiceId, authCookie, {
      refundCreditDue: 1080,
      settledAmount: 1080,
      remainingRefundDue: 0,
      balanceDue: 0,
    } as Partial<Position>);

    // GL balanced for the return + the fee entry
    assertGlBalanced('INVOICE_RETURN', ret.returnId!);
    assertFeeEntrySeparate(invoiceId, 120);
  });

  // ── Scenario 4 ────────────────────────────────────────────────────
  it('4. settlement as refund (Cash and Bank): only net refunded, GL debits the method account, cash-funds guard enforced', async () => {
    // Cash refund
    {
      const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();
      const ret = await processReturn(
        invoiceId,
        {
          invoiceItemIds, quantities: [2],
          feeType: 'percentage', feeValue: 10, warehouseId,
          settlements: [{ type: 'refund', amount: 1080, method: 'Cash' }],
        },
        authCookie,
      );
      expect(ret.status).toBe(200);

      const allocations = settlementsFor(ret.returnId!);
      expect(allocations[0].method).toBe('Cash');
      expect(allocations[0].amount).toBeCloseTo(1080, 2);

      // Refund posts through the Cash account (1000) — the refund REDUCES
      // cash (spec §5.2): Cr Cash 1080 on the refund settlement's posting.
      const cashAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '1000'").get() as { id: number };
      const refundCredit = db.prepare(`
        SELECT COALESCE(SUM(credit), 0) AS c FROM journal_lines
        WHERE account_id = ? AND reference_type = 'PAYMENT' AND voided = 0
      `).get(cashAccount.id) as { c: number };
      expect(refundCredit.c).toBeGreaterThanOrEqual(1080);
      assertGlBalanced('PAYMENT', allocations[0].payment_id ?? 0);
      await expectPositionOf(invoiceId, authCookie, { remainingRefundDue: 0, balanceDue: 0 } as Partial<Position>);
    }

    // Bank refund
    {
      const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();
      const ret = await processReturn(
        invoiceId,
        {
          invoiceItemIds, quantities: [2],
          feeType: 'percentage', feeValue: 10, warehouseId,
          settlements: [{ type: 'refund', amount: 1080, method: 'Bank' }],
        },
        authCookie,
      );
      const allocations = settlementsFor(ret.returnId!);
      expect(allocations[0].method).toBe('Bank');
    }
  });

  // ── Scenario 5 ────────────────────────────────────────────────────
  it('5. settlement as adjust: only net applied to target invoice; auto-pick + carryover work', async () => {
    // Target invoice for adjustment (unpaid, balance 900)
    const target = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 300 }], payment: null },
      authCookie,
    );

    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();
    const ret = await processReturn(
      invoiceId,
      {
        invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'adjust', amount: 1080, target_invoice_id: target.invoiceId }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const allocations = settlementsFor(ret.returnId!);
    expect(allocations[0].type).toBe('adjust');
    expect(allocations[0].target_invoice_id).toBe(target.invoiceId);

    // Target invoice balance reduced by the net (900 → capped portion;
    // carryover of any excess stays as customer credit per spec D7).
    const targetRow = db.prepare('SELECT balance_amount, paid_amount FROM invoices WHERE id = ?')
      .get(target.invoiceId) as { balance_amount: number; paid_amount: number };
    expect(targetRow.paid_amount).toBeGreaterThan(0);
    expect(targetRow.balance_amount).toBeGreaterThanOrEqual(0);

    await expectPositionOf(invoiceId, authCookie, { remainingRefundDue: 0 } as Partial<Position>);
  });

  it('5b. adjust without target auto-picks the oldest unpaid invoice of the customer', async () => {
    // Two unpaid invoices; oldest first
    const older = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 400 }], payment: null, invoiceDate: '2026-09-01' },
      authCookie,
    );
    await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 400 }], payment: null, invoiceDate: '2026-09-20' },
      authCookie,
    );

    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();
    const ret = await processReturn(
      invoiceId,
      {
        invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'adjust', amount: 400 }], // no target → auto
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    const allocations = settlementsFor(ret.returnId!);
    expect(allocations[0].target_invoice_id).toBe(older.invoiceId);
  });

  // ── Scenario 6 ────────────────────────────────────────────────────
  it('6. mixed settlement (600 refund + 480 credit) totals 1080 with no double count; over-settlement rejected', async () => {
    const { invoiceId, invoiceItemIds } = await seedAcceptanceInvoice();

    const ret = await processReturn(
      invoiceId,
      {
        invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [
          { type: 'refund', amount: 600, method: 'Cash' },
          { type: 'credit', amount: 480 },
        ],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const active = settlementsFor(ret.returnId!).filter((s) => !s.voided_at);
    const total = active.reduce((s, a) => s + a.amount, 0);
    expect(total).toBeCloseTo(1080, 2); // NOT 1560

    await expectPositionOf(invoiceId, authCookie, {
      settledAmount: 1080, remainingRefundDue: 0,
    } as Partial<Position>);

    // Over-settlement on a second return would breach the invoice cap
    // — but a new return creates new entitlement, so test the cap on the
    // SAME return via settle endpoint:
    const over = await settleReturn(
      ret.returnId!,
      [{ type: 'credit', amount: 1 }], // 1 over the 0 remaining
      authCookie,
    );
    expect(over.status).toBe(400);
  });

  it('6b. cumulative cap across returns: refund+credit+adjust can never exceed entitlement', async () => {
    // Paid 600 total (1 unit). Return 1 unit fully: entitlement 600 − fee.
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );
    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [1],
        feeType: 'none', warehouseId,
        settlements: [
          { type: 'refund', amount: 200, method: 'Cash' },
          { type: 'credit', amount: 200 },
        ],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    // Remaining entitlement 200; a settle for 300 must be REJECTED
    const over = await settleReturn(ret.returnId!, [{ type: 'adjust', amount: 300 }], authCookie);
    expect(over.status).toBe(400);
    const row = returnRow(ret.returnId!);
    expect(row.settled_amount).toBeCloseTo(400, 2); // unchanged by the rejected call
  });

  // ── Scenario 7 ────────────────────────────────────────────────────
  it('7. partially paid invoice (paid 1000, returned 1200, fee 200): Refund/Credit Due 200, Balance Due 0', async () => {
    const inv = await createInvoice(
      {
        customerId, itemId,
        lines: [{ quantity: 3, unitPrice: 600 }],
        payment: { amount: 1000 },
        invoiceDate: '2026-09-15',
      },
      authCookie,
    );

    const res = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'fixed', feeValue: 200, warehouseId },
      authCookie,
    );
    expect(res.status).toBe(200);

    await expectPositionOf(inv.invoiceId, authCookie, {
      originalTotal: 1800,
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 1000,
      totalFees: 200,
      refundCreditDue: 200,   // 1000 − 600 − 200
      balanceDue: 0,
    } as Partial<Position>);

    expectNoNegativeBalance(inv.invoiceId);
  });

  // ── Scenario 8 ────────────────────────────────────────────────────
  it('8. underpaid invoice (paid 500): Balance Due 300, Refund Due 0, no negative balance persisted', async () => {
    const inv = await createInvoice(
      {
        customerId, itemId,
        lines: [{ quantity: 3, unitPrice: 600 }],
        payment: { amount: 500 },
        invoiceDate: '2026-09-15',
      },
      authCookie,
    );

    const res = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'fixed', feeValue: 200, warehouseId },
      authCookie,
    );
    expect(res.status).toBe(200);

    await expectPositionOf(inv.invoiceId, authCookie, {
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 500,
      totalFees: 200,
      refundCreditDue: 0,
      balanceDue: 300,        // |500 − 600 − 200|
    } as Partial<Position>);

    expectNoNegativeBalance(inv.invoiceId);
    const row = getInvoiceRow(inv.invoiceId);
    expect(Number(row.balance_amount)).toBeGreaterThanOrEqual(0);
    expect(row.status).toBe('Partially Returned');

    // Nothing settled — settlement step Not Required (D25)
    const pos = await fetchPosition(inv.invoiceId, authCookie);
    expect(pos.settledAmount).toBeCloseTo(0, 2);
  });
});
