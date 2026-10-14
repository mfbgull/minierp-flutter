/**
 * Systemic guard: a stock batch whose item does not track expiry must
 * NEVER carry an expiry_date.
 *
 * The boot sweep (boot/expiryDetection.ts) already filters on
 * items.has_expiry, so a stray date does not move stock today. It is still
 * corrupt data: it surfaces on the expiry report, and the moment
 * has_expiry is switched on for that item every such historical batch
 * becomes sweep-eligible and is relocated to the EXPIRED warehouse in a
 * single boot (expiryDetection.test.ts demonstrates exactly that flip).
 *
 * D6 guarded the production output path only. Purchase, goods receipt and
 * the batch PATCH endpoint each decided for themselves and all three wrote
 * the date straight through. These tests lock all four write paths to the
 * shared ItemModel.batchExpiryDate guard.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import ItemModel from '../models/Item';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

let authCookie: string;
let warehouseId: number;
let supplierId: number;

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

/** Creates an item with an explicit has_expiry flag. */
async function createItem(
  code: string,
  hasExpiry: boolean,
  extra: Record<string, unknown> = {},
): Promise<number> {
  const res = await request(app)
    .post('/api/inventory/items')
    .set('Cookie', authCookie)
    .send({
      item_code: `${code}-${Date.now()}`,
      item_name: code,
      unit_of_measure: 'Nos',
      is_purchased: true,
      has_expiry: hasExpiry,
      ...extra,
    });
  expect(res.status).toBe(201);
  return res.body.id as number;
}

/** expiry_date of the most recent batch of an item. */
function latestBatchExpiry(itemId: number): string | null {
  const row = db
    .prepare(
      `SELECT expiry_date FROM stock_batches WHERE item_id = ?
       ORDER BY id DESC LIMIT 1`,
    )
    .get(itemId) as { expiry_date: string | null } | undefined;
  return row?.expiry_date ?? null;
}

async function purchase(
  itemId: number,
  expiryDate?: string,
): Promise<number> {
  const res = await request(app)
    .post('/api/purchases')
    .set('Cookie', authCookie)
    .send({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 10,
      unit_cost: 5,
      purchase_date: '2026-08-01',
      supplier_id: supplierId,
      ...(expiryDate === undefined ? {} : { expiry_date: expiryDate }),
    });
  expect(res.status).toBe(201);
  return (res.body.data?.id ?? res.body.id) as number;
}

/** Creates a PO and receives it, returning the receipt's batch id. */
async function goodsReceipt(
  itemId: number,
  poExpiryDate?: string,
): Promise<number> {
  const po = await request(app)
    .post('/api/purchase-orders')
    .set('Cookie', authCookie)
    .send({
      supplier_id: supplierId,
      po_date: '2026-08-01',
      items: [
        {
          item_id: itemId,
          quantity: 10,
          unit_price: 5,
          ...(poExpiryDate === undefined ? {} : { expiry_date: poExpiryDate }),
        },
      ],
    });
  expect(po.status).toBe(201);
  const poId = po.body.id as number;

  const status = await request(app)
    .post(`/api/purchase-orders/${poId}/status`)
    .set('Cookie', authCookie)
    .send({ status: 'Submitted' });
  expect(status.status).toBe(200);

  const poItem = db
    .prepare(`SELECT id FROM purchase_order_items WHERE po_id = ?`)
    .get(poId) as { id: number };
  expect(poItem).toBeDefined();

  const before = (
    db.prepare(`SELECT COALESCE(MAX(id),0) AS m FROM stock_batches`).get() as {
      m: number;
    }
  ).m;

  const receipt = await request(app)
    .post(`/api/purchase-orders/${poId}/receipts`)
    .set('Cookie', authCookie)
    .send({
      receipt_date: '2026-08-05',
      warehouse_id: warehouseId,
      items: [{ po_item_id: poItem.id, received_quantity: 10 }],
    });
  expect([200, 201]).toContain(receipt.status);

  const batch = db
    .prepare(`SELECT id FROM stock_batches WHERE id > ? ORDER BY id ASC LIMIT 1`)
    .get(before) as { id: number } | undefined;
  expect(batch).toBeDefined();
  return batch!.id;
}

beforeAll(async () => {
  authCookie = await getAuthCookie();
  expect(authCookie).not.toBe('');
  warehouseId = (
    db.prepare('SELECT id FROM warehouses WHERE is_active = 1 ORDER BY id LIMIT 1').get() as {
      id: number;
    }
  ).id;
  supplierId = await resolveSupplierByName('Expiry Guard Supplier', authCookie);
});

describe('ItemModel.batchExpiryDate — the single guard', () => {
  it('returns the date only when the item tracks expiry', async () => {
    const withExpiry = await createItem('GUARD-YES', true);
    const withoutExpiry = await createItem('GUARD-NO', false);

    expect(ItemModel.batchExpiryDate(db, withExpiry, '2027-01-31')).toBe('2027-01-31');
    expect(ItemModel.batchExpiryDate(db, withoutExpiry, '2027-01-31')).toBeNull();
  });

  it('treats an empty date and a missing item row as "no expiry"', async () => {
    const withExpiry = await createItem('GUARD-EMPTY', true);
    expect(ItemModel.batchExpiryDate(db, withExpiry, '')).toBeNull();
    expect(ItemModel.batchExpiryDate(db, withExpiry, undefined)).toBeNull();
    expect(ItemModel.batchExpiryDate(db, withExpiry, null)).toBeNull();
    expect(ItemModel.batchExpiryDate(db, 999_999, '2027-01-31')).toBeNull();
  });
});

