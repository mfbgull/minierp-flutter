/**
 * D29 Option B (Gull, 2026-11-28): the database copy of a backup is
 * encrypted at rest.
 *
 * Option B wraps only the `.db` copy in an encrypted container after its
 * integrity check. The sibling uploads snapshot stays plain — that is the
 * balance Gull chose. Restore needs the passphrase, and losing the
 * passphrase loses every encrypted backup, so the runbook says so.
 *
 * What must hold:
 *   1. the file on disk is not a SQLite file (no `SQLite format 3` header),
 *      and the plaintext copy does not survive beside it;
 *   2. decrypting it with the key yields a database that passes
 *      `integrity_check` and holds the same tables as the live one;
 *   3. the wrong passphrase is refused and leaves no output file;
 *   4. with no key configured the backup stays plain — the old behaviour,
 *      so a deployment that has not set the key is never worse off;
 *   5. the uploads snapshot still pairs by name;
 *   6. a legacy plaintext backup still resolves, lists and deletes, so
 *      pre-encryption backups remain restorable.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import Database from 'better-sqlite3';
import db from '../config/database';
import {
  BACKUP_DIR,
  deleteBackupFile,
  listBackups,
  resolveBackupFilePath,
  runBackup,
  uploadsSnapshotPathFor,
} from '../services/backupService';
import {
  backupPassphrase,
  decryptFileSync,
  isEncryptedFileSync,
} from '../../scripts/lib/backup-crypto';

const SQLITE_MAGIC = 'SQLite format 3';

/** First 16 bytes of a file as text — enough to spot a SQLite header. */
function headerOf(file: string): string {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(16);
    fs.readSync(fd, buf, 0, 16, 0);
    return buf.toString('latin1');
  } finally {
    fs.closeSync(fd);
  }
}

describe('D29 option B: the database copy is encrypted at rest', () => {
  const configuredKey = process.env.BACKUP_ENCRYPTION_KEY;

  afterEach(() => {
    if (configuredKey === undefined) delete process.env.BACKUP_ENCRYPTION_KEY;
    else process.env.BACKUP_ENCRYPTION_KEY = configuredKey;
  });

  it('writes a file that is not a SQLite database', () => {
    const target = runBackup({ trigger: 'manual' });
    expect(target).not.toBeNull();
    const file = target as string;

    expect(path.basename(file)).toMatch(
      /^erp-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:-\d+)?\.db\.enc$/
    );
    expect(isEncryptedFileSync(file)).toBe(true);
    expect(headerOf(file)).not.toContain(SQLITE_MAGIC);
    // The plaintext copy must not survive next to the encrypted one.
    expect(fs.existsSync(file.slice(0, -'.enc'.length))).toBe(false);
  });

  it('decrypts back to a database that passes integrity_check with the same tables', () => {
    const target = runBackup({ trigger: 'manual' }) as string;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bk-dec-'));
    const out = path.join(dir, 'restored.db');
    try {
      decryptFileSync(target, out, backupPassphrase() as string);

      const restored = new Database(out, { readonly: true });
      expect(restored.pragma('integrity_check', { simple: true })).toBe('ok');
      const restoredTables = restored
        .prepare(`SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'table'`)
        .get() as { c: number };
      restored.close();

      const liveTables = db
        .prepare(`SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'table'`)
        .get() as { c: number };
      expect(restoredTables.c).toBe(liveTables.c);
      expect(restoredTables.c).toBeGreaterThan(10);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('refuses the wrong passphrase and leaves no output file', () => {
    const target = runBackup({ trigger: 'manual' }) as string;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bk-bad-'));
    const out = path.join(dir, 'restored.db');
    try {
      expect(() => decryptFileSync(target, out, 'not-the-key')).toThrow();
      expect(fs.existsSync(out)).toBe(false);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('falls back to a plain copy when no key is configured', () => {
    delete process.env.BACKUP_ENCRYPTION_KEY;
    const target = runBackup({ trigger: 'manual' });
    expect(target).not.toBeNull();
    const file = target as string;
    expect(path.basename(file)).toMatch(/\.db$/);
    expect(headerOf(file)).toContain(SQLITE_MAGIC);
  });

  it('pairs the uploads snapshot with the encrypted name', () => {
    const target = runBackup({ trigger: 'manual' }) as string;
    const snapshot = uploadsSnapshotPathFor(target);
    expect(snapshot).toBe(target.replace(/\.db\.enc$/, '.uploads'));
    expect(fs.existsSync(snapshot)).toBe(true);
  });

  it('still resolves, lists and deletes a legacy plaintext backup', () => {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    const legacyName = 'erp-2020-01-01T00-00-00.db';
    const legacy = path.join(BACKUP_DIR, legacyName);
    fs.writeFileSync(legacy, `${SQLITE_MAGIC}\0legacy-plaintext-backup`);

    expect(resolveBackupFilePath(legacyName)).toBe(legacy);
    expect(listBackups().some((b) => b.name === legacyName)).toBe(true);
    // The traversal guard still rejects anything that is not a generated name.
    expect(resolveBackupFilePath('../../erp.db')).toBeNull();
    // A name that matches but does not exist resolves to nothing.
    expect(resolveBackupFilePath('erp-2020-01-01T00-00-01.db.enc')).toBeNull();

    expect(deleteBackupFile(legacyName)).toBe(true);
    expect(fs.existsSync(legacy)).toBe(false);
  });
});
