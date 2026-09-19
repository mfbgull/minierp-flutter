/**
 * Invoice Return — Acceptance scenarios 9–14
 * (invoice-return-spec.md §8 — unpaid invoices, multi-return, fee math,
 * tax mirror, quantity guards)
 *
 * SCAFFOLDING NOTE: describe post-implementation behaviour; intentional
 * red until the new tables/endpoints exist.
 */
import request from 'supertest';
import db from '../config/database';
import app from '../app';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, expectPositionOf, expectNoNegativeBalance, returnRow,
  settlementsFor, assertOriginalLinesUntouched, getInvoiceRow, type Position,
} from './helpers/invoiceReturnSpec';

describe('Invoice Return spec — scenarios 9–14 (unpaid, multi-return, fee/tax math, guards)', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;
  let taxItemId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    itemId = await createItem('Widget B (unpaid scenarios)', authCookie);
    await purchaseStock(itemId, warehouseId, 100, 200, authCookie);
    customerId = await createCustomer('Return Spec Customer 2', authCookie);

    taxItemId = await createItem('Widget T (tax mirror)', authCookie);
    await purchaseStock(taxItemId, warehouseId, 100, 200, authCookie);
  });

  // ── Scenario 9 ────────────────────────────────────────────────────
  it('9. unpaid invoice: return allowed, settlement Not Required, fee always charged (partial → 700, full → 100)', async () => {
    // Spec §3.2: balanceDue = max(0, −NetPosition), NetPosition =
    // totalPaid − currentInvoiceValue − totalFees. Partial: 0 − 600 − 100
    // = −700 → 700 (the return leaves a *lower* obligation than the fee
    // charged, so the customer still owes the fee, not the returned line).
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: null },
      authCookie,
    );
    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'fixed', feeValue: 100, warehouseId },
      authCookie,
    );
    expect(ret.status).toBe(200);

    await expectPositionOf(inv.invoiceId, authCookie, {
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 0,
      totalFees: 100,
      balanceDue: 700,
    } as Partial<Position>);

    // D25: no settlement rows were created
    const allocations = settlementsFor(ret.returnId!);
    expect(allocations.filter((s) => !s.voided_at)).toHaveLength(0);
    expectNoNegativeBalance(inv.invoiceId);

    // Full return: 1800 returned, fee 100 → balance 100
    const inv2 = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: null },
      authCookie,
    );
    const ret2 = await processReturn(
      inv2.invoiceId,
      { invoiceItemIds: inv2.invoiceItemIds, quantities: [3], feeType: 'fixed', feeValue: 100, warehouseId },
      authCookie,
    );
    expect(ret2.status).toBe(200);

    await expectPositionOf(inv2.invoiceId, authCookie, {
      totalReturned: 1800,
      currentInvoiceValue: 0,
      totalFees: 100,
      refundCreditDue: 0,
      balanceDue: 100,
    } as Partial<Position>);
    expectNoNegativeBalance(inv2.invoiceId);
    const row2 = getInvoiceRow(inv2.invoiceId);
    expect(row2.status).toBe('Returned');
  });

  // ── Scenario 10 ───────────────────────────────────────────────────
  it('10. multiple returns (1+1 of 3): per-return documents, quantities and cumulative caps', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    // Return #1: 1 unit, no fee → net 600
    const r1 = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [1],
        feeType: 'none', warehouseId,
        settlements: [{ type: 'refund', amount: 600, method: 'Cash' }],
      },
      authCookie,
    );
    expect(r1.status).toBe(200);

    // Return #2: another unit, no fee → net 600
    const r2 = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [1],
        feeType: 'none', warehouseId,
        settlements: [{ type: 'refund', amount: 600, method: 'Cash' }],
      },
      authCookie,
    );
    expect(r2.status).toBe(200);

    const row1 = returnRow(r1.returnId!);
    const row2 = returnRow(r2.returnId!);
    expect(row1.return_no).not.toBe(row2.return_no); // distinct RET- numbers
    expect(row1.returned_amount).toBeCloseTo(600, 2);
    expect(row2.returned_amount).toBeCloseTo(600, 2);

    await expectPositionOf(inv.invoiceId, authCookie, {
      totalReturned: 1200,
      currentInvoiceValue: 600,
      totalPaid: 1800,
      totalFees: 0,
      refundCreditDue: 1200,
      settledAmount: 1200,
      remainingRefundDue: 0,
      balanceDue: 0,
    } as Partial<Position>);

    // Third return of 2 units must fail — only 1 remains returnable (rule 5)
    const r3 = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'none', warehouseId },
      authCookie,
    );
    expect(r3.status).toBe(400);
  });

  // ── Scenario 11 ───────────────────────────────────────────────────
  it('11. full return on paid invoice: returned 1800, fee 180, net 1620, current value 0', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [3],
        feeType: 'percentage', feeValue: 10, warehouseId,
        settlements: [{ type: 'credit', amount: 1620 }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    await expectPositionOf(inv.invoiceId, authCookie, {
      originalTotal: 1800,
      totalReturned: 1800,
      currentInvoiceValue: 0,
      totalFees: 180,
      refundCreditDue: 1620,
      settledAmount: 1620,
      remainingRefundDue: 0,
      balanceDue: 0,
    } as Partial<Position>);

    const row = getInvoiceRow(inv.invoiceId);
    expect(row.status).toBe('Returned');
    expectNoNegativeBalance(inv.invoiceId);
  });

  // ── Scenario 12 ───────────────────────────────────────────────────
  it('12. fixed vs percentage fee math; base = tax-mirrored returned value (not invoice total)', async () => {
    // Percentage: 10% of returned 1200 → 120
    const invA = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );
    const retA = await processReturn(
      invA.invoiceId,
      { invoiceItemIds: invA.invoiceItemIds, quantities: [2], feeType: 'percentage', feeValue: 10, warehouseId },
      authCookie,
    );
    expect(retA.status).toBe(200);
    expect(returnRow(retA.returnId!).fee_amount).toBeCloseTo(120, 2);
    expect(returnRow(retA.returnId!).net_amount).toBeCloseTo(1080, 2);

    // Fixed: 150 of returned 1200 → 150 (fee clamped to returned value at most)
    const invB = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 3, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );
    const retB = await processReturn(
      invB.invoiceId,
      { invoiceItemIds: invB.invoiceItemIds, quantities: [2], feeType: 'fixed', feeValue: 150, warehouseId },
      authCookie,
    );
    expect(retB.status).toBe(200);
    expect(returnRow(retB.returnId!).fee_amount).toBeCloseTo(150, 2);
    expect(returnRow(retB.returnId!).net_amount).toBeCloseTo(1050, 2);

    // Fee CANNOT exceed the returned value (percentage > 100% clamps)
    const invC = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );
    const retC = await processReturn(
      invC.invoiceId,
      { invoiceItemIds: invC.invoiceItemIds, quantities: [1], feeType: 'fixed', feeValue: 5000, warehouseId },
      authCookie,
    );
    expect(retC.status).toBe(200);
    expect(returnRow(retC.returnId!).fee_amount).toBeCloseTo(600, 2); // clamped
    expect(returnRow(retC.returnId!).net_amount).toBeCloseTo(0, 2);
  });

  // ── Scenario 13 ───────────────────────────────────────────────────
  it('13. tax proportional mirror (ADDITIVE model): returned tax == same proportion of line tax; fee on tax-inclusive base', async () => {
    // 3 units @ 600 + 10% additive tax → line: net 1800, tax 180, amount 1980.
    // decomposeLineAmount is authoritative: tax = net × rate/100 (never
    // extracted from a tax-inclusive total).
    const inv = await createInvoice(
      {
        customerId, itemId: taxItemId,
        lines: [{ quantity: 3, unitPrice: 600, taxRate: 10 }],
        payment: 'full',
      },
      authCookie,
    );

    // Return 2 of 3 → ratio 2/3 → returned net 1200, tax 120, gross 1320.
    // Fee 10% of 1320 = 132 → net settlement 1188.
    // Position: paid 1980 − remaining (1 unit = 660) − fees 132 = 1188. ✓
    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'percentage', feeValue: 10, warehouseId },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const row = returnRow(ret.returnId!);
    expect(row.returned_amount).toBeCloseTo(1320, 2); // tax-inclusive gross
    expect(row.fee_amount).toBeCloseTo(132, 2);
    expect(row.net_amount).toBeCloseTo(1188, 2);

    await expectPositionOf(inv.invoiceId, authCookie, {
      totalReturned: 1320,
      currentInvoiceValue: 660,   // remaining 1 unit incl. tax (600 + 60)
      totalPaid: 1980,
      totalFees: 132,
      refundCreditDue: 1188,      // 1980 − 660 − 132 — matches net settlement
    } as Partial<Position>);
  });

  it('13b. tax mirror GL: tax payable reversed proportionally with the return', async () => {
    const inv = await createInvoice(
      {
        customerId, itemId: taxItemId,
        lines: [{ quantity: 2, unitPrice: 600, taxRate: 10 }],
        payment: 'full',
      },
      authCookie,
    );
    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [1], feeType: 'none', warehouseId },
      authCookie,
    );
    expect(ret.status).toBe(200);

    // Balanced return entry: Dr Sales Returns (net 600) + Dr Tax Payable
    // (tax 60) = Cr AR (gross 660) — additive tax, §3.5.
    const taxAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '2100'").get() as { id: number };
    const taxReversal = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS d FROM journal_lines
      WHERE account_id = ? AND voided = 0
        AND reference_type = 'INVOICE_RETURN'
        AND reference_id = ${ret.returnId}
    `).get(taxAccount.id) as { d: number };
    // 1 of 2 units returned → half of the 120 tax component = 60
    expect(taxReversal.d).toBeCloseTo(60, 2);

    // AR credit for the same group is tax-INCLUSIVE (660 = 600 + 60)
    const arAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '1100'").get() as { id: number };
    const arCredit = db.prepare(`
      SELECT COALESCE(SUM(credit), 0) AS c FROM journal_lines
      WHERE account_id = ? AND voided = 0
        AND reference_type = 'INVOICE_RETURN'
        AND reference_id = ${ret.returnId}
    `).get(arAccount.id) as { c: number };
    expect(arCredit.c).toBeCloseTo(660, 2);

    // Sales Returns debit is tax-EXCLUSIVE (600)
    const salesReturnsAccount = db.prepare("SELECT id FROM chart_of_accounts WHERE code = '4100'").get() as { id: number };
    const srDebit = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS d FROM journal_lines
      WHERE account_id = ? AND voided = 0
        AND reference_type = 'INVOICE_RETURN'
        AND reference_id = ${ret.returnId}
    `).get(salesReturnsAccount.id) as { d: number };
    expect(srDebit.d).toBeCloseTo(600, 2);
  });

  // ── Scenario 14 ───────────────────────────────────────────────────
  it('14. return-quantity guard: cannot exceed sold − returned, even concurrently', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 600 }], payment: 'full' },
      authCookie,
    );

    // Sequential over-return attempt
    const over = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [3], feeType: 'none', warehouseId },
      authCookie,
    );
    expect(over.status).toBe(400);

    // Concurrent double-spend: two parallel returns of the full 2 units —
    // exactly one may succeed (fresh returned_qty read inside the transaction)
    const [a, b] = await Promise.all([
      processReturn(inv.invoiceId, { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'none', warehouseId }, authCookie),
      processReturn(inv.invoiceId, { invoiceItemIds: inv.invoiceItemIds, quantities: [2], feeType: 'none', warehouseId }, authCookie),
    ]);
    const statuses = [a.status, b.status].sort();
    expect(statuses).toEqual([200, 400]); // one succeeds, one is rejected

    // DB state remains consistent: exactly 2 units returned
    const returnedQty = db.prepare(
      'SELECT returned_qty FROM invoice_items WHERE id = ?'
    ).get(inv.invoiceItemIds[0]) as { returned_qty: number };
    expect(Number(returnedQty.returned_qty)).toBeCloseTo(2, 4);
    assertOriginalLinesUntouched(inv.invoiceId, [{ quantity: 2, unitPrice: 600 }]);
  });
});
