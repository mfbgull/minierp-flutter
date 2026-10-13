import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';

const balance = (code: string): number => {
  const row = db.prepare<[string], { balance: number }>(`
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0
  `).get(code);
  return Math.round((row?.balance ?? 0) * 100) / 100;
};

describe('PROD-001 / PROD-005: unpaid production overhead', () => {
  it('reverses the overhead payable when an intact production is deleted without moving cash', async () => {
    const cookie = await getAuthCookie();
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const raw = await createItem('PROD-overhead-void raw', cookie);
    const finished = await createItem('PROD-overhead-void finished', cookie);
    await purchaseStock(raw, warehouse.id, 10, 10, cookie);
    const payableBefore = balance('2200');
    const cashBefore = balance('1000');
    const bankBefore = balance('1010');

    const created = await request(app).post('/api/productions').set('Cookie', cookie).send({
      output_item_id: finished,
      output_quantity: 10,
      input_items: [{ item_id: raw, quantity: 10 }],
      overhead_cost: 50,
      warehouse_id: warehouse.id,
      production_date: '2026-09-10',
    });
    expect(created.status).toBe(201);
    expect(balance('2200') - payableBefore).toBe(-50);

    const productionId = Number(created.body.data?.id ?? created.body.id);
    const removed = await request(app).delete(`/api/productions/${productionId}`).set('Cookie', cookie).send({});
    expect(removed.status).toBe(200);
    expect(balance('2200')).toBe(payableBefore);
    expect(balance('1000')).toBe(cashBefore);
    expect(balance('1010')).toBe(bankBefore);
  });
});
