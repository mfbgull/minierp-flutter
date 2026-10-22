/**
 * Stock-batch list and halt contracts.
 *
 * GET /api/inventory/stock-batches answers two shapes (bare array, or the
 * paged envelope when `page`/`limit` is sent) and applies its item / warehouse
 * / halted filters through one shared predicate; PATCH /:id/halt refuses to
 * halt an already-halted batch. None of these paths was driven by a test
 * before, so their CRAP scores were computed from zero coverage.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock } from './helpers/invoiceReturnSpec';

let cookie = '';
let warehouseId = 0;
let itemId = 0;

const get = (url: string) => request(app).get(url).set('Cookie', cookie);
const patch = (url: string, body: Record<string, unknown>) =>
  request(app).patch(url).set('Cookie', cookie).send(body);

beforeAll(async () => {
  cookie = await getAuthCookie();
  expect(cookie).not.toBe('');
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  itemId = await createItem('SBR-BATCH-ITEM', cookie);
  // A received purchase leaves a stock batch with quantity_remaining > 0,
  // which is what the list endpoint selects on.
  await purchaseStock(itemId, warehouseId, 10, 5, cookie);
});

describe('GET /api/inventory/stock-batches', () => {
  it('returns the bare array for legacy callers (no page/limit)', async () => {
    const res = await get('/api/inventory/stock-batches');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.some((b: { item_id: number }) => b.item_id === itemId)).toBe(true);
  });

  it('filters by item_id', async () => {
    const res = await get(`/api/inventory/stock-batches?item_id=${itemId}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
    expect(res.body.every((b: { item_id: number }) => b.item_id === itemId)).toBe(true);
  });

  it('filters by warehouse_id', async () => {
    const res = await get(`/api/inventory/stock-batches?warehouse_id=${warehouseId}`);
    expect(res.status).toBe(200);
    expect(res.body.every((b: { warehouse_id: number }) => b.warehouse_id === warehouseId)).toBe(true);
  });

  it('filters halted batches on halted=true', async () => {
    const res = await get('/api/inventory/stock-batches?halted=true');
    expect(res.status).toBe(200);
    expect(res.body.every((b: { halted: number }) => Number(b.halted) === 1)).toBe(true);
  });

  it('answers the paged envelope when page/limit is present', async () => {
    const res = await get('/api/inventory/stock-batches?page=1&limit=2');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.pagination).toMatchObject({ page: 1, limit: 2 });
    expect(typeof res.body.pagination.total).toBe('number');
    expect(res.body.data.length).toBeLessThanOrEqual(2);
  });
});

describe('PATCH /api/inventory/stock-batches/:id/halt', () => {
  it('halts a live batch and records the reason', async () => {
    const list = await get(`/api/inventory/stock-batches?item_id=${itemId}`);
    const batch = (list.body as Array<{ id: number; halted: number }>).find((b) => Number(b.halted) === 0);
    expect(batch).toBeDefined();

    const res = await patch(`/api/inventory/stock-batches/${batch!.id}/halt`, { reason: 'damaged in transit' });
    expect(res.status).toBe(200);
    expect(Number(res.body.halted)).toBe(1);
    expect(res.body.halted_reason).toBe('damaged in transit');
  });

  it('refuses to halt an already-halted batch', async () => {
    const halted = await get('/api/inventory/stock-batches?halted=true');
    const batch = (halted.body as Array<{ id: number }>)[0];
    expect(batch).toBeDefined();

    const res = await patch(`/api/inventory/stock-batches/${batch.id}/halt`, { reason: 'again' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Batch is already halted');
  });

  it('answers 404 for an unknown batch', async () => {
    const res = await patch('/api/inventory/stock-batches/99999999/halt', { reason: 'nope' });
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('Batch not found');
  });
});
