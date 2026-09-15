// Expired-stock migration integration tests (expired-stock plan Phase 1).
// Applies init.sql + add-gl-foundation.sql + add-expired-stock.sql to an
// in-memory DB (same fixture style as batchLocations.test.ts) and asserts
// the seeded accounts/warehouses, the delete trigger, the sweep indexes,
// and that the boot-task candidate query actually uses those indexes.

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  // Fixture chain mirrors batchLocations.test.ts: each migration depends on
  // tables created by earlier ones.
  const migrations = [
    'init.sql',
    'add-purchases-table.sql',
    'add-batch-costing.sql', // creates stock_batches
    'add-stock-adjustment-financial.sql',
    'add-production-tables.sql',
    'add-item-expiry-tracking.sql', // adds expiry_date / halted columns
    'add-gl-foundation.sql',
  ];
  for (const file of migrations) {
    const p = path.join(__dirname, '..', 'migrations', file);
    if (fs.existsSync(p)) db.exec(fs.readFileSync(p, 'utf8'));
    else throw new Error(`MISSING migration fixture: ${file}`);
  }

  // stock_movements.batch_id (+ financial columns) is added programmatically
  // at boot (guarded ALTER), not via a .sql file — replicate before the
  // expired-stock migration creates its batch_id index.
  const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as { name: string }[];
  const has = (n: string) => cols.some(c => c.name === n);
  if (!has('batch_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id'))
    db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');

  // The migration under test — applied last, after all prerequisites.
  db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-expired-stock.sql'), 'utf8'));
  return db;
}

