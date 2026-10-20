/**
 * SEC-04 regression tests: self-service edits cannot change own role.
 *
 * The previous guard was inverted — it compared role NAMES and allowed a
 * user to promote themselves to Admin while blocking self-demotion.
 * The fix rejects any self-edit containing role_id, regardless of target.
 *
 * Authority is now resolved from the database on every request (CODE-002 /
 * CODE-003). Mutating the acting user's own role to make a scenario
 * observable would therefore strip their authority before the controller's
 * SEC-04 guard runs. Each scenario instead acts through a real active user
 * whose admin authority holds at request time, so the guard is reached.
 */
import request from 'supertest';
import jwt from 'jsonwebtoken';
import app from '../app';
import db from '../config/database';

function signToken(id: number, username: string): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test JWT secret');
  return jwt.sign(
    { id, username, role: 'admin' },
    secret,
    { issuer: 'mini-erp', audience: 'mini-erp-client', expiresIn: '1h' },
  );
}

describe('User self-role guard (SEC-04)', () => {
  // Holds authority through the legacy users.role column (role_id IS NULL),
  // so a self-edit assigning the Admin system role is a genuine promotion.
  let promoterId: number;
  let promoterToken: string;

  // Holds the Admin system role, so a self-edit assigning the User role is a
  // genuine demotion, and it is also the actor for editing another user.
  let adminActorId: number;
  let adminActorToken: string;

  let victimId: number;

  beforeAll(() => {
    const adminRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get() as { id: number };
    const suffix = Date.now();

    const promoterUsername = `sec04_promoter_${suffix}`;
    const promoter = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
      VALUES (?, ?, 'unused', 'SEC-04 Promoter', 'admin', NULL, 1)
    `).run(promoterUsername, `${promoterUsername}@test.local`);
    promoterId = Number(promoter.lastInsertRowid);
    promoterToken = signToken(promoterId, promoterUsername);

    const actorUsername = `sec04_actor_${suffix}`;
    const actor = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
      VALUES (?, ?, 'unused', 'SEC-04 Admin Actor', 'admin', ?, 1)
    `).run(actorUsername, `${actorUsername}@test.local`, adminRole.id);
    adminActorId = Number(actor.lastInsertRowid);
    adminActorToken = signToken(adminActorId, actorUsername);

    // A second, admin-capable user so we can prove an admin can still edit
    // ANOTHER user's role (including demoting another admin).
    const victimUsername = `sec04_victim_${suffix}`;
    const victim = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
      VALUES (?, ?, 'unused', 'SEC-04 Victim', 'admin', ?, 1)
    `).run(victimUsername, `${victimUsername}@test.local`, adminRole.id);
    victimId = Number(victim.lastInsertRowid);
  });

  it('rejects self-promotion to Admin with 400 and performs no update', async () => {
    const adminRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get() as { id: number };

    const before = db.prepare('SELECT role_id, updated_at FROM users WHERE id = ?').get(promoterId) as { role_id: number | null; updated_at: string };
    expect(before.role_id).toBeNull(); // not a system Admin: the promotion is real

    const res = await request(app)
      .put(`/api/users/${promoterId}`)
      .set('Authorization', `Bearer ${promoterToken}`)
      .send({ role_id: adminRole.id });

    expect(res.status).toBe(400);

    const after = db.prepare('SELECT role_id, updated_at FROM users WHERE id = ?').get(promoterId) as { role_id: number | null; updated_at: string };
    expect(after.role_id).toBe(before.role_id); // unchanged
    expect(after.updated_at).toBe(before.updated_at); // no write reached the row
  });

  it('rejects self-demotion with 400', async () => {
    const adminRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'Admin'`).get() as { id: number };
    const userRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };

    const before = db.prepare('SELECT role_id, updated_at FROM users WHERE id = ?').get(adminActorId) as { role_id: number; updated_at: string };
    expect(before.role_id).toBe(adminRole.id); // genuinely an Admin, so this is a demotion

    const res = await request(app)
      .put(`/api/users/${adminActorId}`)
      .set('Authorization', `Bearer ${adminActorToken}`)
      .send({ role_id: userRole.id });

    expect(res.status).toBe(400);

    const after = db.prepare('SELECT role_id, updated_at FROM users WHERE id = ?').get(adminActorId) as { role_id: number; updated_at: string };
    expect(after.role_id).toBe(before.role_id); // unchanged
    expect(after.updated_at).toBe(before.updated_at); // no write reached the row
  });

  it('allows an admin to update another user\'s role', async () => {
    const userRole = db.prepare(`SELECT id FROM roles WHERE role_name = 'User'`).get() as { id: number };

    const res = await request(app)
      .put(`/api/users/${victimId}`)
      .set('Authorization', `Bearer ${adminActorToken}`)
      .send({ role_id: userRole.id, full_name: 'SEC-04 Victim Renamed' });

    expect(res.status).toBe(200);
    const after = db.prepare('SELECT role_id, full_name FROM users WHERE id = ?').get(victimId) as { role_id: number; full_name: string };
    expect(after.role_id).toBe(userRole.id);
    expect(after.full_name).toBe('SEC-04 Victim Renamed');
  });
});
