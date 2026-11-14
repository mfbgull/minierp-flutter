/**
 * ACCT-008 / D19 — the Idempotency-Key mandate.
 *
 * A missing key is a 400 on the canonical financial writes: invoice create,
 * customer and supplier payments, payment allocation, purchase-order goods
 * receipts, sales returns and return settlement. The deprecated
 * /api/mobile-invoices/* surface stays keyless-compatible (D13's promise to
 * the external mobile app). Supplier-refund writes were already mandatory
 * (PRET-002) and are covered by supplierRefundValidation.test.ts.
 *
 * Written FAILING-FIRST against the D19 decision: every mandate case below
 * returned 201/200 keyless before the flip.
 */
import request from 'supertest';
import { beforeAll, describe, expect, it } from '@jest/globals';
import app from '../app';
import db from '../config/database';
import { createCustomer, createItem, getAuthCookie, purchaseStock, resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

const MANDATE_MESSAGE = /idempotency-key header is required/i;

let seq = 0;
function key(): string {
  seq += 1;
  return `mandate-${Date.now()}-${seq}`;
}

describe('ACCT-008 D19 — Idempotency-Key is mandatory on canonical financial writes', () => {
  let authCookie: string;
  let warehouseId: number;
  let itemId: number;
  let customerId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Idem Mandate Item', authCookie);
    await purchaseStock(itemId, warehouseId, 500, 10, authCookie);
    customerId = await createCustomer('Idem Mandate Customer', authCookie);
  });

  it('rejects a keyless invoice creation with 400 and accepts a keyed one', async () => {
    const payload = {
      customer_id: customerId,
      invoice_date: '2026-11-01',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
    };
    const keyless = await request(app).post('/api/invoices').set('Cookie', authCookie).send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(201);
  });

  it('keeps /api/mobile-invoices keyless-compatible (D13 exemption)', async () => {
    const res = await request(app).post('/api/mobile-invoices/submit').set('Cookie', authCookie).send({
      customer_id: customerId,
      invoice_date: '2026-11-01',
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
    });
    expect(res.status).toBe(201);
  });

  it('rejects a keyless customer payment with 400 and accepts a keyed one', async () => {
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 2, unit_price: 50, tax_rate: 0 }],
      });
    expect(invoice.status).toBe(201);

    const payload = {
      customer_id: customerId,
      payment_date: '2026-11-02',
      amount: 100,
      payment_method: 'Cash',
      invoice_allocations: [{ invoice_id: invoice.body.id, amount: 100 }],
    };
    const keyless = await request(app).post('/api/payments').set('Cookie', authCookie).send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post('/api/payments')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(201);
  });

  it('rejects a keyless payment allocation with 400', async () => {
    // A real unallocated customer payment row (same pattern as
    // idempotencyRound1): the payment lookup runs before the mandate check,
    // so a fabricated id would 404 first.
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 30, tax_rate: 0 }],
      });
    expect(invoice.status).toBe(201);
    const paymentNo = `MANDATE-ALLOC-${Date.now()}-${Math.floor(Math.random() * 1e4)}`;
    const paymentId = Number(db.prepare(`
      INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, created_by)
      VALUES (?, ?, '2026-11-02', 30, 'Cash', 1)
    `).run(paymentNo, customerId).lastInsertRowid);

    const res = await request(app)
      .post(`/api/payments/${paymentId}/allocate`)
      .set('Cookie', authCookie)
      .send({ allocations: [{ invoice_id: invoice.body.id, amount: 30 }] });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects a keyless supplier payment with 400', async () => {
    const res = await request(app).post('/api/payments').set('Cookie', authCookie).send({
      supplier_id: 999999,
      payment_date: '2026-11-02',
      amount: 50,
      payment_method: 'Cash',
    });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });

  it('rejects a keyless purchase-order goods receipt with 400 and accepts a keyed one', async () => {
    supplierId = await resolveSupplierByName(`Mandate Supplier ${Date.now()}`, authCookie);
    const po = await request(app).post('/api/purchase-orders').set('Cookie', authCookie).send({
      supplier_id: supplierId,
      po_date: '2026-11-01',
      items: [{ item_id: itemId, quantity: 5, unit_price: 10 }],
    });
    expect(po.status).toBe(201);
    const poId = po.body.data?.id ?? po.body.id;
    await request(app).post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie).send({ status: 'Submitted' });
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };

    const receiptPayload = {
      receipt_date: '2026-11-02',
      warehouse_id: warehouseId,
      items: [{ po_item_id: poItem.id, received_quantity: 5 }],
    };
    const keyless = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send(receiptPayload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(receiptPayload);
    expect(keyed.status).toBe(201);
  });

  it('rejects a keyless sales return with 400 and accepts a keyed one', async () => {
    // Paid invoice so the return has an entitlement; the return is the
    // mandated write, the settlement comes in its own case.
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 4, unit_price: 50, tax_rate: 0 }],
        record_payment: true,
        payment: { payment_date: '2026-11-01', amount: 200, payment_method: 'Cash' },
      });
    expect(invoice.status).toBe(201);
    const invoiceId = invoice.body.id;
    const invoiceItemId = (db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1'
    ).get(invoiceId) as { id: number }).id;

    const payload = {
      reason: 'mandate probe',
      warehouse_id: warehouseId,
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 1 }],
    };
    const keyless = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .send(payload);
    expect(keyless.status).toBe(400);
    expect((keyless.body as { error: string }).error).toMatch(MANDATE_MESSAGE);

    const keyed = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send(payload);
    expect(keyed.status).toBe(200);
    const returnId = (keyed.body as { data?: { returnId?: number } }).data?.returnId;
    expect(returnId).toBeDefined();
  });

  it('rejects a keyless return settlement with 400', async () => {
    const invoice = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        customer_id: customerId,
        invoice_date: '2026-11-01',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 4, unit_price: 50, tax_rate: 0 }],
        record_payment: true,
        payment: { payment_date: '2026-11-01', amount: 200, payment_method: 'Cash' },
      });
    expect(invoice.status).toBe(201);
    const invoiceId = invoice.body.id;
    const invoiceItemId = (db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1'
    ).get(invoiceId) as { id: number }).id;

    // No disposition: the legacy shim is what leaves a remainder to settle.
    const created = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        reason: 'settle mandate probe',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: invoiceItemId, return_quantity: 4 }],
      });
    expect(created.status).toBe(200);
    const returnId = (created.body as { data?: { returnId?: number } }).data?.returnId;
    expect(returnId).toBeDefined();

    const res = await request(app)
      .post(`/api/invoice-returns/${returnId}/settle`)
      .set('Cookie', authCookie)
      .send({ allocations: [{ type: 'refund', amount: 200, method: 'Cash' }] });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(MANDATE_MESSAGE);
  });
});
