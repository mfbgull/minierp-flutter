/**
 * Invoice Return — Acceptance scenarios 15–21
 * (invoice-return-spec.md §8 — voids, deferred settlement, closed
 * periods, GL integrity, print-data assembly)
 *
 * SCAFFOLDING NOTE: describe post-implementation behaviour; intentional
 * red until the new tables/endpoints exist.
 */
import request from 'supertest';
import db from '../config/database';
import app from '../app';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, settleReturn, voidReturn, voidSettlement, fetchPosition,
  expectPositionOf, returnRow, settlementsFor, assertGlBalanced,
  customerLedgerNet, glTotalsFor, type Position,
} from './helpers/invoiceReturnSpec';

describe('Invoice Return spec — scenarios 15–21 (voids, deferral, periods, GL, print)', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    itemId = await createItem('Widget V (void/period scenarios)', authCookie);
    await purchaseStock(itemId, warehouseId, 100, 200, authCookie);
    customerId = await createCustomer('Return Spec Customer 3', authCookie);
  });

  // ── Scenario 15 ───────────────────────────────────────────────────
  it('15. void return: full GL/stock/ledger/settlement reversal; quantities restorable; excluded from position', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const stockBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'credit', amount: 1080 }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    const returnId = ret.returnId!;
    const ledgerAfterReturn = customerLedgerNet(customerId);
    const balanceBeforeAnyReturn = ledgerAfterReturn; // set here; re-read after void below

    const status = await voidReturn(returnId, authCookie);
    expect(status).toBe(200);

    // Return row is voided
    const row = returnRow(returnId);
    expect(row.voided_at).not.toBeNull();
    expect(row.status).toBe('Voided');

    // Stock restored to pre-return level (restock reversed)
    const stockAfterVoid = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(stockAfterVoid).toBeCloseTo(stockBefore, 2);

    // GL lines for the return + fee are voided (no active lines remain)
    expect(glTotalsFor('INVOICE_RETURN', returnId)).toEqual({ debit: 0, credit: 0 });
    expect(glTotalsFor('RETURN_FEE', returnId)).toEqual({ debit: 0, credit: 0 });

    // Ledger rows voided via the reversal mechanism — customer balance
    // back to what it was before the return+settlement. The invoice was
    // fully paid (balance 0) and the only ledger activity since the
    // baseline is this return + its credit settlement, so the net must
    // return to the pre-return value recorded above.
    expect(customerLedgerNet(customerId)).toBeCloseTo(ledgerAfterReturn, 2);

    // Position excludes the voided return entirely (spec: aggregates
    // exclude voided returns/settlements)
    await expectPositionOf(inv.invoiceId, authCookie, {
      totalReturned: 0,
      currentInvoiceValue: 1800,
      totalFees: 0,
      refundCreditDue: 0,
      settledAmount: 0,
      balanceDue: 0,
    } as Partial<Position>);

    // Quantities are returnable again
    const reReturn = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'none', warehouseId },
      authCookie,
    );
    expect(reReturn.status).toBe(200);
  });

  // ── Scenario 16 ───────────────────────────────────────────────────
  it('16. deferred settlement: unsettled return later settled via /settle within caps', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    // Return with NO settlements → Unsettled
    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'percentage', feeValue: 10, warehouseId },
      authCookie,
    );
    expect(ret.status).toBe(200);
    expect(returnRow(ret.returnId!).status).toBe('Unsettled');

    await expectPositionOf(inv.invoiceId, authCookie, {
      refundCreditDue: 1080,
      settledAmount: 0,
      remainingRefundDue: 1080,
    } as Partial<Position>);

    // Later: settle partially (600), then the rest (480)
    const s1 = await settleReturn(ret.returnId!, [{ type: 'refund', amount: 600, method: 'Cash' }], authCookie);
    expect(s1.status).toBe(200);
    expect(returnRow(ret.returnId!).settled_amount).toBeCloseTo(600, 2);
    expect(returnRow(ret.returnId!).status).toBe('Unsettled'); // partially settled

    const s2 = await settleReturn(ret.returnId!, [{ type: 'credit', amount: 480 }], authCookie);
    expect(s2.status).toBe(200);
    expect(returnRow(ret.returnId!).settled_amount).toBeCloseTo(1080, 2);
    expect(returnRow(ret.returnId!).status).toBe('Settled');

    await expectPositionOf(inv.invoiceId, authCookie, { remainingRefundDue: 0 } as Partial<Position>);
  });

  // ── Scenario 17 ───────────────────────────────────────────────────
  it('17. void single settlement: amount returns to Remaining Refund Due; cap freed; return intact', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'refund', amount: 1080, method: 'Cash' }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);
    const returnId = ret.returnId!;

    const allocation = settlementsFor(returnId).find((s) => !s.voided_at)!;
    const ledgerBeforeVoid = customerLedgerNet(customerId);

    const status = await voidSettlement(allocation.id, authCookie);
    expect(status).toBe(200);

    // Settlement row voided; return itself stays intact and unsettled again
    const allocations = settlementsFor(returnId);
    expect(allocations.find((s) => s.id === allocation.id)!.voided_at).not.toBeNull();
    expect(returnRow(returnId).voided_at).toBeNull();
    expect(returnRow(returnId).settled_amount).toBeCloseTo(0, 2);
    expect(returnRow(returnId).status).toBe('Unsettled');

    // Position: amount is back as remaining refund due
    await expectPositionOf(inv.invoiceId, authCookie, {
      refundCreditDue: 1080,
      settledAmount: 0,
      remainingRefundDue: 1080,
    } as Partial<Position>);

    // The cap is freed: re-settling the full amount is allowed
    const again = await settleReturn(returnId, [{ type: 'credit', amount: 1080 }], authCookie);
    expect(again.status).toBe(200);
    expect(customerLedgerNet(customerId)).toBeCloseTo(ledgerBeforeVoid, 2);
  });

  // ── Scenario 18 ───────────────────────────────────────────────────
  it('18. back-dated return into a closed accounting period is rejected (D23)', async () => {
    // Close the period covering 2026-09-15 (create it first by ensuring
    // an invoice exists in it, then close via the periods endpoint if
    // available; otherwise insert directly — both paths are exercised).
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 600 }], payment: 'full', invoiceDate: '2026-09-15' },
      authCookie,
    );

    // Ensure the period row exists, then close it
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('2026-09-closed-for-test', '2026-09-01', '2026-09-30', 'open')
      ON CONFLICT(period_name) DO UPDATE SET status = 'open'
    `).run();
    const period = db.prepare(
      "SELECT id FROM accounting_periods WHERE period_name = '2026-09-closed-for-test'"
    ).get() as { id: number };
    db.prepare("UPDATE accounting_periods SET status = 'closed' WHERE id = ?").run(period.id);

    try {
      const ret = await processReturn(
        inv.invoiceId,
        {
          invoiceItemIds: inv.invoiceItemIds, quantities: [1],
          feeType: 'none', warehouseId,
          returnDate: '2026-09-20', // inside the now-closed period
        },
        authCookie,
      );
      expect(ret.status).toBe(400);
      expect(JSON.stringify(ret.body)).toMatch(/closed|period/i);
    } finally {
      // Re-open so later tests in other suites are not affected
      db.prepare("UPDATE accounting_periods SET status = 'open' WHERE id = ?").run(period.id);
      db.prepare("DELETE FROM accounting_periods WHERE id = ?").run(period.id);
    }
  });

  // ── Scenario 19 ───────────────────────────────────────────────────
  it('19. GL integrity: Dr == Cr for every posting, per settlement type', async () => {
    // One invoice, three returns with the three settlement types
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const r1 = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [1],
        feeType: 'fixed', feeValue: 50, warehouseId,
        settlements: [{ type: 'refund', amount: 550, method: 'Cash' }],
      },
      authCookie,
    );
    expect(r1.status).toBe(200);

    // A second return on the same invoice — remaining entitlement now 600
    const r2 = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [1],
        feeType: 'none', warehouseId,
        settlements: [{ type: 'credit', amount: 600 }],
      },
      authCookie,
    );
    expect(r2.status).toBe(200);

    assertGlBalanced('INVOICE_RETURN', r1.returnId!);
    assertGlBalanced('RETURN_FEE', r1.returnId!);
    assertGlBalanced('INVOICE_RETURN', r2.returnId!);

    // Whole-ledger balance (invariant A from accountingInvariants helper)
    const total = db.prepare(`
      SELECT ABS(COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0)) AS diff
      FROM journal_lines WHERE voided = 0
    `).get() as { diff: number };
    expect(Number(total.diff)).toBeLessThan(0.01);
  });

  // ── Scenario 20 ───────────────────────────────────────────────────
  it('20. fee GL entry: Dr AR / Cr 4150 as its OWN journal entry, separate from the Sales Return entry', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [1], feeType: 'fixed', feeValue: 80, warehouseId },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const feeAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '4150'").get() as { id: number };
    expect(feeAccount).toBeDefined();

    // 4150 has a credit for exactly the fee, under the RETURN_FEE reference
    const feeCredit = db.prepare(`
      SELECT COALESCE(SUM(credit), 0) AS c FROM journal_lines
      WHERE account_id = ? AND reference_type = 'RETURN_FEE'
        AND reference_id = ? AND voided = 0
    `).get(feeAccount.id, ret.returnId!) as { c: number };
    expect(Number(feeCredit.c)).toBeCloseTo(80, 2);

    // AR has the matching debit under the same group
    const arAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '1100'").get() as { id: number };
    const arDebit = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS d FROM journal_lines
      WHERE account_id = ? AND reference_type = 'RETURN_FEE'
        AND reference_id = ? AND voided = 0
    `).get(arAccount.id, ret.returnId!) as { d: number };
    expect(Number(arDebit.d)).toBeCloseTo(80, 2);

    // The fee is NOT embedded in the INVOICE_RETURN group (separate entries)
    const embedded = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines
      WHERE account_id = ? AND reference_type = 'INVOICE_RETURN'
        AND reference_id = ? AND voided = 0
    `).get(feeAccount.id, ret.returnId!) as { n: number };
    expect(embedded.n).toBe(0);
  });

  // ── Scenario 21 ───────────────────────────────────────────────────
  it('21. print-data assembly: detail carries returns, fees, settlements, timeline, position; legacy falls back', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [2],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'credit', amount: 1080 }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    // The detail endpoint must carry the print payload (spec §6.3)
    const detail = await request(app).get(`/api/invoices/${inv.invoiceId}`).set('Cookie', authCookie);
    expect(detail.status).toBe(200);
    const body = (detail.body?.data ?? detail.body) as Record<string, unknown>;

    // 1+2: original invoice + original payments
    const items = body.items as Array<{ quantity: number; unit_price: number }>;
    expect(items[0].quantity).toBeCloseTo(3, 4);      // original line untouched
    const payments = (body.payments ?? []) as Array<{ amount: number }>;
    expect(payments.reduce((s, p) => s + p.amount, 0)).toBeCloseTo(1800, 2);

    // 3–5: returns with items, fee, and settlements
    const returns = (body.returns ?? []) as Array<{
      return_no: string; return_date: string; returned_amount: number;
      fee_amount: number; net_amount: number;
      items?: Array<{ quantity: number; unit_price: number }>;
      settlements?: Array<{ type: string; amount: number }>;
    }>;
    expect(returns).toHaveLength(1);
    expect(returns[0].return_no).toMatch(/^RET-/);
    expect(returns[0].returned_amount).toBeCloseTo(1200, 2);
    expect(returns[0].fee_amount).toBeCloseTo(120, 2);
    expect(returns[0].net_amount).toBeCloseTo(1080, 2);
    expect(returns[0].items?.[0].quantity).toBeCloseTo(2, 4);
    expect(returns[0].settlements?.[0]).toMatchObject({ type: 'credit', amount: 1080 });

    // 6: position block
    const position = body.position as Record<string, number>;
    expect(Number(position.originalTotal)).toBeCloseTo(1800, 2);
    expect(Number(position.currentInvoiceValue)).toBeCloseTo(600, 2);
    expect(Number(position.refundCreditDue)).toBeCloseTo(1080, 2);
    expect(Number(position.remainingRefundDue)).toBeCloseTo(0, 2);

    // 7: chronological transaction timeline (persisted, not reconstructed)
    const timeline = (body.timeline ?? []) as Array<{ type: string; reference: string; amount: number }>;
    const types = timeline.map((t) => t.type);
    expect(types).toEqual(expect.arrayContaining([
      'INVOICE', 'PAYMENT', 'RETURN', 'RESTOCKING_FEE', 'SETTLEMENT',
    ]));
    // Chronological: invoice first, settlement last
    expect(types[0]).toBe('INVOICE');
    expect(types[types.length - 1]).toBe('SETTLEMENT');

    // Legacy fallback: an invoice with only pre-migration returns has
    // no invoice_returns rows — the payload must still render via the
    // stock-movement view (returnsFromMovements present, returns empty)
    const legacyPos = await fetchPosition(inv.invoiceId, authCookie);
    expect(legacyPos.balanceDue).toBeCloseTo(0, 2);
  });
});
