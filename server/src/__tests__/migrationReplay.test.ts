
import fs from 'fs';
import os from 'os';
import path from 'path';

/**
 * Migration replay suite (audit-remediation task 2.6 / financial-test-invariants).
 * Boots the real ledgered migration path twice against the same database and
 * asserts zero errors + identical sqlite_master after the second boot.
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

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const dbModuleNS = require('../config/database');
    const dbModule = dbModuleNS.default as import('better-sqlite3').Database;

    const fingerprint = (): string => JSON.stringify(
      dbModule.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all()
    );
    const appliedCount = (): number =>
      (dbModule.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n;

    const first = fingerprint();
    const firstApplied = appliedCount();
    expect(firstApplied).toBeGreaterThan(40); // full chain registered

    // Second boot of the same process = every runLedgered call skips (recorded).
    // Force a "second boot" by clearing require cache and re-importing.
    jest.resetModules();
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const db2NS = require('../config/database');
    const db2 = db2NS.default as import('better-sqlite3').Database;

    const second = JSON.stringify(
      db2.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all()
    );

    expect(second).toBe(first);
    // Ledger unchanged — nothing re-executed or double-recorded
    expect((db2.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n).toBe(firstApplied);

    // Let each boot's fire-and-forget bcrypt seed settle before teardown.
    await Promise.all([dbModuleNS.dbSeedReady, db2NS.dbSeedReady]);

    // Close the database before cleanup: on some filesystems (e.g. NTFS
    // mounts) rmSync cannot delete WAL/SHM files held open by better-sqlite3,
    // which made this suite fail with ENOTEMPTY although all assertions
    // had passed. Close BOTH boots' connections — the first import's handle
    // is just as live as the second's.
    try { dbModule.close(); } catch { /* already closed */ }
    try { db2.close(); } catch { /* already closed */ }
    fs.rmSync(dir, { recursive: true, force: true });
    process.env.DATABASE_PATH = savedPath;
  });
});