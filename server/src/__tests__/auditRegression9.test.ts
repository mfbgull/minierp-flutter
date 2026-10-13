import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import db, { seedDefaultPermissions } from '../config/database';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';

const balance = (code: string): number => {
  const row = db.prepare<[string], { balance: number }>(`
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0
  `).get(code);
  return Math.round((row?.balance ?? 0) * 100) / 100;
};

describe('PROD-001 / PROD-005: unpaid production overhead', () => {
  it('reverses the overhead payable when an intact production is deleted without moving cash', async () => {
    const cookie = await getAuthCookie();
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const raw = await createItem('PROD-overhead-void raw', cookie);
    const finished = await createItem('PROD-overhead-void finished', cookie);
    await purchaseStock(raw, warehouse.id, 10, 10, cookie);
    const payableBefore = balance('2200');
    const cashBefore = balance('1000');
    const bankBefore = balance('1010');

    const created = await request(app).post('/api/productions').set('Cookie', cookie).send({
      output_item_id: finished,
      output_quantity: 10,
      input_items: [{ item_id: raw, quantity: 10 }],
      overhead_cost: 50,
      warehouse_id: warehouse.id,
      production_date: '2026-09-10',
    });
    expect(created.status).toBe(201);
    expect(balance('2200') - payableBefore).toBe(-50);

    const productionId = Number(created.body.data?.id ?? created.body.id);
    const removed = await request(app).delete(`/api/productions/${productionId}`).set('Cookie', cookie).send({});
    expect(removed.status).toBe(200);
    expect(balance('2200')).toBe(payableBefore);
    expect(balance('1000')).toBe(cashBefore);
    expect(balance('1010')).toBe(bankBefore);
  });
});

describe('AUTHZ-001: every guarded permission code is grantable', () => {
  const sourceRoot = path.resolve(__dirname, '..');
  const walkedDirs = ['routes', 'controllers', 'middleware'];

  const guardedCodes = (): Set<string> => {
    const codes = new Set<string>();
    for (const dir of walkedDirs) {
      const walk = (current: string): void => {
        for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
          const full = path.join(current, entry.name);
          if (entry.isDirectory()) {
            walk(full);
          } else if (entry.name.endsWith('.ts')) {
            const source = fs.readFileSync(full, 'utf-8');
            const pattern = /requirePermission\(\s*'([A-Za-z_]+)'\s*,\s*'([A-Za-z_]+)'\s*\)/g;
            let match: RegExpExecArray | null;
            while ((match = pattern.exec(source)) !== null) {
              codes.add(`${match[1]}:${match[2]}`);
            }
          }
        }
      };
      walk(path.join(sourceRoot, dir));
    }
    return codes;
  };

  it('every permission a route guards exists in the permissions table', () => {
    const missing = [...guardedCodes()].filter(
      (code) =>
        db.prepare<[string], { n: number }>(
          'SELECT COUNT(*) AS n FROM permissions WHERE permission_name = ?',
        ).get(code)?.n !== 1,
    );
    expect(missing).toEqual([]);
  });

  it('does not guard a route with inventory:write, which D5 retired in favour of inventory:update', () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'routes', 'stockBatches.ts'), 'utf-8');
    expect(source).not.toContain("requirePermission('inventory', 'write')");
    expect(db.prepare<[string], { n: number }>(
      'SELECT COUNT(*) AS n FROM permissions WHERE permission_name = ?',
    ).get('inventory:update')?.n).toBe(1);
  });

  it('leaves reports:create ungranted even when a Manager role exists (D8)', () => {
    // The dormant seed block used to hand reports:create to Manager. It only ever
    // ran on installs that already had a Manager role, so a test that never
    // creates one cannot catch its return. Creating the role here does.
    const roleId = db.prepare<[string], { id: number }>(`
      INSERT INTO roles (role_name, description, is_system_role, is_active)
      VALUES (?, 'd8 regression', 0, 1)
      RETURNING id
    `).get('Manager')?.id as number;

    seedDefaultPermissions();

    const managerHolds = db.prepare<[number], { n: number }>(`
      SELECT COUNT(*) AS n
      FROM role_permissions rp
      JOIN permissions p ON p.id = rp.permission_id
      WHERE rp.role_id = ? AND p.permission_name = 'reports:create'
    `).get(roleId);
    expect(managerHolds?.n).toBe(0);
  });

  it('grants the newly seeded codes to no non-Admin role (D5)', () => {
    // The Admin role is granted every permission by seedDefaultPermissions, which
    // is the existing convention. D5's "grant none by default" means the new
    // codes must not leak into any other role - least of all the read-only User
    // role, which is handed every action='read' permission it has none of.
    const grantedElsewhere = db.prepare<[], { permission_name: string }>(`
      SELECT DISTINCT p.permission_name
      FROM permissions p
      JOIN role_permissions rp ON rp.permission_id = p.id
      JOIN roles r ON r.id = rp.role_id
      WHERE r.role_name <> 'Admin'
        AND p.permission_name IN (
          'accounting:update', 'admin:read', 'admin:create', 'admin:delete',
          'dashboard:create', 'dashboard:update', 'dashboard:delete', 'expenses:delete',
          'forecasts:delete', 'invoices:void', 'owner_equity:read', 'owner_equity:create',
          'owner_equity:edit', 'owner_equity:delete', 'reports:create', 'reports:update',
          'reports:delete'
        )
    `).all();
    expect(grantedElsewhere).toEqual([]);
  });
});

