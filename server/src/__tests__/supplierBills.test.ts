import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { generateToken } from '../middleware/auth';

describe('Supplier bills, input tax and settlement', () => {
  let cookie: string;
  let supplierId: number;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const supplier = await post('/api/suppliers', { supplier_code: 'BILL-REGRESSION', supplier_name: 'Bill regression supplier', phone: '03001234567' });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.id ?? supplier.body.data?.id;
    expect(supplierId).toBeGreaterThan(0);
    expect((await post('/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 500, payment_method: 'Cash' })).status).toBe(201);
  });

  it('recognizes net expense and recoverable tax, pays once, and reverses cleanly', async () => {
    const body = { supplier_id: supplierId, bill_no: 'VENDOR-INV-1', bill_date: '2026-09-03', due_date: '2026-09-20', net_amount: 100, input_tax_amount: 15, description: 'Supplier service bill' };
    const created = await request(app).post('/api/supplier-bills').set('Cookie', cookie).set('Idempotency-Key', 'supplier-bill-create').send(body);
    expect(created.status).toBe(201);
    const billId = created.body.data.id;
    const retry = await request(app).post('/api/supplier-bills').set('Cookie', cookie).set('Idempotency-Key', 'supplier-bill-create').send(body);
    expect(retry.status).toBe(201);
    expect(retry.body.data.id).toBe(billId);
    expect(created.body.data.total_amount).toBe(115);
    const tax = db.prepare(`SELECT SUM(jl.debit - jl.credit) AS amount FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id WHERE a.code = '1320' AND jl.voided = 0`).get();
    expect(tax).toEqual({ amount: 15 });
    expectAllInvariantsHold('supplier bill posted', db);
    const paymentBody = { amount: 50, payment_date: '2026-09-04', payment_method: 'Cash' };
    const payment = await request(app).post(`/api/supplier-bills/${billId}/payments`).set('Cookie', cookie).set('Idempotency-Key', 'supplier-bill-pay').send(paymentBody);
    expect(payment.status).toBe(201);
    expect((await request(app).post(`/api/supplier-bills/${billId}/payments`).set('Cookie', cookie).set('Idempotency-Key', 'supplier-bill-pay').send(paymentBody)).status).toBe(201);
    const detail = await request(app).get(`/api/supplier-bills/${billId}`).set('Cookie', cookie);
    expect(detail.body.data.balance_amount).toBe(65);
    const backdated = await request(app).put(`/api/payments/${payment.body.data.id}`).set('Cookie', cookie).send({ payment_date: '2026-09-02' });
    expect(backdated.status).toBe(400);
    expectAllInvariantsHold('supplier bill partially paid', db);
    expect((await post(`/api/supplier-bills/${billId}/void`, { reason: 'Correction' })).status).toBe(409);
    const reversed = await request(app).delete(`/api/payments/${payment.body.data.id}`).set('Cookie', cookie);
    expect([200, 204]).toContain(reversed.status);
    expect((await post(`/api/supplier-bills/${billId}/void`, { reason: 'Correction' })).status).toBe(200);
    expectAllInvariantsHold('supplier bill and payment reversed', db);
  });

  it('rejects duplicate target allocations before they can overpay a purchase', async () => {
    const itemId = await createItem('Duplicate allocation regression', cookie);
    const warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const purchase = await post('/api/purchases', { item_id: itemId, warehouse_id: warehouseId, supplier_id: supplierId, quantity: 1, unit_cost: 100, purchase_date: '2026-09-06' });
    expect(purchase.status).toBe(201);
    const purchaseId = purchase.body.id ?? purchase.body.data?.id;
    const payment = await post('/api/payments', { supplier_id: supplierId, amount: 120, payment_date: '2026-09-07', payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: purchaseId, amount: 60 }, { purchase_id: purchaseId, amount: 60 }] });
    expect(payment.status).toBe(400);
    expectAllInvariantsHold('duplicate supplier allocations rejected', db);
  });

  it('includes non-stock bills in expenses and recoverable tax reports without treating tax as expense', async () => {
    const bill = await post('/api/supplier-bills', { supplier_id: supplierId, bill_no: 'REPORT-INV',
      bill_date: '2026-09-12', net_amount: 100, input_tax_amount: 15, description: 'Reportable services' });
    expect(bill.status).toBe(201);
    const tax = await request(app).get('/api/reports/tax-summary').set('Cookie', cookie)
      .query({ startDate: '2026-09-12', endDate: '2026-09-12' });
    expect(tax.status).toBe(200);
    expect(tax.body.data).toMatchObject({ total_tax: 0, input_tax: 15, net_tax: -15 });
    const pnl = await request(app).get('/api/reports/profit-loss').set('Cookie', cookie)
      .query({ fromDate: '2026-09-12', toDate: '2026-09-12' });
    expect(pnl.status).toBe(200);
    expect(pnl.body.data.totalExpenses).toBe(100);
    expect(pnl.body.data.expenses).toContainEqual({ expense_category: 'Supplier bills', total: 100 });
    for (const [metric, value] of [['expenses', 100], ['net_profit', -100]]) {
      const kpi = await request(app).get('/api/dashboard/kpi').set('Cookie', cookie)
        .query({ metric, fromDate: '2026-09-12', toDate: '2026-09-12' });
      expect(kpi.status).toBe(200);
      expect(kpi.body.data.value).toBe(value);
    }
    expect((await post(`/api/supplier-bills/${bill.body.data.id}/void`, { reason: 'Report reversal' })).status).toBe(200);
    const reversed = await request(app).get('/api/reports/tax-summary').set('Cookie', cookie)
      .query({ startDate: '2026-09-12', endDate: '2026-09-12' });
    expect(reversed.body.data.input_tax).toBe(0);
  });

  it('allows a corrected bill number after void while preserving the original retry result', async () => {
    const body = { supplier_id: supplierId, bill_no: 'REISSUE-INV', bill_date: '2026-09-13', net_amount: 20, description: 'Original' };
    const original = await post('/api/supplier-bills', body).set('Idempotency-Key', 'bill-reissue-original');
    expect(original.status).toBe(201);
    expect((await post(`/api/supplier-bills/${original.body.data.id}/void`, { reason: 'Incorrect amount' })).status).toBe(200);
    const corrected = await post('/api/supplier-bills', { ...body, net_amount: 25 }).set('Idempotency-Key', 'bill-reissue-corrected');
    expect(corrected.status).toBe(201);
    expect(corrected.body.data.id).not.toBe(original.body.data.id);
    const replay = await post('/api/supplier-bills', body).set('Idempotency-Key', 'bill-reissue-original');
    expect(replay.status).toBe(201);
    expect(replay.body.data.id).toBe(original.body.data.id);
    expect(replay.body.data.voided_at).toBeTruthy();
    expectAllInvariantsHold('supplier bill corrected without overwriting history', db);
  });

  for (const approved of [false, true]) {
    it(`requires expense approval when a purchaser records a non-stock bill (approval=${approved})`, async () => {
      const name = `bill_purchaser_${approved ? 'approved' : 'limited'}`;
      const role = db.prepare('INSERT INTO roles (role_name, is_active) VALUES (?, 1)').run(name);
      const user = db.prepare(`INSERT INTO users (username, email, full_name, password_hash, role, role_id, is_active)
        VALUES (?, ?, ?, 'unused', 'user', ?, 1)`).run(name, `${name}@example.test`, name, role.lastInsertRowid);
      for (const permission of approved ? ['purchases:create', 'expenses:approve'] : ['purchases:create']) {
        expect(db.prepare('INSERT INTO role_permissions (role_id, permission_id) SELECT ?, id FROM permissions WHERE permission_name = ?').run(role.lastInsertRowid, permission).changes).toBe(1);
      }
      const token = generateToken({ id: Number(user.lastInsertRowid), username: name, role: 'user' });
      const before = db.prepare('SELECT COUNT(*) AS count FROM supplier_bills').get();
      const response = await request(app).post('/api/supplier-bills').auth(token, { type: 'bearer' }).send({
        supplier_id: supplierId, bill_no: name, bill_date: '2026-09-08', net_amount: 10, description: 'Approval boundary',
      });
      expect(response.status).toBe(approved ? 201 : 403);
      if (!approved) expect(db.prepare('SELECT COUNT(*) AS count FROM supplier_bills').get()).toEqual(before);
      expectAllInvariantsHold('supplier bill approval boundary', db);
    });
  }
});
