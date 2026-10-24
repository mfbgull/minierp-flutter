import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import activityLogModel from '../models/ActivityLog';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `ActivityLogModel.find` (CRAP 156) and
 * `getStats` (CRAP 30), exercised through the mounted read routes.
 */
describe('activity log API', () => {
  let cookie = '';
  let adminId = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    adminId = (
      db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
    ).id;
    db.prepare('DELETE FROM activity_log').run();
    activityLogModel.insert(adminId, 'ITEM_CREATE', 'Item', 1, 'Created widget', 'INFO', '10.0.0.1');
    activityLogModel.insert(adminId, 'ITEM_UPDATE', 'Item', 1, 'Updated widget', 'WARN');
    activityLogModel.insert(null, 'SYSTEM_CLEANUP', 'Setting', 2, 'Nightly cleanup', 'INFO');
  });

  const get = (query: Record<string, string> = {}) =>
    request(app).get('/api/activity-logs').set('Cookie', cookie).query(query);

  it('filters by user, entity, action, level and paging', async () => {
    const byUser = await get({ user_id: String(adminId), limit: '10', offset: '1' });
    expect(byUser.status).toBe(200);
    expect(byUser.body.total).toBeGreaterThanOrEqual(2);
    expect(byUser.body.limit).toBe(10);
    expect(byUser.body.offset).toBe(1);

    const byEntity = await get({ entity_type: 'Item', entity_id: '1' });
    expect(byEntity.body.data).toHaveLength(2);

    const byAction = await get({ action: 'ITEM_UPDATE' });
    expect(byAction.body.data).toHaveLength(1);

    const byLevel = await get({ log_level: 'WARN' });
    expect(byLevel.body.data).toHaveLength(1);
    expect(byLevel.body.data[0].action).toBe('ITEM_UPDATE');
  });

  it('filters by date range and free-text search', async () => {
    const today = new Date();
    const iso = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);

    const ranged = await get({
      start_date: iso(yesterday),
      end_date: iso(today),
    });
    expect(ranged.status).toBe(200);
    expect(ranged.body.total).toBeGreaterThanOrEqual(3);

    const future = new Date(today);
    future.setDate(today.getDate() + 2);
    const empty = await get({ start_date: iso(future) });
    expect(empty.body.total).toBe(0);

    const searched = await get({ search: 'widget' });
    expect(searched.body.total).toBe(2);

    const byType = await get({ search: 'Setting' });
    expect(byType.body.total).toBe(1);
  });

  it('returns stats for the full history and a date range', async () => {
    const all = await request(app).get('/api/activity-logs/stats').set('Cookie', cookie);
    expect(all.status).toBe(200);
    expect(all.body.data.totalLogs).toBeGreaterThanOrEqual(3);
    expect(all.body.data.users).toEqual(
      expect.arrayContaining([{ username: 'admin', count: 2 }])
    );
    expect(all.body.data.actions.length).toBeGreaterThanOrEqual(3);

    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    const ranged = await request(app)
      .get('/api/activity-logs/stats')
      .set('Cookie', cookie)
      .query({ start_date: today, end_date: today });
    expect(ranged.status).toBe(200);
    expect(ranged.body.data.totalLogs).toBeGreaterThanOrEqual(3);

    const future = new Date();
    future.setDate(future.getDate() + 3);
    const empty = await request(app)
      .get('/api/activity-logs/stats')
      .set('Cookie', cookie)
      .query({
        start_date: `${future.getFullYear()}-${String(future.getMonth() + 1).padStart(2, '0')}-${String(future.getDate()).padStart(2, '0')}`,
      });
    expect(empty.body.data.totalLogs).toBeGreaterThanOrEqual(3);
  });
});