describe('purchase batch expiry is gated on the item', () => {
  it('DROPS a supplied expiry_date when the item does not track expiry', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PURCHASE-NO', false);
    await purchase(itemId, '2027-05-31');
    expect(latestBatchExpiry(itemId)).toBeNull();
  });

  it('keeps a supplied expiry_date when the item DOES track expiry', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PURCHASE-YES', true);
    await purchase(itemId, '2027-05-31');
    expect(latestBatchExpiry(itemId)).toBe('2027-05-31');
  });

  it('leaves the date NULL when an expiry-tracking item is bought without one', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PURCHASE-NONE', true);
    await purchase(itemId);
    expect(latestBatchExpiry(itemId)).toBeNull();
  });
});

describe('goods receipt batch expiry is gated on the item', () => {
  it('DROPS a supplied expiry_date when the item does not track expiry', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PO-NO', false);
    const batchId = await goodsReceipt(itemId, '2027-05-31');
    const row = db.prepare(`SELECT expiry_date FROM stock_batches WHERE id = ?`).get(batchId) as {
      expiry_date: string | null;
    };
    expect(row.expiry_date).toBeNull();
  });

  it('keeps a supplied expiry_date when the item DOES track expiry', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PO-YES', true);
    const batchId = await goodsReceipt(itemId, '2027-05-31');
    const row = db.prepare(`SELECT expiry_date FROM stock_batches WHERE id = ?`).get(batchId) as {
      expiry_date: string | null;
    };
    expect(row.expiry_date).toBe('2027-05-31');
  });
});

describe('PATCH /stock-batches/:id is gated on the item', () => {
  it('refuses to stamp an expiry date on a non-expiry item batch', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PATCH-NO', false);
    await purchase(itemId);

    const batch = db
      .prepare(`SELECT id FROM stock_batches WHERE item_id = ? ORDER BY id DESC LIMIT 1`)
      .get(itemId) as { id: number };

    const res = await request(app)
      .patch(`/api/inventory/stock-batches/${batch.id}`)
      .set('Cookie', authCookie)
      .send({ expiry_date: '2027-05-31' });

    expect([200, 400]).toContain(res.status);
    const row = db.prepare(`SELECT expiry_date FROM stock_batches WHERE id = ?`).get(batch.id) as {
      expiry_date: string | null;
    };
    expect(row.expiry_date).toBeNull();
  });

  it('accepts an expiry date for an expiry-tracking item batch', async () => {
    const itemId = await createItem('EXPIRY-GUARD-PATCH-YES', true);
    await purchase(itemId);

    const batch = db
      .prepare(`SELECT id FROM stock_batches WHERE item_id = ? ORDER BY id DESC LIMIT 1`)
      .get(itemId) as { id: number };

    const res = await request(app)
      .patch(`/api/inventory/stock-batches/${batch.id}`)
      .set('Cookie', authCookie)
      .send({ expiry_date: '2099-05-31' });

    expect(res.status).toBe(200);
    const row = db.prepare(`SELECT expiry_date FROM stock_batches WHERE id = ?`).get(batch.id) as {
      expiry_date: string | null;
    };
    expect(row.expiry_date).toBe('2099-05-31');
  });
});

describe('joint production stamps expiry per output line', () => {
  it('gives the date only to the expiry-tracking co-product', async () => {
    // Raw material, stock it so the production can consume it.
    const rawId = await createItem('EXPIRY-GUARD-PROD-RAW', false);
    await purchase(rawId);

    // Output A tracks expiry; output B does not. Different UoM on purpose —
    // this is the D6 co-product case.
    const outputA = await createItem('EXPIRY-GUARD-OUT-A', true, {
      unit_of_measure: 'Litre',
      is_manufactured: true,
    });
    const outputB = await createItem('EXPIRY-GUARD-OUT-B', false, {
      unit_of_measure: 'kg',
      is_manufactured: true,
    });

    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        outputs: [
          { item_id: outputA, quantity: 4 },
          { item_id: outputB, quantity: 6 },
        ],
        warehouse_id: warehouseId,
        production_date: '2026-08-10',
        input_items: [{ item_id: rawId, quantity: 8 }],
        overhead_cost: 10,
        expiry_date: '2027-05-31',
      });
    expect(res.status).toBe(201);
    const productionId = res.body.data?.id ?? res.body.id;

    const batches = db
      .prepare(
        `SELECT b.item_id, b.expiry_date
         FROM stock_batches b
         WHERE b.source_type = 'PRODUCTION' AND b.source_id = ?`,
      )
      .all(productionId) as Array<{ item_id: number; expiry_date: string | null }>;

    expect(batches).toHaveLength(2);
    const a = batches.find((b) => b.item_id === outputA);
    const b = batches.find((b) => b.item_id === outputB);
    expect(a?.expiry_date).toBe('2027-05-31');
    expect(b?.expiry_date).toBeNull();

    // And the sweep must not move the non-expiry co-product's batch even
    // though it shares the production with an expiry-tracking sibling.
    const { runExpiryDetection } = await import('../boot/expiryDetection');
    runExpiryDetection(db);
    const swept = db
      .prepare(`SELECT warehouse_id FROM stock_batches WHERE source_type = 'PRODUCTION' AND source_id = ? AND item_id = ?`)
      .get(productionId, outputB) as { warehouse_id: number };
    expect(swept.warehouse_id).toBe(warehouseId);
  });
});