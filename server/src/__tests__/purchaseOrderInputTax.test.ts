import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

describe('Recoverable tax on purchase-order receipts', () => {
  let cookie: string;
  let supplierId: number;
  let itemId: number;
  let warehouseId: number;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  const taxBalance = () => (db.prepare(`SELECT ROUND(COALESCE(SUM(j.debit-j.credit),0),2) AS amount
    FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code='1320' AND j.voided=0`).get() as { amount: number }).amount;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const supplier = await post('/api/suppliers', { supplier_code: 'PO-TAX', supplier_name: 'PO tax supplier' });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data.id;
    itemId = await createItem('PO recoverable tax stock', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  });

  it('recognizes tax only on receipt, preserves rounding, and reverses returns and receipt voids', async () => {
    const created = await post('/api/purchase-orders', { supplier_id: supplierId, warehouse_id: warehouseId,
      po_date: '2026-09-01', items: [{ item_id: itemId, quantity: 3, unit_price: 10, input_tax_amount: 1 }] });
    expect(created.status).toBe(201);
    const poId = created.body.id;
    expect(created.body.total_amount).toBe(31);
    expect(taxBalance()).toBe(0);
    const lineId = (db.prepare('SELECT id FROM purchase_order_items WHERE po_id=?').get(poId) as { id: number }).id;
    expect((await post(`/api/purchase-orders/${poId}/status`, { status: 'Submitted' })).status).toBe(200);
    const receive = (date: string, qty: number) => post(`/api/purchase-orders/${poId}/receipts`, {
      receipt_date: date, warehouse_id: warehouseId, items: [{ po_item_id: lineId, received_quantity: qty }] });
    const first = await receive('2026-09-02', 1);
    expect(first.status).toBe(201);
    expect(taxBalance()).toBeCloseTo(0.33, 8);
    expectAllInvariantsHold('first taxed partial PO receipt', db);
    const second = await receive('2026-09-03', 2);
    expect(second.status).toBe(201);
    expect(taxBalance()).toBe(1);
    expectAllInvariantsHold('all ordered input tax recognized', db);
    const returned = await post('/api/purchase-returns', { source_type: 'PURCHASE_ORDER', source_id: poId,
      warehouse_id: warehouseId, return_date: '2026-09-04', items: [{ source_item_id: lineId, quantity: 3 }] });
    expect(returned.status).toBe(201);
    const returnId = returned.body.data?.id ?? returned.body.id;
    expect(db.prepare('SELECT total_amount, input_tax_amount FROM purchase_returns WHERE id=?').get(returnId))
      .toEqual({ total_amount: 31, input_tax_amount: 1 });
    expect(taxBalance()).toBe(0);
    expectAllInvariantsHold('all PO goods and tax returned', db);
    expect((await post(`/api/purchase-returns/${returnId}/void`, { reason: 'Correction' })).status).toBe(200);
    expect(taxBalance()).toBe(1);
    const secondId = second.body.id;
    expect((await post(`/api/purchase-orders/${poId}/receipts/${secondId}/void`, { reason: 'Correction' })).status).toBe(200);
    expect(taxBalance()).toBeCloseTo(0.33, 8);
    expectAllInvariantsHold('taxed receipt void', db);
  });
});
