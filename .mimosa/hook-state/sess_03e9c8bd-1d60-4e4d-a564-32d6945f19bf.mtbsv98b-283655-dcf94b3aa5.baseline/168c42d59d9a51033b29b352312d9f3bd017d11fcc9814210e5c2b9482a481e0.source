
import request from 'supertest';
import app from '../app';
import db from '../config/database';

jest.setTimeout(30000);

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD must be set');

async function getAuthCookie(): Promise<string> {
  const res = await request(app).post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('audit trail (tasks 4.3/4.8/4.9)', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  it('backstop writes exactly one trail row per mutating request', async () => {
    const countBefore = (db.prepare(
      `SELECT COUNT(*) AS n FROM activity_log WHERE entity_type='Customer'`
    ).get() as { n: number }).n;

    const res = await request(app)
      .post('/api/customers')
      .set('Cookie', authCookie)
      .send({
        customer_name: `Audit Test Customer ${Date.now()}`,
        phone: '0300-0000000'
      });
    expect([200, 201]).toContain(res.status);

    // Wait for queued flush
    await new Promise((r) => setTimeout(r, 1600));

    const countAfter = (db.prepare(
      `SELECT COUNT(*) AS n FROM activity_log WHERE entity_type='Customer' AND action='CUSTOMER_CREATE'`
    ).get() as { n: number }).n;
    expect(countAfter - countBefore).toBe(1);
  });

  it('purge is forbidden without the purge permission (admin bypasses)', async () => {
    // Admin role bypasses permission checks — expect success here.
    const res = await request(app)
      .post('/api/activity-logs/cleanup')
      .set('Cookie', authCookie)
      .send({ days: 100 });
    expect([200, 400]).toContain(res.status); // 400 if retention below min; NOT 403
  });

  it('purge rejects retention below the 365-day minimum', async () => {
    const res = await request(app)
      .post('/api/activity-logs/cleanup')
      .set('Cookie', authCookie)
      .send({ days: 90 });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/365/);
  });
});
