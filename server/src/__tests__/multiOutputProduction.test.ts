/**
 * D6 joint-production (multi-output) end-to-end regression suite.
 *
 * Drives real POST /productions through the HTTP stack and asserts the
 * whole chain, because the failure mode that matters is a split between
 * any two links:
 *
 *   raw materials deducted -> outputs in their own batches -> overhead
 *   absorbed -> allocated costs sum EXACTLY to total batch cost ->
 *   inventory valuation agrees -> GL clearing nets to zero -> reversal
 *   restores both -> negative stock stays impossible.
 *
 * The server allocation rule under test (models/Production.ts):
 *   pool      = roundCurrency(totalMaterialCost + overheadCost)
 *   weight[i] = qty[i] * items.standard_selling_price   (0 if unpriced)
 *               fallback to qty[i] when NO output is priced
 *   share[i]  = roundCurrency(pool * weight[i] / totalWeight), except the
 *               LAST line which takes roundCurrency(pool - allocatedSoFar)
 * The last-line remainder is what makes the shares sum to the pool exactly;
 * every money assertion below is an exact-cent equality, not a tolerance.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { roundCurrency } from '../utils/currency';
import { roundQty } from '../utils/quantity';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

let authCookie: string;
let warehouseId: number;
let supplierId: number;
let stamp = 0;

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies]).find(
    (c: string) => c.startsWith('token='),
  );
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

async function createItem(
  name: string,
  opts: { sellingPrice?: number; cost?: number; uom?: string } = {},
): Promise<number> {
  stamp += 1;
  const res = await request(app)
    .post('/api/inventory/items')
    .set('Cookie', authCookie)
    .send({
      item_code: `MO-${stamp}-${name}`,
      item_name: name,
      unit_of_measure: opts.uom ?? 'Nos',
      is_purchased: true,
      is_manufactured: true,
      standard_cost: opts.cost ?? 0,
      standard_selling_price: opts.sellingPrice ?? 0,
    });
  expect(res.status).toBe(201);
  return res.body.id as number;
}

/** Stocks `itemId` by purchasing `qty` at `unitCost`. */
async function stock(
  itemId: number,
  qty: number,
  unitCost: number,
  date: string,
): Promise<void> {
  const res = await request(app)
    .post('/api/purchases')
    .set('Cookie', authCookie)
    .send({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: qty,
      unit_cost: unitCost,
      purchase_date: date,
      supplier_id: supplierId,
    });
  expect(res.status).toBe(201);
}

function balance(itemId: number, wh: number): number {
  const row = db
    .prepare(`SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`)
    .get(itemId, wh) as { quantity: number } | undefined;
  return row ? Number(row.quantity) : 0;
}

interface OutputRow {
  item_id: number;
  quantity: number;
  unit_cost: number;
  allocated_cost: number;
}

function outputsOf(productionId: number): OutputRow[] {
  return db
    .prepare(
      `SELECT item_id, quantity, unit_cost, allocated_cost
       FROM production_outputs WHERE production_id = ? ORDER BY id ASC`,
    )
    .all(productionId) as OutputRow[];
}

/**
 * Debit and credit totals on the production_clearing account for one run.
 *
 * The legs are keyed by DIFFERENT ids: the consume/overhead debits carry
 * reference_id = production id, but the output credit carries reference_id =
 * stock_movements.id (postFinancialEntryForProduction keys off the movement
 * row). Filtering on the production id alone sees only the debits and makes
 * a balanced account look one-sided.
 */
function clearingTotals(productionId: number): { dr: number; cr: number } {
  const acct = db
    .prepare(`SELECT id FROM chart_of_accounts WHERE text_code = 'production_clearing'`)
    .get() as { id: number } | undefined;
  if (!acct) return { dr: 0, cr: 0 };
  const row = db
    .prepare(
      `SELECT COALESCE(SUM(debit),0) AS dr, COALESCE(SUM(credit),0) AS cr
       FROM journal_lines
       WHERE account_id = ? AND COALESCE(voided, 0) = 0
         AND (
           (reference_type IN ('production_consume','production_overhead')
             AND reference_id = ?)
           OR (reference_type = 'production'
             AND reference_id IN (
               SELECT id FROM stock_movements
               WHERE reference_docno = (
                 SELECT production_no FROM productions WHERE id = ?
               ) AND movement_type = 'PRODUCTION'
             ))
         )`,
    )
    .get(acct.id, productionId, productionId) as { dr: number; cr: number };
  return { dr: Number(row.dr), cr: Number(row.cr) };
}

