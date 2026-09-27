/**
 * Migration checksum validation (audit-remediation task 37).
 *
 * runLedgered stamps every applied migration row with the sha256[:16] of its
 * file (or 'inline' for in-memory fns) but never compared it on later boots,
 * so an edited historical migration went undetected. These tests cover the
 * verification pass:
 *   a) a clean ledger — matching hashes plus 'inline' rows — verifies OK;
 *   b) an applied migration file edited afterwards is detected, and the boot
 *      aborts with an actionable remediation message;
 *   c) detection never writes to or destroys the database;
 *   d) edge cases: 'inline' rows, a file deleted after applying, and a
 *      brand-new database with no ledger table;
 *   e) the real ledger against the real migrations directory verifies
 *      cleanly — the no-false-positive guarantee, since every suite in the
 *      repo boots this module.
 *
 * No real file under src/migrations is ever touched: every scenario uses a
 * throwaway temp dir plus an in-memory database, cleaned up in finally blocks
 * so the tree stays byte-identical even if an assertion fails mid-way.
 */
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';

import Database from 'better-sqlite3';
import db, { MIGRATIONS_DIR, verifyMigrationChecksums } from '../config/database';

// schema_migrations has exactly this shape (config/database.ts ensureMigrationsTable).
const SCHEMA_MIGRATIONS_DDL = `CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL,
  checksum TEXT NOT NULL
)`;

/** Independent re-derivation of checksumOfFile(): sha256, first 16 hex chars. */
const sha16 = (absPath: string): string =>
  crypto.createHash('sha256').update(fs.readFileSync(absPath)).digest('hex').slice(0, 16);

/** In-memory ledger + throwaway migrations dir. Never touches src/migrations. */
const scratchLedger = (): { dir: string; ledger: Database.Database } => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-checksum-'));
  const ledger = new Database(':memory:');
  ledger.exec(SCHEMA_MIGRATIONS_DDL);
  return { dir, ledger };
};

/** Record an applied migration row the way both runLedgered insert paths do. */
const record = (ledger: Database.Database, filename: string, checksum: string): void => {
  ledger
    .prepare('INSERT INTO schema_migrations (filename, applied_at, checksum) VALUES (?, ?, ?)')
    .run(filename, new Date().toISOString(), checksum);
};

/** Run a verifier call that must fail, returning its message (unknown -> string). */
const captureFailureMessage = (fn: () => void): string => {
  try {
    fn();
  } catch (err: unknown) {
    return err instanceof Error ? err.message : String(err);
  }
  throw new Error('expected verifyMigrationChecksums to throw, but it did not');
};

