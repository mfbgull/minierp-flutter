import request from 'supertest';
import app from '../app';

/**
 * Integration tests for `GET /api/dashboard/boot` (spec 7.1) — the
 * composite payload that cuts the dashboard's boot fan-out from 8
 * parallel GETs to 1. The jest setup seeds a fresh temp DB with the
 * admin user; the boot endpoint is read-only so no fixtures are
 * required beyond empty tables (blocks degrade to null / [] / null).
 */

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
  if (!tokenCookie) return '';
  return tokenCookie.split(';')[0];
}

describe('GET /api/dashboard/boot (composite boot payload, spec 7.1)', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
  });

  it('401s without a token', async () => {
    const res = await request(app).get('/api/dashboard/boot');
    expect(res.status).toBe(401);
  });

  it('returns summary + layout + kpis + cash + ar + expiryAlerts + topCustomers in one payload', async () => {
    const res = await request(app)
      .get('/api/dashboard/boot')
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);

    const data = res.body.data;
    for (const key of [
      'summary',
      'layout',
      'kpis',
      'cash',
      'ar',
      'expiryAlerts',
      'topCustomers',
    ]) {
      expect(data).toHaveProperty(key);
    }

    // Summary is the real DashboardModel.getSummary payload.
    expect(typeof data.summary.totalStockValue).toBe('number');
    expect(Array.isArray(data.summary.lowStockItems)).toBe(true);

    // Fresh DB → no saved layout yet (null), empty optional blocks.
    expect(data.layout).toBeNull();
    expect(data.kpis).toEqual({});
    expect(data.expiryAlerts).toEqual([]);
    expect(data.topCustomers).toEqual([]);
  });

  it('resolves the requested KPI metrics and honours the date range', async () => {
    const res = await request(app)
      .get('/api/dashboard/boot')
      .query({
        metrics: 'stock_value,sales_revenue',
        fromDate: '2026-01-01',
        toDate: '2026-12-31',
      })
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    const kpis = res.body.data.kpis as Record<string, unknown>;
    expect(Object.keys(kpis).sort()).toEqual(['sales_revenue', 'stock_value']);
    // Known metric → KpiResult shape; out-of-range window → null, not a 500.
    for (const value of Object.values(kpis)) {
      if (value === null) continue;
      expect(value).toHaveProperty('metric');
      expect(value).toHaveProperty('value');
    }
  });
});
