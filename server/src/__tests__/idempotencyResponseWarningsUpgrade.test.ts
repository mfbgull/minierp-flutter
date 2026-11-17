/**
 * BUG-013 F5 / migration 128 — retry-after-partial-apply and pre-128 upgrade.
 *
 * CHARACTERIZATION of the migration-128 recovery path. Migration 128 adds
 * `idempotency_keys.response_warnings` (TEXT, nullable) so an idempotency
 * replay of a LOST response returns the same stock warnings the first caller
 * was sent. The value cannot be recomputed (no bin `status_override` history is
 * retained), so it must be stored beside the key.
 *
 * The step must be RETRY-SAFE. A bare `ALTER TABLE ... ADD COLUMN` in a .sql
 * file is not: if the process dies after the ALTER but before the ledger
 * INSERT, the column exists with no ledger row, the next boot re-runs the file,
 * SQLite answers `duplicate column name`, and runLedgered's catch calls
 * process.exit(1) — the server cannot boot. This spec drives the crash window
 * on purpose and asserts the guarded `fn.` form recovers.
 *
 * Probe only: it does not assert business rules beyond the migration contract.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';

jest.setTimeout(60000);

interface DatabaseModule {
  default: Database.Database;
  applyPendingMigrations: () => void;
  dbSeedReady: Promise<void>;
}

const MIGRATION_KEY = 'fn.runIdempotencyResponseWarningsMigration';
const COLUMN = 'response_warnings';

let dir: string;
let previousPath: string | undefined;
let loaded: DatabaseModule | undefined;

async function loadDatabaseModule(): Promise<DatabaseModule> {
  jest.resetModules();
  loaded = (await import('../config/database')) as unknown as DatabaseModule;
  return loaded;
}

function hasColumn(db: Database.Database, table: string, column: string): boolean {
  const cols = db.pragma(`table_info('${table}')`) as Array<{ name: string }>;
  return cols.some((c) => c.name === column);
}

function ledgerRow(db: Database.Database, filename: string): { filename: string } | undefined {
  return db.prepare('SELECT filename FROM schema_migrations WHERE filename = ?').get(filename) as
    | { filename: string }
    | undefined;
}

/** Rebuild the pre-128 world on a chain-applied DB: no column, no ledger row. */
function simulatePre128(db: Database.Database): void {
  db.exec(`ALTER TABLE idempotency_keys DROP COLUMN ${COLUMN}`);
  db.prepare('DELETE FROM schema_migrations WHERE filename = ?').run(MIGRATION_KEY);
}

beforeEach(() => {
  previousPath = process.env.DATABASE_PATH;
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mig128-'));
  process.env.DATABASE_PATH = dir;
  loaded = undefined;
});

afterEach(() => {
  try {
    loaded?.default.close();
  } catch {
    // already closed
  }
  process.env.DATABASE_PATH = previousPath;
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('migration 128 — idempotency response_warnings', () => {
  it('adds the column and records the ledger row on a fresh chain', async () => {
    const mod = await loadDatabaseModule();
    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    expect(hasColumn(mod.default, 'idempotency_keys', COLUMN)).toBe(true);
    expect(ledgerRow(mod.default, MIGRATION_KEY)).toBeDefined();
  });

  it('RECOVERS when the process dies after the ALTER but before the ledger row', async () => {
    const mod = await loadDatabaseModule();
    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    // The exact crash window: the column landed, the ledger row did not.
    simulatePre128(mod.default);
    expect(hasColumn(mod.default, 'idempotency_keys', COLUMN)).toBe(false);
    expect(ledgerRow(mod.default, MIGRATION_KEY)).toBeUndefined();

    // The retry must not throw and must restore the ledger row.
    expect(() => mod.applyPendingMigrations()).not.toThrow();
    await mod.dbSeedReady;
    expect(hasColumn(mod.default, 'idempotency_keys', COLUMN)).toBe(true);
    expect(ledgerRow(mod.default, MIGRATION_KEY)).toBeDefined();
  });

  it('RED CONTROL: the unguarded form fails in the same crash window', async () => {
    const mod = await loadDatabaseModule();
    mod.applyPendingMigrations();
    await mod.dbSeedReady;
    simulatePre128(mod.default);

    // What the old .sql file did: an unconditional ALTER. Here the column is
    // already present, which is exactly the crashed state, so it must fail.
    mod.default.exec(`ALTER TABLE idempotency_keys ADD COLUMN ${COLUMN} TEXT`);

    // Second attempt — the retry the boot would perform — is the failure.
    expect(() =>
      mod.default.exec(`ALTER TABLE idempotency_keys ADD COLUMN ${COLUMN} TEXT`),
    ).toThrow(/duplicate column name/i);
  });

  it('is idempotent — a second apply adds no ledger row and keeps one column', async () => {
    const mod = await loadDatabaseModule();
    mod.applyPendingMigrations();
    await mod.dbSeedReady;
    const before = (
      mod.default.prepare('SELECT COUNT(*) AS c FROM schema_migrations').get() as { c: number }
    ).c;

    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    const after = (
      mod.default.prepare('SELECT COUNT(*) AS c FROM schema_migrations').get() as { c: number }
    ).c;
    expect(after).toBe(before);
    const names = (mod.default.pragma("table_info('idempotency_keys')") as Array<{ name: string }>)
      .map((c) => c.name)
      .filter((n) => n === COLUMN);
    expect(names).toHaveLength(1);
  });

  it('replays a PRE-128 row (no stored warnings) as an empty list', async () => {
    const mod = await loadDatabaseModule();
    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    // A key claimed before the column existed: value is absent, not '[]'.
    mod.default
      .prepare(
        'INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, completed_at) VALUES (?,?,?,?,CURRENT_TIMESTAMP)',
      )
      .run('legacy-key', 'invoice_create', 'hash-1', 1);

    const { findIdempotencyWarnings } = (await import('../utils/idempotency')) as unknown as {
      findIdempotencyWarnings: (db: Database.Database, scope: string, key: string) => string[];
    };
    expect(findIdempotencyWarnings(mod.default, 'invoice_create', 'legacy-key')).toEqual([]);
  });
});
