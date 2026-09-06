// Integration tests for customer/item soft-delete and restore
// (SHORTCOMINGS-FIX 4.2)

import request from 'supertest';
import app from '../app';

let authToken: string;

beforeAll(async () => {
  // Login as admin to get auth token
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
  authToken = res.body.data.token;
});

describe('Customer soft-delete and restore', () => {
  let customerId: number;

  it('creates a customer', async () => {
    const res = await request(app)
      .post('/api/customers')
      .set('Authorization', `Bearer ${authToken}`)
      .send({ customer_name: 'Test Customer SD', phone: '555-0100' });
    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    customerId = res.body.data.id;
  });

  it('soft-deletes the customer', async () => {
    const res = await request(app)
      .delete(`/api/customers/${customerId}`)
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it('deleted customer is hidden from list', async () => {
    const res = await request(app)
      .get('/api/customers?search=Test+Customer+SD')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    const names = res.body.data.map((c: any) => c.customer_name);
    expect(names).not.toContain('Test Customer SD');
  });

  it('restores the customer', async () => {
    const res = await request(app)
      .post(`/api/customers/${customerId}/restore`)
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it('restored customer appears in list again', async () => {
    const res = await request(app)
      .get('/api/customers?search=Test+Customer+SD')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    const names = res.body.data.map((c: any) => c.customer_name);
    expect(names).toContain('Test Customer SD');
  });
});

describe('Item soft-delete and restore', () => {
  let itemId: number;

  it('creates an item', async () => {
    const res = await request(app)
      .post('/api/inventory/items')
      .set('Authorization', `Bearer ${authToken}`)
      .send({
        item_code: 'SD-TEST-001',
        item_name: 'Soft Delete Test Item',
        selling_price: 50,
      });
    expect(res.status).toBe(201);
    // Item create returns the raw item (no `success` wrapper) — same
    // contract the api.integration tests pin.
    itemId = res.body.id;
  });

  it('soft-deletes the item', async () => {
    const res = await request(app)
      .delete(`/api/inventory/items/${itemId}`)
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it('restores the item', async () => {
    const res = await request(app)
      .post(`/api/inventory/items/${itemId}/restore`)
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
