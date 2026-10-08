/**
 * SEC-001 — forecast model config accepted arbitrary SQL in a column *name*.
 *
 * `forecastService.setModelConfig` built its SET clause from
 * `Object.entries(config)`, and the route's validator was
 * `z.object({}).passthrough()`, so a caller could place arbitrary SQL where a
 * column name belongs.
 *
 * Measured exploit (blind boolean oracle):
 *   PUT /api/forecasts/models/1
 *   { "model_type = (SELECT password_hash FROM users LIMIT 1) = 'guess'": 1 }
 *   → SET model_type = (SELECT password_hash FROM users LIMIT 1) = 'guess' = ?
 *   → the comparison result is stored, and GET /api/forecasts/models/1 does
 *     `SELECT *`, so the bit is readable.
 *
 * `true` → stored 1, `false` → stored 0. Any user holding only
 * `forecasts:create` could extract any table's contents one guess at a time.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');

const ORACLE_KEY = "model_type = (SELECT password_hash FROM users LIMIT 1) = 'SECRET'";

let authCookie = '';
let itemId = 0;

async function login(): Promise<void> {
  const res = await request(app).post('/api/auth/login').send({ username: 'admin', password: TEST_PASSWORD! });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return;
  const token = (Array.isArray(cookies) ? cookies : [cookies]).find((c: string) => c.startsWith('token='));
  if (token) authCookie = token.split(';')[0];
}

beforeAll(async () => {
  await login();
  const item = db.prepare(`INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
                           VALUES ('SEC001', 'SEC001 Probe', 'Nos', 10, 1, 1)`).run();
  itemId = Number(item.lastInsertRowid);
});

afterAll(() => {
  db.prepare('DELETE FROM forecast_model_config WHERE item_id = ?').run(itemId);
  db.prepare('DELETE FROM items WHERE id = ?').run(itemId);
});

const readModelType = (): unknown =>
  (db.prepare('SELECT model_type FROM forecast_model_config WHERE item_id = ?').get(itemId) as { model_type: unknown } | undefined)
    ?.model_type;

describe('SEC-001 — forecast model config rejects injected column names', () => {
  it('a legitimate config still saves', async () => {
    const res = await request(app)
      .put(`/api/forecasts/models/${itemId}`)
      .set('Cookie', authCookie)
      .send({ model_type: 'holt_winters', lead_time_days: 14, ses_alpha: 0.3 });

    expect(res.status).toBe(200);
    expect(readModelType()).toBe('holt_winters');
  });

  it('an injected column name is rejected with 400 and writes nothing', async () => {
    const before = db.prepare('SELECT COUNT(*) n FROM forecast_model_config').get() as { n: number };
    const beforeType = readModelType();

    const res = await request(app)
      .put(`/api/forecasts/models/${itemId}`)
      .set('Cookie', authCookie)
      .send({ [ORACLE_KEY]: 1 });

    expect(res.status).toBe(400);

    const after = db.prepare('SELECT COUNT(*) n FROM forecast_model_config').get() as { n: number };
    expect(after.n).toBe(before.n);
    expect(readModelType()).toBe(beforeType);
  });

  it('the boolean oracle cannot be constructed — a guessed secret never lands as 1', async () => {
    const res = await request(app)
      .put(`/api/forecasts/models/${itemId}`)
      .set('Cookie', authCookie)
      .send({ [ORACLE_KEY]: 1 });

    expect(res.status).toBe(400);
    // The oracle's tell: a successful injection stores 1 or 0 in model_type.
    expect([1, 0]).not.toContain(readModelType());
  });

  it('an unknown but harmless field is also rejected rather than silently written', async () => {
    const res = await request(app)
      .put(`/api/forecasts/models/${itemId}`)
      .set('Cookie', authCookie)
      .send({ created_at: '1999-01-01 00:00:00' });

    expect(res.status).toBe(400);

    const row = db.prepare('SELECT created_at FROM forecast_model_config WHERE item_id = ?').get(itemId) as
      { created_at: string } | undefined;
    expect(row?.created_at).not.toBe('1999-01-01 00:00:00');
  });

  it('the service layer drops an unknown key even when the schema is bypassed', () => {
    // Defence in depth: a non-HTTP caller reaches setModelConfig directly.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const svc = require('../services/forecastService') as typeof import('../services/forecastService');

    svc.setModelConfig({ item_id: itemId, model_type: 'holt', [ORACLE_KEY]: 1 } as never);

    expect(readModelType()).toBe('holt');
  });
});
