/**
 * Path resolution for the database and uploads directories (utils/serverRoot).
 *
 * Regression guard for the two layout bugs this replaced:
 *  - `../../../database` from src/ resolves to a stale repo-root database/
 *    (user_version 95, last activity 2026-09-12) instead of server/database/,
 *    so a dev-mode script could silently read or write the wrong database;
 *  - `'../../database'` from a compiled dist/src/services/ landed in
 *    server/dist/database/, putting backups and employee uploads outside the
 *    canonical directories.
 *
 * Tests run from src/, which is exactly the layout where the old arithmetic
 * picked the wrong directory, so these assertions do fail against it.
 */
import fs from 'fs';
import path from 'path';
import { findServerRoot, defaultDbDir, defaultUploadsDir } from '../utils/serverRoot';

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

describe('server path resolution', () => {
  const serverRoot = nearestPackageRoot(__dirname);

  it('anchors on the server package root', () => {
    expect(findServerRoot()).toBe(serverRoot);
  });

  it('resolves the database directory inside the server package', () => {
    expect(defaultDbDir()).toBe(path.join(serverRoot, 'database'));
  });

  it('resolves the uploads directory inside the server package', () => {
    expect(defaultUploadsDir()).toBe(path.join(serverRoot, 'uploads'));
  });

  it('never resolves either directory outside the server package', () => {
    for (const dir of [defaultDbDir(), defaultUploadsDir()]) {
      const rel = path.relative(serverRoot, dir);
      expect(rel.startsWith('..')).toBe(false);
    }
  });

  it('cannot select a repo-root database/ directory', () => {
    // <repo-root>/database — the stale copy the old '../../../database' hit.
    expect(defaultDbDir()).not.toBe(path.resolve(serverRoot, '..', 'database'));
  });
});
