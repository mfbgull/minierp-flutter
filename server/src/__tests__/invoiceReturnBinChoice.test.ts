/**
 * Decision (2) — partial return of a line sold from two bins.
 *
 * Gull decided (audit/DECISIONS.md, "DECIDED — partial return of a line sold
 * from two bins"): every new sale persists the EXACT per-bin draw, including an
 * unreserved FIFO sale, and a return replays those recorded draws. When a line
 * has no recorded draw (a sale written before draws existed, or an unbatched
 * legacy sale), the return must NOT guess: the user names the bin, and the
 * server validates it. A missing historical allocation is never inferred and is
 * never silently parked in the warehouse DEFAULT bin.
 *
 * These tests drive the rule through the real routes
 * (`POST /api/invoices`, `POST /api/invoices/:id/return`,
 * `GET /api/invoices/:id`), not the model layer, so the wiring is exercised.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createCustomer, createItem, getAuthCookie, nextIdemKey, purchaseStock } from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let customerId = 0;
let warehouseA = 0;
let seq = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('Bin Choice Customer', cookie);
  warehouseA = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function rackLocation(wh: number, code: string): number {
  db.prepare('INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)')
    .run(wh, code, code);
  return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
    .get(wh, code) as { id: number }).id;
}

/** Move stock inside the batch from the warehouse DEFAULT bin to a rack bin. */
function moveToRack(batchId: number, wh: number, locId: number, qty: number): void {
  const def = defaultLocation(wh);
  db.prepare('UPDATE batch_stock_by_location SET quantity_physical = quantity_physical - ?, quantity_available = quantity_available - ? WHERE batch_id = ? AND location_id = ?')
    .run(qty, qty, batchId, def);
  db.prepare(`INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
              VALUES (?, ?, ?, 0, ?)`).run(batchId, locId, qty, qty);
}

function batchIdsOf(itemId: number, wh: number): number[] {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY received_date ASC, id ASC',
  ).all(itemId, wh) as Array<{ id: number }>).map((r) => r.id);
}

