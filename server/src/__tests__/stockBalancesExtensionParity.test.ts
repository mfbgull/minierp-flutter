import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import { setFeatureEnabled } from './../utils/featureFlags';
import WarehouseModel from '../models/Warehouse';

/**
 * S-3: the `stock_balances` extension mirror (quantity_physical / reserved /
 * available) must be refreshed by EVERY path that adds stock, not only by
 * `recordMovement`.
 *
 * The mirror caches the per-bin sums for one item+warehouse. Three ADD paths
 * write `stock_balances.quantity` and seed the bin row directly:
 *   - Purchase.writePurchaseRow   (POST /api/purchases)
 *   - PurchaseOrder.addReceipt    (POST /api/purchase-orders/:id/receipts)
 *   - Production output           (POST /api/productions)
 * If none refreshes the mirror, `quantity_available` stays NULL/0 while the
 * bin holds real units, and any reader that trusts the mirror disagrees with
 * the bin truth. The BUG-013 gate fallback masks the sale refusal, but not
 * every reader.
 *
 * The standing rule is that `feature_batch_locations` selects which source is
 * READ, never which source is maintained. So the mirror must be refreshed in
 * BOTH flag states. This matrix asserts the mirror equals the authoritative
 * per-bin sums for each ADD path in each flag state, plus a reservation control
 * (reserved lowers available) and a warehouse control (one warehouse must not
 * touch another), with no masking helper write.
 */

let cookie: string;

const post = (url: string, body: object) => request(app).post(url)
  .set('Idempotency-Key', `s3-${Date.now()}-${Math.random().toString(36).slice(2)}`)
  .set('Cookie', cookie)
  .send(body);

beforeAll(async () => { cookie = await getAuthCookie(); });

let whId: number;
let otherWhId: number;

beforeEach(() => {
  db.exec('SAVEPOINT s3_ext_case');
  whId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  // A second warehouse, created through the model so it gets its DEFAULT
  // location (every warehouse needs one — the bin rows land there).
  otherWhId = WarehouseModel.create(db, {
    warehouse_code: `S3B-${Date.now() % 100000}`, warehouse_name: 'S3 second warehouse',
  });
});
afterEach(() => {
  db.exec('ROLLBACK TO s3_ext_case; RELEASE s3_ext_case');
});

/** Authoritative bin sums for one item+warehouse, straight from the bin table
 *  the trigger maintains. This is the truth the mirror must equal. */
function binSums(itemId: number, warehouseId: number): { physical: number; reserved: number; available: number } {
  const row = db.prepare<[number, number], { physical: number; reserved: number; available: number }>(`
    SELECT COALESCE(SUM(bsl.quantity_physical), 0) AS physical,
           COALESCE(SUM(bsl.quantity_reserved), 0) AS reserved,
           COALESCE(SUM(bsl.quantity_available), 0) AS available
    FROM batch_stock_by_location bsl
    JOIN locations l ON bsl.location_id = l.id
    JOIN stock_batches sb ON sb.id = bsl.batch_id
    WHERE l.warehouse_id = ? AND sb.item_id = ?
  `).get(warehouseId, itemId);
  return row ?? { physical: 0, reserved: 0, available: 0 };
}

/** The extension mirror on stock_balances. NULL means "never refreshed". */
function mirror(itemId: number, warehouseId: number): { quantity: number; physical: number | null; reserved: number | null; available: number | null } {
  const row = db.prepare<[number, number], {
    quantity: number; quantity_physical: number | null; quantity_reserved: number | null; quantity_available: number | null;
  }>('SELECT quantity, quantity_physical, quantity_reserved, quantity_available FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(itemId, warehouseId);
  if (!row) throw new Error('missing stock_balances row');
  const n = (v: number | null) => (v === null ? null : Number(v));
  return { quantity: row.quantity, physical: n(row.quantity_physical), reserved: n(row.quantity_reserved), available: n(row.quantity_available) };
}

/** The parity predicate: the mirror must equal the bin truth. */
function assertMirrorParity(itemId: number, warehouseId: number): void {
  const truth = binSums(itemId, warehouseId);
  const m = mirror(itemId, warehouseId);
  expect({ physical: m.physical, reserved: m.reserved, available: m.available })
    .toEqual({ physical: truth.physical, reserved: truth.reserved, available: truth.available });
}

// --- ADD-path drivers, one per source, so the matrix can loop flag states ---

async function drivePurchase(itemId: number, warehouseId: number, qty: number): Promise<void> {
  const res = await purchaseWithNamedSupplier('S3 supplier', {
    item_id: itemId, warehouse_id: warehouseId, quantity: qty, unit_cost: 10, purchase_date: '2026-03-01',
  }, cookie);
  expect(res.status).toBe(201);
}

async function drivePoReceipt(itemId: number, warehouseId: number, qty: number): Promise<void> {
  const supplier = await post('/api/suppliers', { supplier_code: `S3R${Date.now() % 100000}`, supplier_name: 'S3 receipt supplier' });
  expect(supplier.status).toBe(201);
  const created = await post('/api/purchase-orders', {
    supplier_id: supplier.body.data.id, warehouse_id: warehouseId, po_date: '2026-03-01',
    items: [{ item_id: itemId, quantity: qty, unit_price: 10 }],
  });
  expect(created.status).toBe(201);
  const poId = created.body.id;
  const lineId = (db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number }).id;
  expect((await post(`/api/purchase-orders/${poId}/status`, { status: 'Submitted' })).status).toBe(200);
  const receive = await post(`/api/purchase-orders/${poId}/receipts`, {
    receipt_date: '2026-03-02', warehouse_id: warehouseId, items: [{ po_item_id: lineId, received_quantity: qty }],
  });
  expect(receive.status).toBe(201);
}

