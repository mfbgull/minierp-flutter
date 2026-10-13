import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
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
