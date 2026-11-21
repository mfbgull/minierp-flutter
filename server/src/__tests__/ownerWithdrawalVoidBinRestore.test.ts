/**
 * A voided goods owner-withdrawal must return stock to the SAME two stores it
 * was taken from: `stock_batches.quantity_remaining` and the batch's
 * `batch_stock_by_location` row.
 *
 * Confirmed defect: `restoreConsumption` incremented only the batch total and
 * then called `recordMovement`, whose inbound branch reuses
 * `syncBatchStockByLocationForNewBatch`. That helper is written for a batch
 * that does not exist yet — its `INSERT OR IGNORE` seeds a row and otherwise
 * does nothing. For an EXISTING bin row the restore was therefore a no-op, so
 * after withdraw-then-void the batch total said 10 while the bin still held 4
 * physical / 4 reserved. The two stores disagreed permanently.
 *
 * Scenario (PI's fresh-DB probe, real API only):
 *   purchase 10 → reserve 4 → withdraw 4 → void the withdrawal
 * Expected after the void: batch total 10, bin physical 10, bin reserved 4
 * (the reservation must survive), available 6.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createCustomer, createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';

// Reservations are flag-gated (StockReservationModel.create refuses a
// flag-off database), so the reserve scenario needs the flag ON. The flag
// default stays OFF in this repo — the test turns it on explicitly.
const FLAG = 'feature_batch_locations';

const AS_OF = '2026-10-15';

let cookie = '';
let customerId = 0;
let warehouseId = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  expect(cookie).not.toBe('');
  customerId = await createCustomer('OW Void Bin Customer', cookie);
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

  // The default location arrival, ungated, is what the restore must update.
  expect(defaultLocation(warehouseId)).toBeGreaterThan(0);
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function batchOf(itemId: number): number {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id ASC LIMIT 1',
  ).get(itemId, warehouseId) as { id: number }).id;
}

function batchRemaining(batchId: number): number {
  return Number((db.prepare('SELECT quantity_remaining FROM stock_batches WHERE id = ?')
    .get(batchId) as { quantity_remaining: number }).quantity_remaining);
}

function binRow(batchId: number, locationId: number): { physical: number; reserved: number; available: number } {
  const r = db.prepare(
    `SELECT quantity_physical AS physical, quantity_reserved AS reserved, quantity_available AS available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;
  if (!r) throw new Error(`no batch_stock_by_location row for batch ${batchId} / location ${locationId}`);
  return r;
}

/** The bin row must exist so a missing row is a clear failure, not a silent 0. */
function hasBinRow(batchId: number, locationId: number): boolean {
  return db.prepare('SELECT 1 FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?')
    .get(batchId, locationId) !== undefined;
}

function createLocation(wh: number, code: string): number {
  const existing = db.prepare(
    'SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?',
  ).get(wh, code) as { id: number } | undefined;
  if (existing) return existing.id;
  const ins = db.prepare(
    'INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)',
  ).run(wh, code, `Bin ${code}`);
  return ins.lastInsertRowid as number;
}

/** Move a batch's whole physical stock between bins, keeping the total fixed. */
function moveWholeBatchToBin(batchId: number, fromId: number, toId: number, qty: number): void {
  db.prepare(`
    UPDATE batch_stock_by_location
    SET quantity_physical = 0, quantity_available = 0
    WHERE batch_id = ? AND location_id = ?
  `).run(batchId, fromId);
  db.prepare(`
    INSERT INTO batch_stock_by_location
      (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
    VALUES (?, ?, ?, 0, ?)
  `).run(batchId, toId, qty, qty);
}

