/**
 * BUG-013 / S-2: the LEGACY (flag-OFF) consume path must scope its bin write
 * to the batch's own warehouse, and must not subtract the whole take from
 * EVERY bin row of the batch.
 *
 * WHY THIS EXISTS. `consumeLegacyBatches` writes:
 *
 *   UPDATE batch_stock_by_location
 *   SET quantity_physical = MAX(0, quantity_physical - ?)
 *   WHERE batch_id = ?
 *
 * The WHERE names neither a location nor a warehouse. So when one batch is
 * split across two bins, EACH bin loses the FULL take. With bins 5 + 5 and a
 * sale of 3, the two bins become 2 + 2 (physical 4) instead of 5 + 2 (physical
 * 7): the bin total drifts THREE below the batch total that the same loop just
 * decremented. `MAX(0, ...)` absorbs the overflow per row, so the error is not
 * self-correcting. A batch whose bins live in another warehouse is decremented
 * in the wrong warehouse. The flag is OFF here, so nothing reads the bin table
 * yet — but the write is deliberately ungated ("the flag chooses which source
 * is READ, never which is WRITTEN"), so a later flag flip exposes the drift.
 *
 * The spec drives the REAL invoice route on the real test database. It does
 * not call the model helper directly and does not mock a repository: a
 * source-level assertion cannot tell "the wrong bin moved" from "nothing
 * moved".
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let warehouseA = 0;
let warehouseB = 0;

function warehouses(): { a: number; b: number } {
  const rows = db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>;
  return { a: rows[0].id, b: rows[1].id };
}

/** Master batch total: the flag-OFF source of truth. */
function batchTotal(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  return Number(row.q);
}

/** Warehouse balance: the number a stock report shows. */
function balance(itemId: number, wh: number): number {
  const row = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
    .get(itemId, wh) as { quantity: number } | undefined;
  return row ? Number(row.quantity) : 0;
}

interface BinRow { locationId: number; physical: number }

/** Every bin row of every batch of this item+warehouse, keyed by location. */
function bins(itemId: number, wh: number): BinRow[] {
  return (db.prepare(
    `SELECT bsl.location_id AS locationId, bsl.quantity_physical AS physical
     FROM batch_stock_by_location bsl
     JOIN stock_batches sb ON sb.id = bsl.batch_id
     JOIN locations l ON l.id = bsl.location_id
     WHERE sb.item_id = ? AND l.warehouse_id = ?
     ORDER BY bsl.location_id ASC`,
  ).all(itemId, wh) as Array<{ locationId: number; physical: number }>)
    .map((r) => ({ locationId: r.locationId, physical: Number(r.physical) }));
}

function physicalTotal(itemId: number, wh: number): number {
  return bins(itemId, wh).reduce((s, b) => s + b.physical, 0);
}

/** The batch that holds this item in this warehouse (the only one). */
function batchIdOf(itemId: number, wh: number): number {
  const row = db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id ASC LIMIT 1',
  ).get(itemId, wh) as { id: number } | undefined;
  expect(row?.id).toBeTruthy();
  return row!.id;
}

/** A second location in the same warehouse, so the batch can be split. */
function secondLocation(wh: number, code: string): number {
  db.prepare(
    `INSERT OR IGNORE INTO locations (warehouse_id, location_code, location_name)
     VALUES (?, ?, ?)`,
  ).run(wh, code, code);
  const row = db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
    .get(wh, code) as { id: number };
  return row.id;
}

/**
 * Split one batch's physical holding across two bins of `wh`: the DEFAULT bin
 * keeps `keep`, a second bin takes `move`. The master batch row is unchanged —
 * only the bin split moves, which is exactly the shape a flag-ON warehouse
 * carries when the legacy path then consumes it.
 */
