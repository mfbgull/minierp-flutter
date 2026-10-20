import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

describe('Recoverable tax on stock purchases', () => {
  let cookie: string;
  let supplierId: number;
  let itemId: number;
  let warehouseId: number;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  const balance = (code: string) => (db.prepare(`SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS amount FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id WHERE a.code = ? AND jl.voided = 0`).get(code) as { amount: number }).amount;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const supplier = await post('/api/suppliers', { supplier_code: 'STOCK-TAX', supplier_name: 'Stock tax supplier' });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data.id;
    itemId = await createItem('Recoverable tax stock', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    expect((await post('/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 500, payment_method: 'Cash' })).status).toBe(201);
  });

  it('keeps tax outside inventory, settles gross, and reverses tax with a partial return', async () => {
    const purchase = await post('/api/purchases', { supplier_id: supplierId, item_id: itemId, warehouse_id: warehouseId,
      quantity: 10, unit_cost: 10, input_tax_amount: 15, purchase_date: '2026-09-03', invoice_no: 'STOCK-TAX-INV' });
    expect(purchase.status).toBe(201);
    const purchaseId = purchase.body.id ?? purchase.body.data?.id;
    expect(purchase.body.input_tax_amount ?? purchase.body.data?.input_tax_amount).toBe(15);
    expect(balance('1200')).toBe(100);
    expect(balance('1320')).toBe(15);
    expect(balance('2000')).toBe(-115);
    expectAllInvariantsHold('stock purchase with recoverable tax', db);
    const payment = await post('/api/payments', { supplier_id: supplierId, amount: 115, payment_date: '2026-09-04', payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: purchaseId, amount: 115 }] });
    expect(payment.status).toBe(201);
    expect(balance('1000')).toBe(385);
    const returned = await post('/api/purchase-returns', { source_type: 'PURCHASE', source_id: purchaseId,
      warehouse_id: warehouseId, return_date: '2026-09-05', disposition: 'credit_on_account',
      items: [{ source_item_id: purchaseId, quantity: 2 }] });
    expect(returned.status).toBe(201);
    const returnId = returned.body.data?.id ?? returned.body.id;
    const header = db.prepare('SELECT total_amount, input_tax_amount FROM purchase_returns WHERE id = ?').get(returnId);
    expect(header).toEqual({ total_amount: 23, input_tax_amount: 3 });
    expect(balance('1200')).toBe(80);
    expect(balance('1320')).toBe(12);
    expectAllInvariantsHold('partial taxed purchase return', db);
    const note = db.prepare('SELECT id FROM credit_notes WHERE source_id = ?').get(returnId) as { id: number };
    const refunded = await post('/api/supplier-refunds', { credit_note_id: note.id, refund_date: '2026-09-06', amount: 23, payment_method: 'Cash' });
    expect(refunded.status).toBe(201);
    expect(balance('1000')).toBe(408);
    expectAllInvariantsHold('supplier refund includes returned tax', db);
    expect((await post(`/api/purchase-returns/${returnId}/void`, { reason: 'Correction' })).status).toBe(200);
    expect(balance('1200')).toBe(100);
    expect(balance('1320')).toBe(15);
    expect(balance('1000')).toBe(385);
    expectAllInvariantsHold('taxed return and refund reversed', db);
  });

  it('rejects an invalid recoverable-tax amount without posting a purchase', async () => {
    const before = db.prepare('SELECT COUNT(*) AS count FROM purchases').get();
    const result = await post('/api/purchases', { supplier_id: supplierId, item_id: itemId, warehouse_id: warehouseId,
      quantity: 1, unit_cost: 10, input_tax_amount: -1, purchase_date: '2026-09-07' });
    expect(result.status).toBe(400);
    expect(db.prepare('SELECT COUNT(*) AS count FROM purchases').get()).toEqual(before);
  });

  it('caps settlement at the gross payable remaining after an unpaid return', async () => {
    const purchase = await post('/api/purchases', { supplier_id: supplierId, item_id: itemId, warehouse_id: warehouseId,
      quantity: 10, unit_cost: 10, input_tax_amount: 15, purchase_date: '2026-09-07' });
    expect(purchase.status).toBe(201);
    const id = purchase.body.id;
    const returned = await post('/api/purchase-returns', { source_type: 'PURCHASE', source_id: id,
      warehouse_id: warehouseId, return_date: '2026-09-08', disposition: 'credit_on_account',
      items: [{ source_item_id: id, quantity: 2 }] });
    expect(returned.status).toBe(201);
    const before = db.prepare('SELECT COUNT(*) AS count FROM payments').get();
    const overpaid = await post('/api/payments', { supplier_id: supplierId, amount: 115, payment_date: '2026-09-09', payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: id, amount: 115 }] });
    expect(overpaid.status).toBe(400);
    expect(db.prepare('SELECT COUNT(*) AS count FROM payments').get()).toEqual(before);
    expect((await post('/api/payments', { supplier_id: supplierId, amount: 92, payment_date: '2026-09-09', payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: id, amount: 92 }] })).status).toBe(201);
    expectAllInvariantsHold('net payable settled after an unpaid taxed return', db);
  });

  it('replays every line of a multi-item purchase without duplicating stock or journals', async () => {
    const body = { supplier_id: supplierId, warehouse_id: warehouseId, purchase_date: '2026-09-10',
      items: [{ item_id: itemId, quantity: 1, unit_cost: 10, input_tax_amount: 1.5 },
        { item_id: itemId, quantity: 2, unit_cost: 10, input_tax_amount: 3 }] };
    const first = await post('/api/purchases', body).set('Idempotency-Key', 'taxed-multi-replay');
    expect(first.status).toBe(201);
    expect(first.body).toHaveLength(2);
    const before = db.prepare('SELECT COUNT(*) AS count FROM purchases').get();
    const replay = await post('/api/purchases', body).set('Idempotency-Key', 'taxed-multi-replay');
    expect(replay.status).toBe(201);
    expect(replay.body).toEqual(first.body);
    expect(db.prepare('SELECT COUNT(*) AS count FROM purchases').get()).toEqual(before);
    expectAllInvariantsHold('multi-item taxed purchase replay', db);
  });
});
