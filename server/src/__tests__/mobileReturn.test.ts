/**
 * Invoice Return — Mobile endpoint parity (spec §5.3 / D17).
 *
 * The mobile `POST /api/mobile-invoices/:id/return` must delegate to the
 * same `InvoiceReturnService.processReturn` as the desktop endpoint, so
 * both clients produce byte-identical money results. This suite seeds the
 * §17 acceptance fixture (3 × 600 = 1800, fully paid) on two invoices,
 * runs the same return (2 × 600, 10% fee, refund settlement) through the
 * mobile endpoint on one and the desktop endpoint on the other, and
 * asserts the positions match.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  fetchPosition, type Position,
} from './helpers/invoiceReturnSpec';

const MOBILE_BODY = {
  items: [], // filled per invoice
  fee_type: 'percentage',
  fee_value: 10,
  return_date: '2026-09-16',
  reason: 'Mobile parity return',
  settlements: [{ type: 'refund', amount: 1080, method: 'Cash' }],
};

describe('Mobile invoice return endpoint — parity with desktop (spec §5.3)', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;

    itemId = await createItem('Widget A (mobile parity)', authCookie);
    await purchaseStock(itemId, warehouseId, 50, 300, authCookie);
    customerId = await createCustomer('Mobile Parity Customer', authCookie);
  });

  async function seedInvoice(): Promise<{ invoiceId: number; invoiceItemIds: number[] }> {
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

  it('accepts the desktop payload and produces the acceptance math', async () => {
    const { invoiceId, invoiceItemIds } = await seedInvoice();

    const res = await request(app)
      .post(`/api/mobile-invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .send({
        ...MOBILE_BODY,
        items: [
          { invoice_item_id: invoiceItemIds[0], return_quantity: 2 },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);

    const data = res.body.data as Record<string, unknown>;
    expect(Number(data.returnedAmount)).toBeCloseTo(1200, 2);
    expect(Number(data.feeAmount)).toBeCloseTo(120, 2);
    expect(Number(data.netAmount)).toBeCloseTo(1080, 2);
    expect(typeof data.returnNo === 'string' && data.returnNo.length > 0).toBe(true);

    const position = await fetchPosition(invoiceId, authCookie);
    expect(position.originalTotal).toBeCloseTo(1800, 2);
    expect(position.totalReturned).toBeCloseTo(1200, 2);
    expect(position.currentInvoiceValue).toBeCloseTo(600, 2);
    expect(position.totalPaid).toBeCloseTo(1800, 2);
    expect(position.totalFees).toBeCloseTo(120, 2);
    // Fully settled by the refund allocation carried in the same call.
    expect(position.settledAmount).toBeCloseTo(1080, 2);
    expect(position.remainingRefundDue).toBeCloseTo(0, 2);
    expect(position.balanceDue).toBeCloseTo(0, 2);
  });

  it('produces the same position as the desktop endpoint for identical input', async () => {
    const mobile = await seedInvoice();
    const desktop = await seedInvoice();

    const items = [
      { invoice_item_id: mobile.invoiceItemIds[0], return_quantity: 2 },
    ];
    const mobileRes = await request(app)
      .post(`/api/mobile-invoices/${mobile.invoiceId}/return`)
      .set('Cookie', authCookie)
      .send({
        ...MOBILE_BODY,
        items,
        settlements: null, // legacy shim path — unsettled on purpose
        warehouse_id: warehouseId,
      });
    expect(mobileRes.status).toBe(200);

    const desktopRes = await request(app)
      .post(`/api/invoices/${desktop.invoiceId}/return`)
      .set('Cookie', authCookie)
      .send({
        ...MOBILE_BODY,
        items: [
          { invoice_item_id: desktop.invoiceItemIds[0], return_quantity: 2 },
        ],
        settlements: null,
        warehouse_id: warehouseId,
      });
    expect(desktopRes.status).toBe(200);

    const mobilePosition = await fetchPosition(mobile.invoiceId, authCookie);
    const desktopPosition = await fetchPosition(desktop.invoiceId, authCookie);

    const strip = (p: Position) => ({
      returned: p.totalReturned,
      fees: p.totalFees,
      refundDue: p.refundCreditDue,
      settled: p.settledAmount,
    });
    expect(strip(mobilePosition)).toEqual(strip(desktopPosition));
    expect(mobilePosition.totalReturned).toBeCloseTo(1200, 2);
    expect(mobilePosition.totalFees).toBeCloseTo(120, 2);
    expect(mobilePosition.refundCreditDue).toBeCloseTo(1080, 2);
  });

  it('rejects an empty items array with a 400', async () => {
    const { invoiceId } = await seedInvoice();
    const res = await request(app)
      .post(`/api/mobile-invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .send({ ...MOBILE_BODY, items: [] });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
  });
});
