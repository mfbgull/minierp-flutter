import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

describe('Supplier advances are assets until explicitly applied', () => {
  let cookie: string;
  let supplierId: number;
  let billId: number;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const supplier = await post('/api/suppliers', { supplier_code: 'PREPAY-REG', supplier_name: 'Prepayment supplier' });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data.id;
    expect((await post('/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 500, payment_method: 'Cash' })).status).toBe(201);
    const bill = await post('/api/supplier-bills', { supplier_id: supplierId, bill_no: 'PREPAY-BILL', bill_date: '2026-09-03', net_amount: 100, input_tax_amount: 15, description: 'Services' });
    expect(bill.status).toBe(201);
    billId = bill.body.data.id;
  });

  it('pays cash once, applies without more cash, and restores availability on payment reversal', async () => {
    const body = { supplier_id: supplierId, prepay_date: '2026-09-02', amount: 200, payment_method: 'Cash' };
    const created = await request(app).post('/api/supplier-prepayments').set('Cookie', cookie).set('Idempotency-Key', 'prepay-create').send(body);
    expect(created.status).toBe(201);
    const prepayId = created.body.data.id;
    const retry = await request(app).post('/api/supplier-prepayments').set('Cookie', cookie).set('Idempotency-Key', 'prepay-create').send(body);
    expect(retry.body.data.id).toBe(prepayId);
    const feed = await request(app).get('/api/payments/unified').query({ fromDate: '2026-09-02', toDate: '2026-09-02' }).set('Cookie', cookie);
    expect(feed.status).toBe(200);
    expect(feed.body.data).toEqual([expect.objectContaining({ source: 'supplier_advance', source_id: prepayId, amount: 200, direction: 'out' })]);
    expectAllInvariantsHold('supplier advance paid', db);
    const cashBeforeApply = db.prepare(`SELECT SUM(jl.debit - jl.credit) AS amount FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id WHERE a.code = '1000' AND jl.voided = 0`).get();
    const allocation = { applied_at: '2026-09-04', allocations: [{ kind: 'supplier_bill', id: billId, amount: 115 }] };
    const applied = await request(app).post(`/api/supplier-prepayments/${prepayId}/apply`).set('Cookie', cookie).set('Idempotency-Key', 'prepay-apply').send(allocation);
    expect(applied.status).toBe(201);
    const replay = await request(app).post(`/api/supplier-prepayments/${prepayId}/apply`).set('Cookie', cookie).set('Idempotency-Key', 'prepay-apply').send(allocation);
    expect(replay.body.data.id).toBe(applied.body.data.id);
    const detail = await request(app).get(`/api/supplier-prepayments/${prepayId}`).set('Cookie', cookie);
    expect(detail.body.data.available_amount).toBe(85);
    expect(db.prepare(`SELECT SUM(jl.debit - jl.credit) AS amount FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id WHERE a.code = '1000' AND jl.voided = 0`).get()).toEqual(cashBeforeApply);
    expectAllInvariantsHold('supplier advance applied', db);
    const edited = await request(app).put(`/api/payments/${applied.body.data.id}`).set('Cookie', cookie).send({ payment_method: 'Cash' });
    expect(edited.status).toBe(409);
    expectAllInvariantsHold('advance application edit rejected', db);
    expect((await post(`/api/supplier-prepayments/${prepayId}/void`, { reason: 'Correction' })).status).toBe(409);
    expect((await request(app).delete(`/api/payments/${applied.body.data.id}`).set('Cookie', cookie)).status).toBe(200);
    const restored = await request(app).get(`/api/supplier-prepayments/${prepayId}`).set('Cookie', cookie);
    expect(restored.body.data.available_amount).toBe(200);
    expect((await post(`/api/supplier-prepayments/${prepayId}/void`, { reason: 'Correction' })).status).toBe(200);
    expectAllInvariantsHold('supplier advance and application reversed', db);
  });

  it('filters searchable targets by supplier and rejects invalid applications without financial writes', async () => {
    const advance = await post('/api/supplier-prepayments', { supplier_id: supplierId, prepay_date: '2026-09-02', amount: 50, payment_method: 'Cash' });
    expect(advance.status).toBe(201);
    const id = advance.body.data.id;
    const other = await post('/api/suppliers', { supplier_code: 'PREPAY-OTHER', supplier_name: 'Other supplier' });
    expect(other.status).toBe(201);
    const otherBill = await post('/api/supplier-bills', { supplier_id: other.body.data.id, bill_no: 'FOREIGN-BILL', bill_date: '2026-09-03', net_amount: 10, description: 'Other services' });
    expect(otherBill.status).toBe(201);
    const targets = await request(app).get(`/api/supplier-prepayments/${id}/targets`).set('Cookie', cookie).query({ search: 'PREPAY-BILL' });
    expect(targets.status).toBe(200);
    expect(targets.body.data).toEqual([expect.objectContaining({ kind: 'supplier_bill', id: billId, balance_amount: 115 })]);
    const foreignTargets = await request(app).get(`/api/supplier-prepayments/${id}/targets`).set('Cookie', cookie).query({ search: 'FOREIGN-BILL' });
    expect(foreignTargets.body.data).toEqual([]);
    for (const [date, target, amount] of [['2026-09-04', billId, 51], ['2026-09-01', billId, 10], ['2026-09-04', otherBill.body.data.id, 10]] as const) {
      const before = db.prepare('SELECT COUNT(*) AS count FROM payments').get();
      const result = await post(`/api/supplier-prepayments/${id}/apply`, {
        applied_at: date, allocations: [{ kind: 'supplier_bill', id: target, amount }],
      });
      expect(result.status).toBe(400);
      expect(db.prepare('SELECT COUNT(*) AS count FROM payments').get()).toEqual(before);
      expectAllInvariantsHold('invalid supplier advance application rejected', db);
    }
    const detail = await request(app).get(`/api/supplier-prepayments/${id}`).set('Cookie', cookie);
    expect(detail.body.data.available_amount).toBe(50);
  });
});
