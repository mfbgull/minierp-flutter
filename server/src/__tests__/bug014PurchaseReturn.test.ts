/**
 * BUG-014 paths 3 and 4: a purchase return draws stock from BOTH sources, and
 * voiding it credits BOTH back.
 *
 * Path 3 — `drawSourceBatchLocations` (the consume side): the bin sweep ran
 * only when the flag was on, while the `stock_batches` draw ran always. With
 * the flag off the batch lost units and the bin kept them.
 *
 * Path 4 — `restoreConsumedReturnBatch` / `restoreLegacyReturnStock` (the void
 * side): the batch was credited always, the bin only when the flag was on.
 *
 * Gull's case: part of the batch was already sold before the return. The bin
 * must not go below zero and must not trip the CHECK constraint.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold, batchLocationDriftImbalances } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';

let cookie = '';
let customerId = 0;
let supplierId = 0;
let warehouseId = 0;

function binTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    `SELECT COALESCE(SUM(bsl.quantity_available), 0) AS q
     FROM batch_stock_by_location bsl
     JOIN stock_batches sb ON sb.id = bsl.batch_id
     WHERE sb.item_id = ? AND sb.warehouse_id = ?`,
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

function batchTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

/** Sell `qty` through the real invoice route, to shrink the sellable batch. */
async function sell(itemId: number, qty: number, key: string): Promise<void> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(key))
    .send({
      customer_id: customerId,
      invoice_date: '2026-10-18',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: qty, unit_price: 100 }],
      payment_method: 'Cash',
      paid_amount: qty * 100,
    });
  expect([200, 201]).toContain(res.status);
}

/** Buy one item via the real route; returns the purchase id (the item's source). */
async function purchaseOne(
  itemId: number,
  qty: number,
  unitCost: number,
  key: string,
  date: string,
): Promise<number> {
  const res = await request(app)
    .post('/api/purchases')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(key))
    .send({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: qty,
      unit_cost: unitCost,
      purchase_date: date,
      supplier_id: supplierId,
      supplier_name: 'BUG-014 P34 Supplier',
    });
  expect([200, 201]).toContain(res.status);
  const id = (res.body as { data?: { id: number }; id?: number }).data?.id
    ?? (res.body as { id?: number }).id;
  expect(id).toBeTruthy();
  return id as number;
}

/** Return `qty` against a purchase through the real route; returns the return id. */
async function returnStock(purchaseId: number, qty: number, key: string, date: string): Promise<number> {
  const res = await request(app)
    .post('/api/purchase-returns')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(key))
    .send({
      return_date: date,
      source_type: 'PURCHASE',
      source_id: purchaseId,
      warehouse_id: warehouseId,
      reason: 'Damaged on delivery',
      items: [{ source_item_id: purchaseId, quantity: qty }],
    });
  expect([200, 201]).toContain(res.status);
  const id = (res.body as { data?: { id: number } }).data?.id;
  expect(id).toBeTruthy();
  return id as number;
}

describe('BUG-014: purchase return moves both stock sources with the flag OFF', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = await createCustomer('BUG-014 P34 Customer', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>)[0].id;
    const s = await request(app)
      .post('/api/suppliers')
      .set('Cookie', cookie)
      .send({ supplier_code: 'BUG014P34', supplier_name: 'BUG-014 P34 Supplier' });
    expect([200, 201]).toContain(s.status);
    supplierId = ((s.body as { data?: { id: number } }).data?.id ?? 0) as number;
    expect(supplierId).toBeTruthy();
  });

  for (const flagOn of [false, true]) {
    const label = flagOn ? 'flag ON' : 'flag OFF';

    it(`draws the batch and the bin down together on return (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-P3 ${label}`, cookie);
      const purchaseId = await purchaseOne(itemId, 10, 40, `bug014-p3-buy-${flagOn}`, '2026-10-03');
      expect(batchTotal(itemId, warehouseId)).toBe(10);
      const beforeBin = binTotal(itemId, warehouseId);

      await returnStock(purchaseId, 4, `bug014-p3-${flagOn}`, '2026-10-04');

      expect(batchTotal(itemId, warehouseId)).toBe(6);
      expect(beforeBin - binTotal(itemId, warehouseId)).toBe(4);
      expect(batchLocationDriftImbalances(db)).toEqual([]);
      expectAllInvariantsHold(`bug014-p3-${flagOn}`, db);
    });

    it(`credits the batch and the bin back on return void (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-P4 ${label}`, cookie);
      const purchaseId = await purchaseOne(itemId, 10, 40, `bug014-p4-buy-${flagOn}`, '2026-10-03');
      const returnId = await returnStock(purchaseId, 4, `bug014-p4-${flagOn}`, '2026-10-04');
      expect(batchTotal(itemId, warehouseId)).toBe(6);

      const beforeBin = binTotal(itemId, warehouseId);
      const voided = await request(app)
        .post(`/api/purchase-returns/${returnId}/void`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`bug014-p4-void-${flagOn}`))
        .send({ reason: 'Wrong stock' });
      expect([200, 201]).toContain(voided.status);

      expect(batchTotal(itemId, warehouseId)).toBe(10);
      expect(binTotal(itemId, warehouseId) - beforeBin).toBe(4);
      expect(batchLocationDriftImbalances(db)).toEqual([]);
      expectAllInvariantsHold(`bug014-p4-${flagOn}`, db);
    });

    it(`never drives a bin below zero when part of the batch was sold (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-P34sold ${label}`, cookie);
      const purchaseId = await purchaseOne(itemId, 10, 40, `bug014-p34-buy-${flagOn}`, '2026-10-03');
      // Sell 6 first: only 4 remain, and the return asks for exactly 4.
      await sell(itemId, 6, `bug014-p34-sold-${flagOn}`);
      expect(batchTotal(itemId, warehouseId)).toBe(4);

      await returnStock(purchaseId, 4, `bug014-p34-ret-${flagOn}`, '2026-10-05');

      expect(batchTotal(itemId, warehouseId)).toBe(0);
      expect(binTotal(itemId, warehouseId)).toBe(0);
      // The CHECK on batch_stock_by_location forbids a negative physical
      // quantity; reaching this line proves it did not fire.
      const negatives = db.prepare(
        'SELECT COUNT(*) AS n FROM batch_stock_by_location WHERE quantity_physical < 0',
      ).get() as { n: number };
      expect(negatives.n).toBe(0);
      expect(batchLocationDriftImbalances(db)).toEqual([]);
      expectAllInvariantsHold(`bug014-p34-sold-${flagOn}`, db);
    });
  }
});
