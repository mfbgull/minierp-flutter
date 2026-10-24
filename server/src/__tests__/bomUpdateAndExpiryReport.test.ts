import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import ReportsModel from '../models/Reports';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `BOMModel.update` transaction callback
 * (CRAP 30) and `reportsController.getExpiryReport` (CRAP 30).
 */
describe('BOM update', () => {
  let cookie = '';
  let bomId = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    const finished = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('BOM-U-FG', 'Finished')`)
      .run();
    const material = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('BOM-U-RM', 'Material')`)
      .run();
    const bom = db
      .prepare(
        `INSERT INTO boms (bom_no, bom_name, finished_item_id, quantity, created_by)
         VALUES ('BOM-U-1', 'Original', ?, 1, 1)`
      )
      .run(finished.lastInsertRowid);
    bomId = Number(bom.lastInsertRowid);
    db.prepare(
      `INSERT INTO bom_items (bom_id, item_id, quantity) VALUES (?, ?, 2)`
    ).run(bomId, material.lastInsertRowid);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('replaces the component list and keeps is_active when omitted', async () => {
    const material = db
      .prepare(`SELECT id FROM items WHERE item_code = 'BOM-U-RM'`)
      .get() as { id: number };

    const res = await request(app)
      .put(`/api/boms/${bomId}`)
      .set('Cookie', cookie)
      .send({ bom_name: 'Updated', quantity: 3, items: [{ item_id: material.id, quantity: 5 }] });

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ id: bomId, bom_name: 'Updated', quantity: 3, is_active: 1 });
    const items = db
      .prepare('SELECT item_id, quantity FROM bom_items WHERE bom_id = ?')
      .all(bomId) as Array<{ item_id: number; quantity: number }>;
    expect(items).toEqual([{ item_id: material.id, quantity: 5 }]);
  });

  it('updates header fields without touching components', async () => {
    const before = db
      .prepare('SELECT item_id, quantity FROM bom_items WHERE bom_id = ?')
      .all(bomId);

    const res = await request(app)
      .put(`/api/boms/${bomId}`)
      .set('Cookie', cookie)
      .send({ description: 'refreshed', is_active: 0 });

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ id: bomId, description: 'refreshed', is_active: 0 });
    expect(db.prepare('SELECT item_id, quantity FROM bom_items WHERE bom_id = ?').all(bomId)).toEqual(
      before
    );
  });
});

describe('GET /api/reports/expiry', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const get = (query: Record<string, string> = {}) =>
    request(app).get('/api/reports/expiry').set('Cookie', cookie).query(query);

  it('passes the optional filters through', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getExpiryReport')
      .mockReturnValue({ batches: [] } as unknown as ReturnType<
        typeof ReportsModel.getExpiryReport
      >);

    const res = await get({ warehouse_id: '2', threshold_days: '30', status: 'expired' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, data: { batches: [] } });
    expect(spy).toHaveBeenCalledWith(expect.anything(), {
      warehouseId: 2,
      thresholdDays: 30,
      status: 'expired',
    });
  });

  it('omits every filter when none is supplied', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getExpiryReport')
      .mockReturnValue({ batches: [] } as unknown as ReturnType<
        typeof ReportsModel.getExpiryReport
      >);

    expect((await get()).status).toBe(200);
    expect(spy).toHaveBeenCalledWith(expect.anything(), {
      warehouseId: undefined,
      thresholdDays: undefined,
      status: undefined,
    });
  });

  it('returns a sanitized 500 when the report fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(ReportsModel, 'getExpiryReport').mockImplementation(() => {
      throw new Error('forced expiry failure');
    });

    const res = await get();
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to fetch expiry report' });
  });
});
