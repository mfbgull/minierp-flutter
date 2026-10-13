/**
 * Audit regression tests, round 7 — privilege escalation through user / role
 * management. Each test encodes CORRECT behaviour and is expected to FAIL on
 * commit 87f1265b until the finding is fixed (assertions are fix-agnostic).
 *
 *   AUTHZ-002  only an administrator may modify, reset, deactivate or delete an administrator account
 *   AUTHZ-003  a non-admin may not hand out a role that carries permissions they do not hold
 *   AUTHZ-004  a non-admin may not grant permissions to a role beyond those they hold themselves
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

const PASSWORD = 'Regression#12345';
let seq = 0;

function permissionId(module: string, action: string): number {
  let row = db.prepare('SELECT id FROM permissions WHERE module = ? AND action = ?').get(module, action) as { id: number } | undefined;
  if (!row) {
    row = {
      id: db.prepare(`INSERT INTO permissions (permission_name, module, action, description) VALUES (?, ?, ?, 'regression')`)
        .run(`${module}:${action}`, module, action).lastInsertRowid as number,
    };
  }
  return row.id;
}

function createRole(name: string, permissions: Array<[string, string]>): number {
  const roleId = db.prepare(
    `INSERT INTO roles (role_name, description, is_system_role, is_active) VALUES (?, 'regression', 0, 1)`
  ).run(name).lastInsertRowid as number;
  for (const [module, action] of permissions) {
    db.prepare('INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)').run(roleId, permissionId(module, action));
  }
  return roleId;
}

async function createActor(permissions: Array<[string, string]>): Promise<{ cookie: string; userId: number; roleId: number }> {
  seq += 1;
  const username = `reg7_actor_${seq}`;
  const roleId = createRole(`reg7_role_${seq}`, permissions);
  const userId = db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
    VALUES (?, ?, ?, ?, 'user', ?, 1)
  `).run(username, `${username}@example.test`, bcrypt.hashSync(PASSWORD, 10), username, roleId).lastInsertRowid as number;
  const res = await request(app).post('/api/auth/login').send({ username, password: PASSWORD });
  const cookie = ((res.headers['set-cookie'] as unknown as string[] | undefined) ?? [])
    .find((c) => c.startsWith('token='))?.split(';')[0] ?? '';
  expect(cookie).not.toBe('');
  return { cookie, userId, roleId };
}

const as = (cookie: string) => ({
  post: (url: string, body: unknown) => request(app).post(url).set('Cookie', cookie).send(body as object),
  put: (url: string, body: unknown) => request(app).put(url).set('Cookie', cookie).send(body as object),
  del: (url: string) => request(app).delete(url).set('Cookie', cookie).send({}),
});

const userRow = (id: number) =>
  db.prepare('SELECT username, email, password_hash, is_active, role, role_id FROM users WHERE id = ?').get(id) as {
    username: string; email: string; password_hash: string; is_active: number; role: string; role_id: number | null;
  } | undefined;

let adminId: number;
let adminRoleId: number;

beforeAll(async () => {
  await getAuthCookie(); // makes sure the seeded admin exists
  adminId = (db.prepare("SELECT id FROM users WHERE role = 'admin' ORDER BY id LIMIT 1").get() as { id: number }).id;
  adminRoleId = (db.prepare("SELECT id FROM roles WHERE role_name = 'Admin' ORDER BY id LIMIT 1").get() as { id: number }).id;
});

describe('AUTHZ-002: administrator accounts are protected from non-admins', () => {
  let manager: { cookie: string; userId: number };

  beforeAll(async () => {
    manager = await createActor([['users', 'read'], ['users', 'create'], ['users', 'update'], ['users', 'delete']]);
  });

  const resetBody = (password: string) => ({ new_password: password, password, newPassword: password });

  it('control: the manager can reset an ordinary user\'s password', async () => {
    const victimId = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
      VALUES ('reg7_plain', 'reg7_plain@example.test', ?, 'Plain', 'user', NULL, 1)
    `).run(bcrypt.hashSync(PASSWORD, 10)).lastInsertRowid as number;
    const before = userRow(victimId)!.password_hash;
    const res = await as(manager.cookie).put(`/api/users/${victimId}/reset-password`, resetBody('Another#Password99'));
    expect(res.status).toBe(200);
    expect(userRow(victimId)!.password_hash).not.toBe(before);
  });

  it('cannot reset the administrator\'s password', async () => {
    const before = userRow(adminId)!.password_hash;
    const res = await as(manager.cookie).put(`/api/users/${adminId}/reset-password`, resetBody('Takeover#98765432'));
    expect(res.status).toBe(403);
    expect(userRow(adminId)!.password_hash).toBe(before);
  });

  it('cannot change the administrator\'s e-mail address', async () => {
    const before = userRow(adminId)!.email;
    const res = await as(manager.cookie).put(`/api/users/${adminId}`, { email: 'attacker@evil.test' });
    expect(res.status).toBe(403);
    expect(userRow(adminId)!.email).toBe(before);
  });

  it('cannot deactivate or delete another administrator', async () => {
    const secondAdmin = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
      VALUES ('reg7_admin2', 'reg7_admin2@example.test', ?, 'Second Admin', 'admin', NULL, 1)
    `).run(bcrypt.hashSync(PASSWORD, 10)).lastInsertRowid as number;
    const toggle = await as(manager.cookie).put(`/api/users/${secondAdmin}/toggle-status`, { is_active: false });
    expect(toggle.status).toBe(403);
    expect(userRow(secondAdmin)!.is_active).toBe(1);
    const del = await as(manager.cookie).del(`/api/users/${secondAdmin}`);
    expect(del.status).toBe(403);
    expect(userRow(secondAdmin)).toBeDefined();
  });
});

describe('AUTHZ-003: roles that exceed the assigner\'s own permissions cannot be handed out', () => {
  let manager: { cookie: string; userId: number };

  beforeAll(async () => {
    manager = await createActor([['users', 'read'], ['users', 'create'], ['users', 'update']]);
  });

  it('control: assigning a role the manager already fully holds is allowed', async () => {
    const subsetRole = createRole('reg7_subset_role', [['users', 'read']]);
    const res = await as(manager.cookie).post('/api/users', {
      username: 'reg7_subset_user', email: 'reg7_subset@example.test', password: 'Subset#Password99',
      full_name: 'Subset User', role_id: subsetRole, is_active: true,
    });
    expect([200, 201]).toContain(res.status);
  });

  it('cannot create a user with the system Admin role', async () => {
    const res = await as(manager.cookie).post('/api/users', {
      username: 'reg7_escalated', email: 'reg7_escalated@example.test', password: 'Escalated#Password99',
      full_name: 'Escalated', role_id: adminRoleId, is_active: true,
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(db.prepare(`SELECT id FROM users WHERE username = 'reg7_escalated'`).get()).toBeUndefined();
  });

  it('cannot promote an existing user to the Admin role', async () => {
    const victim = await createActor([]);
    const res = await as(manager.cookie).put(`/api/users/${victim.userId}`, { role_id: adminRoleId });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(userRow(victim.userId)!.role_id).toBe(victim.roleId);
  });
});

describe('AUTHZ-004: a role manager cannot grant permissions they do not hold', () => {
  let roleManager: { cookie: string; userId: number; roleId: number };

  beforeAll(async () => {
    roleManager = await createActor([['roles', 'read'], ['roles', 'create'], ['roles', 'update']]);
  });

  const permissionCount = (roleId: number): number =>
    (db.prepare('SELECT COUNT(*) AS n FROM role_permissions WHERE role_id = ?').get(roleId) as { n: number }).n;

  it('control: granting a subset of one\'s own permissions to another role is allowed', async () => {
    const target = createRole('reg7_target_role', []);
    const readRoles = permissionId('roles', 'read');
    const res = await as(roleManager.cookie).put(`/api/roles/${target}/permissions`, { permissions: [readRoles] });
    expect(res.status).toBe(200);
    expect(permissionCount(target)).toBe(1);
  });

  it('cannot grant its own role every permission', async () => {
    const all = (db.prepare('SELECT id FROM permissions').all() as Array<{ id: number }>).map((p) => p.id);
    const before = permissionCount(roleManager.roleId);
    const res = await as(roleManager.cookie).put(`/api/roles/${roleManager.roleId}/permissions`, { permissions: all });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(permissionCount(roleManager.roleId)).toBe(before);
  });

  it('cannot create a role that carries permissions beyond its own', async () => {
    const payments = permissionId('payments', 'delete');
    const res = await as(roleManager.cookie).post('/api/roles', {
      role_name: 'reg7_overpowered', description: 'regression', permissions: [payments],
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(db.prepare(`SELECT id FROM roles WHERE role_name = 'reg7_overpowered'`).get()).toBeUndefined();
  });
});
