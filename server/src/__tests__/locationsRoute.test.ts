/**
 * GET /api/inventory/locations — bins of one warehouse (route level).
 *
 * The return flow calls this to ask the user which bin receives a line that
 * has no recorded draw, so the list must be warehouse-scoped and must carry
 * the seeded DEFAULT bin as well as the racks.
 *
 * RED-first target: the route did not exist. Every case below fails with 404
 * until it is registered.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

interface LocationRow {
  location_id: number;
  warehouse_id: number;
  location_code: string;
  location_name: string;
  is_active: number;
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('GET /api/inventory/locations', () => {
  let cookie: string;
  const createdWarehouses: number[] = [];

  beforeAll(async () => {
    cookie = await getAuthCookie();
    expect(cookie).not.toBe('');
  });

  afterAll(() => {
    for (const id of createdWarehouses) {
      // Bins first: a warehouse cannot be deleted while its locations exist.
      db.prepare('DELETE FROM batch_stock_by_location WHERE location_id IN (SELECT id FROM locations WHERE warehouse_id = ?)').run(id);
      db.prepare('DELETE FROM locations WHERE warehouse_id = ?').run(id);
      db.prepare('DELETE FROM warehouses WHERE id = ?').run(id);
    }
  });

  async function createWarehouse(tag: string): Promise<number> {
    const res = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', cookie)
      .send({
        warehouse_code: `WH-LOC-${tag}-${Date.now()}`,
        warehouse_name: `Locations route ${tag}`,
      });
    expect(res.status).toBe(201);
    const id = (res.body as { id?: number; data?: { id: number } }).id
      ?? (res.body as { data: { id: number } }).data.id;
    createdWarehouses.push(id);
    return id;
  }

  it('returns the warehouse DEFAULT bin plus its racks, and only that warehouse', async () => {
    const warehouseA = await createWarehouse('a');
    const warehouseB = await createWarehouse('b');
    // BUG-013: creating a warehouse seeds its DEFAULT location.
    db.prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, 'RACK-A', 'Rack A')`
    ).run(warehouseA);

    const res = await request(app)
      .get(`/api/inventory/locations?warehouse_id=${warehouseA}`)
      .set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    const rows = res.body.data as LocationRow[];
    // Ordered by id: DEFAULT is seeded first, the rack follows.
    expect(rows.map(r => r.location_code)).toEqual(['DEFAULT', 'RACK-A']);
    expect(rows[0]).toEqual({
      location_id: expect.any(Number),
      warehouse_id: warehouseA,
      location_code: 'DEFAULT',
      location_name: expect.any(String),
      is_active: 1,
    });

    // Warehouse scoping: B's own DEFAULT is not in A's list.
    const other = await request(app)
      .get(`/api/inventory/locations?warehouse_id=${warehouseB}`)
      .set('Cookie', cookie);
    expect((other.body.data as LocationRow[]).map(r => r.location_code)).toEqual(['DEFAULT']);
    expect((other.body.data as LocationRow[]).every(r => r.warehouse_id === warehouseB)).toBe(true);
  });

  it('keeps a bin that holds no stock in the list', async () => {
    const warehouse = await createWarehouse('empty');
    db.prepare(
      `INSERT INTO locations (warehouse_id, location_code, location_name) VALUES (?, 'EMPTY', 'Never stocked')`
    ).run(warehouse);

    const res = await request(app)
      .get(`/api/inventory/locations?warehouse_id=${warehouse}`)
      .set('Cookie', cookie);

    expect(res.status).toBe(200);
    // The customer can bring goods back to a bin the sale emptied, so zero
    // stock must not hide the bin from the choice.
    expect((res.body.data as LocationRow[]).map(r => r.location_code)).toEqual(['DEFAULT', 'EMPTY']);
  });

  it('rejects a missing or non-positive warehouse_id with 400', async () => {
    for (const query of ['', '?warehouse_id=abc', '?warehouse_id=0', '?warehouse_id=-4']) {
      const res = await request(app)
        .get(`/api/inventory/locations${query}`)
        .set('Cookie', cookie);
      expect(res.status).toBe(400);
      expect(res.body.error).toContain('warehouse_id');
    }
  });

  it('returns an empty list for a warehouse id that does not exist', async () => {
    const res = await request(app)
      .get('/api/inventory/locations?warehouse_id=999999')
      .set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
  });

  it('requires authentication', async () => {
    const res = await request(app).get('/api/inventory/locations?warehouse_id=1');
    expect(res.status).toBe(401);
  });
});
