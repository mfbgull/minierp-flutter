import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { getAuthCookie, createItem, purchaseWithNamedSupplier, resolveSupplierByName } from './helpers/invoiceReturnSpec';

let cookie = '';
let warehouseId = 0;
let seq = 0;
const get = (url: string) => request(app).get(url).set('Cookie', cookie);
const post = (url: string, body: Record<string, unknown>) => request(app).post(url).set('Cookie', cookie).send(body);

beforeAll(async () => {
  cookie = await getAuthCookie();
  const warehouses = await get('/api/inventory/warehouses');
  expect(warehouses.status).toBe(200);
  warehouseId = warehouses.body.data[0].id;
});

async function buy(itemId: number, name: string, quantity = 5): Promise<void> {
  const res = await purchaseWithNamedSupplier(name, {
    item_id: itemId, warehouse_id: warehouseId, quantity, unit_cost: 10,
    purchase_date: new Date().toISOString().slice(0, 10),
  }, cookie);
  expect(res.status).toBe(201);
}

async function warehouse(): Promise<number> {
  seq += 1;
  const res = await post('/api/inventory/warehouses', {
    warehouse_code: `BRAND-WH-${seq}`, warehouse_name: `Brand warehouse ${seq}`,
  });
  expect(res.status).toBe(201);
  return res.body.id;
}

