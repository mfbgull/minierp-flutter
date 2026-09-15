/**
 * Expired-stock plan Phase 1 — system-warehouse delete guard (API level).
 *
 * EXPIRED / DAMAGED (is_system = 1) are permanent infrastructure: the boot
 * task resolves the EXPIRED warehouse by code, so deleting it would silently
 * break expiry detection. Covers:
 *   1. DELETE of a system warehouse → 400 with a structured error, row intact
 *   2. DELETE of a normal warehouse → succeeds (guard does not over-block)
 *   3. System warehouses cannot be updated to is_system = 0 via the API
 *      (update path leaves the flag alone; flag is not client-writable)
 *   4. DB trigger backstop: direct SQL DELETE also aborts
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

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
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('System warehouse delete guard', () => {
  let authCookie: string;
  let normalWarehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    // Fresh system warehouses: the migration seeds them once. If a prior run
    // already deleted... it cannot (trigger). So they must exist here.
    const expired = db.prepare(
      `SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED' AND is_system = 1`
    ).get() as { id: number } | undefined;
    const damaged = db.prepare(
      `SELECT id FROM warehouses WHERE warehouse_code = 'DAMAGED' AND is_system = 1`
    ).get() as { id: number } | undefined;
    if (!expired || !damaged) {
      throw new Error(
        'System warehouses missing — run the add-expired-stock migration before this suite.'
      );
    }

    // A normal warehouse the test is allowed to delete at the end.
    const created = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', authCookie)
      .send({
        warehouse_code: `WH-SYSGUARD-${Date.now()}`,
        warehouse_name: 'System Guard Test WH',
      });
    if (created.status !== 201) {
      throw new Error(`Warehouse creation failed: ${JSON.stringify(created.body)}`);
    }
    normalWarehouseId = created.body.data?.id ?? created.body.id;
    expect(normalWarehouseId).toBeGreaterThan(0);
  });

  it('rejects DELETE of the EXPIRED system warehouse with a 400', async () => {
    const id = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    const res = await request(app)
      .delete(`/api/inventory/warehouses/${id}`)
      .set('Cookie', authCookie);

    expect(res.status).toBe(400);
    expect(res.body.error).toContain('system warehouse');

    // Row intact after the rejected delete
    const still = db.prepare(`SELECT COUNT(*) AS n FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { n: number };
    expect(still.n).toBe(1);
  });

  it('rejects DELETE of the DAMAGED system warehouse with a 400', async () => {
    const id = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'DAMAGED'`).get() as { id: number }).id;
    const res = await request(app)
      .delete(`/api/inventory/warehouses/${id}`)
      .set('Cookie', authCookie);

    expect(res.status).toBe(400);
    expect(res.body.error).toContain('system warehouse');
  });

  it('allows DELETE of a normal warehouse (guard does not over-block)', async () => {
    const res = await request(app)
      .delete(`/api/inventory/warehouses/${normalWarehouseId}`)
      .set('Cookie', authCookie);

    expect(res.status).toBe(200);
    // WarehouseModel.delete is a soft delete (is_active = 0), not a hard DELETE:
    const row = db.prepare(`SELECT is_active FROM warehouses WHERE id = ?`).get(normalWarehouseId) as { is_active: number };
    expect(row.is_active).toBe(0);
  });

  it('does not expose is_system for client tampering via the update endpoint', async () => {
    // Even if a client posts is_system in the body, the update handler only
    // writes whitelisted fields (code/name/location/is_active) — verify the
    // flag is unchanged after an update attempt that includes it.
    const id = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    const res = await request(app)
      .put(`/api/inventory/warehouses/${id}`)
      .set('Cookie', authCookie)
      .send({ warehouse_name: 'Expired Stock', is_system: 0 });

    expect([200, 400, 500]).toContain(res.status); // handler-defined outcomes
    const flag = db.prepare(`SELECT is_system FROM warehouses WHERE id = ?`).get(id) as { is_system: number };
    expect(flag.is_system).toBe(1);
  });

  it('DB trigger backstop: direct SQL delete of a system warehouse aborts', () => {
    let aborted = '';
    try {
      db.prepare(`DELETE FROM warehouses WHERE warehouse_code = 'EXPIRED'`).run();
    } catch (err) {
      aborted = (err as Error).message;
    }
    expect(aborted).toContain('Cannot delete system warehouse');
  });

  it('rejects CREATE with a reserved system warehouse code (case-insensitive)', async () => {
    for (const code of ['EXPIRED', 'expired', 'DAMAGED', 'Damaged']) {
      const res = await request(app)
        .post('/api/inventory/warehouses')
        .set('Cookie', authCookie)
        .send({ warehouse_code: code, warehouse_name: 'Squat Test' });
      expect(res.status).toBe(400);
      expect(res.body.error).toContain('reserved system warehouse code');
    }
    // Non-reserved codes still work
    const ok = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', authCookie)
      .send({
        warehouse_code: `WH-RESERVE-OK-${Date.now()}`,
        warehouse_name: 'Reserve Guard OK',
      });
    expect(ok.status).toBe(201);
  });

  it('rejects RENAME into a reserved system warehouse code', async () => {
    const created = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', authCookie)
      .send({
        warehouse_code: `WH-RENAME-${Date.now()}`,
        warehouse_name: 'Rename Guard WH',
      });
    expect(created.status).toBe(201);
    const id = created.body.data?.id ?? created.body.id;

    const res = await request(app)
      .put(`/api/inventory/warehouses/${id}`)
      .set('Cookie', authCookie)
      .send({ warehouse_code: 'EXPIRED' });
    expect(res.status).toBe(400);
    expect(res.body.error).toContain('reserved system warehouse code');
  });
});