function binRow(batchId: number, locationId: number): { physical: number; reserved: number; available: number } {
  const r = db.prepare(
    `SELECT quantity_physical as physical, quantity_reserved as reserved, quantity_available as available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;
  return r ?? { physical: 0, reserved: 0, available: 0 };
}

function drawsOf(lineId: number): Array<{ batch_id: number; location_id: number; quantity: number }> {
  return db.prepare(
    'SELECT batch_id, location_id, quantity FROM invoice_item_bin_consumption WHERE invoice_item_id = ? ORDER BY id',
  ).all(lineId) as Array<{ batch_id: number; location_id: number; quantity: number }>;
}

/** The bins a return actually restocked, as the return document recorded them. */
function returnBatchRows(invoiceId: number): Array<{ batch_id: number; location_id: number; quantity: number }> {
  return db.prepare(
    'SELECT batch_id, location_id, quantity FROM invoice_return_batches WHERE invoice_id = ? ORDER BY id',
  ).all(invoiceId) as Array<{ batch_id: number; location_id: number; quantity: number }>;
}

function returnedQtyOf(lineId: number): number {
  return Number((db.prepare('SELECT returned_qty FROM invoice_items WHERE id = ?').get(lineId) as
    { returned_qty: number }).returned_qty);
}

/** One unreserved FIFO sale of `qty`, returning the invoice id and its line id. */
async function sellFifo(itemId: number, qty: number, tag: string): Promise<{ invoiceId: number; lineId: number }> {
  seq += 1;
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`bin-${tag}-${seq}`))
    .send({
      customer_id: customerId,
      invoice_date: AS_OF,
      warehouse_id: warehouseA,
      items: [{ item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0 }],
    });
  expect(res.status).toBe(201);
  const invoiceId = (db.prepare('SELECT id FROM invoices ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
  const lineId = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1')
    .get(invoiceId) as { id: number }).id;
  return { invoiceId, lineId };
}

function returnRaw(invoiceId: number, body: unknown, tag: string) {
  seq += 1;
  return request(app)
    .post(`/api/invoices/${invoiceId}/return`)
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`bin-${tag}-${seq}`))
    .send(body as object);
}

/**
 * A batch with stock on TWO rack bins and nothing in DEFAULT, so a sale can
 * only draw on the racks — the case where the old DEFAULT fallback put the
 * returned goods in a bin that never held them.
 */
async function twoRackBins(tag: string): Promise<{ item: number; b1: number; r1: number; r2: number; dl: number }> {
  seq += 1;
  const item = await createItem(`BIN-${tag}-${Date.now()}-${seq}`, cookie);
  await purchaseStock(item, warehouseA, 10, 40, cookie, AS_OF);
  const [b1] = batchIdsOf(item, warehouseA);
  const dl = defaultLocation(warehouseA);
  const r1 = rackLocation(warehouseA, `BIN-${tag}-R1-${Date.now()}-${seq}`);
  const r2 = rackLocation(warehouseA, `BIN-${tag}-R2-${Date.now()}-${seq}`);
  moveToRack(b1, warehouseA, r1, 6);
  moveToRack(b1, warehouseA, r2, 4);
  return { item, b1, r1, r2, dl };
}

describe('Decision 2: a sale records the exact per-bin draw of every line', () => {
  it('records the draws of an unreserved FIFO sale across two bins', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2, dl } = await twoRackBins('fifo-draw');

    const { lineId } = await sellFifo(item, 8, 'fifo-draw');

    // The sale drew 6 from the first rack and 2 from the second.
    expect(binRow(b1, r1)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b1, dl)).toEqual({ physical: 0, reserved: 0, available: 0 });

    // The unreserved sale is no longer anonymous: the draw is on the ledger,
    // in the order the units left the bins.
    expect(drawsOf(lineId)).toEqual([
      { batch_id: b1, location_id: r1, quantity: 6 },
      { batch_id: b1, location_id: r2, quantity: 2 },
    ]);
  });

  it('exposes the recorded draws on the invoice detail for the return picker', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2 } = await twoRackBins('detail');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'detail');

    const res = await request(app).get(`/api/invoices/${invoiceId}`).set('Cookie', cookie);
    expect(res.status).toBe(200);
    const items = res.body.items as Array<{
      id: number;
      bin_consumption?: Array<{ batch_id: number; location_id: number; quantity: number }>;
    }>;
    const line = items.find((i) => i.id === lineId);
    expect(line).toBeDefined();
    expect(line?.bin_consumption).toEqual([
      { batch_id: b1, location_id: r1, quantity: 6 },
      { batch_id: b1, location_id: r2, quantity: 2 },
    ]);
  });
});

describe('Decision 2: a return replays the bins the line recorded', () => {
  it('restocks a partial return on the recorded bins, never the DEFAULT bin', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2, dl } = await twoRackBins('replay');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'replay');

    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2 }],
      reason: 'two-bin partial',
    }, 'replay');

    expect(res.status).toBe(200);
    // The replay walks the recorded draws in order: the first rack gains the 2.
    expect(binRow(b1, r1)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
    // The bin that never held the goods stays empty.
    expect(binRow(b1, dl)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(returnBatchRows(invoiceId)).toEqual([{ batch_id: b1, location_id: r1, quantity: 2 }]);
  });

  it('negative control: the recorded draw wins over a bin the client suggests', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2 } = await twoRackBins('ledger-wins');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'ledger-wins');

    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2, location_id: r2 }],
      reason: 'ledger wins',
    }, 'ledger-wins');

    expect(res.status).toBe(200);
    expect(binRow(b1, r1)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });
});

describe('Decision 2: a line with no recorded draw requires a chosen bin', () => {
  /** Delete the ledger rows: the state of a sale recorded before draws existed. */
  function forgetDraws(lineId: number): void {
    db.prepare('DELETE FROM invoice_item_bin_consumption WHERE invoice_item_id = ?').run(lineId);
  }

  it('rejects the return when no bin is chosen and moves nothing', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2, dl } = await twoRackBins('no-draw');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'no-draw');
    forgetDraws(lineId);

    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2 }],
      reason: 'no bin chosen',
    }, 'no-draw');

    expect(res.status).toBe(400);
    expect(String(res.body.error)).toContain('bin');
    // The refusal must be total: no restock anywhere, no quantity consumed.
    expect(binRow(b1, r1)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b1, dl)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(returnedQtyOf(lineId)).toBe(0);
    expect(returnBatchRows(invoiceId)).toEqual([]);
    const headers = db.prepare('SELECT COUNT(*) AS c FROM invoice_returns WHERE invoice_id = ?')
      .get(invoiceId) as { c: number };
    expect(Number(headers.c)).toBe(0);
  });

  it('restocks into the bin the user chooses', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r1, r2, dl } = await twoRackBins('choose');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'choose');
    forgetDraws(lineId);

    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2, location_id: r2 }],
      reason: 'user chose the second rack',
    }, 'choose');

    expect(res.status).toBe(200);
    // Exactly where the user said: the bin they picked, not DEFAULT and not r1.
    expect(binRow(b1, r2)).toEqual({ physical: 4, reserved: 0, available: 4 });
    expect(binRow(b1, r1)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(binRow(b1, dl)).toEqual({ physical: 0, reserved: 0, available: 0 });
    expect(returnBatchRows(invoiceId)).toEqual([{ batch_id: b1, location_id: r2, quantity: 2 }]);
    expect(returnedQtyOf(lineId)).toBe(2);
  });

  it('rejects a chosen bin that belongs to another warehouse', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r2 } = await twoRackBins('foreign-bin');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'foreign-bin');
    forgetDraws(lineId);

    seq += 1;
    db.prepare("INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES (?, ?, 1)")
      .run(`BIN-OTHER-${Date.now()}-${seq}`, `BIN Other ${seq}`);
    const otherWh = (db.prepare('SELECT id FROM warehouses ORDER BY id DESC LIMIT 1')
      .get() as { id: number }).id;
    const otherBin = rackLocation(otherWh, `BIN-OTHER-R1-${Date.now()}-${seq}`);

    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2, location_id: otherBin }],
      reason: 'foreign bin',
    }, 'foreign-bin');

    expect(res.status).toBe(400);
    expect(String(res.body.error)).toContain('warehouse');
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(returnedQtyOf(lineId)).toBe(0);
    expect(returnBatchRows(invoiceId)).toEqual([]);
  });

  it('rejects a chosen bin that does not exist', async () => {
    setFeatureEnabled(db, FLAG, true);
    const { item, b1, r2 } = await twoRackBins('ghost-bin');

    const { invoiceId, lineId } = await sellFifo(item, 8, 'ghost-bin');
    forgetDraws(lineId);

    const missingBin = (db.prepare('SELECT MAX(id) AS id FROM locations').get() as { id: number }).id + 1000;
    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 2, location_id: missingBin }],
      reason: 'ghost bin',
    }, 'ghost-bin');

    expect(res.status).toBe(400);
    expect(binRow(b1, r2)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(returnedQtyOf(lineId)).toBe(0);
  });

  it('negative control: an unbatched legacy line needs no bin choice', async () => {
    setFeatureEnabled(db, FLAG, true);
    seq += 1;
    const item = await createItem(`BIN-LEGACY-${Date.now()}-${seq}`, cookie);
    // Opening stock that predates batch costing: a balance with no batch rows.
    db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, 10)
       ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = 10`,
    ).run(item, warehouseA);

    const { invoiceId, lineId } = await sellFifo(item, 2, 'legacy');

    // Nothing was drawn from a bin, so there is no bin to name and no bin to
    // touch: the return is accepted and only the balance movement is written.
    const res = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 1 }],
      reason: 'legacy unbatched return',
    }, 'legacy');

    expect(res.status).toBe(200);
    expect(returnBatchRows(invoiceId)).toEqual([]);
    expect(returnedQtyOf(lineId)).toBe(1);
  });
});