describe('REP-005: report engine gaps', () => {
  let adminCookie: string;
  const report = (config: unknown) =>
    request(app).post('/api/reports/custom/run').set('Cookie', adminCookie).send({ config });

  const seedEmployee = async (code: string, department: string, salary: number): Promise<void> => {
    const made = await request(app).post('/api/employees').set('Cookie', adminCookie).send({
      first_name: 'Rep', last_name: code, employee_code: code,
      email: `${code.toLowerCase()}@example.test`,
      department, designation: 'Clerk', hire_date: '2026-01-01', salary,
    });
    expect(made.status).toBe(201);
  };

  beforeAll(async () => {
    adminCookie = await getAuthCookie();
    await seedEmployee('REP5-A1', 'REP5Alpha', 1000);
    await seedEmployee('REP5-A2', 'REP5Alpha', 2000);
    await seedEmployee('REP5-B1', 'REP5Beta', 500);

    db.transaction(() => {
      const insert = db.prepare(`
        INSERT INTO employees (employee_code, first_name, last_name, department, designation,
          date_of_joining, salary, is_active, created_by)
        VALUES (?, 'Bulk', ?, 'REP5Bulk', 'Clerk', '2026-01-01', 10, 1,
          (SELECT id FROM users ORDER BY id LIMIT 1))
      `);
      for (let i = 0; i < 1200; i += 1) {
        insert.run(`REP5-BULK-${i}`, `row${i}`);
      }
    })();
  });

  it('computes requested group aggregates instead of returning an arbitrary row value', async () => {
    const res = await report({
      entity: 'employees',
      columns: [{ field: 'department' }],
      // The employees API assigns its own employee_code, so the fixture is
      // selected by salary: the 1,200-row bulk fixture is paid 10 each.
      filters: [{ field: 'salary', operator: 'greater_than', value: 100 }],
      groupBy: {
        enabled: true,
        fields: ['department'],
        aggregates: [{ field: 'salary', fn: 'SUM', alias: 'total_salary' }],
      },
    });
    expect(res.status).toBe(200);
    const rows = res.body.data.rows as Array<{ department: string; total_salary: number }>;
    const totals = rows.map((r) => Number(r.total_salary)).sort((a, b) => a - b);
    expect(totals).toEqual([500, 3000]);
  });

  const bulkRows = () =>
    report({
      entity: 'employees',
      columns: [{ field: 'employee_code' }],
      filters: [{ field: 'employee_code', operator: 'starts_with', value: 'REP5-BULK-' }],
    });

  it('caps an absurd requested row limit instead of accepting it', async () => {
    const res = await report({
      entity: 'employees',
      columns: [{ field: 'employee_code' }],
      filters: [{ field: 'employee_code', operator: 'starts_with', value: 'REP5-BULK-' }],
      limit: 1e12,
    });
    expect(res.status).toBe(200);
    expect((res.body.data.rows as unknown[]).length).toBeLessThanOrEqual(1000);
  });

  it('applies a default row limit when the report does not ask for one', async () => {
    const res = await bulkRows();
    expect(res.status).toBe(200);
    expect((res.body.data.rows as unknown[]).length).toBeGreaterThan(0);
    expect((res.body.data.rows as unknown[]).length).toBeLessThanOrEqual(1000);
  });

  it('treats LIKE wildcards in contains as literal characters', async () => {
    // Unescaped, '%' is a metacharacter, so '%REP5Alpha%' matches every value
    // merely CONTAINING 'REP5Alpha' - here the other department too.
    const wildcard = await report({
      entity: 'employees',
      columns: [{ field: 'department' }],
      filters: [{ field: 'department', operator: 'contains', value: '%REP5Alpha%' }],
      limit: 50,
    });
    expect(wildcard.status).toBe(200);
    const departments = (wildcard.body.data.rows as Array<{ department: string }>)
      .map((r) => r.department);
    expect(departments).not.toContain('REP5Beta');

    const literal = await report({
      entity: 'employees',
      columns: [{ field: 'department' }],
      filters: [{ field: 'department', operator: 'contains', value: 'REP5Alpha' }],
      limit: 50,
    });
    expect(literal.status).toBe(200);
    expect((literal.body.data.rows as unknown[]).length).toBeGreaterThan(0);
  });
});
