import fs from 'fs';
import path from 'path';

/**
 * The server package root, found by walking up to the nearest package.json.
 *
 * A fixed __dirname '..' count is layout-dependent: these modules run from
 * src/ under ts-node but from dist/src/ once compiled, so the same count lands
 * one directory too high or too low depending on the build. That silently
 * pointed at a stale repo-root database/ instead of server/database/.
 */
export function findServerRoot(): string {
  let dir = __dirname;
  for (let i = 0; i < 10; i += 1) {
    if (fs.existsSync(path.join(dir, 'package.json'))) return dir;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  throw new Error(`FATAL: no package.json found above ${__dirname}; cannot resolve the server root`);
}

/** Default database directory: <server-root>/database. */
export function defaultDbDir(): string {
  return path.join(findServerRoot(), 'database');
}

/** Default uploads directory: <server-root>/uploads. */
export function defaultUploadsDir(): string {
  return path.join(findServerRoot(), 'uploads');
}

/**
 * Uploads directory actually used at runtime. Installed packages keep the
 * server tree read-only (Program Files, /usr/lib, an AppImage mount), so the
 * launcher redirects uploads into a writable per-user data directory.
 */
export function resolveUploadsDir(): string {
  return process.env.UPLOADS_DIR || defaultUploadsDir();
}

/** Log directory: LOG_DIR override, else <cwd>/logs. */
export function resolveLogDir(): string {
  return process.env.LOG_DIR || path.join(process.cwd(), 'logs');
}
