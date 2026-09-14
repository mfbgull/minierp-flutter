// invoice-expired-stock-exclusion change (tasks 4.2, 7.1–7.9):
// expired inventory must never be sellable — item picker excludes
// zero-sellable items, every sale path 400-rejects expired consumption,
// FEFO skips expired batches in both flag states, returns never
// re-sell expired stock, and the batch-expiry PATCH guard closes the
// manual unblock vector.
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import StockMovementModel from '../models/StockMovement';

let token = '';
let seq = 0;
let invoiceSeq = 5000;
const PAST = '2020-01-01';
const FUTURE = '2100-01-01';

interface SeededItem {
  itemId: number;
  warehouseId: number;
  customerId: number;
  expiredBatchId: number;
  freshBatchId: number;
}

function firstWarehouseId(): number {
  return (db.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get() as { id: number }).id;
}

async function login(): Promise<void> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: 'test-admin-password-secure-2026' });
  const cookies = res.headers['set-cookie'];
  if (!cookies) throw new Error('login returned no cookies');
  const list = Array.isArray(cookies) ? cookies : [cookies];
  const t = list.find((c: string) => c.startsWith('token='));
  if (!t) throw new Error('login returned no token cookie');
  token = t.split(';')[0];
}

function parseResponseBody(
  res: { status: number; body?: unknown },
  context: string
): Record<string, unknown> {
  const body = (res.body ?? {}) as Record<string, unknown>;
  if (res.status >= 400) {
    const message = typeof body.error === 'string' ? body.error : JSON.stringify(body);
    throw new Error(`${context}: ${res.status} ${message}`);
  }
  return body;
}

function seedItemWithBatches(freshQty: number, expiredQty: number): SeededItem {
  const warehouseId = firstWarehouseId();
  seq += 1;

  const itemId = (db.prepare(
    `INSERT INTO items (item_code, item_name, unit_of_measure, has_expiry, current_stock, created_by)
     VALUES (?, ?, 'pcs', 1, 0, 1)`
  ).run(`EX-IT-${seq}`, `Expiry Item ${seq}`) as { lastInsertRowid?: number }).lastInsertRowid as number;

  const customerId = (db.prepare(
    `INSERT INTO customers (customer_code, customer_name, phone, created_at, updated_at)
     VALUES (?, ?, ?, datetime('now'), datetime('now'))`
  ).run(`EX-C-${seq}`, `EX Cust ${seq}`, `0300-0000${String(seq).slice(-4)}`) as { lastInsertRowid?: number }).lastInsertRowid as number;

  let expiredBatchId = 0;
  let freshBatchId = 0;
  const totalQty = (expiredQty || 0) + (freshQty || 0);

  if (expiredQty > 0) {
    const seeded = seedBatch(db, {
      itemId,
      warehouseId,
      batchNo: `EX-EXP-${seq}`,
      qty: expiredQty,
      expiry: PAST,
    });
    expiredBatchId = seeded.batchId;
  }

  if (freshQty > 0) {
    const seeded = seedBatch(db, {
      itemId,
      warehouseId,
      batchNo: `EX-FRE-${seq}`,
      qty: freshQty,
      expiry: FUTURE,
    });
    freshBatchId = seeded.batchId;
  }

  // stock_balances mirrors what the purchase flow writes: quantity =
  // total on hand; the batch-location extension columns (flag ON) hold
  // the same total because every batch — expired ones too — has an
  // ACTIVE location row. Sellability (expiry filtering) is applied at
  // read time, not in these columns.
  db.prepare(
    `INSERT INTO stock_balances (item_id, warehouse_id, quantity, quantity_physical, quantity_reserved, quantity_available)
     VALUES (?, ?, ?, ?, 0, ?)
     ON CONFLICT(item_id, warehouse_id) DO UPDATE SET
       quantity = excluded.quantity,
       quantity_physical = excluded.quantity_physical,
       quantity_reserved = 0,
       quantity_available = excluded.quantity_available`
  ).run(itemId, warehouseId, totalQty, totalQty, totalQty);

  return { itemId, warehouseId, customerId, expiredBatchId, freshBatchId };
}