describe('migration checksum validation (audit task 37)', () => {
  it('a) a clean ledger — matching hashes plus inline rows — verifies without error', () => {
    const { dir, ledger } = scratchLedger();
    try {
      fs.writeFileSync(path.join(dir, 'add-foo.sql'), '-- v1\n');
      fs.writeFileSync(path.join(dir, 'add-bar.sql'), '-- v1\n');
      record(ledger, 'add-foo.sql', sha16(path.join(dir, 'add-foo.sql')));
      record(ledger, 'add-bar.sql', sha16(path.join(dir, 'add-bar.sql')));
      record(ledger, 'fn.runFooMigration', 'inline'); // inline fn: no file on disk
      expect(() => verifyMigrationChecksums(ledger, dir)).not.toThrow();
    } finally {
      ledger.close();
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('b) an applied migration edited afterwards fails the boot with an actionable message', () => {
    const { dir, ledger } = scratchLedger();
    try {
      const file = path.join(dir, 'add-invoice-returns.sql');
      fs.writeFileSync(file, 'CREATE TABLE a (id INTEGER);\n');
      const recorded = sha16(file);
      record(ledger, 'add-invoice-returns.sql', recorded);

      // Untampered boot is still clean — the check is not hypersensitive.
      expect(() => verifyMigrationChecksums(ledger, dir)).not.toThrow();

      // The historical migration is edited after it was applied.
      fs.appendFileSync(file, 'CREATE TABLE b (id INTEGER);\n');
      const current = sha16(file);
      expect(current).not.toBe(recorded);

      const message = captureFailureMessage(() => verifyMigrationChecksums(ledger, dir));
      // Names the offending file and shows both checksums.
      expect(message).toContain("FATAL: migration 'add-invoice-returns.sql' was modified after it was applied.");
      expect(message).toContain(`recorded checksum: ${recorded}`);
      expect(message).toContain(`current checksum:  ${current}`);
      // Remediation (required behaviour #3): restore OR add a new migration — never reset.
      expect(message).toContain('restore the original file');
      expect(message).toContain('create a NEW migration');
      expect(message).toContain('Do NOT reset');
    } finally {
      ledger.close();
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('c) detection never writes to or destroys the database', () => {
    const { dir, ledger } = scratchLedger();
    try {
      fs.writeFileSync(path.join(dir, 'add-goods.sql'), '-- v1\n');
      // A real-looking hash that cannot match the file content: a ledger that
      // was already tampered before this boot.
      record(ledger, 'add-goods.sql', '0123456789abcdef');

      const rowsBefore = JSON.stringify(
        ledger.prepare('SELECT * FROM schema_migrations ORDER BY filename').all()
      );
      const schemaBefore = JSON.stringify(
        ledger.prepare("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name").all()
      );
      const versionBefore = ledger.pragma('user_version', { simple: true }) as number;

      expect(() => verifyMigrationChecksums(ledger, dir)).toThrow();

      // No auto-repair, no drop/recreate: the ledger row and the schema are intact.
      expect(JSON.stringify(ledger.prepare('SELECT * FROM schema_migrations ORDER BY filename').all())).toBe(rowsBefore);
      expect(JSON.stringify(ledger.prepare("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name").all())).toBe(schemaBefore);
      expect(ledger.pragma('user_version', { simple: true }) as number).toBe(versionBefore);
      // No transaction was left open for the caller to commit.
      expect(ledger.inTransaction).toBe(false);
    } finally {
      ledger.close();
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('d) edge cases: inline rows skip, a deleted applied file warns, no ledger table is a no-op', () => {
    // 1. 'inline' rows (in-memory fns) are skipped, never reported as a mismatch.
    const inline = scratchLedger();
    try {
      record(inline.ledger, 'fn.runAnything', 'inline');
      expect(() => verifyMigrationChecksums(inline.ledger, inline.dir)).not.toThrow();
    } finally {
      inline.ledger.close();
      fs.rmSync(inline.dir, { recursive: true, force: true });
    }

    // 2. A real hash was recorded, but the file has since been deleted. The
    //    applied schema is still internally consistent, so this warns rather
    //    than aborting the boot (a content *edit* is what aborts).
    const deleted = scratchLedger();
    try {
      record(deleted.ledger, 'add-removed.sql', 'abcdef0123456789');
      expect(() => verifyMigrationChecksums(deleted.ledger, deleted.dir)).not.toThrow();
    } finally {
      deleted.ledger.close();
      fs.rmSync(deleted.dir, { recursive: true, force: true });
    }

    // 3. Brand-new database with no schema_migrations at all: nothing to verify.
    const fresh = new Database(':memory:');
    try {
      expect(() => verifyMigrationChecksums(fresh, os.tmpdir())).not.toThrow();
    } finally {
      fresh.close();
    }
  });

  it('e) the real ledger against the real migrations directory verifies cleanly (no false positives)', () => {
    // Every other suite in the repo boots database.ts, so a false positive
    // here would break the whole suite. The shared test database was migrated
    // by this very jest run from the real files, so every file-backed row must
    // still match its recorded hash and every 'inline' row must skip.
    const rows = db.prepare('SELECT filename, checksum FROM schema_migrations').all() as {
      filename: string;
      checksum: string;
    }[];
    expect(rows.length).toBeGreaterThan(40); // the full chain registered
    // The check must actually exercise real files, not only 'inline' rows.
    expect(rows.filter((r) => r.checksum !== 'inline').length).toBeGreaterThan(0);
    expect(() => verifyMigrationChecksums(db, MIGRATIONS_DIR)).not.toThrow();
  });
});
