/**
 * BUG-014 path 2: restoring a deleted invoice re-consumes the batch, and the
 * bin mirror must go down with it.
 *
 * `reconsumeRestoredInvoiceItems` -> `consumeBatch` decrements
 * `stock_batches.quantity_remaining` unconditionally but drew
 * `batch_stock_by_location` down only when the flag was on. With the flag off
 * a delete-then-restore cycle left a bin holding stock its batch no longer
 * had.
 *
 * The per-bin invariant `physical = available + reserved` still held in that
 * state, so an inside-one-table check misses it. The drift helper's per-batch
 * comparison is what catches it, and this test asserts both.
 *
 * Driven through the real routes: `DELETE /api/invoices/:id`, then
 * `POST /api/invoices/:id/restore`.
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
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const SALE_DATE = '2026-10-17';

let cookie = '';
let customerId = 0;
let warehouseId = 0;

function locationTotal(itemId: number, wh: number): number {
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

async function sell(itemId: number, qty: number, key: string): Promise<number> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(key))
    .send({
      customer_id: customerId,
      invoice_date: SALE_DATE,
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: qty, unit_price: 100 }],
      payment_method: 'Cash',
      paid_amount: qty * 100,
    });
  expect([200, 201]).toContain(res.status);
  const id = (res.body as { data?: { id: number }; id?: number }).data?.id
    ?? (res.body as { id?: number }).id;
  expect(id).toBeTruthy();
  return id as number;
}

describe('BUG-014: invoice restore draws both stock sources down with the flag OFF', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = await createCustomer('BUG-014 P2 Customer', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>)[0].id;
  });

  for (const flagOn of [false, true]) {
    const label = flagOn ? 'flag ON' : 'flag OFF';

    it(`takes the batch and the bin down by the same quantity (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-P2 ${label}`, cookie);
      await purchaseStock(itemId, warehouseId, 10, 40, cookie, '2026-10-02');
      const invoiceId = await sell(itemId, 4, `bug014-p2-${flagOn}`);

      // Delete credits the batch and the bin back (path 1).
      const del = await request(app)
        .delete(`/api/invoices/${invoiceId}`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`bug014-p2-del-${flagOn}`));
      expect([200, 204]).toContain(del.status);

      const beforeBatch = batchTotal(itemId, warehouseId);
      const beforeLoc = locationTotal(itemId, warehouseId);
      expect(beforeBatch).toBe(10);
      expect(beforeLoc).toBe(10);

      // Restore re-consumes 4 from BOTH sources (path 2).
      const restore = await request(app)
        .post(`/api/invoices/${invoiceId}/restore`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`bug014-p2-res-${flagOn}`));
      expect([200, 201]).toContain(restore.status);

      expect(beforeBatch - batchTotal(itemId, warehouseId)).toBe(4);
      expect(beforeLoc - locationTotal(itemId, warehouseId)).toBe(4);

      // The cross-source check: no batch reports more in a bin than it holds.
      expect(batchLocationDriftImbalances(db)).toEqual([]);
      expectAllInvariantsHold(`bug014-p2-${flagOn}`, db);
    });
  }
});