function seedBatch(
  dbInner: typeof db,
  opts: { itemId: number; warehouseId: number; batchNo: string; qty: number; expiry: string }
): { batchId: number; locationId: number } {
  const batchResult = dbInner
    .prepare(
      `INSERT INTO stock_batches (item_id, warehouse_id, batch_no, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
       VALUES (?, ?, ?, 'PURCHASE', 0, ?, ?, 10, date('now'), ?)`
    )
    .run(opts.itemId, opts.warehouseId, opts.batchNo, opts.qty, opts.qty, opts.expiry);
  const batchId = Number((batchResult as { lastInsertRowid?: number }).lastInsertRowid);

  const locResult = dbInner
    .prepare(
      `INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available, status_override, created_at, updated_at)
       VALUES (?, ?, ?, 0, ?, 'ACTIVE', datetime('now'), datetime('now'))`
    )
    .run(batchId, opts.warehouseId, opts.qty, opts.qty);
  const locationId = Number((locResult as { lastInsertRowid?: number }).lastInsertRowid);

  return { batchId, locationId };
}

/** Keep the batch-location extension columns aligned after raw batch edits. */
function refreshBalanceExtension(itemId: number, warehouseId: number): void {
  db.prepare(
    `UPDATE stock_balances SET
       quantity = COALESCE((SELECT SUM(quantity_remaining) FROM stock_batches WHERE item_id = ? AND warehouse_id = ?), 0),
       quantity_physical = COALESCE((SELECT SUM(bsl.quantity_physical) FROM batch_stock_by_location bsl JOIN locations l ON bsl.location_id = l.id JOIN stock_batches sb ON sb.id = bsl.batch_id WHERE sb.item_id = ? AND l.warehouse_id = ?), 0),
       quantity_available = COALESCE((SELECT SUM(bsl.quantity_available) FROM batch_stock_by_location bsl JOIN locations l ON bsl.location_id = l.id JOIN stock_batches sb ON sb.id = bsl.batch_id WHERE sb.item_id = ? AND l.warehouse_id = ?), 0)
     WHERE item_id = ? AND warehouse_id = ?`
  ).run(itemId, warehouseId, itemId, warehouseId, itemId, warehouseId, itemId, warehouseId);
}

function refreshLocationRows(itemId: number, warehouseId: number): void {
  // After backdating expiry we keep location rows as-is; their
  // quantity_available already matches stock_batches.quantity_remaining.
  refreshBalanceExtension(itemId, warehouseId);
}

function sellableQty(itemId: number, warehouseId?: number): number {
  const rows = StockMovementModel.getSellableAvailability(itemId, warehouseId ?? null, db);
  return rows.reduce((s, w) => s + Number(w.sellable_qty ?? 0), 0);
}

function postInvoice(payload: Record<string, unknown>): Promise<request.Response> {
  invoiceSeq += 1;
  return request(app)
    .post('/api/invoices')
    .set('Cookie', token)
    .send({ invoice_no: `INV-EX-${invoiceSeq}`, ...payload });
}

interface InvoiceLine {
  item_id: number;
  quantity: number;
  unit_price: number;
  warehouse_id: number;
}

beforeAll(async () => {
  await login();
});

afterEach(() => {
  setFeatureEnabled(db, 'feature_batch_locations', false);
});

describe('Scenario 1/2 (7.1) — items endpoint sellable_only + sellable_qty', () => {
  it('excludes an item whose only batch is expired; includes with correct sellable_qty once fresh stock exists', async () => {
    const onlyExpired = seedItemWithBatches(0, 50);
    const mixed = seedItemWithBatches(60, 200);

    const res = await request(app)
      .get('/api/inventory/items?sellable_only=1&limit=10000')
      .set('Cookie', token);
    expect(res.status).toBe(200);
    const body = parseResponseBody(res, 'items list');
    const items: Array<{ id: number; sellable_qty?: number }> = Array.isArray(body.data)
      ? (body.data as Array<{ id: number; sellable_qty?: number }>)
      : [];
    const ids = items.map((i) => i.id);
    expect(ids).not.toContain(onlyExpired.itemId);
    expect(ids).toContain(mixed.itemId);
    const mixedRow = items.find((i) => i.id === mixed.itemId)!;
    // 60 non-expired + 200 expired → sellable 60, not 260
    expect(Number(mixedRow.sellable_qty ?? 0)).toBe(60);
  });

  it('sellable_qty is 0 for the only-expired item without the filter', () => {
    const onlyExpired = seedItemWithBatches(0, 50);
    expect(sellableQty(onlyExpired.itemId, onlyExpired.warehouseId)).toBe(0);
  });
});

