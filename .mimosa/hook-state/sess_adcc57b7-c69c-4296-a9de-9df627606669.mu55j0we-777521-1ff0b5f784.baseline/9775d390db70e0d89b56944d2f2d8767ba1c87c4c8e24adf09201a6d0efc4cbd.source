
import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';

/**
 * Task 7.6: backup produced while WAL holds committed txns passes
 * integrity_check and contains those rows on restore into a fresh file.
 */
describe('backup WAL durability (task 7.6)', () => {
  it('VACUUM INTO captures committed WAL transactions; copy passes integrity_check', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bk-wal-'));
    const main = path.join(dir, 'erp.db');
    const db = new Database(main);
    db.pragma('journal_mode = WAL');
    db.pragma('synchronous = NORMAL');

    // Committed txn that lives in the -wal file (not yet checkpointed)
    db.exec(`CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)`);
    db.prepare(`INSERT INTO t (v) VALUES ('committed-in-wal')`).run();

    // VACUUM INTO from the live connection
    const target = path.join(dir, 'backup.db');
    db.exec(`VACUUM INTO '${target}'`);

    // integrity check on the copy
    const copy = new Database(target, { readonly: true });
    expect(copy.pragma('integrity_check', { simple: true })).toBe('ok');

    // Row present when the copy is opened as a live database (restore = use the file)
    const r2 = new Database(target, { readonly: true });
    const row = r2.prepare('SELECT v FROM t').get() as { v: string } | undefined;
    r2.close(); copy.close(); db.close();
    expect(row?.v).toBe('committed-in-wal');

    fs.rmSync(dir, { recursive: true, force: true });
  });
});
