
import fs from 'fs';
import os from 'os';
import path from 'path';

/**
 * Migration replay suite (audit-remediation task 2.6 / financial-test-invariants).
 * Runs the real ledgered boot path twice against the same database and asserts
 * zero errors + identical sqlite_master after the second boot.
 */
describe('migration replay (task 2.6)', () => {
  it('boots the ledger twice with identical schema and no re-execution', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-replay-'));
    // This suite points the process-global DB path at a throwaway dir and
    // deletes it at the end. Restore it afterwards, await the async admin
    // seed, and close BOTH connections before cleanup. createDefaultUser()
    // hashes the admin password fire-and-forget (~300ms); if the test tears
    // the database down first, that deferred insert lands on a closed/deleted
    // handle, its catch calls process.exit(1), and the jest worker dies —
    // taking every suite scheduled after this one down with it.
    const savedPath = process.env.DATABASE_PATH;
    process.env.DATABASE_PATH = dir;
    process.env.NODE_ENV = 'test';
    process.env.JWT_SECRET = 'replay-test-secret';
    process.env.DEFAULT_ADMIN_PASSWORD = 'replay-admin-pass';

    type DbNs = {
      default: import('better-sqlite3').Database;
      applyPendingMigrations: () => void;
      dbSeedReady: Promise<void>;
    };

    // A boot = fresh module graph + the explicit migration entrypoint. Without
    // resetModules() the first boot would silently reuse whichever connection
    // setup.ts already opened, so both boots must build their own.
    const boot = async (): Promise<DbNs> => {
      jest.resetModules();
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const ns = require('../config/database') as DbNs;
      ns.applyPendingMigrations();
      await ns.dbSeedReady;
      return ns;
    };

    const fingerprintOf = (db: import('better-sqlite3').Database): string =>
      JSON.stringify(
        db.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all()
      );
    const appliedCount = (db: import('better-sqlite3').Database): number =>
      (db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n;

    const boot1 = await boot();
    const first = fingerprintOf(boot1.default);
    const firstApplied = appliedCount(boot1.default);
    expect(firstApplied).toBeGreaterThan(40); // full chain registered

    const boot2 = await boot();
    expect(fingerprintOf(boot2.default)).toBe(first);
    // Ledger unchanged — nothing re-executed or double-recorded
    expect(appliedCount(boot2.default)).toBe(firstApplied);

    // Close the database before cleanup: on some filesystems (e.g. NTFS
    // mounts) rmSync cannot delete WAL/SHM files held open by better-sqlite3,
    // which made this suite fail with ENOTEMPTY although all assertions
    // had passed. Close BOTH boots' connections — the first import's handle
    // is just as live as the second's.
    try { boot1.default.close(); } catch { /* already closed */ }
    try { boot2.default.close(); } catch { /* already closed */ }
    fs.rmSync(dir, { recursive: true, force: true });
    process.env.DATABASE_PATH = savedPath;
  });
});