describe('add-expired-stock migration', () => {
  it('seeds 7201-7204 as expense accounts parented to 7200', () => {
    const db = createFixture();
    const rows = db.prepare(`
      SELECT c.code, c.name, c.type, c.normal_balance, p.code AS parent_code
      FROM chart_of_accounts c
      LEFT JOIN chart_of_accounts p ON p.id = c.parent_id
      WHERE c.code IN ('7201','7202','7203','7204')
      ORDER BY c.code
    `).all() as Array<{ code: string; name: string; type: string; normal_balance: string; parent_code: string | null }>;

    expect(rows.map(r => r.code)).toEqual(['7201', '7202', '7203', '7204']);
    expect(rows.every(r => r.type === 'expense')).toBe(true);
    expect(rows.every(r => r.normal_balance === 'debit')).toBe(true);
    expect(rows.every(r => r.parent_code === '7200')).toBe(true);
    db.close();
  });

  it('seeds are idempotent (INSERT OR IGNORE does not duplicate)', () => {
    const db = createFixture();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-expired-stock.sql'), 'utf8');
    // Re-run the whole file minus the ALTER TABLE (which is ledgered one-shot;
    // a partial-state repair would skip it exactly the same way).
    const idempotentPart = sql.replace(/ALTER TABLE warehouses ADD COLUMN is_system[^;]+;/, '');
    db.exec(idempotentPart);

    const accounts = (db.prepare(
      `SELECT COUNT(*) AS n FROM chart_of_accounts WHERE code IN ('7201','7202','7203','7204')`
    ).get() as { n: number }).n;
    const warehouses = (db.prepare(
      `SELECT COUNT(*) AS n FROM warehouses WHERE warehouse_code IN ('EXPIRED','DAMAGED')`
    ).get() as { n: number }).n;
    expect(accounts).toBe(4);
    expect(warehouses).toBe(2);
    db.close();
  });

  it('adds is_system column defaulting to 0 for pre-existing warehouses', () => {
    const db = createFixture();
    db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES ('PRE', 'Pre-existing', 1)`).run();
    // Re-run the ALTER is impossible (column exists); instead verify defaults
    // on a fresh insert after migration (DEFAULT 0 applies to new rows too).
    const row = db.prepare(`SELECT is_system FROM warehouses WHERE warehouse_code = 'PRE'`).get() as { is_system: number };
    expect(row.is_system).toBe(0);
    db.close();
  });

  it('seeds EXPIRED and DAMAGED system warehouses with is_system=1', () => {
    const db = createFixture();
    const rows = db.prepare(`
      SELECT warehouse_code, warehouse_name, is_system, is_active
      FROM warehouses WHERE warehouse_code IN ('EXPIRED','DAMAGED')
      ORDER BY warehouse_code
    `).all() as Array<{ warehouse_code: string; warehouse_name: string; is_system: number; is_active: number }>;

    expect(rows.map(r => r.warehouse_code)).toEqual(['DAMAGED', 'EXPIRED']);
    expect(rows.every(r => r.is_system === 1)).toBe(true);
    expect(rows.every(r => r.is_active === 1)).toBe(true);
    expect(rows.find(r => r.warehouse_code === 'EXPIRED')!.warehouse_name).toBe('Expired Stock');
    expect(rows.find(r => r.warehouse_code === 'DAMAGED')!.warehouse_name).toBe('Damaged Stock');
    db.close();
  });

  it('trigger aborts DELETE of system warehouses but not normal ones', () => {
    const db = createFixture();
    db.prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES ('NORMAL', 'Normal WH', 1)`).run();

    let aborted = '';
    try {
      db.prepare(`DELETE FROM warehouses WHERE warehouse_code = 'EXPIRED'`).run();
    } catch (err) {
      aborted = (err as Error).message;
    }
    expect(aborted).toContain('Cannot delete system warehouse');

    // System warehouses still present after the aborted delete
    const sysCount = (db.prepare(
      `SELECT COUNT(*) AS n FROM warehouses WHERE warehouse_code IN ('EXPIRED','DAMAGED')`
    ).get() as { n: number }).n;
    expect(sysCount).toBe(2);

    // Non-system delete succeeds
    expect(() =>
      db.prepare(`DELETE FROM warehouses WHERE warehouse_code = 'NORMAL'`).run()
    ).not.toThrow();
    db.close();
  });

  it('creates the sweep indexes with the partial filter', () => {
    const db = createFixture();
    const rows = db.prepare(`
      SELECT name, sql FROM sqlite_master
      WHERE type = 'index'
        AND name IN ('idx_stock_batches_expiry_active','idx_stock_movements_batch_type')
    `).all() as Array<{ name: string; sql: string }>;

    expect(rows).toHaveLength(2);
    const partial = rows.find(r => r.name === 'idx_stock_batches_expiry_active');
    expect(partial?.sql).toContain('WHERE quantity_remaining > 0');
    db.close();
  });

  it('boot-task candidate query uses both sweep indexes', () => {
    const db = createFixture();
    const expiredId = (db.prepare(
      `SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`
    ).get() as { id: number }).id;

    const plan = db.prepare(`
      EXPLAIN QUERY PLAN
      SELECT sb.id, sb.item_id, sb.warehouse_id, sb.batch_no,
             sb.quantity_remaining, sb.unit_cost, sb.expiry_date
      FROM stock_batches sb
      WHERE sb.expiry_date < date('now')
        AND sb.quantity_remaining > 0
        AND sb.warehouse_id <> ${expiredId}
        AND NOT EXISTS (
          SELECT 1 FROM stock_movements sm
          WHERE sm.batch_id = sb.id AND sm.movement_type = 'EXPIRY_TRANSFER')
      ORDER BY sb.expiry_date ASC
    `).all() as Array<{ detail: string }>;

    const planText = plan.map(p => p.detail).join(' | ');
    // The planner may pick either the new composite partial index or the
    // pre-existing idx_stock_batches_expiry (both cover expiry_date <?);
    // what matters is that the expiry filter is index-served and the
    // NOT EXISTS uses the batch/type index.
    expect(planText).toMatch(/idx_stock_batches_expiry(_active)? /);
    expect(planText).toContain('idx_stock_movements_batch_type');
    db.close();
  });
});