/**
 * Successive partial returns. The bin walk must CONTINUE where the previous
 * return stopped, and it must read that progress from the returning LINE only.
 * A too-high seed over-fills one bin and leaves another short; a too-low one
 * restarts at the first bin and does the same. Both are silent stock damage.
 */
describe('Decision 2: a second partial return continues where the first stopped', () => {
  it('walks the remaining bins of a batch after an earlier return filled the first', async () => {
    setFeatureEnabled(db, FLAG, true);
    seq += 1;
    const item = await createItem(`BIN-MULTI-${Date.now()}-${seq}`, cookie);
    const dl = defaultLocation(warehouseA);
    // Two batches of the same item. Batch 1 stays in DEFAULT, batch 2 is split
    // across two rack bins, so the line's draw list spans batch AND bin.
    await purchaseStock(item, warehouseA, 6, 40, cookie, AS_OF);
    await purchaseStock(item, warehouseA, 6, 40, cookie, AS_OF);
    const [b1, b2] = batchIdsOf(item, warehouseA);
    const r3 = rackLocation(warehouseA, `BIN-MULTI-R3-${Date.now()}-${seq}`);
    const r4 = rackLocation(warehouseA, `BIN-MULTI-R4-${Date.now()}-${seq}`);
    moveToRack(b2, warehouseA, r3, 4);
    moveToRack(b2, warehouseA, r4, 2);

    const { invoiceId, lineId } = await sellFifo(item, 12, 'multi');

    expect(drawsOf(lineId)).toEqual([
      { batch_id: b1, location_id: dl, quantity: 6 },
      { batch_id: b2, location_id: r3, quantity: 4 },
      { batch_id: b2, location_id: r4, quantity: 2 },
    ]);

    // First return: one third of the sale, so each batch gives back 2 units.
    const first = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 4 }],
      reason: 'first partial',
    }, 'multi-1');
    expect(first.status).toBe(200);
    expect(binRow(b1, dl)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b2, r3)).toEqual({ physical: 2, reserved: 0, available: 2 });
    expect(binRow(b2, r4)).toEqual({ physical: 0, reserved: 0, available: 0 });

    // Second return of the remaining 8. Batch 2 must resume its own walk: r3
    // stops at the 4 units it gave the sale and the rest lands on r4.
    const second = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineId, return_quantity: 8 }],
      reason: 'second partial',
    }, 'multi-2');
    expect(second.status).toBe(200);
    expect(binRow(b1, dl)).toEqual({ physical: 6, reserved: 0, available: 6 });
    expect(binRow(b2, r3)).toEqual({ physical: 4, reserved: 0, available: 4 });
    expect(binRow(b2, r4)).toEqual({ physical: 2, reserved: 0, available: 2 });
  });

  it('seeds a line only from its own restores, never from a sibling line', async () => {
    setFeatureEnabled(db, FLAG, true);
    seq += 1;
    const item = await createItem(`BIN-TWOLINE-${Date.now()}-${seq}`, cookie);
    const dl = defaultLocation(warehouseA);
    // One batch: 12 units in DEFAULT and 2 on a rack.
    await purchaseStock(item, warehouseA, 14, 40, cookie, AS_OF);
    const [b1] = batchIdsOf(item, warehouseA);
    const r3 = rackLocation(warehouseA, `BIN-TWOLINE-R3-${Date.now()}-${seq}`);
    moveToRack(b1, warehouseA, r3, 2);

    const before = {
      dl: binRow(b1, dl),
      r3: binRow(b1, r3),
    };

    // Two lines of the same item. The first draws only from DEFAULT; the second
    // draws the rest of DEFAULT and then the rack.
    seq += 1;
    const created = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey(`bin-twoline-${seq}`))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        warehouse_id: warehouseA,
        items: [
          { item_id: item, quantity: 8, unit_price: 50, tax_rate: 0 },
          { item_id: item, quantity: 6, unit_price: 50, tax_rate: 0 },
        ],
      });
    expect(created.status).toBe(201);
    const invoiceId = (db.prepare('SELECT id FROM invoices ORDER BY id DESC LIMIT 1')
      .get() as { id: number }).id;
    const lineIds = (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoiceId) as Array<{ id: number }>).map((r) => r.id);
    expect(lineIds).toHaveLength(2);

    expect(drawsOf(lineIds[0])).toEqual([{ batch_id: b1, location_id: dl, quantity: 8 }]);
    expect(drawsOf(lineIds[1])).toEqual([
      { batch_id: b1, location_id: dl, quantity: 4 },
      { batch_id: b1, location_id: r3, quantity: 2 },
    ]);

    // The sibling line is returned in full first, which restores all 8 DEFAULT
    // units of ITS draw. That must not make the second line believe its own 4
    // DEFAULT units are already back.
    const firstLine = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineIds[0], return_quantity: 8 }],
      reason: 'first line back',
    }, 'twoline-1');
    expect(firstLine.status).toBe(200);

    const secondLine = await returnRaw(invoiceId, {
      items: [{ invoice_item_id: lineIds[1], return_quantity: 6 }],
      reason: 'second line back',
    }, 'twoline-2');
    expect(secondLine.status).toBe(200);

    // Every unit of both lines is back, so every bin holds exactly what it held
    // before the sale. A seed taken from the sibling line would send this line's
    // DEFAULT units to the rack and over-fill it.
    expect(binRow(b1, dl)).toEqual(before.dl);
    expect(binRow(b1, r3)).toEqual(before.r3);
  });
});