beforeAll(async () => {
  authCookie = await getAuthCookie();
  expect(authCookie).not.toBe('');
  warehouseId = (
    db
      .prepare('SELECT id FROM warehouses WHERE is_active = 1 AND is_system = 0 ORDER BY id LIMIT 1')
      .get() as { id: number }
  ).id;
  supplierId = await resolveSupplierByName('MultiOutput Supplier', authCookie);
});

describe('joint production: cost split, valuation and GL', () => {
  // 20 units of raw material at 5 => 100 consumed; overhead 20 => pool 120.
  // Output A priced 10/unit, qty 4  -> weight 40
  // Output B priced 30/unit, qty 2  -> weight 60  => 40/60 split of 120
  const RAW_QTY = 20;
  const RAW_COST = 5;
  const OVERHEAD = 20;
  const A_QTY = 4;
  const B_QTY = 2;

  let rawId: number;
  let aId: number;
  let bId: number;
  let productionId: number;

  beforeAll(async () => {
    rawId = await createItem('MO-Raw', { cost: RAW_COST });
    aId = await createItem('MO-A', { sellingPrice: 10, uom: 'Litre' });
    bId = await createItem('MO-B', { sellingPrice: 30, uom: 'kg' });
    await stock(rawId, RAW_QTY, RAW_COST, '2026-08-01');

    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        outputs: [
          { item_id: aId, quantity: A_QTY },
          { item_id: bId, quantity: B_QTY },
        ],
        warehouse_id: warehouseId,
        production_date: '2026-08-10',
        input_items: [{ item_id: rawId, quantity: RAW_QTY }],
        overhead_cost: OVERHEAD,
      });
    expect(res.status).toBe(201);
    productionId = res.body.data?.id ?? res.body.id;
    expect(productionId).toBeDefined();
  });

  it('deducts the raw materials exactly', () => {
    // 20 consumed of 20 purchased, purchased at 5 => FIFO cost 100.
    expect(balance(rawId, warehouseId)).toBe(0);
    const remaining = db
      .prepare(
        `SELECT COALESCE(SUM(quantity_remaining),0) AS q FROM stock_batches WHERE item_id = ?`,
      )
      .get(rawId) as { q: number };
    expect(Number(remaining.q)).toBe(0);
  });

  it('adds every output to the finished-goods warehouse in its OWN batch', () => {
    const batches = db
      .prepare(
        `SELECT item_id, warehouse_id, quantity_original, quantity_remaining, unit_cost
         FROM stock_batches
         WHERE source_type = 'PRODUCTION' AND source_id = ?
         ORDER BY id ASC`,
      )
      .all(productionId) as Array<{
      item_id: number;
      warehouse_id: number;
      quantity_original: number;
      quantity_remaining: number;
      unit_cost: number;
    }>;

    expect(batches).toHaveLength(2);
    expect(batches.map((b) => b.item_id)).toEqual([aId, bId]);
    for (const b of batches) {
      expect(b.warehouse_id).toBe(warehouseId);
      expect(Number(b.quantity_original)).toBeGreaterThan(0);
      expect(Number(b.quantity_remaining)).toBe(Number(b.quantity_original));
    }
    // Distinct batches — one output never lands in another's batch.
    expect(balance(aId, warehouseId)).toBe(A_QTY);
    expect(balance(bId, warehouseId)).toBe(B_QTY);
  });

  it('includes the overhead in the production cost', () => {
    const p = db
      .prepare(`SELECT total_material_cost, overhead_cost, total_batch_cost FROM productions WHERE id = ?`)
      .get(productionId) as {
      total_material_cost: number;
      overhead_cost: number;
      total_batch_cost: number;
    };
    // Material is the FIFO cost only; overhead is added on top.
    expect(Number(p.total_material_cost)).toBe(RAW_QTY * RAW_COST);
    expect(Number(p.overhead_cost)).toBe(OVERHEAD);
    expect(Number(p.total_batch_cost)).toBe(
      roundCurrency(Number(p.total_material_cost) + OVERHEAD),
    );
  });

  it('allocates by relative sales value — the pricier output takes the bigger share', () => {
    const outs = outputsOf(productionId);
    expect(outs).toHaveLength(2);

    const pool = RAW_QTY * RAW_COST + OVERHEAD; // 120
    const weightA = A_QTY * 10; // 40
    const weightB = B_QTY * 30; // 60
    const totalWeight = weightA + weightB;

    const expectedA = roundCurrency((pool * weightA) / totalWeight); // 48
    const expectedB = roundCurrency(pool - expectedA); // last line absorbs remainder

    expect(Number(outs[0].allocated_cost)).toBe(expectedA);
    expect(Number(outs[1].allocated_cost)).toBe(expectedB);
    // The pricier-per-unit output carries strictly more cost here.
    expect(Number(outs[1].allocated_cost)).toBeGreaterThan(Number(outs[0].allocated_cost));
  });

  it('sums the allocated costs EXACTLY to the total production cost', () => {
    const outs = outputsOf(productionId);
    const sum = roundCurrency(
      outs.reduce((acc, o) => acc + Number(o.allocated_cost), 0),
    );
    const p = db
      .prepare(`SELECT total_batch_cost FROM productions WHERE id = ?`)
      .get(productionId) as { total_batch_cost: number };

    // Exact cent equality — not a tolerance. This is the invariant the GL
    // posting relies on to make production_clearing net to zero.
    expect(sum).toBe(roundCurrency(Number(p.total_batch_cost)));
  });

  it('stores each output unit cost as allocated / quantity', () => {
    for (const o of outputsOf(productionId)) {
      expect(Number(o.unit_cost)).toBe(
        roundQty(Number(o.allocated_cost) / Number(o.quantity), 6),
      );
    }
  });

  it('leaves the production_clearing account balanced', () => {
    const { dr, cr } = clearingTotals(productionId);
    expect(roundCurrency(dr)).toBe(roundCurrency(cr));
    expect(roundCurrency(dr)).toBe(RAW_QTY * RAW_COST + OVERHEAD);
  });

  it('reversal restores inventory and leaves the GL clean', async () => {
    const rawBefore = balance(rawId, warehouseId);
    const aBefore = balance(aId, warehouseId);
    const bBefore = balance(bId, warehouseId);

    const del = await request(app)
      .delete(`/api/productions/${productionId}`)
      .set('Cookie', authCookie);
    expect(del.status).toBe(200);

    expect(balance(rawId, warehouseId)).toBeGreaterThan(rawBefore);
    expect(balance(aId, warehouseId)).toBe(0);
    expect(balance(bId, warehouseId)).toBe(0);

    // Every GL line for the run is voided or reversed — nothing active left.
    const { dr, cr } = clearingTotals(productionId);
    expect(roundCurrency(dr)).toBe(roundCurrency(cr));
    expect(roundCurrency(dr)).toBe(0);

    // A second delete must not double-reverse.
    const again = await request(app)
      .delete(`/api/productions/${productionId}`)
      .set('Cookie', authCookie);
    expect([200, 404]).toContain(again.status);
  });
});

