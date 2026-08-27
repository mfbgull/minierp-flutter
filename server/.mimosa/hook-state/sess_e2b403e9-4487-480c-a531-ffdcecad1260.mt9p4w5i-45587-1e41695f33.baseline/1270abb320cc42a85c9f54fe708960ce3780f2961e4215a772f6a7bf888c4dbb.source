
import fs from 'fs';
import os from 'os';
import path from 'path';

/**
 * Migration replay suite (audit-remediation task 2.6 / financial-test-invariants).
 * Boots the real ledgered migration path twice against the same database and
 * asserts zero errors + identical sqlite_master after the second boot.
 */
describe('migration replay (task 2.6)', () => {
  it('boots the ledger twice with identical schema and no re-execution', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-replay-'));
    process.env.DATABASE_PATH = dir;
    process.env.NODE_ENV = 'test';
    process.env.JWT_SECRET = 'replay-test-secret';
    process.env.DEFAULT_ADMIN_PASSWORD = 'replay-admin-pass';

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const dbModule = require('../config/database').default as import('better-sqlite3').Database;

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
    const db2 = (require('../config/database').default) as import('better-sqlite3').Database;

    const second = JSON.stringify(
      db2.prepare(`SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all()
    );

    expect(second).toBe(first);
    // Ledger unchanged — nothing re-executed or double-recorded
    expect((db2.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n).toBe(firstApplied);
    fs.rmSync(dir, { recursive: true, force: true });
  });
});