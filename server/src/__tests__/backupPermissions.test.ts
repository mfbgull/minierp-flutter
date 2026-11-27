/**
 * BK-extra (audit/FINDINGS-STATUS.md): a backup is a full copy of the books.
 *
 * `VACUUM INTO` writes the backup with the process umask, so the dump inherits
 * whatever that is — under a permissive umask (root, or a user running with
 * umask 000) the copy of the database, its uploads snapshot and the whole
 * backup directory can be readable by every account on the machine. The
 * database itself is no wider than that, but a backup is a second full copy
 * that retention leaves on disk for weeks and that operators copy to other
 * drives, so it must not be the weakest copy.
 *
 * This pins the group/other permission bits only. The owner keeps full access,
 * and the group keeps the same access it has on the database file, so the
 * service can still prune and read what it wrote.
 *
 * Scope note: encryption is NOT covered here and is NOT implemented; whether
 * backups must be encrypted at rest is an open product decision, recorded in
 * audit/DECISIONS.md.
 */
import fs from 'fs';
import { BACKUP_DIR, runBackup } from '../services/backupService';

/** True when the group/other bits allow a read (or more) by another account. */
function readableByOthers(stat: fs.Stats): boolean {
  // S_IRGRP=0o040, S_IROTH=0o004; a write or exec grant implies they can read too.
  return (stat.mode & 0o044) !== 0;
}

describe('BK-extra: a backup is not readable by other accounts', () => {
  it('writes the copy, its uploads snapshot and the backup dir without group/other read', () => {
    const target = runBackup({ trigger: 'manual' });
    expect(target).not.toBeNull();
    const backupPath = target as string;
    const snapshot = backupPath.replace(/\.db$/, '.uploads');

    const offenders: string[] = [];
    for (const p of [BACKUP_DIR, backupPath, snapshot]) {
      if (!fs.existsSync(p)) continue;
      const stat = fs.statSync(p);
      if (readableByOthers(stat)) {
        offenders.push(`${p} mode=${(stat.mode & 0o777).toString(8)}`);
      }
    }

    expect(offenders).toEqual([]);
  });
});
