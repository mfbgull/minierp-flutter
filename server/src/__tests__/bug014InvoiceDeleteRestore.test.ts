/**
 * BUG-014 path 1: deleting an invoice restores the sold stock to BOTH sources.
 *
 * `restoreSaleBatchQuantities` credits `stock_batches.quantity_remaining`
 * unconditionally, but the `batch_stock_by_location` restore sat inside an
 * `isFeatureEnabled('feature_batch_locations')` branch. With the flag off the
 * master batch grew and the bin did not, so turning the flag on later showed
 * the sold units as still gone — or, after a second cycle, showed a bin
 * quantity that disagreed with its batch.
 *
 * The case Gull asked for explicitly: a batch with NO location row at restore
 * time. The mirror must be created, not skipped.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const SALE_DATE = '2026-10-16';

let cookie = '';
let customerId = 0;
let warehouseId = 0;

function snapshot(itemId: number, wh: number): { balance: number; batch: number; location: number } {
  const balance = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(itemId, wh) as { quantity: number } | undefined;
  const batch = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  const loc = db.prepare(
    `SELECT COALESCE(SUM(bsl.quantity_available), 0) AS q
     FROM batch_stock_by_location bsl
     JOIN stock_batches sb ON sb.id = bsl.batch_id
     WHERE sb.item_id = ? AND sb.warehouse_id = ?`,
  ).get(itemId, wh) as { q: number };
  return { balance: Number(balance?.quantity ?? 0), batch: Number(batch.q), location: Number(loc.q) };
}

/** Sell `qty` of an item through the real invoice route. */
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

describe('BUG-014: invoice delete restores both stock sources with the flag OFF', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = await createCustomer('BUG-014 Restore Customer', cookie);
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>)[0].id;
  });

  for (const flagOn of [false, true]) {
    const label = flagOn ? 'flag ON' : 'flag OFF';

    it(`restores the bin mirror when the batch already has a location row (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-A ${label}`, cookie);
      await purchaseStock(itemId, warehouseId, 10, 40, cookie, '2026-10-01');
      const invoiceId = await sell(itemId, 4, `bug014-a-${flagOn}`);

      const afterSale = snapshot(itemId, warehouseId);
      expect(afterSale.balance).toBe(6);

      const del = await request(app)
        .delete(`/api/invoices/${invoiceId}`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`bug014-a-del-${flagOn}`));
      expect([200, 204]).toContain(del.status);

      const restored = snapshot(itemId, warehouseId);
      expect({ where: `restore-cov-${label}`, ...restored })
        .toEqual({ where: `restore-cov-${label}`, balance: 10, batch: 10, location: 10 });
      expectAllInvariantsHold(`bug014-a-${flagOn}`, db);
    });

    it(`creates the bin mirror for a batch that has no location row (${label})`, async () => {
      setFeatureEnabled(db, FLAG, flagOn);
      const itemId = await createItem(`BUG014-B ${label}`, cookie);
      await purchaseStock(itemId, warehouseId, 8, 40, cookie, '2026-10-01');
      db.prepare(
        `DELETE FROM batch_stock_by_location
         WHERE batch_id IN (SELECT id FROM stock_batches WHERE item_id = ?)`,
      ).run(itemId);
      expect(snapshot(itemId, warehouseId).location).toBe(0);

      const invoiceId = await sell(itemId, 3, `bug014-b-${flagOn}`);
      // Selling rebuilds the row; drop it again so the restore meets no row.
      db.prepare(
        `DELETE FROM batch_stock_by_location
         WHERE batch_id IN (SELECT id FROM stock_batches WHERE item_id = ?)`,
      ).run(itemId);
      const beforeRestore = snapshot(itemId, warehouseId);
      expect(beforeRestore.location).toBe(0);

      const del = await request(app)
        .delete(`/api/invoices/${invoiceId}`)
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`bug014-b-del-${flagOn}`));
      expect([200, 204]).toContain(del.status);

      // The mirror must EXIST and carry exactly the restored units. The
      // batch-level write credits the same 3, so the two sources agree on the
      // delta even though this fixture removed the unsold 5 from the mirror.
      const restored = snapshot(itemId, warehouseId);
      expect(restored.location).toBe(3);
      expect(restored.batch - beforeRestore.batch).toBe(restored.location - beforeRestore.location);
      expect(restored.balance).toBe(8);
      expectAllInvariantsHold(`bug014-b-${flagOn}`, db);
    });
  }
});