function seedSalesOrder(status: string): string {
  const soNo = `SO-OWV-${status}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  db.prepare(`
    INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, warehouse_id)
    VALUES (?, ?, ?, ?, 0, ?)
  `).run(soNo, customerId, AS_OF, status, warehouseId);
  return soNo;
}

const post = (url: string, body: Record<string, unknown>) =>
  request(app).post(url)
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`owv-${Math.random().toString(36).slice(2)}`))
    .send(body);

const del = (url: string) => request(app).delete(url).set('Cookie', cookie);

describe('goods owner-withdrawal void restores the bin, not just the batch total', () => {
  it('the feature flag is OFF by default in a fresh database', () => {
    const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(FLAG) as { value: string } | undefined;
    expect(row?.value === '1' ? 'on' : 'off').toBe('off');
  });

  it('purchase 10, reserve 4, withdraw 4, void → batch 10 and bin physical 10 / reserved 4', async () => {
    const itemId = await createItem('OWV-BIN-ITEM', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);

    // A bin row is written by the purchase path whether the flag is on or
    // off (BUG-013); this scenario needs reservations, which are flag-gated.
    setFeatureEnabled(db, FLAG, true);

    // ── baseline: the purchase seeded both stores ──────────────────────
    expect(batchRemaining(batchId)).toBe(10);
    expect(hasBinRow(batchId, locId)).toBe(true);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });

    // ── reserve 4 in that bin ──────────────────────────────────────────
    const reserved = await post('/api/inventory/reservations', {
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Confirmed'),
      reference_line_id: 1,
      bins: [{ batch_id: batchId, location_id: locId, quantity: 4 }],
    });
    expect(reserved.status).toBe(201);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 4, available: 6 });

    // ── withdraw 4 units of stock ──────────────────────────────────────
    const withdrawal = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: AS_OF,
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 4 }],
    });
    expect([200, 201]).toContain(withdrawal.status);
    const withdrawalId = (withdrawal.body?.data?.id ?? withdrawal.body?.id) as number;
    expect(withdrawalId).toBeGreaterThan(0);

    // Taken from both stores, symmetric with the sale path.
    expect(batchRemaining(batchId)).toBe(6);
    expect(binRow(batchId, locId)).toEqual({ physical: 6, reserved: 4, available: 2 });

    // ── void it ────────────────────────────────────────────────────────
    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);

    // ── the defect: the bin was never incremented ──────────────────────
    expect(batchRemaining(batchId)).toBe(10);
    const after = binRow(batchId, locId);
    // Reservation must survive the void — it is a promise, not stock movement.
    expect(after.reserved).toBe(4);
    expect(after.physical).toBe(10);
    expect(after.available).toBe(6);
  });

  it('after the void, the bin - not the batch total - decides what is sellable', async () => {
    const itemId = await createItem('OWV-BIN-SALE', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    setFeatureEnabled(db, FLAG, true);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);

    const reserved = await post('/api/inventory/reservations', {
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity_reserved: 4,
      reference_doctype: 'SALES_ORDER',
      reference_docno: seedSalesOrder('Confirmed'),
      reference_line_id: 1,
      bins: [{ batch_id: batchId, location_id: locId, quantity: 4 }],
    });
    expect(reserved.status).toBe(201);

    const withdrawal = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: AS_OF,
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 4 }],
    });
    expect([200, 201]).toContain(withdrawal.status);
    const withdrawalId = (withdrawal.body?.data?.id ?? withdrawal.body?.id) as number;

    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);

    // The 4 restored units are unreserved, so 6 units must be sellable:
    // 10 physical - 4 reserved. With the restore stranded the bin only
    // reports 2 free and this legal sale is refused.
    const sale = await post('/api/invoices', {
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: 6, unit_price: 50, tax_rate: 0 }],
    });
    expect([200, 201]).toContain(sale.status);

    // Both stores agree after the legal sale: 4 physical, 4 reserved, 0 free.
    expect(batchRemaining(batchId)).toBe(4);
    expect(binRow(batchId, locId)).toEqual({ physical: 4, reserved: 4, available: 0 });
  });

  //
  // Cross-review finding (current logic, new records): the void restored to the
  // warehouse DEFAULT bin regardless of where the units were taken from. The
  // stock came back to a bin that never held it, so the batch total agreed with
  // neither bin: after void, batch 10 while DEFAULT held 4 and the true source
  // bin still held 6. Selling from the source bin then under-reported stock and
  // selling against DEFAULT fabricated 4 units.
  //
  it('void returns units to the bin they were taken from, not the DEFAULT bin', async () => {
    const itemId = await createItem('OWV-NONDEF-ITEM', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    setFeatureEnabled(db, FLAG, true);

    const batchId = batchOf(itemId);
    const defaultId = defaultLocation(warehouseId);

    // A real named bin, created through the same table the API validates
    // against. The purchase landed everything in DEFAULT; move the whole
    // batch into the named bin so the withdrawal has to consume from it.
    const namedId = createLocation(warehouseId, 'OWV-AISLE-B');
    moveWholeBatchToBin(batchId, defaultId, namedId, 10);

    expect(binRow(batchId, defaultId)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(binRow(batchId, namedId)).toEqual({ physical: 10, reserved: 0, available: 10 });

    // ── withdraw 4: the consumer must draw them from the named bin ────
    const withdrawal = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: AS_OF,
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 4 }],
    });
    expect([200, 201]).toContain(withdrawal.status);
    const withdrawalId = (withdrawal.body?.data?.id ?? withdrawal.body?.id) as number;
    expect(withdrawalId).toBeGreaterThan(0);

    expect(batchRemaining(batchId)).toBe(6);
    expect(binRow(batchId, namedId)).toEqual({ physical: 6, reserved: 0, available: 6 });
    expect(binRow(batchId, defaultId)).toEqual({ physical: 0, reserved: 0, available: 0 });

    // ── void: the 4 units belong back in the NAMED bin ────────────────
    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);

    expect(batchRemaining(batchId)).toBe(10);
    // The defect: these were restored to DEFAULT, leaving 4 / 0.
    expect(binRow(batchId, namedId)).toEqual({ physical: 10, reserved: 0, available: 10 });
    expect(binRow(batchId, defaultId)).toEqual({ physical: 0, reserved: 0, available: 0 });
  });

  //
  // Re-review finding (current logic, new records): two withdrawal LINES that
  // draw the SAME batch produced two `stock_movements` rows for one batch. The
  // restore looped over those rows and, for each one, replayed EVERY ledger row
  // of that batch. Withdraw 4 + 3 from one batch therefore restored the batch
  // draw twice: batch total 10 but bin physical 17. The batch total and the bin
  // mirror disagreed, and the bin fabricated 7 units.
  //
  it('void of two lines drawing the same batch restores the bin once, not once per line', async () => {
    const itemId = await createItem('OWV-DUP-VOID', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    setFeatureEnabled(db, FLAG, true);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);
    expect(batchRemaining(batchId)).toBe(10);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });

    // Two lines, same item and batch, 4 + 3 = 7.
    const withdrawal = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: AS_OF,
      kind: 'goods',
      items: [
        { item_id: itemId, warehouse_id: warehouseId, quantity: 4 },
        { item_id: itemId, warehouse_id: warehouseId, quantity: 3 },
      ],
    });
    expect([200, 201]).toContain(withdrawal.status);
    const withdrawalId = (withdrawal.body?.data?.id ?? withdrawal.body?.id) as number;
    expect(withdrawalId).toBeGreaterThan(0);

    expect(batchRemaining(batchId)).toBe(3);
    expect(binRow(batchId, locId)).toEqual({ physical: 3, reserved: 0, available: 3 });

    const voided = await del(`/api/owner-equity/withdrawals/${withdrawalId}`);
    expect([200, 204]).toContain(voided.status);

    // Both stores must return to exactly 10. The defect left the bin at 17.
    expect(batchRemaining(batchId)).toBe(10);
    expect(binRow(batchId, locId)).toEqual({ physical: 10, reserved: 0, available: 10 });
  });

  it('edit/re-post of two same-batch lines restores each draw exactly once', async () => {
    const itemId = await createItem('OWV-DUP-EDIT', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    setFeatureEnabled(db, FLAG, true);

    const batchId = batchOf(itemId);
    const locId = defaultLocation(warehouseId);

    const withdrawal = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: AS_OF,
      kind: 'goods',
      items: [
        { item_id: itemId, warehouse_id: warehouseId, quantity: 4 },
        { item_id: itemId, warehouse_id: warehouseId, quantity: 3 },
      ],
    });
    expect([200, 201]).toContain(withdrawal.status);
    const withdrawalId = (withdrawal.body?.data?.id ?? withdrawal.body?.id) as number;
    expect(batchRemaining(batchId)).toBe(3);
    expect(binRow(batchId, locId)).toEqual({ physical: 3, reserved: 0, available: 3 });

    // Replace both lines with a single 5-unit line: restore 7, then consume 5.
    const edited = await request(app)
      .put(`/api/owner-equity/withdrawals/${withdrawalId}`)
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('owv-edit'))
      .send({
        withdrawal_date: AS_OF,
        kind: 'goods',
        items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 5 }],
      });
    expect([200, 201]).toContain(edited.status);

    // Both stores must agree at exactly 5. The defect left the bin at 12.
    expect(batchRemaining(batchId)).toBe(5);
    expect(binRow(batchId, locId)).toEqual({ physical: 5, reserved: 0, available: 5 });
  });
});
