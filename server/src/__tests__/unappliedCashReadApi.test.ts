import { beforeAll, beforeEach, test, expect } from '@jest/globals';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createCustomer } from './helpers/invoiceReturnSpec';

let cookie: string;
let noPermissionToken: string;
let customerId: number;
let sequence = 0;
beforeAll(async () => {
  cookie = await getAuthCookie();
  // A real active user whose assigned role holds no permissions: authority is
  // resolved from the database, so this token authenticates but is forbidden.
  const role = db.prepare('INSERT INTO roles (role_name, is_active) VALUES (?, 1)').run('Cash read no permissions');
  const user = db.prepare(`INSERT INTO users (username, email, full_name, password_hash, role, role_id, is_active)
    VALUES ('cash-read-none', 'cash-read-none@example.test', 'No permissions', 'unused', 'user', ?, 1)`).run(role.lastInsertRowid);
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test JWT secret');
  noPermissionToken = jwt.sign({ id: Number(user.lastInsertRowid), username: 'cash-read-none', role: 'user' }, secret,
    { issuer: 'mini-erp', audience: 'mini-erp-client', expiresIn: '1h' });
});
beforeEach(async () => { customerId = await createCustomer(`Cash reads ${++sequence}`, cookie); });

function get(path: string) { return request(app).get(path).set('Cookie', cookie); }
function receive(owner: number, amount: number, date: string) {
  return request(app).post(`/api/customers/${owner}/unapplied-cash`).set('Cookie', cookie)
    .set('Idempotency-Key', `read-fixture-${++sequence}`).send({ amount, operation_date: date });
}

test('summaries are independent of receipt pagination and obey operation date and customer ownership', async () => {
  const first = await receive(customerId, 100, '2026-10-01');
  const future = await receive(customerId, 200, '2026-10-10');
  expect(first.status).toBe(201);
  expect(future.status).toBe(201);
  const other = await createCustomer(`Other cash reads ${++sequence}`, cookie);
  expect((await receive(other, 900, '2026-10-01')).status).toBe(201);
  db.prepare(`INSERT INTO customer_credit_sources (customer_id,kind,credited_amount,credited_at)
    VALUES (?,'RETURN_CREDIT',700,'2026-10-01')`).run(customerId);
  const changes = db.prepare<[], { total: number }>('SELECT total_changes() total').get()?.total;
  const result = await get(`/api/customers/${customerId}/unapplied-cash?operation_date=2026-10-02&page=2&limit=1`);
  expect(result.status).toBe(200);
  expect(result.body.data).toMatchObject({ operation_date: '2026-10-02', remaining_amount: 300, available_amount: 100, refundable_amount: 100 });
  expect(result.body.data.receipts).toEqual([expect.objectContaining({ payment_id: first.body.data.paymentId, can_reverse: true })]);
  expect(result.body.pagination).toMatchObject({ currentPage: 2, totalPages: 2, totalItems: 2, limit: 1 });
  expect(db.prepare('SELECT total_changes() total').get()).toEqual({ total: changes });
});

test('voided receipts remain visible but cannot contribute capacity or reverse again', async () => {
  const received = await receive(customerId, 80, '2026-10-01');
  expect(received.status).toBe(201);
  const reversed = await request(app).post(`/api/payments/${received.body.data.paymentId}/reverse`).set('Cookie', cookie)
    .set('Idempotency-Key', `reverse-read-${++sequence}`).send({ reason: 'Fixture' });
  expect(reversed.status).toBe(200);
  const result = await get(`/api/customers/${customerId}/unapplied-cash?operation_date=2026-10-02`);
  expect(result.status).toBe(200);
  expect(result.body.data).toMatchObject({ remaining_amount: 0, available_amount: 0, refundable_amount: 0,
    receipts: [expect.objectContaining({ payment_id: received.body.data.paymentId, voided_at: expect.any(String), can_reverse: false })] });
});

test('activity is paginated and date-filtered while capacity stays independent', async () => {
  expect((await receive(customerId, 100, '2026-10-01')).status).toBe(201);
  for (const date of ['2026-10-02', '2026-10-03']) {
    expect((await request(app).post('/api/unapplied-cash/refund').set('Cookie', cookie)
      .set('Idempotency-Key', `activity-${++sequence}`).send({ customer_id: customerId, amount: 10, operation_date: date })).status).toBe(200);
  }
  const result = await get(`/api/customers/${customerId}/unapplied-cash/activity?fromDate=2026-10-03&toDate=2026-10-03&limit=1`);
  expect(result.status).toBe(200);
  expect(result.body.pagination.totalItems).toBe(1);
  expect(result.body.data).toEqual([expect.objectContaining({ operation: 'REFUND', operation_date: '2026-10-03', total_amount: 10,
    lines: [expect.objectContaining({ amount: 10, kind: 'REFUND' })] })]);
  expect((await get(`/api/customers/${customerId}/unapplied-cash?operation_date=2026-10-03`)).body.data.remaining_amount).toBe(80);
});

test.each([
  '?page=0', '?limit=0', '?limit=101', '?page=9007199254740992', '?operation_date=2026-02-30',
  '/activity?fromDate=2026-10-03&toDate=2026-10-01', '/activity?fromDate=2026-02-30',
])('rejects malformed cash read queries %s', async suffix => {
  expect((await get(`/api/customers/${customerId}/unapplied-cash${suffix}`)).status).toBe(400);
});

test('empty and missing customers are distinct; cash reads and capability require authentication', async () => {
  const empty = await get(`/api/customers/${customerId}/unapplied-cash`);
  expect(empty.status).toBe(200);
  expect(empty.body.data).toMatchObject({ remaining_amount: 0, receipts: [] });
  for (const suffix of ['', '/activity']) {
    expect((await get(`/api/customers/99999999/unapplied-cash${suffix}`)).status).toBe(404);
    expect((await request(app).get(`/api/customers/${customerId}/unapplied-cash${suffix}`)).status).toBe(401);
  }
  expect((await request(app).get('/api/unapplied-cash/capabilities')).status).toBe(401);
  const capability = await get('/api/unapplied-cash/capabilities');
  expect(capability.status).toBe(200);
  expect(capability.body.data).toEqual({ receive: 'durable-v1', apply: 'permanent-application-v1', refund: 'permanent-application-v1', reverse: 'guarded-status-v1' });
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test secret');
  const missingToken = jwt.sign({ id: 99999999, username: 'missing', role: 'user' }, secret, { issuer: 'mini-erp', audience: 'mini-erp-client' });
  expect((await request(app).get(`/api/customers/${customerId}/unapplied-cash`).set('Authorization', `Bearer ${missingToken}`)).status).toBe(401);
  expect((await request(app).get(`/api/customers/${customerId}/unapplied-cash`).set('Authorization', `Bearer ${noPermissionToken}`)).status).toBe(403);
});
