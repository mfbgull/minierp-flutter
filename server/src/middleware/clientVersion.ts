import { NextFunction, Request, Response } from 'express';
import logger from '../utils/logger';

export const CLIENT_VERSION_HEADER = 'x-client-version';

/**
 * Minimum supported desktop-client version. A client below this still
 * works, but the server warns: a build older than this does not send the
 * Idempotency-Key that the financial writes now require, so its retries
 * cannot be replayed.
 *
 * Warn only — the server never rejects on version. Bump when a new
 * mandatory client behaviour ships.
 */
export const MIN_CLIENT_VERSION = '0.2.0';

/** Parse `major.minor.patch[-pre]` into comparable numbers. */
function parseVersion(value: string): [number, number, number] | null {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(value.trim());
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

/** True when `version` is strictly below `minimum`. */
export function isVersionBelow(version: string, minimum: string): boolean {
  const a = parseVersion(version);
  const b = parseVersion(minimum);
  if (!a || !b) return false; // Unparseable → do not warn on a guess.
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] < b[i];
  }
  return false;
}

/**
 * Log the client version on every API request and warn when it is below
 * the minimum. Warn only: the desktop client ships before or with the
 * server mandate (see audit/DECISIONS.md), so an old build is expected
 * briefly and must not be locked out.
 */
export function observeClientVersion(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const raw = req.headers[CLIENT_VERSION_HEADER];
  const version = Array.isArray(raw) ? raw[0] : raw;

  if (typeof version === 'string' && version.length > 0) {
    logger.debug('[client-version] request', {
      version,
      method: req.method,
      path: req.originalUrl.split('?')[0],
    });
    if (isVersionBelow(version, MIN_CLIENT_VERSION)) {
      logger.warn('[client-version] below minimum supported version', {
        version,
        minimum: MIN_CLIENT_VERSION,
        method: req.method,
        path: req.originalUrl.split('?')[0],
        userId: (req as Request & { user?: { id: number } }).user?.id ?? null,
      });
      res.setHeader('X-Min-Client-Version', MIN_CLIENT_VERSION);
    }
  }
  next();
}