function splitBatchAcrossBins(itemId: number, wh: number, keep: number, move: number): { first: number; second: number } {
  const batchId = batchIdOf(itemId, wh);
  const first = (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
  const second = secondLocation(wh, `BIN-${itemId}`);
  db.prepare(
    `UPDATE batch_stock_by_location SET quantity_physical = ?, quantity_reserved = 0
     WHERE batch_id = ? AND location_id = ?`,
  ).run(keep, batchId, first);
  db.prepare(
    `INSERT INTO batch_stock_by_location
       (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, 0, ?)
     ON CONFLICT(batch_id, location_id)
     DO UPDATE SET quantity_physical = excluded.quantity_physical, quantity_reserved = 0`,
  ).run(batchId, second, move, move);
  return { first, second };
}

/** Sell `qty` through the REAL invoice route against a named warehouse. */
async function sell(itemId: number, wh: number, qty: number, label: string): Promise<void> {
  const customerId = await createCustomer(`S2 Customer ${label}`, cookie);
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`s2-${label}`))
    .send({
      customer_id: customerId,
      invoice_date: AS_OF,
      due_date: '2026-12-15',
      items: [{ item_id: itemId, warehouse_id: wh, quantity: qty, unit_price: 30, tax_rate: 0 }],
    });
  expect(res.status).toBe(201);
}

describe('BUG-013 S-2: legacy consume scopes the bin write to the consumed warehouse', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = warehouses();
    warehouseA = wh.a;
    warehouseB = wh.b;
  });

  for (const featureOn of [false, true]) {
    const label = featureOn ? 'flag ON' : 'flag OFF';

    describe(label, () => {
      beforeAll(() => {
        setFeatureEnabled(db, FLAG, featureOn);
      });

      it('takes the sale out of ONE bin, not the full take out of every bin', async () => {
        const itemId = await createItem(`S2 Split ${label}`, cookie);
        await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);

        // Two bins of 5 each.
        const { first, second } = splitBatchAcrossBins(itemId, warehouseA, 5, 5);
        expect(physicalTotal(itemId, warehouseA)).toBe(10);
        expect(balance(itemId, warehouseA)).toBe(10);

        await sell(itemId, warehouseA, 3, `split-${featureOn}`);

        const rows = bins(itemId, warehouseA);
        const byLoc = new Map(rows.map((r) => [r.locationId, r.physical]));
        const reads = [byLoc.get(first), byLoc.get(second)].sort((a, b) => Number(a) - Number(b));
        // One bin takes the whole sale, the other is untouched. Both bins
        // reading 2 (the S-2 defect) fails here; the sum check below is
        // order-agnostic about WHICH bin moved.
        expect(reads).toEqual([2, 5]);

        // The bin total must equal the batch total and the warehouse balance.
        expect(physicalTotal(itemId, warehouseA)).toBe(7);
        expect(batchTotal(itemId, warehouseA)).toBe(7);
        expect(balance(itemId, warehouseA)).toBe(7);
      });

      it('does not decrement bins that live in a different warehouse', async () => {
        const itemId = await createItem(`S2 CrossWh ${label}`, cookie);
        // Buy into warehouse B, so the batch's own warehouse is B.
        await purchaseStock(itemId, warehouseB, 10, 40, cookie, AS_OF);

        // Put two bins of the B-batch into warehouse A's bins as well, so a
        // batch_id-only WHERE would reach across the warehouse boundary.
        const batchId = batchIdOf(itemId, warehouseB);
        const locA = secondLocation(warehouseA, `XA-${itemId}`);
        db.prepare(
          `INSERT INTO batch_stock_by_location
             (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
           VALUES (?, ?, 5, 0, 5)
           ON CONFLICT(batch_id, location_id)
           DO UPDATE SET quantity_physical = excluded.quantity_physical, quantity_reserved = 0`,
        ).run(batchId, locA);

        const foreignBefore = bins(itemId, warehouseA).reduce((s, b) => s + b.physical, 0);
        expect(foreignBefore).toBe(5);

        await sell(itemId, warehouseB, 3, `crosswh-${featureOn}`);

        const foreignAfter = bins(itemId, warehouseA).reduce((s, b) => s + b.physical, 0);
        expect(foreignAfter).toBe(5);
      });
    });
  }
});
