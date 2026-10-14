/**
 * Audit regression tests, round 6 — custom report engine.
 * Each test encodes CORRECT behaviour and is expected to FAIL on commit
 * 87f1265b until the finding is fixed (assertions are fix-agnostic).
 *
 *   REP-001  running a report requires read permission on the entity's module
 *   REP-002  the field whitelist cannot be bypassed (computed-column shadowing, HAVING)
 *   REP-003  every field the registry advertises must be selectable
 *   REP-004  HAVING filters with a bound value must execute (count query parameter mismatch)
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';
import { getAllEntities } from '../services/entityRegistry';

let adminCookie: string;
let employeeId: number;
let reportsOnly: string;       // reports:read + reports:create
let reportsPlusEmployees: string; // ... + employees:read

const PASSWORD = 'Regression#12345';

async function login(username: string): Promise<string> {
  const res = await request(app).post('/api/auth/login').send({ username, password: PASSWORD });
  const cookies = (res.headers['set-cookie'] as unknown as string[] | undefined) ?? [];
  return (cookies.find((c) => c.startsWith('token=')) ?? '').split(';')[0];
}

async function createUser(username: string, permissions: Array<[string, string]>): Promise<string> {
  const roleId = db.prepare(
    `INSERT INTO roles (role_name, description, is_system_role, is_active) VALUES (?, 'regression', 0, 1)`
  ).run(`role_${username}`).lastInsertRowid as number;
  for (const [module, action] of permissions) {
    let permission = db.prepare('SELECT id FROM permissions WHERE module = ? AND action = ?').get(module, action) as { id: number } | undefined;
    if (!permission) {
      permission = {
        id: db.prepare(`INSERT INTO permissions (permission_name, module, action, description) VALUES (?, ?, ?, 'regression')`)
          .run(`${module}:${action}`, module, action).lastInsertRowid as number,
      };
    }
    db.prepare('INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)').run(roleId, permission.id);
  }
  db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, role_id, is_active)
    VALUES (?, ?, ?, ?, 'user', ?, 1)
  `).run(username, `${username}@example.test`, bcrypt.hashSync(PASSWORD, 10), username, roleId);
  return login(username);
}

const run = (cookie: string, config: unknown) =>
  request(app).post('/api/reports/custom/run').set('Cookie', cookie).send({ config });

beforeAll(async () => {
  adminCookie = await getAuthCookie();
  const created = await request(app).post('/api/employees').set('Cookie', adminCookie).send({
    first_name: 'Report', last_name: 'Target', employee_code: 'REP-1', email: 'rep@example.test',
    department_id: 1, position: 'Clerk', hire_date: '2026-01-01', salary: 5000,
  });
  expect(created.status).toBe(201);
  employeeId = (created.body?.data?.id ?? created.body?.id) as number;
  db.prepare(`UPDATE employees SET bank_iban = 'PK36SCBL0000001123456702' WHERE id = ?`).run(employeeId);

  reportsOnly = await createUser('reg_reports_only', [['reports', 'read'], ['reports', 'create']]);
  reportsPlusEmployees = await createUser('reg_reports_employees', [['reports', 'read'], ['reports', 'create'], ['employees', 'read']]);
});

describe('REP-001: entity-level permission on report execution', () => {
  const salaryReport = { entity: 'employees', columns: [{ field: 'first_name' }, { field: 'salary' }] };

  it('control: admin can run an employees report', async () => {
    const res = await run(adminCookie, salaryReport);
    expect(res.status).toBe(200);
  });

  it('control: a user who also holds employees:read can run it', async () => {
    const res = await run(reportsPlusEmployees, salaryReport);
    expect(res.status).toBe(200);
    expect(res.body.data.rows.some((r: { salary: number }) => r.salary === 5000)).toBe(true);
  });

  it('control: the same user is denied the employees module directly', async () => {
    const res = await request(app).get('/api/employees').set('Cookie', reportsOnly);
    expect(res.status).toBe(403);
  });

  it('a reports-only user cannot read salaries through the report engine', async () => {
    const res = await run(reportsOnly, salaryReport);
    expect(res.status).toBe(403);
    expect(JSON.stringify(res.body)).not.toContain('5000');
  });

  it('a reports-only user cannot read the activity log through the report engine', async () => {
    const res = await run(reportsOnly, { entity: 'activity_log', columns: [{ field: 'description' }], limit: 5 });
    expect(res.status).toBe(403);
  });

  it('a saved report on a forbidden entity cannot be created-and-run by a reports-only user', async () => {
    const created = await request(app).post('/api/reports/custom').set('Cookie', reportsOnly).send({
      name: 'Salary dump', entity: 'employees', config: salaryReport,
    });
    if (created.status >= 400) return; // rejecting the save is also a valid fix
    const reportId = created.body?.data?.id;
    const res = await request(app).post('/api/reports/custom/run').set('Cookie', reportsOnly).send({ reportId });
    expect(res.status).toBe(403);
  });
});

describe('REP-002: the field whitelist cannot be bypassed', () => {
  // `bank_iban` is a real employees column that is deliberately NOT in the registry.
  const shadowConfig = (operator: string, value: string) => ({
    entity: 'employees',
    columns: [{ field: 'first_name' }, { field: 'dummy' }],
    computedColumns: [
      { name: 'bank_iban', expression: '1', type: 'number' },
      { name: 'dummy', expression: '1', type: 'number' },
    ],
    filters: [{ field: 'id', operator: 'equals', value: employeeId }, { field: 'bank_iban', operator: operator, value }],
  });

  it('control: filtering directly on a non-registry column is rejected', async () => {
    const res = await run(adminCookie, {
      entity: 'employees', columns: [{ field: 'first_name' }],
      filters: [{ field: 'bank_iban', operator: 'starts_with', value: 'PK' }],
    });
    expect(res.status).toBe(400);
  });

  it('a computed column named after a hidden column cannot be used to filter on it', async () => {
    const res = await run(reportsPlusEmployees, shadowConfig('starts_with', 'PK36'));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('no yes/no oracle: a correct and an incorrect prefix are both refused', async () => {
    const right = await run(reportsPlusEmployees, shadowConfig('starts_with', 'PK36'));
    const wrong = await run(reportsPlusEmployees, shadowConfig('starts_with', 'ZZ99'));
    expect(right.status).toBeGreaterThanOrEqual(400);
    expect(wrong.status).toBeGreaterThanOrEqual(400);
  });

  it('HAVING cannot reference a column outside the entity field list', async () => {
    const res = await run(reportsPlusEmployees, {
      entity: 'employees', columns: [{ field: 'employee_code' }],
      groupBy: {
        enabled: true, fields: ['employee_code'],
        // is_not_null binds no parameter, so this exercises the field check itself
        having: [{ field: 'bank_iban', operator: 'is_not_null' }],
      },
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('control: a legitimate computed column still works', async () => {
    const res = await run(reportsPlusEmployees, {
      entity: 'employees', columns: [{ field: 'first_name' }, { field: 'double_salary' }],
      computedColumns: [{ name: 'double_salary', expression: 'salary * 2', type: 'number' }],
      filters: [{ field: 'id', operator: 'equals', value: employeeId }],
    });
    expect(res.status).toBe(200);
    expect(res.body.data.rows[0].double_salary).toBe(10000);
  });
});

describe('REP-003: every advertised registry field is selectable', () => {
  it('no entity field fails with a SQL error', async () => {
    const broken: string[] = [];
    for (const entity of getAllEntities()) {
      for (const field of entity.fields) {
        const res = await run(adminCookie, { entity: entity.key, columns: [{ field: field.name }], limit: 1 });
        if (res.status !== 200) broken.push(`${entity.key}.${field.name}: ${res.body?.error ?? res.status}`);
      }
    }
    expect(broken).toEqual([]);
  });
});

describe('REP-004: HAVING with a bound value', () => {
  it('executes and filters (MAX(salary) > 1 grouped by department)', async () => {
    const res = await run(adminCookie, {
      entity: 'employees',
      columns: [{ field: 'department' }, { field: 'max_salary' }],
      computedColumns: [{ name: 'max_salary', expression: 'MAX(salary)', type: 'number' }],
      groupBy: {
        enabled: true, fields: ['department'],
        having: [{ field: 'max_salary', operator: 'greater_than', value: 1 }],
      },
    });
    expect(res.status).toBe(200);
    expect(res.body.data.rows.length).toBeGreaterThan(0);
  });
});