describe('joint production: guards', () => {
  it('rejects a production that would consume more than is on hand', async () => {
    const raw = await createItem('MO-Short', { cost: 5 });
    await stock(raw, 3, 5, '2026-08-01');
    const out = await createItem('MO-ShortOut', { sellingPrice: 10 });

    const rawBefore = balance(raw, warehouseId);
    const outBefore = balance(out, warehouseId);

    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        outputs: [{ item_id: out, quantity: 1 }],
        warehouse_id: warehouseId,
        production_date: '2026-08-11',
        input_items: [{ item_id: raw, quantity: 99 }],
        overhead_cost: 0,
      });

    expect(res.status).toBeGreaterThanOrEqual(400);
    // No partial write: stock untouched, no output batch created.
    expect(balance(raw, warehouseId)).toBe(rawBefore);
    expect(balance(out, warehouseId)).toBe(outBefore);
    const orphan = db
      .prepare(
        `SELECT COUNT(*) AS n FROM stock_batches
         WHERE source_type = 'PRODUCTION' AND item_id = ?`,
      )
      .get(out) as { n: number };
    expect(Number(orphan.n)).toBe(0);
  });

  it('rejects a duplicate output item', async () => {
    const raw = await createItem('MO-DupRaw', { cost: 5 });
    await stock(raw, 10, 5, '2026-08-01');
    const out = await createItem('MO-DupOut', { sellingPrice: 10 });

    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        outputs: [
          { item_id: out, quantity: 1 },
          { item_id: out, quantity: 2 },
        ],
        warehouse_id: warehouseId,
        production_date: '2026-08-12',
        input_items: [{ item_id: raw, quantity: 5 }],
      });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('rejects an output that is also a consumed input', async () => {
    const raw = await createItem('MO-CycleRaw', { cost: 5 });
    await stock(raw, 10, 5, '2026-08-01');

    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        outputs: [{ item_id: raw, quantity: 1 }],
        warehouse_id: warehouseId,
        production_date: '2026-08-13',
        input_items: [{ item_id: raw, quantity: 5 }],
      });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});