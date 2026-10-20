import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';

let cookie: string;
let customerId: number;
let itemId: number;
let outputId: number;
let warehouseId: number;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('Validation status customer', cookie);
  itemId = await createItem('Validation status input', cookie);
  outputId = await createItem('Validation status output', cookie);
  const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
  if (!warehouse) throw new Error('Missing fixture warehouse');
  warehouseId = warehouse.id;
  await purchaseStock(itemId, warehouseId, 10, 10, cookie, '2026-09-01');
});

function invoiceBody() {
  return {
    customer_id: customerId, invoice_date: '2026-09-05',
    items: [{ item_id: itemId, quantity: 1, unit_price: 20, warehouse_id: warehouseId }],
  };
}

function financialState() {
  return {
    invoices: db.prepare('SELECT * FROM invoices ORDER BY id').all(),
    lines: db.prepare('SELECT * FROM journal_lines ORDER BY id').all(),
    batches: db.prepare('SELECT * FROM stock_batches ORDER BY id').all(),
  };
}

describe('CODE-001: invalid client input returns actionable 4xx without writes', () => {
  it.each(['/api/invoices', '/api/mobile-invoices/submit'])('rejects an unknown item on %s with 404', async (path) => {
    const body = invoiceBody();
    const before = financialState();
    const response = await request(app).post(path).set('Cookie', cookie)
      .send({ ...body, items: [{ ...body.items[0], item_id: 999999 }] });
    expect(response.status).toBe(404);
    expect(JSON.stringify(response.body)).not.toMatch(/SQLITE_|FOREIGN KEY|stack|\.ts:\d/);
    expect(financialState()).toEqual(before);
  });

  it.each(['/api/invoices', '/api/mobile-invoices/submit'])('rejects an unknown customer on %s with 404', async (path) => {
    const before = financialState();
    const response = await request(app).post(path).set('Cookie', cookie)
      .send({ ...invoiceBody(), customer_id: 999999 });
    expect(response.status).toBe(404);
    expect(JSON.stringify(response.body)).not.toMatch(/SQLITE_|FOREIGN KEY|stack|\.ts:\d/);
    expect(financialState()).toEqual(before);
  });

  it.each([
    { quantity: -1 }, { unit_price: -1 }, { quantity: 'Infinity' }, { item_id: 'not-an-id' },
  ])('rejects an invalid mobile invoice line: %j', async (change) => {
    const body = invoiceBody();
    const before = financialState();
    const response = await request(app).post('/api/mobile-invoices/submit').set('Cookie', cookie)
      .send({ ...body, items: [{ ...body.items[0], ...change }] });
    expect(response.status).toBe(400);
    expect(financialState()).toEqual(before);
  });

  it.each([
    { overhead_cost: -10, input_quantity: 1 },
    { overhead_cost: 0, input_quantity: 1000 },
  ])('rejects invalid production input: %j', async ({ overhead_cost, input_quantity }) => {
    const before = financialState();
    const response = await request(app).post('/api/productions').set('Cookie', cookie).send({
      output_item_id: outputId, output_quantity: 1, warehouse_id: warehouseId,
      production_date: '2026-09-05', overhead_cost,
      input_items: [{ item_id: itemId, quantity: input_quantity }],
    });
    expect(response.status).toBe(400);
    expect(response.body.error).toMatch(/overhead|stock/i);
    expect(financialState()).toEqual(before);
  });
});
