/**
 * PUT /api/owner-equity/withdrawals/:id — the `items` branch.
 *
 * `withdrawalItemUpdate` decides what `items` means for the withdrawal kind:
 * a goods withdrawal validates every line and refuses client-supplied costing
 * fields, a cash withdrawal ignores `items` entirely. Nothing drove either
 * branch before, so its score came from zero coverage.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock } from './helpers/invoiceReturnSpec';

let cookie = '';
let csrf = { cookie: '', token: '' };
let warehouseId = 0;

const put = (url: string, body: Record<string, unknown>) =>
  request(app).put(url).set('Cookie', [cookie, csrf.cookie].filter(Boolean)).set('x-csrf-token', csrf.token).send(body);

const post = (url: string, body: Record<string, unknown>) =>
  request(app).post(url).set('Cookie', [cookie, csrf.cookie].filter(Boolean)).set('x-csrf-token', csrf.token).send(body);

const idOf = (res: request.Response): number => (res.body?.data?.id ?? res.body?.id) as number;

async function fetchCsrf(): Promise<void> {
  const res = await request(app).get('/api/customers').set('Cookie', cookie);
  const cookies = res.headers['set-cookie'];
  if (!cookies) return;
  const list = Array.isArray(cookies) ? cookies : [cookies];
  const csrfCookie = list.find((c) => c.startsWith('csrf-token='));
  csrf = { cookie: csrfCookie ? csrfCookie.split(';')[0] : '', token: csrfCookie ? csrfCookie.split(';')[0].split('=')[1] : '' };
}

beforeAll(async () => {
  cookie = await getAuthCookie();
  expect(cookie).not.toBe('');
  await fetchCsrf();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

  // A fresh suite database starts with no cash on hand, and the cash-funds
  // guard rejects withdrawals against a zero balance.
  const funded = await post('/api/owner-equity/capital', {
    capital_date: '2026-09-01',
    amount: 5000,
  });
  expect([200, 201]).toContain(funded.status);
});

describe('PUT /api/owner-equity/withdrawals/:id — item lines', () => {
  it('rejects client-supplied costing fields on a goods withdrawal', async () => {
    const itemId = await createItem('OWE-EDIT-COST', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const created = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: '2026-09-14',
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 2 }],
    });
    expect([200, 201]).toContain(created.status);
    const withdrawalId = idOf(created);

    const res = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, {
      withdrawal_date: '2026-09-14',
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 3, unit_cost: 99 }],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Client-supplied costing fields (unit_cost/batch_id/line_total) are not accepted');
  });

  it('rejects an empty item list on a goods withdrawal', async () => {
    const itemId = await createItem('OWE-EDIT-EMPTY', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const created = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: '2026-09-15',
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 1 }],
    });
    expect([200, 201]).toContain(created.status);

    const res = await put(`/api/owner-equity/withdrawals/${idOf(created)}`, {
      withdrawal_date: '2026-09-15',
      kind: 'goods',
      items: [],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('A goods withdrawal requires at least one item line');
  });

  it('accepts valid item lines and updates the goods withdrawal', async () => {
    const itemId = await createItem('OWE-EDIT-OK', cookie);
    await purchaseStock(itemId, warehouseId, 10, 5, cookie);

    const created = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: '2026-09-16',
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 2 }],
    });
    expect([200, 201]).toContain(created.status);
    const withdrawalId = idOf(created);

    const res = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, {
      withdrawal_date: '2026-09-16',
      kind: 'goods',
      items: [{ item_id: itemId, warehouse_id: warehouseId, quantity: 3 }],
    });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.id).toBe(withdrawalId);
  });

  it('ignores items on a cash withdrawal instead of validating them', async () => {
    const created = await post('/api/owner-equity/withdrawals', {
      withdrawal_date: '2026-09-17',
      kind: 'cash',
      amount: 50,
      payment_method: 'Cash',
    });
    expect([200, 201]).toContain(created.status);
    const withdrawalId = idOf(created);

    const res = await put(`/api/owner-equity/withdrawals/${withdrawalId}`, {
      withdrawal_date: '2026-09-17',
      kind: 'cash',
      items: [{ item_id: 1, warehouse_id: warehouseId, quantity: 0 }],
    });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
