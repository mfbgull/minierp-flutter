import { beforeAll, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import {
  assertGlBalanced,
  createCustomer,
  createInvoice,
  createItem,
  expectNoNegativeBalance,
  fetchPosition,
  getAuthCookie,
  processReturn,
  purchaseStock,
  settlementsFor,
  type Position,
} from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `invoiceReturnService.applyLegacyAdjust`
 * (CRAP 90). Exercises the legacy `disposition: 'adjust'` path:
 * explicit targets, auto-pick oldest-first, carryover/early break,
 * paid-target skip, and the no-unpaid-invoices failure.
 */
describe('invoiceReturnService.applyLegacyAdjust', () => {
  let authCookie = '';
  let itemId = 0;
  let warehouseId = 0;
  let sequence = 0;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    const warehouse = db
      .prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1')
      .get() as { id: number };
    warehouseId = warehouse.id;
    itemId = await createItem('Legacy adjust item', authCookie);
    await purchaseStock(itemId, warehouseId, 500, 300, authCookie);
  });

  async function customer(name: string): Promise<number> {
    sequence += 1;
    return createCustomer(`${name} ${Date.now()}-${sequence}`, authCookie);
  }

  async function paidSource(customerId: number) {
    return createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 3, unitPrice: 600 }],
        payment: 'full',
        invoiceDate: '2026-09-15',
      },
      authCookie,
    );
  }

  async function unpaidTarget(
    customerId: number,
    amount: number,
    invoiceDate: string,
  ) {
    return createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 1, unitPrice: amount }],
        payment: null,
        invoiceDate,
      },
      authCookie,
    );
  }

  it('applies an explicit target list oldest-first and carries the excess forward', async () => {
    const customerId = await customer('Legacy explicit');
    const first = await unpaidTarget(customerId, 900, '2026-09-01');
    const second = await unpaidTarget(customerId, 500, '2026-09-02');
    const source = await paidSource(customerId);

    const result = await processReturn(
      source.invoiceId,
      {
        invoiceItemIds: source.invoiceItemIds,
        quantities: [2],
        feeType: 'percentage',
        feeValue: 10,
        warehouseId,
        disposition: 'adjust',
        adjustInvoiceIds: [first.invoiceId, second.invoiceId],
      },
      authCookie,
    );

    expect(result.status).toBe(200);
    expect(result.returnId).toBeDefined();
    const settlements = settlementsFor(result.returnId!);
    expect(settlements.map((row) => [row.target_invoice_id, row.amount])).toEqual([
      [first.invoiceId, 900],
      [second.invoiceId, 180],
    ]);
    const firstRow = db
      .prepare('SELECT balance_amount FROM invoices WHERE id = ?')
      .get(first.invoiceId) as { balance_amount: number };
    const secondRow = db
      .prepare('SELECT balance_amount FROM invoices WHERE id = ?')
      .get(second.invoiceId) as { balance_amount: number };
    expect(firstRow.balance_amount).toBe(0);
    expect(secondRow.balance_amount).toBe(320);
    expectNoNegativeBalance(first.invoiceId);
    expectNoNegativeBalance(second.invoiceId);
    assertGlBalanced('INVOICE_RETURN', result.returnId!);
    for (const settlement of settlements) {
      assertGlBalanced('PAYMENT', settlement.payment_id ?? 0);
    }
    await expectPositionOfRemaining(result, source.invoiceId);
  });

  it('auto-picks the oldest unpaid invoice and stops once the credit is used', async () => {
    const customerId = await customer('Legacy auto');
    const first = await unpaidTarget(customerId, 900, '2026-09-01');
    const second = await unpaidTarget(customerId, 500, '2026-09-02');
    const source = await paidSource(customerId);

    const result = await processReturn(
      source.invoiceId,
      {
        invoiceItemIds: source.invoiceItemIds,
        quantities: [2],
        feeType: 'percentage',
        feeValue: 25, // net 900, exactly the first target
        warehouseId,
        disposition: 'adjust',
      },
      authCookie,
    );

    expect(result.status).toBe(200);
    const settlements = settlementsFor(result.returnId!);
    expect(settlements.map((row) => [row.target_invoice_id, row.amount])).toEqual([
      [first.invoiceId, 900],
    ]);
    const secondRow = db
      .prepare('SELECT balance_amount FROM invoices WHERE id = ?')
      .get(second.invoiceId) as { balance_amount: number };
    expect(secondRow.balance_amount).toBe(500);
    assertGlBalanced('INVOICE_RETURN', result.returnId!);
    await expectPositionOfRemaining(result, source.invoiceId);
  });

  it('rejects an adjust with no unpaid invoice to target', async () => {
    const customerId = await customer('Legacy none');
    const source = await paidSource(customerId);

    const result = await processReturn(
      source.invoiceId,
      {
        invoiceItemIds: source.invoiceItemIds,
        quantities: [2],
        feeType: 'percentage',
        feeValue: 10,
        warehouseId,
        disposition: 'adjust',
      },
      authCookie,
    );

    expect(result.status).toBe(400);
    expect(String((result.body as { error?: string }).error)).toMatch(
      /No unpaid invoices/i,
    );
  });

  it('skips an explicit target whose balance is already zero', async () => {
    const customerId = await customer('Legacy paid target');
    const paidTarget = await createInvoice(
      {
        customerId,
        itemId,
        lines: [{ quantity: 1, unitPrice: 500 }],
        payment: 'full',
        invoiceDate: '2026-09-01',
      },
      authCookie,
    );
    const source = await paidSource(customerId);

    const result = await processReturn(
      source.invoiceId,
      {
        invoiceItemIds: source.invoiceItemIds,
        quantities: [2],
        feeType: 'percentage',
        feeValue: 10,
        warehouseId,
        disposition: 'adjust',
        adjustInvoiceIds: [paidTarget.invoiceId],
      },
      authCookie,
    );

    expect(result.status).toBe(200);
    expect(settlementsFor(result.returnId!)).toEqual([]);
    expectNoNegativeBalance(paidTarget.invoiceId);
  });

  async function expectPositionOfRemaining(
    result: { returnId?: number },
    invoiceId: number,
  ): Promise<void> {
    expect(result.returnId).toBeDefined();
    const position = await fetchPosition(invoiceId, authCookie);
    expect(position).toMatchObject({
      remainingRefundDue: 0,
    } as Partial<Position>);
  }
});
