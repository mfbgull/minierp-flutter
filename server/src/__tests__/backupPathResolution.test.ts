/**
 * Backup/uploads path resolution (backupService.ts).
 *
 * Regression guard for backups being written to server/dist/database/backups/
 * instead of server/database/backups/. The cause was a fixed __dirname '..'
 * count: correct under ts-node (src/services/), one level too high once
 * compiled to dist/src/services/. The failure is silent — the backup succeeds
 * and integrity_check passes, it just lands outside the canonical directory that
 * retention, restore docs and any external sync actually look at.
 *
 * Tests run from src/, where the old code resolved correctly, so this asserts
 * the invariant rather than reproducing the bad value: both directories must be
 * anchored on the package root, and neither may land under a dist/ subtree.
 */
import fs from 'fs';
import path from 'path';
import { dbDir } from '../config/database';
import { BACKUP_DIR, UPLOADS_DIR } from '../services/backupService';

function nearestPackageRoot(from: string): string {
  let dir = from;
  for (let i = 0; i < 10; i += 1) {
    if (fs.existsSync(path.join(dir, 'package.json'))) return dir;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  throw new Error('no package.json found above ' + from);
}

describe('backup path resolution', () => {
  const serverRoot = nearestPackageRoot(__dirname);

  it('anchors uploads on the server root, not on __dirname arithmetic', () => {
    if (process.env.UPLOADS_DIR) return; // explicit override wins
    expect(UPLOADS_DIR).toBe(path.join(serverRoot, 'uploads'));
  });

  it('nests backups inside the directory the database actually opened', () => {
    if (process.env.BACKUP_DIR) return;
    expect(BACKUP_DIR).toBe(path.join(dbDir, 'backups'));
  });

  it('never resolves either directory into a dist/ subtree', () => {
    for (const dir of [BACKUP_DIR, UPLOADS_DIR]) {
      expect(path.relative(serverRoot, dir).split(path.sep)).not.toContain('dist');
    }
  });
});
