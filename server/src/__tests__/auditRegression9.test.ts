import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import db, { seedDefaultPermissions } from '../config/database';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';
import { runBackup, deleteBackupFile } from '../services/backupService';

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

describe('ACCT-006 / ACCT-007: date and pricing bounds', () => {
  let cookie: string;
  let customerId: number;
  let itemId: number;

  const postInvoice = (payload: Record<string, unknown>) =>
    request(app).post('/api/invoices').set('Cookie', cookie).send(payload);

  const invoice = (overrides: Record<string, unknown> = {}) => ({
    customer_id: customerId,
    invoice_date: '2026-09-15',
    due_date: '2026-10-15',
    items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
    ...overrides,
  });

  const line = (over: Record<string, unknown>) =>
    invoice({ items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0, discount_type: 'none', discount_value: 0, ...over }] });

  beforeAll(async () => {
    cookie = await getAuthCookie();
    const customer = await request(app).post('/api/customers').set('Cookie', cookie)
      .send({ customer_name: 'ACCT007 customer', phone: '0300' + (Date.now() % 10000000) });
    expect(customer.status).toBe(201);
    customerId = (customer.body?.data?.id ?? customer.body?.id) as number;
    itemId = await createItem('ACCT007 item', cookie);
    await purchaseStock(itemId, 1, 50, 10, cookie);
  });

  it('ACCT-006: rejects a calendar date that does not exist', async () => {
    const res = await postInvoice(invoice({ invoice_date: '2026-13-45' }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-006: rejects a far-future invoice date', async () => {
    const res = await postInvoice(invoice({ invoice_date: '2031-01-01' }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects a negative tax rate', async () => {
    const res = await postInvoice(line({ tax_rate: -5 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects an absurd tax rate', async () => {
    const res = await postInvoice(line({ tax_rate: 500 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects a zero unit price', async () => {
    const res = await postInvoice(line({ unit_price: 0 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects an absurd unit price', async () => {
    const res = await postInvoice(line({ unit_price: 1e15 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects a percentage discount above 100', async () => {
    const res = await postInvoice(line({ discount_type: 'percentage', discount_value: 150 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('ACCT-007: rejects a negative discount', async () => {
    const res = await postInvoice(line({ discount_type: 'percentage', discount_value: -10 }));
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});

describe('WO-002: damaged stock can be written off', () => {
  let cookie: string;
  let warehouseId: number;

  const lastOpenBatch = (itemId: number): number => {
    const row = db.prepare<[number], { id: number }>(
      `SELECT id FROM stock_batches WHERE item_id = ? AND quantity_remaining > 0 ORDER BY id DESC LIMIT 1`,
    ).get(itemId);
    if (!row) throw new Error(`No open batch for item ${itemId}`);
    return row.id;
  };

  const writeOff = (batchIds: number[]) =>
    request(app)
      .post('/api/inventory/damaged/write-off')
      .set('Cookie', cookie)
      .send({ batchIds, reason: 'damaged in transit', glAccount: '7202' });

  beforeAll(async () => {
    cookie = await getAuthCookie();
    const wh = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!wh) throw new Error('Missing fixture warehouse');
    warehouseId = wh.id;
  });

  it('writes off an undamaged-date batch with no expiry date and posts Dr 7202 / Cr 1200', async () => {
    const item = await createItem('WO-002 no-expiry item', cookie);
    await purchaseStock(item, warehouseId, 5, 8, cookie);
    const batchId = lastOpenBatch(item);
    const lossBefore = balance('7202');
    const assetBefore = balance('1200');

    const res = await writeOff([batchId]);

    expect(res.status).toBe(200);
    expect(res.body.data[0].error).toBeUndefined();
    expect(res.body.data[0].value).toBe(40); // 5 x 8
    expect(balance('7202') - lossBefore).toBe(40);
    expect(balance('1200') - assetBefore).toBe(-40);

    const batch = db.prepare<[number], { quantity_remaining: number }>(
      'SELECT quantity_remaining FROM stock_batches WHERE id = ?',
    ).get(batchId);
    expect(batch?.quantity_remaining).toBe(0);

    const mv = db.prepare<[number], { remarks: string; journal_entry_id: number }>(`
      SELECT mv.remarks, mv.journal_entry_id
      FROM stock_movements mv
      JOIN stock_batches b ON b.id = mv.batch_id
      WHERE b.item_id = ? AND mv.movement_type = 'WRITE_OFF'
    `).get(item);
    expect(mv?.remarks).toContain('gl=7202');
    expect(mv?.journal_entry_id).toBeGreaterThan(0);
  });

  it('writes off a batch already parked in the DAMAGED warehouse without re-transferring', async () => {
    const item = await createItem('WO-002 damaged-warehouse item', cookie);
    await purchaseStock(item, warehouseId, 4, 10, cookie);
    const sourceBatchId = lastOpenBatch(item);

    const moved = await request(app)
      .post('/api/inventory/damaged/transfer')
      .set('Cookie', cookie)
      .send({ batchId: sourceBatchId });
    expect(moved.status).toBe(200);
    const mirrorBatchId = Number(moved.body.data?.mirrorBatchId);
    expect(mirrorBatchId).toBeGreaterThan(0);

    const lossBefore = balance('7202');
    const res = await writeOff([mirrorBatchId]);

    expect(res.status).toBe(200);
    expect(res.body.data[0].error).toBeUndefined();
    expect(res.body.data[0].transferred).toBe(false);
    expect(balance('7202') - lossBefore).toBe(40); // 4 x 10
  });

  it('still refuses the expired write-off for a batch with no expiry date', async () => {
    const item = await createItem('WO-002 expired-endpoint item', cookie);
    await purchaseStock(item, warehouseId, 2, 5, cookie);
    const batchId = lastOpenBatch(item);

    const res = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', cookie)
      .send({ batchIds: [batchId], reason: 'not actually expired', glAccount: '7201' });

    expect(res.status).toBe(400);
    expect(JSON.stringify(res.body)).toContain('not expired');
  });
});

describe('D7: backups cover server/uploads/', () => {
  const uploadsDir = path.join(__dirname, '../../uploads');
  const markerName = `d7-cover-${Date.now()}.txt`;

  it('creates an uploads snapshot paired with every database backup', () => {
    fs.mkdirSync(path.join(uploadsDir, 'employees'), { recursive: true });
    const marker = path.join(uploadsDir, 'employees', markerName);
    fs.writeFileSync(marker, 'employee document that a restore must recover');

    try {
      const target = runBackup({ trigger: 'manual' });
      expect(target).not.toBeNull();

      const dbBase = path.basename(target as string); // erp-<stamp>.db
      const snapshot = path.join(path.dirname(target as string), dbBase.replace(/\.db$/, '.uploads'));
      expect(fs.existsSync(snapshot)).toBe(true);
      expect(fs.existsSync(path.join(snapshot, 'employees', markerName))).toBe(true);

      // The pairing must be derivable, not incidental: the snapshot name is
      // the backup name with .db -> .uploads, so a restore can find it.
      const restored = fs.readFileSync(path.join(snapshot, 'employees', markerName), 'utf8');
      expect(restored).toContain('restore must recover');
    } finally {
      fs.rmSync(path.join(uploadsDir, 'employees', markerName), { force: true });
    }
  });

  it('prunes an uploads snapshot when its database backup is pruned', () => {
    // Two backups with a marker far in the past must both disappear: the .db
    // by retention, the .uploads because its partner is gone.
    const target = runBackup({ trigger: 'manual' });
    expect(target).not.toBeNull();
    const dbBase = path.basename(target as string);
    const snapshot = path.join(path.dirname(target as string), dbBase.replace(/\.db$/, '.uploads'));
    expect(fs.existsSync(snapshot)).toBe(true);

    const past = new Date(Date.now() - 400 * 24 * 60 * 60 * 1000);
    fs.utimesSync(target as string, past, past);
    fs.utimesSync(snapshot, past, past);

    runBackup({ trigger: 'manual' }); // retention runs inside

    expect(fs.existsSync(target as string)).toBe(false);
    expect(fs.existsSync(snapshot)).toBe(false);
  });

  it('deleting a backup removes its uploads snapshot too', () => {
    const target = runBackup({ trigger: 'manual' });
    expect(target).not.toBeNull();
    const dbBase = path.basename(target as string);
    const snapshot = path.join(path.dirname(target as string), dbBase.replace(/\.db$/, '.uploads'));
    expect(fs.existsSync(snapshot)).toBe(true);

    expect(deleteBackupFile(dbBase)).toBe(true);
    expect(fs.existsSync(snapshot)).toBe(false);
  });
});

describe('D6: joint production with multiple outputs allocated by relative sales value', () => {
  let cookie: string;

  beforeAll(async () => { cookie = await getAuthCookie(); });

  it('splits materials + overhead between outputs by relative sales value', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');

    const seed = await createItem('D6 mustard seed', cookie);
    const oil = await createItem('D6 mustard oil', cookie);
    const cake = await createItem('D6 mustard cake', cookie);
    await purchaseStock(seed, warehouse.id, 100, 10, cookie); // materials 1,000.00

    // Relative sales value: oil 10 x 100 = 1,000; cake 50 x 10 = 500 -> 2:1
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(100, oil);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(10, cake);

    const clearingBefore = balance('7000');
    const payableBefore = balance('2200');
    const assetBefore = balance('1200');

    const res = await request(app).post('/api/productions').set('Cookie', cookie).send({
      warehouse_id: warehouse.id,
      production_date: '2026-09-12',
      overhead_cost: 500,
      input_items: [{ item_id: seed, quantity: 100 }],
      outputs: [
        { item_id: oil, quantity: 10 },
        { item_id: cake, quantity: 50 },
      ],
    });
    expect(res.status).toBe(201);
    const productionId = Number(res.body.data?.id ?? res.body.id);

    // Joint cost = 1,000 materials + 500 overhead = 1,500, split 2:1
    const detail = await request(app).get(`/api/productions/${productionId}`).set('Cookie', cookie);
    expect(detail.status).toBe(200);
    const outputs = detail.body.data?.outputs ?? detail.body.outputs;
    expect(outputs).toHaveLength(2);
    const allocated = (outputs as Array<{ item_id: number; quantity: number; allocated_cost: number; unit_cost: number }>)
      .reduce((sum, o) => sum + o.allocated_cost, 0);
    expect(allocated).toBe(1500);

    const oilOut = (outputs as Array<{ item_id: number; allocated_cost: number; unit_cost: number }>)
      .find((o) => o.item_id === oil);
    const cakeOut = (outputs as Array<{ item_id: number; allocated_cost: number; unit_cost: number }>)
      .find((o) => o.item_id === cake);
    expect(oilOut?.allocated_cost).toBe(1000);
    expect(cakeOut?.allocated_cost).toBe(500);
    expect(oilOut?.unit_cost).toBeCloseTo(100, 3);   // 1000 / 10
    expect(cakeOut?.unit_cost).toBeCloseTo(10, 3);   // 500 / 50

    // Both output batches exist in stock
    const batches = db.prepare<[number], { n: number }>(
      `SELECT COUNT(DISTINCT item_id) AS n FROM stock_batches WHERE source_type = 'PRODUCTION' AND source_id = ?`,
    ).get(productionId);
    expect(batches?.n).toBe(2);

    // GL: clearing absorbs materials + overhead and is fully relieved by the
    // output postings; overhead accrues as payable; inventory rises by the
    // absorbed overhead only (materials were already inventory).
    expect(balance('7000') - clearingBefore).toBe(0);
    // balance() is debit - credit, so a credit to the 2200 liability is negative
    expect(balance('2200') - payableBefore).toBe(-500);
    expect(balance('1200') - assetBefore).toBe(500);
  });

  it('stamps the expiry date only on outputs that track expiry', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');

    const seed = await createItem('D6 expiry seed', cookie);
    const oil = await createItem('D6 expiry oil', cookie);
    const cake = await createItem('D6 expiry cake', cookie);
    await purchaseStock(seed, warehouse.id, 50, 2, cookie);

    // The primary output tracks expiry; the co-product does not.
    db.prepare('UPDATE items SET has_expiry = 1 WHERE id = ?').run(oil);
    db.prepare('UPDATE items SET has_expiry = 0 WHERE id = ?').run(cake);

    const res = await request(app).post('/api/productions').set('Cookie', cookie).send({
      warehouse_id: warehouse.id,
      production_date: '2026-09-14',
      expiry_date: '2027-01-01',
      input_items: [{ item_id: seed, quantity: 50 }],
      outputs: [
        { item_id: oil, quantity: 5 },
        { item_id: cake, quantity: 20 },
      ],
    });
    expect(res.status).toBe(201);
    const productionId = Number(res.body.data?.id ?? res.body.id);

    const expiryOf = (itemId: number) =>
      db.prepare<[number, number], { expiry_date: string | null }>(
        `SELECT expiry_date FROM stock_batches WHERE source_type = 'PRODUCTION' AND source_id = ? AND item_id = ?`,
      ).get(productionId, itemId)?.expiry_date ?? null;

    expect(expiryOf(oil)).toBe('2027-01-01');
    // The co-product does not track expiry — it must not carry a date the
    // boot-time expiry sweep would act on (that sweep filters on
    // expiry_date alone).
    expect(expiryOf(cake)).toBeNull();
  });

  it('accepts the Flutter form payload verbatim (float quantities + bom_id + outputs[])', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');

    const seed = await createItem('D6 contract seed', cookie);
    const oil = await createItem('D6 contract oil', cookie);
    const cake = await createItem('D6 contract cake', cookie);
    await purchaseStock(seed, warehouse.id, 100, 10, cookie);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(100, oil);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(10, cake);

    // The BOM whose finished item is the PRIMARY output — what the Flutter
    // form's BOM picker yields.
    const bomId = db
      .prepare('INSERT INTO boms (bom_no, bom_name, finished_item_id, quantity, created_by) VALUES (?, ?, ?, ?, 1)')
      .run(`BOM-CTR-${oil}`, 'Contract BOM', oil, 10).lastInsertRowid;

    // Sent byte-for-byte as production_form_dialog.dart builds it: no
    // output_item_id / output_quantity when co-products exist, FLOAT
    // quantities (Dart num → JSON 10.0), bom_id alongside outputs[].
    const res = await request(app).post('/api/productions').set('Cookie', cookie).send({
      outputs: [
        { item_id: oil, quantity: 10.0 },
        { item_id: cake, quantity: 50.0 },
      ],
      warehouse_id: warehouse.id,
      production_date: '2026-09-18',
      bom_id: Number(bomId),
      overhead_cost: 0,
      input_items: [{ item_id: seed, quantity: 100 }],
    });
    expect(res.status).toBe(201);

    // Every key Production.fromJson reads must be present, or the client
    // silently renders blanks.
    const body = res.body.data ?? res.body;
    expect(body.production_no).toBeTruthy();
    expect(body.output_item_id).toBe(oil);
    expect(body.output_quantity).toBe(10);
    expect(Array.isArray(body.outputs)).toBe(true);
    expect(body.outputs).toHaveLength(2);
    for (const line of body.outputs as Array<Record<string, unknown>>) {
      expect(typeof line.item_code).toBe('string');
      expect(typeof line.item_name).toBe('string');
      expect(typeof line.allocated_cost === 'number').toBe(true);
      expect(typeof line.unit_cost === 'number').toBe(true);
    }
    // Float quantities survive the round trip.
    expect(Number((body.outputs as Array<{ quantity: number }>)[0].quantity)).toBe(10);
    expect(Number((body.outputs as Array<{ quantity: number }>)[1].quantity)).toBe(50);
  });

  it('answers a BOM/primary-output mismatch with 400, not an opaque 500', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');

    const seed = await createItem('D6 mismatch seed', cookie);
    const oil = await createItem('D6 mismatch oil', cookie);
    const cake = await createItem('D6 mismatch cake', cookie);
    await purchaseStock(seed, warehouse.id, 50, 2, cookie);

    // A BOM that produces the CO-PRODUCT — listed second, so it does not
    // match the primary output.
    const bomId = db
      .prepare('INSERT INTO boms (bom_no, bom_name, finished_item_id, quantity, created_by) VALUES (?, ?, ?, ?, 1)')
      .run(`BOM-MIS-${cake}`, 'Mismatched BOM', cake, 10).lastInsertRowid;

    const res = await request(app).post('/api/productions').set('Cookie', cookie).send({
      outputs: [
        { item_id: oil, quantity: 5 },
        { item_id: cake, quantity: 20 },
      ],
      warehouse_id: warehouse.id,
      production_date: '2026-09-19',
      bom_id: Number(bomId),
      input_items: [{ item_id: seed, quantity: 50 }],
    });
    // Previously a 500 with the reason buried in the server log — the
    // controller now answers the client error directly.
    expect(res.status).toBe(400);
    expect(String(res.body.error)).toContain(`primary output is item ${oil}`);

    // And nothing was written.
    const n = db
      .prepare<[number, number], { n: number }>(
        `SELECT COUNT(*) AS n FROM stock_batches WHERE source_type = 'PRODUCTION' AND item_id IN (?, ?)`,
      )
      .get(oil, cake);
    expect(Number(n?.n)).toBe(0);
  });

  it('refuses outputs that repeat an item or an input item', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const seed = await createItem('D6 guard seed', cookie);
    const oil = await createItem('D6 guard oil', cookie);
    const cake = await createItem('D6 guard cake', cookie);
    await purchaseStock(seed, warehouse.id, 10, 1, cookie);

    const base = {
      warehouse_id: warehouse.id,
      production_date: '2026-09-12',
      input_items: [{ item_id: seed, quantity: 10 }],
    };

    const repeated = await request(app).post('/api/productions').set('Cookie', cookie).send({
      ...base,
      outputs: [
        { item_id: oil, quantity: 1 },
        { item_id: oil, quantity: 2 },
      ],
    });
    expect(repeated.status).toBeGreaterThanOrEqual(400);

    const circular = await request(app).post('/api/productions').set('Cookie', cookie).send({
      ...base,
      outputs: [
        { item_id: seed, quantity: 1 },
        { item_id: cake, quantity: 2 },
      ],
    });
    expect(circular.status).toBeGreaterThanOrEqual(400);

    const badQty = await request(app).post('/api/productions').set('Cookie', cookie).send({
      ...base,
      outputs: [
        { item_id: oil, quantity: 0 },
        { item_id: cake, quantity: 2 },
      ],
    });
    expect(badQty.status).toBeGreaterThanOrEqual(400);
  });

  it('deletes a multi-output production: both batches and their GL go with it', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const seed = await createItem('D6 delete seed', cookie);
    const oil = await createItem('D6 delete oil', cookie);
    const cake = await createItem('D6 delete cake', cookie);
    await purchaseStock(seed, warehouse.id, 20, 5, cookie);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(100, oil);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(10, cake);

    const clearingBefore = balance('7000');
    const payableBefore = balance('2200');

    const created = await request(app).post('/api/productions').set('Cookie', cookie).send({
      warehouse_id: warehouse.id,
      production_date: '2026-09-13',
      overhead_cost: 60,
      input_items: [{ item_id: seed, quantity: 20 }],
      outputs: [
        { item_id: oil, quantity: 2 },
        { item_id: cake, quantity: 4 },
      ],
    });
    expect(created.status).toBe(201);
    const productionId = Number(created.body.data?.id ?? created.body.id);
    expect(balance('2200') - payableBefore).toBe(-60); // credit to a liability

    const removed = await request(app).delete(`/api/productions/${productionId}`).set('Cookie', cookie).send({});
    expect(removed.status).toBe(200);

    const left = db.prepare<[number], { n: number }>(
      `SELECT COUNT(*) AS n FROM stock_batches WHERE source_type = 'PRODUCTION' AND source_id = ? AND quantity_remaining > 0`,
    ).get(productionId);
    expect(left?.n).toBe(0);
    expect(balance('7000')).toBe(clearingBefore);
    expect(balance('2200')).toBe(payableBefore);
  });

  it('keeps single-output productions working unchanged', async () => {
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');
    const raw = await createItem('D6 single raw', cookie);
    const out = await createItem('D6 single out', cookie);
    await purchaseStock(raw, warehouse.id, 10, 4, cookie);

    const res = await request(app).post('/api/productions').set('Cookie', cookie).send({
      output_item_id: out,
      output_quantity: 5,
      warehouse_id: warehouse.id,
      production_date: '2026-09-14',
      input_items: [{ item_id: raw, quantity: 10 }],
    });
    expect(res.status).toBe(201);
    const productionId = Number(res.body.data?.id ?? res.body.id);
    const detail = await request(app).get(`/api/productions/${productionId}`).set('Cookie', cookie);
    const outputs = detail.body.data?.outputs ?? detail.body.outputs;
    expect(outputs).toHaveLength(1);
    expect(outputs[0].allocated_cost).toBe(40);
  });
});

describe('D6: production summary by item counts every output line', () => {
  it('counts the secondary output of a joint production in that item summary', async () => {
    const cookie = await getAuthCookie();
    const warehouse = db.prepare<[], { id: number }>('SELECT id FROM warehouses ORDER BY id LIMIT 1').get();
    if (!warehouse) throw new Error('Missing fixture warehouse');

    const seed = await createItem('D6 summary seed', cookie);
    const oil = await createItem('D6 summary oil', cookie);
    const cake = await createItem('D6 summary cake', cookie);
    await purchaseStock(seed, warehouse.id, 30, 3, cookie);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(100, oil);
    db.prepare('UPDATE items SET standard_selling_price = ? WHERE id = ?').run(10, cake);

    const created = await request(app).post('/api/productions').set('Cookie', cookie).send({
      warehouse_id: warehouse.id,
      production_date: '2026-09-16',
      input_items: [{ item_id: seed, quantity: 30 }],
      // cake is the SECOND line: the primary-output column does not name it
      outputs: [
        { item_id: oil, quantity: 3 },
        { item_id: cake, quantity: 9 },
      ],
    });
    expect(created.status).toBe(201);

    const forCake = await request(app).get(`/api/productions/summary/item/${cake}`).set('Cookie', cookie);
    expect(forCake.status).toBe(200);
    expect(Number(forCake.body.total_quantity_produced)).toBe(9);
    expect(Number(forCake.body.production_count)).toBe(1);
  });
});