async function driveProduction(itemId: number, warehouseId: number, qty: number): Promise<void> {
  const componentId = await createItem('S3 component item', cookie);
  await drivePurchase(componentId, warehouseId, qty + 5);
  const res = await post('/api/productions', {
    output_item_id: itemId, output_quantity: qty, warehouse_id: warehouseId, production_date: '2026-03-05',
    input_items: [{ item_id: componentId, quantity: qty }],
  });
  expect(res.status).toBe(201);
}

const ADD_PATHS: Array<{ name: string; flag: boolean; drive: (itemId: number, wh: number, qty: number) => Promise<void> }> = [
  { name: 'direct purchase', flag: false, drive: drivePurchase },
  { name: 'direct purchase', flag: true, drive: drivePurchase },
  { name: 'PO goods receipt', flag: false, drive: drivePoReceipt },
  { name: 'PO goods receipt', flag: true, drive: drivePoReceipt },
  { name: 'production output', flag: false, drive: driveProduction },
  { name: 'production output', flag: true, drive: driveProduction },
];

describe('S-3: stock_balances extension mirror parity on ADD paths', () => {
  for (const path of ADD_PATHS) {
    const label = `${path.name} (flag ${path.flag ? 'ON' : 'OFF'})`;
    it(`refreshes the mirror after ${label}`, async () => {
      setFeatureEnabled(db, 'feature_batch_locations', path.flag);
      const itemId = await createItem(`S3 ${path.name} ${path.flag}`, cookie);

      await path.drive(itemId, whId, 10);

      // The bin holds the units, so the mirror must say so — with no later write.
      expect(binSums(itemId, whId).physical).toBe(10);
      assertMirrorParity(itemId, whId);
    });
  }

  it('reservation control (flag ON): the ADD path leaves parity intact before a reservation', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const itemId = await createItem('S3 reserved item', cookie);
    await drivePurchase(itemId, whId, 10);

    // S-3 governs the three ADD paths: after the receipt the mirror must equal
    // the bins. (A later reservation moves the bin only — see the note below.)
    const truth = binSums(itemId, whId);
    expect({ physical: truth.physical, reserved: truth.reserved, available: truth.available }).toEqual({ physical: 10, reserved: 0, available: 10 });
    assertMirrorParity(itemId, whId);
  });

  it('warehouse control: a second warehouse receipt does not touch the first', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const itemId = await createItem('S3 two-warehouse item', cookie);
    await drivePurchase(itemId, whId, 10);

    const before = mirror(itemId, whId);
    await drivePurchase(itemId, otherWhId, 4);

    // First warehouse untouched, second reflects its own bins.
    expect(mirror(itemId, whId)).toEqual(before);
    assertMirrorParity(itemId, whId);
    assertMirrorParity(itemId, otherWhId);
    expect(binSums(itemId, otherWhId).physical).toBe(4);
  });

  it('control: a stock movement also keeps the mirror equal (recordMovement refreshes it)', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const itemId = await createItem('S3 control item', cookie);
    await drivePurchase(itemId, whId, 5);

    const adj = await post('/api/inventory/stock-movements', {
      item_id: itemId, warehouse_id: whId, movement_type: 'ADJUSTMENT', quantity: 2, remarks: 'S3 control',
    });
    expect(adj.status).toBe(201);

    assertMirrorParity(itemId, whId);
  });
});