describe('item manufacturer and batch suppliers', () => {
  it('persists, searches, updates, preserves omitted and explicitly clears a manufacturer', async () => {
    const payload = { item_code: 'BRAND-1', item_name: 'Milk', unit_of_measure: 'Ltr', manufacturer_name: '  Nestle  ' };
    const created = await post('/api/inventory/items', payload);
    expect(created.status).toBe(201);
    expect(created.body.manufacturer_name).toBe('Nestle');
    const id = created.body.id;
    const list = await get('/api/inventory/items?search=Nestle');
    expect(list.body.data.map((item: { id: number }) => item.id)).toContain(id);
    const update = (body: Record<string, unknown>) => request(app).put(`/api/inventory/items/${id}`).set('Cookie', cookie).send(body);
    expect((await update({ ...payload, manufacturer_name: 'Acme' })).body.manufacturer_name).toBe('Acme');
    const { manufacturer_name: omitted, ...withoutManufacturer } = payload;
    expect(omitted).toBeDefined();
    expect((await update(withoutManufacturer)).body.manufacturer_name).toBe('Acme');
    expect((await update({ ...payload, manufacturer_name: '' })).body.manufacturer_name).toBeNull();
  });

  it('rejects invalid manufacturer data on create and update', async () => {
    const id = await createItem('Validation fixture', cookie);
    for (const value of [123, {}, 'x'.repeat(201)]) {
      expect((await post('/api/inventory/items', { item_code: `BAD-${seq++}`, item_name: 'Bad', manufacturer_name: value })).status).toBe(400);
      expect((await request(app).put(`/api/inventory/items/${id}`).set('Cookie', cookie).send({ item_name: 'Bad', manufacturer_name: value })).status).toBe(400);
    }
  });

  it('identifies two suppliers for the same item, in both list shapes', async () => {
    const id = await createItem('Two supplier item', cookie);
    await buy(id, 'ABC Traders');
    await buy(id, 'XYZ Distributors');
    const list = await get(`/api/inventory/stock-batches?item_id=${id}`);
    expect(list.status).toBe(200);
    expect(list.body.map((batch: { suppliers: { supplier_name: string }[] }) => batch.suppliers[0].supplier_name).sort()).toEqual(['ABC Traders', 'XYZ Distributors']);
    const page = await get(`/api/inventory/stock-batches?item_id=${id}&page=1&limit=1`);
    expect(page.body.data[0].suppliers).toEqual(list.body[0].suppliers);
    expect(page.body.pagination.total).toBe(2);
  });

  it('resolves a purchase-order receipt supplier through its receipt line', async () => {
    const id = await createItem('Receipt supplier item', cookie);
    const otherId = await createItem('First receipt line', cookie);
    const supplierId = await resolveSupplierByName('Receipt Supplier', cookie);
    const date = new Date().toISOString().slice(0, 10);
    const po = await post('/api/purchase-orders', { supplier_id: supplierId, warehouse_id: warehouseId,
      po_date: date, items: [
        { item_id: otherId, quantity: 2, unit_price: 10 },
        { item_id: id, quantity: 2, unit_price: 10 },
      ] });
    expect(po.status).toBe(201);
    const detail = await get(`/api/purchase-orders/${po.body.id}`);
    expect((await post(`/api/purchase-orders/${po.body.id}/status`, { status: 'Submitted' })).status).toBe(200);
    const received = await post(`/api/purchase-orders/${po.body.id}/receipts`, {
      receipt_date: date, warehouse_id: warehouseId,
      items: detail.body.items.map((line: { id: number }) => ({ po_item_id: line.id, received_quantity: 2 })),
    });
    expect(received.status).toBe(201);
    const batches = await get(`/api/inventory/stock-batches?item_id=${id}`);
    expect(batches.body[0].suppliers).toEqual([{ supplier_id: supplierId, supplier_name: 'Receipt Supplier' }]);
  });

  it('rolls back a transfer if its provenance cannot be recorded', async () => {
    const id = await createItem('Atomic provenance item', cookie);
    await buy(id, 'ABC Traders');
    const destination = await warehouse();
    db.exec(`CREATE TRIGGER reject_batch_provenance BEFORE INSERT ON stock_batch_sources
      BEGIN SELECT RAISE(ABORT, 'test provenance failure'); END;`);
    try {
      const transfer = await post('/api/inventory/stock-transfers', {
        item_id: id, from_warehouse_id: warehouseId, to_warehouse_id: destination, quantity: 5,
      });
      expect(transfer.status).toBeGreaterThanOrEqual(400);
      const batches = await get(`/api/inventory/stock-batches?item_id=${id}`);
      expect(batches.body).toHaveLength(1);
      expect(batches.body[0].warehouse_id).toBe(warehouseId);
      expect(batches.body[0].quantity_remaining).toBe(5);
      expect(db.prepare('SELECT COUNT(*) AS n FROM stock_movements WHERE item_id = ? AND movement_type = ?').get(id, 'TRANSFER')).toEqual({ n: 0 });
    } finally {
      db.exec('DROP TRIGGER reject_batch_provenance');
    }
  });

  it('retains all suppliers across a mixed transfer and a second transfer', async () => {
    const id = await createItem('Mixed supplier transfer', cookie);
    await buy(id, 'ABC Traders', 3);
    await buy(id, 'XYZ Distributors', 7);
    const second = await warehouse();
    const third = await warehouse();
    for (const [from, to] of [[warehouseId, second], [second, third]]) {
      const res = await post('/api/inventory/stock-transfers', { item_id: id, from_warehouse_id: from, to_warehouse_id: to, quantity: 10 });
      expect(res.status).toBe(201);
    }
    const batches = await get(`/api/inventory/stock-batches?item_id=${id}&warehouse_id=${third}`);
    expect(batches.status).toBe(200);
    expect(batches.body).toHaveLength(1);
    expect(batches.body[0].suppliers.map((s: { supplier_name: string }) => s.supplier_name).sort()).toEqual(['ABC Traders', 'XYZ Distributors']);
    expect(batches.body[0].quantity_remaining).toBe(10);
    expect(batches.body[0].unit_cost).toBe(10);
    expectAllInvariantsHold('mixed supplier batch transferred twice', db);
  });

  it('leaves an untraceable historical batch unknown rather than guessing a supplier', async () => {
    const id = await createItem('Untraceable item', cookie);
    await buy(id, 'ABC Traders');
    const destination = await warehouse();
    expect((await post('/api/inventory/stock-transfers', {
      item_id: id, from_warehouse_id: warehouseId, to_warehouse_id: destination, quantity: 5,
    })).status).toBe(201);
    // Simulate a historical general transfer: its movement names only a
    // primary batch and cannot prove whether it consumed other suppliers.
    db.prepare('DELETE FROM stock_batch_sources WHERE batch_id IN (SELECT id FROM stock_batches WHERE item_id = ?)').run(id);
    const res = await get(`/api/inventory/stock-batches?item_id=${id}`);
    expect(res.status).toBe(200);
    expect(res.body[0].suppliers).toEqual([{ supplier_id: null, supplier_name: null }]);
  });

  it('keeps an unknown contribution visible alongside a known supplier', async () => {
    const item = await post('/api/inventory/items', {
      item_code: 'BRAND-PARTIAL', item_name: 'Partially traced stock', current_stock: 5,
      warehouse_id: warehouseId, standard_cost: 10,
    });
    expect(item.status).toBe(201);
    await buy(item.body.id, 'ABC Traders');
    const destination = await warehouse();
    expect((await post('/api/inventory/stock-transfers', {
      item_id: item.body.id, from_warehouse_id: warehouseId, to_warehouse_id: destination, quantity: 10,
    })).status).toBe(201);
    const res = await get(`/api/inventory/stock-batches?item_id=${item.body.id}`);
    expect(res.body[0].suppliers).toEqual(expect.arrayContaining([
      { supplier_id: null, supplier_name: null },
      expect.objectContaining({ supplier_name: 'ABC Traders' }),
    ]));
  });
});
