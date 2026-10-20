/**
 * DB-INIT: importing the database module must not apply migrations.
 *
 * A read-only A-J accounting verification imported `config/database` purely to
 * reuse the invariant collectors, and the import silently advanced the LIVE
 * database's user_version 103 -> 107. Reading money out of the books must never
 * be able to change the books.
 *
 * These tests pin the separation:
 *   - importing the module opens a connection and nothing else
 *   - applyPendingMigrations() is the explicit, opt-in write boundary
 *   - applying twice is a no-op
 *   - a tampered migration ledger fails loudly instead of booting anyway
 *
 * Every case runs against its own temp database; the live DB is never opened.
 * Modules load through `await import()` because a static import is hoisted and
 * cached, which would defeat jest.resetModules() between cases.
 */
import fs from 'fs';
import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';

jest.setTimeout(60000);

interface DatabaseModule {
  default: Database.Database;
  applyPendingMigrations: () => void;
  dbSeedReady: Promise<void>;
}

let dir: string;
let previousPath: string | undefined;
let loaded: DatabaseModule | undefined;

async function loadDatabaseModule(): Promise<DatabaseModule> {
  jest.resetModules();
  loaded = (await import('../config/database')) as unknown as DatabaseModule;
  return loaded;
}

function openRaw(): Database.Database {
  return new Database(path.join(dir, 'erp.db'), { readonly: true, fileMustExist: true });
}

function countTable(name: string): number {
  const raw = openRaw();
  try {
    return (
      raw.prepare("SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND name=?").get(name) as {
        c: number;
      }
    ).c;
  } finally {
    raw.close();
  }
}

function userVersion(): number {
  const raw = openRaw();
  try {
    return raw.pragma('user_version', { simple: true }) as number;
  } finally {
    raw.close();
  }
}

function countAppliedMigrations(mod: DatabaseModule): number {
  return (mod.default.prepare('SELECT COUNT(*) AS c FROM schema_migrations').get() as { c: number }).c;
}

beforeEach(() => {
  previousPath = process.env.DATABASE_PATH;
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dbinit-'));
  process.env.DATABASE_PATH = dir;
  loaded = undefined;
});

afterEach(() => {
  // Release the module's own handle so the temp dir can be removed.
  try {
    loaded?.default.close();
  } catch {
    // already closed, or never opened
  }
  loaded = undefined;
  if (previousPath === undefined) delete process.env.DATABASE_PATH;
  else process.env.DATABASE_PATH = previousPath;
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('database module initialization boundary', () => {
  it.each([undefined, 'admin123'])('does not seed an administrator with a missing or weak configured password (%s)', async (password) => {
    const previousPassword = process.env.DEFAULT_ADMIN_PASSWORD;
    if (password === undefined) delete process.env.DEFAULT_ADMIN_PASSWORD;
    else process.env.DEFAULT_ADMIN_PASSWORD = password;
    const mod = await loadDatabaseModule();
    const exitSpy = jest.spyOn(process, 'exit').mockImplementation(() => {
      throw new Error('Unsafe admin bootstrap refused');
    });

    try {
      expect(() => mod.applyPendingMigrations()).toThrow();
    } finally {
      await mod.dbSeedReady;
      exitSpy.mockRestore();
      if (previousPassword === undefined) delete process.env.DEFAULT_ADMIN_PASSWORD;
      else process.env.DEFAULT_ADMIN_PASSWORD = previousPassword;
    }
    expect(countTable('users')).toBe(0);
  });

  it('does NOT apply migrations merely by importing the module', async () => {
    const mod = await loadDatabaseModule();

    expect(mod.default.open).toBe(true);
    expect(countTable('schema_migrations')).toBe(0);
    expect(countTable('users')).toBe(0);
    expect(userVersion()).toBe(0);
  });

  it('applies the full migration set when applyPendingMigrations() is called', async () => {
    const mod = await loadDatabaseModule();

    expect(typeof mod.applyPendingMigrations).toBe('function');
    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    expect(countTable('schema_migrations')).toBe(1);
    expect(countTable('users')).toBe(1);
    expect(userVersion()).toBeGreaterThan(0);
    expect(mod.default.open).toBe(true);
  });

  it('is idempotent — a second call adds no new ledger rows', async () => {
    const mod = await loadDatabaseModule();

    mod.applyPendingMigrations();
    await mod.dbSeedReady;
    const first = countAppliedMigrations(mod);
    const firstVersion = userVersion();

    mod.applyPendingMigrations();
    await mod.dbSeedReady;

    expect(countAppliedMigrations(mod)).toBe(first);
    expect(userVersion()).toBe(firstVersion);
  });

  it('refuses to boot when a recorded migration checksum no longer matches', async () => {
    const first = await loadDatabaseModule();
    first.applyPendingMigrations();
    await first.dbSeedReady;
    first.default
      .prepare(
        "UPDATE schema_migrations SET checksum = 'tampered' WHERE filename = (SELECT filename FROM schema_migrations LIMIT 1)"
      )
      .run();
    first.default.close();
    loaded = undefined;

    const reopened = await loadDatabaseModule();
    // Import the logger the module already holds — importing it here (after
    // loadDatabaseModule, before any further reset) resolves the same cached
    // instance rather than a second copy the spy would not affect.
    const { default: logger } = (await import('../utils/logger')) as unknown as {
      default: { error: (...args: unknown[]) => void };
    };
    const exitSpy = jest.spyOn(process, 'exit').mockImplementation((code?: string | number | null) => {
      throw new Error(`process.exit(${String(code)})`);
    });
    const errorSpy = jest.spyOn(logger, 'error').mockImplementation(() => {});

    try {
      expect(() => reopened.applyPendingMigrations()).toThrow('process.exit');
      expect(errorSpy).toHaveBeenCalled();
    } finally {
      exitSpy.mockRestore();
      errorSpy.mockRestore();
    }
  });

  it('lets the invariant collectors be imported without migrating the database', async () => {
    await loadDatabaseModule();
    jest.resetModules();

    const invariants = (await import('./helpers/accountingInvariants')) as unknown as {
      expectAllInvariantsHold: (context: string) => void;
    };

    expect(typeof invariants.expectAllInvariantsHold).toBe('function');
    expect(countTable('schema_migrations')).toBe(0);
    expect(userVersion()).toBe(0);
  });
});
