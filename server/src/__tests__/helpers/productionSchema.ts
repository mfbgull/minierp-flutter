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
  // Lazy require so importing this module does not itself trigger a boot.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const migrated = require('../../config/database').default as Database.Database;
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

/** An isolated, empty database with the production schema. Cheap; DDL replay. */
export function createFixtureDb(): Database.Database {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-fixture-'));
  const db = new Database(path.join(dir, 'erp.db'));
  db.pragma('foreign_keys = ON');
  for (const sql of productionSchemaSql()) db.exec(sql);
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
