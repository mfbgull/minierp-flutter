import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';

/**
 * Test fixtures that need the real production schema.
 *
 * WHY THIS EXISTS
 * 24 test files each maintained their own hand-written MIGRATIONS array. That
 * duplicated list is why no migration could be added without editing 24 files,
 * which blocked DB-002 write-time prevention (docs/bugs.md BUG-005).
 *
 * A generated .sql list does NOT fix it. Replaying the .sql files alone fails:
 * inline fn.* migrations create tables and columns that later .sql files depend
 * on (add-bom-tables needs item_id, add-search-indexes needs main.quotations,
 * add-expired-stock needs batch_id). A .sql-only schema is broken, not merely
 * incomplete. See docs/test-migration-order.ts.
 *
 * WHY THIS CLONES INSTEAD OF RE-BOOTING
 * Re-requiring config/database under jest.resetModules() does yield the right
 * schema, but it re-runs the whole boot: the async admin seed, the 4150 guard,
 * the balance assertion. Deleting the temp dir at teardown races that in-flight
 * seed, whose failure path is process.exit(1). Cloning the schema out of the
 * already-migrated test database avoids all of those side effects.
 *
 * The schema comes from the real migration runner, not from a list here, so
 * adding a migration needs no test change.
 *
 * Data is deliberately NOT copied: fixtures want an empty database.
 */

const open: Database.Database[] = [];
let cachedSql: string[] | null = null;

/** Captured once per test file; the boot runs the full migration sequence. */
function productionSchemaSql(): string[] {
  if (cachedSql !== null) return cachedSql;
  const migrated = migratedDb();
  const rows = migrated
    .prepare(
      `SELECT sql FROM sqlite_master
        WHERE sql IS NOT NULL
          AND name NOT LIKE 'sqlite_%'
          AND type IN ('table','index','trigger','view')
        ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1
                           WHEN 'view' THEN 2 ELSE 3 END, name`,
    )
    .all() as Array<{ sql: string }>;
  cachedSql = rows.map((r) => r.sql);
  return cachedSql;
}

/**
 * Tables whose rows are static reference data seeded by the migrations, not
 * business records a test creates.
 *
 * Only these are ever copied. Transactional and mutable data - invoices,
 * payments, journal lines, stock movements, ledger entries - is deliberately
 * excluded: copying it would give a "fresh" fixture pre-existing history and
 * quietly invalidate any test that counts rows or sums balances.
 */
const REFERENCE_TABLES = ['chart_of_accounts'] as const;

function migratedDb(): Database.Database {
  // Lazy require so importing this module does not itself trigger a boot.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return require('../../config/database').default as Database.Database;
}

function copyReferenceRows(from: Database.Database, to: Database.Database): void {
  for (const table of REFERENCE_TABLES) {
    const columns = (from.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>).map(
      (c) => c.name,
    );
    if (columns.length === 0) continue;
    const rows = from.prepare(`SELECT ${columns.join(', ')} FROM ${table}`).all() as Array<
      Record<string, unknown>
    >;
    if (rows.length === 0) continue;
    const placeholders = columns.map(() => '?').join(', ');
    const insert = to.prepare(
      `INSERT OR IGNORE INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})`,
    );
    for (const row of rows) insert.run(...columns.map((c) => row[c]));
  }
}

export interface FixtureOptions {
  /**
   * Copy the migrations' seeded reference rows (currently chart_of_accounts)
   * into the fixture. Off by default, so the base behaviour stays schema-only.
   *
   * Needed by anything that posts to the ledger: accounting code resolves
   * accounts by code and aborts when a required one is absent.
   */
  reference?: boolean;
}

export function seedCustomers(db: Database.Database, count = 3): void {
  const insert = db.prepare(
    `INSERT INTO customers
       (id, customer_code, customer_name, current_balance, credit_balance)
     VALUES (?, ?, ?, 0, 0)`
  );
  db.transaction(() => {
    for (let index = 1; index <= count; index += 1) {
      insert.run(index, `SEED-${index}`, `Seed Customer ${index}`);
    }
  })();
}

export function seedHistoricalLedger(db: Database.Database): void {
  const customer = db.prepare(
    `INSERT INTO customers
       (id, customer_code, customer_name, current_balance, credit_balance)
     VALUES (?, ?, ?, 0, 0)`
  );
  const ledger = db.prepare(
    `INSERT INTO customer_ledger
       (customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const grants: Array<[number, number[]]> = [
    [1, [450.20, 1000]],
    [12, [1000, 900, 500]],
    [13, [700, 500]],
    [14, [600, 600]],
    [15, [600, 600, 550, 550]],
  ];
  const refunds = new Map<number, number>([[1, 1200], [12, 2300], [13, 400], [15, 550]]);
  db.transaction(() => {
    for (const [customerId, amounts] of grants) {
      customer.run(customerId, `HIST-${customerId}`, `Historical Customer ${customerId}`);
      let balance = 0;
      for (const [index, amount] of amounts.entries()) {
        balance = Math.round((balance - amount) * 100) / 100;
        const date = `2026-09-0${index + 1}`;
        ledger.run(customerId, date, 'RETURN', `RET-${customerId}-${index}`,
          0, amount, balance, `${date} 10:00:00`);
      }
      const refund = refunds.get(customerId);
      if (refund !== undefined) {
        balance = Math.round((balance + refund) * 100) / 100;
        ledger.run(customerId, '2026-09-12', 'REFUND', `PAY-SEED-${customerId}`,
          refund, 0, balance, '2026-09-12 10:00:00');
      }
      if (customerId === 15) {
        for (const [index, amount] of [1200, 600].entries()) {
          balance = Math.round((balance - amount) * 100) / 100;
          ledger.run(customerId, '2026-09-13', 'CREDIT_OFFSET', `OFF-15-${index}`,
            0, amount, balance, `2026-09-13 1${index}:00:00`);
        }
      }
    }
  })();
}

/** An isolated, empty database with the production schema. Cheap; DDL replay. */
export function createFixtureDb(options: FixtureOptions = {}): Database.Database {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-fixture-'));
  const db = new Database(path.join(dir, 'erp.db'));
  db.pragma('foreign_keys = ON');
  for (const sql of productionSchemaSql()) db.exec(sql);
  if (options.reference === true) copyReferenceRows(migratedDb(), db);
  open.push(db);
  return db;
}

/** Close every fixture and delete its temp directory. Call from afterAll. */
export function cleanupFixtureDbs(): void {
  while (open.length > 0) {
    const db = open.pop();
    if (db === undefined) continue;
    const dir = path.dirname(db.name);
    try {
      db.close();
    } catch {
      // Already closed.
    }
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch {
      // Best effort: a leftover temp dir is not worth failing a test over.
    }
  }
}
