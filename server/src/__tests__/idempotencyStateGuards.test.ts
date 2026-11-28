/**
 * Issue #36 - an unkeyed mutating route must rely on a state guard that makes
 * a retry harmless.
 *
 * `POST /api/inventory/physical-counts/:id/cancel` takes no Idempotency-Key.
 * `PhysicalCountModel.cancelCount` refuses a Completed count. A second cancel
 * of a Cancelled count sets the same value again, so it must return 200,
 * leave the status at Cancelled, and post no stock movement or balance.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

let cookie = '';
let warehouseId = 0;

function countOf(sql: string, ...params: unknown[]): number {
  return Number((db.prepare(sql).get(...(params as [])) as { n: number }).n);
}

describe('Issue #36: physical-count cancel is retry-safe without a key', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', cookie)
      .send({
        warehouse_code: `PC-GUARD-${Date.now()}`,
        warehouse_name: 'Physical Count Guard WH',
      });
    expect(wh.status).toBe(201);
    warehouseId = ((wh.body as { data?: { id: number }; id?: number }).data?.id
      ?? (wh.body as { id?: number }).id) as number;
    expect(warehouseId).toBeTruthy();
  });

  it('cancels twice with no second effect', async () => {
    const created = await request(app)
      .post('/api/inventory/physical-counts')
      .set('Cookie', cookie)
      .send({ warehouse_id: warehouseId, count_date: '2026-11-20', notes: 'issue-36 guard' });
    expect(created.status).toBe(201);
    const countId = (created.body as { id: number }).id;
    expect(countId).toBeTruthy();

    const first = await request(app)
      .post(`/api/inventory/physical-counts/${countId}/cancel`)
      .set('Cookie', cookie);
    expect(first.status).toBe(200);
    expect((first.body as { status: string }).status).toBe('Cancelled');

    const second = await request(app)
      .post(`/api/inventory/physical-counts/${countId}/cancel`)
      .set('Cookie', cookie);
    expect(second.status).toBe(200);
    expect((second.body as { status: string }).status).toBe('Cancelled');

    const row = db.prepare('SELECT status FROM physical_counts WHERE id = ?')
      .get(countId) as { status: string };
    expect(row.status).toBe('Cancelled');

    expect(countOf('SELECT COUNT(*) AS n FROM stock_movements WHERE warehouse_id = ?', warehouseId)).toBe(0);
    expect(countOf('SELECT COUNT(*) AS n FROM stock_balances WHERE warehouse_id = ?', warehouseId)).toBe(0);
  });
});