describe('Scenario 3 (7.2 + 4.2) — FEFO multi-batch skips expired, consumes earliest non-expired first', () => {
  it('consumes earliest-expiry non-expired batch first, both flag states', async () => {
    for (const flag of [false, true]) {
      setFeatureEnabled(db, 'feature_batch_locations', flag);
      const { itemId, warehouseId, customerId } = seedItemWithBatches(0, 0);
      const expired = seedBatch(db, {
        itemId,
        warehouseId,
        batchNo: `EX3-EXP-${seq}`,
        qty: 200,
        expiry: PAST,
      });
      const earlier = seedBatch(db, {
        itemId,
        warehouseId,
        batchNo: `EX3-EAR-${seq}`,
        qty: 60,
        expiry: '2099-12-31',
      });
      const later = seedBatch(db, {
        itemId,
        warehouseId,
        batchNo: `EX3-LAT-${seq}`,
        qty: 50,
        expiry: '2099-12-31',
      });
      // Make `earlier` strictly earlier than `later` (received_date tiebreak).
      db.prepare(`UPDATE stock_batches SET expiry_date = '2098-12-31' WHERE id = ?`).run(earlier.batchId);
      refreshBalanceExtension(itemId, warehouseId);

      const res = await postInvoice({
        customer_id: customerId,
        invoice_date: '2026-09-14',
        total_amount: 600, // 60 × 10
        items: [
          { item_id: itemId, quantity: 60, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
        ],
      });
      parseResponseBody(res, `create invoice (flag ${flag ? 'ON' : 'OFF'})`);

      const remaining = db
        .prepare(`SELECT batch_no, quantity_remaining FROM stock_batches WHERE id IN (?, ?, ?)`)
        .all(expired.batchId, earlier.batchId, later.batchId) as Array<{ batch_no: string; quantity_remaining: number }>;
      const map = Object.fromEntries(remaining.map((r) => [r.batch_no, Number(r.quantity_remaining)]));
      // Expired batch untouched; earliest non-expired consumed first.
      expect(Number(map[`EX3-EXP-${seq}`])).toBe(200);
      expect(Number(map[`EX3-EAR-${seq}`])).toBeCloseTo(0, 6);
      expect(Number(map[`EX3-LAT-${seq}`])).toBe(50);
    }
  });
});

describe('Scenario 4 (7.3) — insufficient non-expired stock → 400, nothing changes', () => {
  it('rejects qty 100 when only 60 non-expired + 200 expired; stock/movements untouched', async () => {
    for (const flag of [false, true]) {
      setFeatureEnabled(db, 'feature_batch_locations', flag);
      const { itemId, warehouseId, customerId } = seedItemWithBatches(60, 200);

      const res = await postInvoice({
        customer_id: customerId,
        invoice_date: '2026-09-14',
        total_amount: 1000, // 100 × 10
        items: [
          { item_id: itemId, quantity: 100, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
        ],
      });
      expect(res.status).toBeGreaterThanOrEqual(400);
      expect(res.status).toBeLessThan(500);
      const body = res.body as { error?: string };
      expect(body.error ?? '').toMatch(/sellable stock/i);

      const movements = db
        .prepare(`SELECT COUNT(*) AS count FROM stock_movements WHERE item_id = ?`)
        .get(itemId) as { count: number };
      expect(movements.count).toBe(0);
      const batchSum = db
        .prepare(`SELECT SUM(quantity_remaining) AS q FROM stock_batches WHERE item_id = ?`)
        .get(itemId) as { q: number };
      expect(Number(batchSum.q)).toBe(260);
    }
  });
});

describe('Scenario 5 (7.4/7.5) — expiry mid-draft + API bypass vectors', () => {
  it('direct POST /api/invoices with only-expired stock → 400; expired_batch_overrides payload is inert', async () => {
    const { itemId, warehouseId, customerId } = seedItemWithBatches(0, 40);

    const res = await postInvoice({
      customer_id: customerId,
      invoice_date: '2026-09-14',
      total_amount: 100, // 10 × 10
      // Legacy-client payload must not bypass the sale block.
      expired_batch_overrides: { [itemId]: { override_sale: 1 } },
      items: [
        { item_id: itemId, quantity: 10, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
      ],
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    const body = res.body as { error?: string };
    expect(body.error ?? '').toMatch(/sellable stock/i);
  });

  it('backdated expiry on a saved invoice line: update after expiry → 400, invoice intact', async () => {
    const { itemId, warehouseId, customerId, freshBatchId } = seedItemWithBatches(40, 0);

    const createRes = await postInvoice({
      customer_id: customerId,
      invoice_date: '2026-09-14',
      total_amount: 100, // 10 × 10
      items: [
        { item_id: itemId, quantity: 10, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
      ],
    });
    parseResponseBody(createRes, 'create invoice');
    const invoiceId = (createRes.body as { id?: number }).id as number;

    // Expiry passes mid-draft: the batch the line consumed goes stale.
    db.prepare(`UPDATE stock_batches SET expiry_date = ? WHERE id = ?`).run(PAST, freshBatchId);
    refreshLocationRows(itemId, warehouseId);

    const updRes = await request(app)
      .put(`/api/invoices/${invoiceId}`)
      .set('Cookie', token)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-14',
        total_amount: 100,
        items: [
          { item_id: itemId, quantity: 10, unit_price: 10, warehouse_id: warehouseId },
        ],
      });
    expect(updRes.status).toBeGreaterThanOrEqual(400);
    expect(updRes.status).toBeLessThan(500);

    const invoice = db.prepare(`SELECT status FROM invoices WHERE id = ?`).get(invoiceId) as { status: string };
    expect(invoice.status).not.toBe('Cancelled');
  });
});

describe('Scenario 6 (7.6) — returns never re-sell expired stock', () => {
  it('batch expiring after sale: return restores the batch, sellable availability unchanged, re-sale rejected', async () => {
    const { itemId, warehouseId, customerId, freshBatchId } = seedItemWithBatches(50, 0);

    const invoiceRes = await postInvoice({
      customer_id: customerId,
      invoice_date: '2026-09-14',
      total_amount: 200, // 20 × 10
      items: [
        { item_id: itemId, quantity: 20, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
      ],
    });
    parseResponseBody(invoiceRes, 'create invoice');
    const invoiceId = (invoiceRes.body as { id?: number }).id as number;
    const saleItemId = (db.prepare(`SELECT id FROM invoice_items WHERE invoice_id = ?`).get(invoiceId) as { id: number }).id;

    // The batch expires after the sale…
    db.prepare(`UPDATE stock_batches SET expiry_date = ? WHERE id = ?`).run(PAST, freshBatchId);
    refreshLocationRows(itemId, warehouseId);
    const sellableAtExpiry = sellableQty(itemId, warehouseId);

    // …the customer returns 10 units. Stock goes back to the batch, but
    // sellable availability must not grow (expired goods ≠ sellable).
    const returnRes = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', token)
      .send({
        return_date: new Date().toISOString().slice(0, 10),
        items: [{ invoice_item_id: saleItemId, return_quantity: 10 }],
        disposition: 'credit',
      });
    parseResponseBody(returnRes, 'return');

    expect(sellableQty(itemId, warehouseId)).toBe(sellableAtExpiry);

    // A new invoice line for the returned qty is rejected.
    const resaleRes = await postInvoice({
      customer_id: customerId,
      invoice_date: '2026-09-14',
      total_amount: 100, // 10 × 10
      items: [
        { item_id: itemId, quantity: 10, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
      ],
    });
    expect(resaleRes.status).toBeGreaterThanOrEqual(400);
    expect(resaleRes.status).toBeLessThan(500);
  });
});

describe('Scenario 7 (7.7 guard) — batch expiry PATCH guard', () => {
  it('rejects null/past expiry_date while quantity_remaining > 0; allows edits when remaining = 0', async () => {
    const { freshBatchId } = seedItemWithBatches(60, 50);
    const id = freshBatchId;

    // null expiry rejected (zod + guard agree)
    const nullRes = await request(app)
      .patch(`/api/inventory/stock-batches/${id}`)
      .set('Cookie', token)
      .send({ expiry_date: null });
    expect(nullRes.status).toBeGreaterThanOrEqual(400);

    // backdate rejected by the guard
    const pastRes = await request(app)
      .patch(`/api/inventory/stock-batches/${id}`)
      .set('Cookie', token)
      .send({ expiry_date: PAST });
    expect(pastRes.status).toBeGreaterThanOrEqual(400);

    // once the batch is fully consumed, backdating is allowed
    db.prepare(`UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?`).run(id);
    const okRes = await request(app)
      .patch(`/api/inventory/stock-batches/${id}`)
      .set('Cookie', token)
      .send({ expiry_date: PAST });
    expect(okRes.status).toBeLessThan(300);
  });
});

describe('7.8 — both feature-flag states behave identically for sale blocking', () => {
  it('expired-only sale is rejected under both flag states', async () => {
    for (const flag of [false, true]) {
      setFeatureEnabled(db, 'feature_batch_locations', flag);
      const { itemId, warehouseId, customerId } = seedItemWithBatches(0, 30);

      const res = await postInvoice({
        customer_id: customerId,
        invoice_date: '2026-09-14',
        total_amount: 10, // 1 × 10
        items: [
          { item_id: itemId, quantity: 1, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
        ],
      });
      expect(res.status).toBeGreaterThanOrEqual(400);
      expect(res.status).toBeLessThan(500);
      const body = res.body as { error?: string };
      expect(body.error ?? '').toMatch(/sellable stock/i);
    }
  });
});

describe('7.9 — full lifecycle invariant (create → return → cancel leaves stock consistent)', () => {
  it('create → partial return → cancel guard holds', async () => {
    const { itemId, warehouseId, customerId } = seedItemWithBatches(50, 0);

    const invRes = await postInvoice({
      customer_id: customerId,
      invoice_date: '2026-09-14',
      total_amount: 200, // 20 × 10
      items: [
        { item_id: itemId, quantity: 20, unit_price: 10, warehouse_id: warehouseId } as InvoiceLine,
      ],
    });
    parseResponseBody(invRes, 'create invoice');
    const invoiceId = (invRes.body as { id?: number }).id as number;
    const lifecycleItemId = (db.prepare(`SELECT id FROM invoice_items WHERE invoice_id = ?`).get(invoiceId) as { id: number }).id;

    const retRes = await request(app)
      .post(`/api/invoices/${invoiceId}/return`)
      .set('Cookie', token)
      .send({
        return_date: new Date().toISOString().slice(0, 10),
        items: [{ invoice_item_id: lifecycleItemId, return_quantity: 5 }],
        disposition: 'credit',
      });
    parseResponseBody(retRes, 'return');

    // Cancel after a return is guarded (returned_amount > 0) — 400, and
    // stock stays consistent: sold 20, returned 5.
    const cancelRes = await request(app)
      .put(`/api/invoices/${invoiceId}/cancel`)
      .set('Cookie', token)
      .send({});
    expect(cancelRes.status).toBeGreaterThanOrEqual(400);
    expect(cancelRes.status).toBeLessThan(500);

    const batchSum = db
      .prepare(`SELECT SUM(quantity_remaining) AS q FROM stock_batches WHERE item_id = ?`)
      .get(itemId) as { q: number };
    expect(Number(batchSum.q)).toBe(35);
  });
});
