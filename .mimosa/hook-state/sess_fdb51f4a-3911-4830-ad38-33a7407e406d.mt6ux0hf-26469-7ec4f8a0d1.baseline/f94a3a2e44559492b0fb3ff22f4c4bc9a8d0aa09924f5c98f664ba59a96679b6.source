/**
 * SEC-04 regression tests: self-service edits cannot change own role.
 *
 * The previous guard was inverted — it compared role NAMES and allowed a
 * user to promote themselves to Admin while blocking self-demotion.
 * The fix rejects any self-edit containing role_id, regardless of target.
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function login(username: string, password: string): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username, password });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('User self-role guard (SEC-04)', () => {
  let adminCookie: string;
  let adminId: number;
  let victimId: number;
  let victimUsername: string;
  const victimPassword = 'victim-pass-123';

  beforeAll(async () => {
    adminCookie = await login('admin', TEST_PASSWORD);
    expect(adminCookie).not.toBe('');

    // Resolve the real admin id from the session.
    const me = await request(app).get('/api/auth/me').set('Cookie', adminCookie);
    adminId = me.body.data.id;

    // A second active admin-capable user (role_id of the seeded Admin role)
    // so we can prove an admin can still edit ANOTHER user's role.
    const adminRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get() as { id: number };
    victimUsername = `sec04_victim_${Date.now()}`;
    const created = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active, role_id)
      VALUES (?, ?, ?, 'SEC-04 Victim', 'admin', 1, ?)
    `).run(victimUsername, `${victimUsername}@test.local`, bcrypt.hashSync(victimPassword, 12), adminRole.id);
    victimId = created.lastInsertRowid as number;
  });

  afterAll(() => {
    try {
      db.prepare('DELETE FROM activity_log WHERE entity_type = \'User\' AND (entity_id = ? OR entity_id = ?)').run(adminId, victimId);
      db.prepare('DELETE FROM users WHERE id = ?').run(victimId);
    } catch {
      /* ignore cleanup errors */
    }
  });

  it('rejects self-promotion to Admin with 400 and performs no update', async () => {
    const adminRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get() as { id: number };
    const userRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };

    // Baseline: put the admin on the User role so "promotion" is observable.
    db.prepare('UPDATE users SET role_id = ? WHERE id = ?').run(userRole.id, adminId);
    const before = db.prepare('SELECT role_id FROM users WHERE id = ?').get(adminId) as { role_id: number };

    const res = await request(app)
      .put(`/api/users/${adminId}`)
      .set('Cookie', adminCookie)
      .send({ role_id: adminRole.id });

    expect(res.status).toBe(400);

    const after = db.prepare('SELECT role_id FROM users WHERE id = ?').get(adminId) as { role_id: number };
    expect(after.role_id).toBe(before.role_id); // unchanged
  });

  it('rejects self-demotion with 400', async () => {
    const userRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };

    const res = await request(app)
      .put(`/api/users/${adminId}`)
      .set('Cookie', adminCookie)
      .send({ role_id: userRole.id });

    expect(res.status).toBe(400);
  });

  it('allows an admin to update another user\'s role', async () => {
    const userRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };

    const res = await request(app)
      .put(`/api/users/${victimId}`)
      .set('Cookie', adminCookie)
      .send({ role_id: userRole.id, full_name: 'SEC-04 Victim Renamed' });

    expect(res.status).toBe(200);
    const after = db.prepare('SELECT role_id, full_name FROM users WHERE id = ?').get(victimId) as { role_id: number; full_name: string };
    expect(after.role_id).toBe(userRole.id);
    expect(after.full_name).toBe('SEC-04 Victim Renamed');
  });
});
