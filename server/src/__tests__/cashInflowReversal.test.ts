import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import SupplierRefundModel from '../models/SupplierRefund';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { SupplierPaymentService } from '../services/SupplierPaymentService';

let cookie: string;

beforeAll(async () => { cookie = await getAuthCookie(); });
beforeEach(() => { db.exec('SAVEPOINT cash_inflow_case'); });
afterEach(() => { db.exec('ROLLBACK TO cash_inflow_case; RELEASE cash_inflow_case'); });

async function capital(amount: number, date: string, method = 'Cash'): Promise<number> {
  const response = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
    .send({ amount, capital_date: date, payment_method: method });
  expect(response.status).toBe(201);
  const data: { data: { id: number } } = response.body;
  return data.data.id;
}

async function spend(amount: number, date: string): Promise<void> {
  const response = await request(app).post('/api/owner-equity/withdrawals').set('Cookie', cookie)
    .send({ amount, withdrawal_date: date, payment_method: 'Cash', kind: 'cash' });
  expect(response.status).toBe(201);
}

function snapshot() {
  return {
    capital: db.prepare('SELECT * FROM owner_capital ORDER BY id').all(),
    lines: db.prepare('SELECT * FROM journal_lines ORDER BY id').all(),
  };
}

describe('cash inflow corrections preserve every later daily balance', () => {
  it('rejects a supplier-refund void through the mounted route without changing financial records', async () => {
    await capital(100, '2026-08-01');
    const itemId = await createItem('Refund void item', cookie);
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const purchase = await purchaseWithNamedSupplier('Refund void supplier', {
      item_id: itemId, warehouse_id: warehouse.id, quantity: 10, unit_cost: 10,
      purchase_date: '2026-08-02',
    }, cookie);
    expect(purchase.status).toBe(201);
    const purchaseId = purchase.body.data?.id ?? purchase.body.id;
    const supplier = db.prepare<[number], { supplier_id: number }>('SELECT supplier_id FROM purchases WHERE id = ?').get(purchaseId);
    if (!supplier) throw new Error('Missing fixture supplier');
    new SupplierPaymentService(db).recordSupplierPayment({
      supplierId: supplier.supplier_id, paymentDate: '2026-08-02', amount: 100, paymentMethod: 'Cash',
      allocations: [{ kind: 'purchase', id: purchaseId, amount: 100 }],
    });
    const returned = await request(app).post('/api/purchase-returns').set('Cookie', cookie).send({
      return_date: '2026-09-01', source_type: 'PURCHASE', source_id: purchaseId,
      warehouse_id: warehouse.id, disposition: 'credit_on_account',
      items: [{ source_item_id: purchaseId, quantity: 10 }],
    });
    expect(returned.status).toBe(201);
    const note = db.prepare<[number], { id: number }>('SELECT id FROM credit_notes WHERE source_id = ?')
      .get(returned.body.data?.id ?? returned.body.id);
    if (!note) throw new Error('Missing fixture credit note');
    const refund = SupplierRefundModel.create({
      credit_note_id: note.id, refund_date: '2026-09-01', amount: 100,
    }, 1, db);
    await spend(100, '2026-09-02');
    expectAllInvariantsHold('before rejected supplier refund void');
    const before = db.prepare('SELECT * FROM journal_lines ORDER BY id').all();

    const response = await request(app).post(`/api/supplier-refunds/${refund.id}/void`)
      .set('Cookie', cookie).send({ reason: 'Correction' });

    expect(response.status).toBe(400);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(SupplierRefundModel.getById(refund.id, db)?.status).toBe('POSTED');
    expect(db.prepare('SELECT * FROM journal_lines ORDER BY id').all()).toEqual(before);
    expectAllInvariantsHold('after rejected supplier refund void');
  });

  it('rejects a void even when a later deposit has restored the current balance', async () => {
    const id = await capital(1000, '2026-09-01');
    await spend(900, '2026-09-02');
    await capital(1000, '2026-09-03');
    const before = snapshot();

    const response = await request(app).delete(`/api/owner-equity/capital/${id}`)
      .set('Cookie', cookie).send({ reason: 'Correction' });

    expect(response.status).toBe(400);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-02');
    expect(snapshot()).toEqual(before);
  });

  it.each([
    { amount: 100 },
    { capital_date: '2026-09-03' },
    { payment_method: 'Bank' },
  ])('rejects an edit that removes funds needed by later spending: %j', async (change) => {
    const id = await capital(1000, '2026-09-01');
    await spend(900, '2026-09-02');
    await capital(1000, '2026-09-03');
    const before = snapshot();

    const response = await request(app).put(`/api/owner-equity/capital/${id}`)
      .set('Cookie', cookie).send({ amount: 1000, capital_date: '2026-09-01', payment_method: 'Cash', ...change });

    expect(response.status).toBe(400);
    expect(snapshot()).toEqual(before);
  });

  it('allows a reduction to exactly the amount already spent', async () => {
    const id = await capital(1000, '2026-09-01');
    await spend(900, '2026-09-02');

    const response = await request(app).put(`/api/owner-equity/capital/${id}`)
      .set('Cookie', cookie).send({ amount: 900, capital_date: '2026-09-01', payment_method: 'Cash' });

    expect(response.status).toBe(200);
  });

  it('allows voiding an inflow when earlier funds cover every later expense', async () => {
    await capital(1000, '2026-08-31');
    const id = await capital(1000, '2026-09-01');
    await spend(900, '2026-09-02');

    const response = await request(app).delete(`/api/owner-equity/capital/${id}`)
      .set('Cookie', cookie).send({ reason: 'Correction' });

    expect(response.status).toBe(200);
  });
});
