import { createRequire } from 'module';
import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';

interface VerifyResult {
  ok: boolean;
  message?: string;
}

const requireFromHere = createRequire(__filename);
const { verifySnapshotAt } = requireFromHere('../../scripts/lib/backup-verify.js') as {
  verifySnapshotAt: (snapshotPath: string) => VerifyResult;
};

describe('verifySnapshotAt', () => {
  let dir = '';

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'backup-verify-'));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('accepts a valid database', () => {
    const snapshot = path.join(dir, 'valid.db');
    const db = new Database(snapshot);
    db.exec('CREATE TABLE sample (id INTEGER PRIMARY KEY)');
    db.close();

    expect(verifySnapshotAt(snapshot)).toEqual({ ok: true });
  });

  it('reports a missing snapshot', () => {
    const result = verifySnapshotAt(path.join(dir, 'missing.db'));

    expect(result.ok).toBe(false);
    expect(result.message).toMatch(/integrity_check could not run/);
  });

  it('reports a non-database file', () => {
    const snapshot = path.join(dir, 'garbage.db');
    fs.writeFileSync(snapshot, 'this is not a sqlite database');

    const result = verifySnapshotAt(snapshot);

    expect(result.ok).toBe(false);
    expect(result.message).toMatch(/integrity_check could not run/);
  });
});
