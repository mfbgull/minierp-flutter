/**
 * Reversal-rules Phase 4 regression tests — status-machine validation on
 * status-changing endpoints that historically accepted arbitrary status
 * values (the PO updateStatus matrix already had this via C3).
 *
 * Covered:
 *   - SO update: Draft→Confirmed allowed; Draft→Invoiced rejected
 *     (bypasses conversion, breaks reversal expectations).
 *   - Quotation update: Draft→Sent allowed; Sent→Converted rejected
 *     (conversion is a guarded workflow, not a hand edit).
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('Status-machine validation (Phase 4)', () => {
  let authCookie: string;
  let customerId: number;
  let itemId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const customer = await request(app)
      .post('/api/customers')
      .set('Cookie', authCookie)
      .send({ customer_name: `SM Customer ${Date.now()}`, phone: '555-0420' });
    expect(customer.status).toBe(201);
    customerId = customer.body.data.id;

    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `SM-${Date.now()}`, item_name: 'Status Machine Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;
  });

  function soBody(status: string) {
    return {
      customer_id: customerId,
      so_date: '2026-08-10',
      delivery_date: '2026-08-15',
      status,
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 1, unit_price: 10, warehouse_id: warehouseId }],
    };
  }

  async function createSO(status: string): Promise<number> {
    const res = await request(app)
      .post('/api/sales-orders')
      .set('Cookie', authCookie)
      .send(soBody(status));
    expect(res.status).toBe(201);
    return res.body.id as number;
  }

  async function updateSO(id: number, status: string) {
    return request(app)
      .put(`/api/sales-orders/${id}`)
      .set('Cookie', authCookie)
      .send(soBody(status));
  }

  async function createQuotation(status: string): Promise<number> {
    const res = await request(app)
      .post('/api/quotations')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        quotation_date: '2026-08-10',
        expiry_date: '2026-08-30',
        status,
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 10, warehouse_id: warehouseId }],
      });
    expect(res.status).toBe(201);
    return res.body.data?.id ?? res.body.id;
  }

  async function updateQuotation(id: number, status: string) {
    return request(app)
      .put(`/api/quotations/${id}`)
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        quotation_date: '2026-08-10',
        expiry_date: '2026-08-30',
        status,
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 10, warehouse_id: warehouseId }],
      });
  }

  it('SO: allows Draft → Confirmed (valid forward transition)', async () => {
    const soId = await createSO('Draft');
    const res = await updateSO(soId, 'Confirmed');
    expect(res.status).toBe(200);
    const row = db.prepare('SELECT status FROM sales_orders WHERE id = ?').get(soId) as { status: string };
    expect(row.status).toBe('Confirmed');
  });

  it('SO: rejects Draft → Invoiced (bypasses conversion)', async () => {
    const soId = await createSO('Draft');
    const res = await updateSO(soId, 'Invoiced');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot transition sales order from Draft to Invoiced/i);
    const row = db.prepare('SELECT status FROM sales_orders WHERE id = ?').get(soId) as { status: string };
    expect(row.status).toBe('Draft');
  });

  it('SO: rejects Invoiced → Draft (terminal state stays terminal)', async () => {
    // Reach Invoiced legitimately: create Confirmed SO then convert via update path is
    // not possible (Confirmed → Delivered only), so seed the row directly to isolate
    // the machine guard from the conversion workflow.
    const soId = await createSO('Confirmed');
    db.prepare(`UPDATE sales_orders SET status = 'Invoiced' WHERE id = ?`).run(soId);
    const res = await updateSO(soId, 'Draft');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot update a Invoiced sales order|Cannot transition/i);
  });

  it('Quotation: allows Draft → Sent', async () => {
    const qId = await createQuotation('Draft');
    const res = await updateQuotation(qId, 'Sent');
    expect(res.status).toBe(200);
    const row = db.prepare('SELECT status FROM quotations WHERE id = ?').get(qId) as { status: string };
    expect(row.status).toBe('Sent');
  });

  it('Quotation: rejects Sent → Converted (conversion is a guarded workflow)', async () => {
    const qId = await createQuotation('Sent');
    const res = await updateQuotation(qId, 'Converted');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot transition quotation from Sent to Converted/i);
    const row = db.prepare('SELECT status FROM quotations WHERE id = ?').get(qId) as { status: string };
    expect(row.status).toBe('Sent');
  });
});
