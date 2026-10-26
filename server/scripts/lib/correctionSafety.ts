/**
 * Fail-closed authorization gate for historical financial correction scripts.
 *
 * Context: `apply-customer15-correction.ts` and `rollback-customer15-correction.ts`
 * were committed without any safety surface. Both resolve their database through
 * `config/database`, which falls back to `defaultDbDir()` — i.e. the LIVE
 * `server/database/erp.db`. Running either by accident rewrites customer 15's
 * financial history. Nothing below changes the correction's accounting logic;
 * it only decides whether the script is allowed to proceed at all.
 *
 * Four independent gates, each fail-closed:
 *   1. AUTHORIZATION   — an exact, non-default token must be present in the env.
 *   2. IDENTITY        — the resolved database path must be stated explicitly, so
 *                        the operator cannot rely on an implicit default.
 *   3. LIVE EXCLUSION  — targeting the live database is refused unless it is
 *                        separately enabled AND the live file's SHA-256 matches
 *                        a checksum the caller supplies, which forces the
 *                        operator to have measured the live file first.
 *   4. APPLY FLAG      — without `--apply` the script exits before touching data.
 *
 * Preconditions and idempotency are the caller's concern and are checked by each
 * script after this gate passes.
 */
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { defaultDbDir } from '../../src/utils/serverRoot';

/** The live database, resolved the same way the scripts resolve their own. */
export const LIVE_DB_PATH: string = path.join(defaultDbDir(), 'erp.db');

/** Deliberately awkward: a caller must be told this value, not discover it. */
const AUTH_TOKEN = 'CUSTOMER15-CORRECTION-AUTHORIZED';

export interface GateResult {
  /** Absolute path of the database this invocation would modify. */
  dbPath: string;
  /** True when that path is the live database. */
  isLive: boolean;
}

function fail(scriptName: string, msg: string, extra?: string): never {
  console.error(`\nREFUSED: ${scriptName}\n\n  ${msg}\n`);
  if (extra) console.error(`${extra}\n`);
  process.exit(1);
}

export function sha256File(filePath: string): string {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function targetsLiveDatabase(dbPath: string): boolean {
  if (dbPath === path.resolve(LIVE_DB_PATH)) return true;
  const live = fs.statSync(LIVE_DB_PATH, { bigint: true, throwIfNoEntry: false });
  if (!live) return false;
  // stat follows directory/file symlinks; device and inode also identify hardlinks.
  const target = fs.statSync(dbPath, { bigint: true, throwIfNoEntry: false });
  return live.dev === target?.dev && live.ino === target?.ino;
}

/**
 * Runs every gate and returns the resolved target, or exits non-zero.
 * Call this before opening any write.
 */
export function assertCorrectionAuthorized(scriptName: string): GateResult {
  // ── Gate 1: authorization token ──────────────────────────────────────────
  if (process.env.CORRECTION_AUTHORIZED !== AUTH_TOKEN) {
    fail(
      scriptName,
      'Missing or incorrect CORRECTION_AUTHORIZED. This script rewrites recorded financial history.',
      `Required environment:\n  CORRECTION_AUTHORIZED=${AUTH_TOKEN}`,
    );
  }

  // ── Gate 2: the target database must be stated explicitly ────────────────
  const dbDir = process.env.DATABASE_PATH;
  if (!dbDir) {
    fail(
      scriptName,
      'DATABASE_PATH is not set, so the target database is implicit. State it explicitly.',
      `Example (isolated copy):\n  DATABASE_PATH=/tmp/scratch npx ts-node --transpile-only scripts/${scriptName}.ts --apply`,
    );
  }
  const dbPath = path.join(path.resolve(dbDir), 'erp.db');
  if (!fs.existsSync(dbPath)) {
    fail(scriptName, `No database file at ${dbPath}`);
  }
  const isLive = targetsLiveDatabase(dbPath);

  // ── Gate 3: the live database needs a separate, checksum-bound override ──
  if (isLive) {
    if (process.env.CORRECTION_ALLOW_LIVE !== '1') {
      fail(
        scriptName,
        'This would modify the LIVE database.',
        `Live path: ${LIVE_DB_PATH}\nTo proceed deliberately you must ALSO set:\n` +
          `  CORRECTION_ALLOW_LIVE=1\n  CORRECTION_LIVE_SHA256=$(sha256sum ${LIVE_DB_PATH} | cut -d' ' -f1)`,
      );
    }
    const expected = process.env.CORRECTION_LIVE_SHA256;
    if (!expected) {
      fail(
        scriptName,
        'CORRECTION_LIVE_SHA256 is required when targeting the live database. Measure it first.',
        `  CORRECTION_LIVE_SHA256=$(sha256sum ${LIVE_DB_PATH} | cut -d' ' -f1)`,
      );
    }
    const actual = sha256File(dbPath);
    if (actual !== expected) {
      fail(
        scriptName,
        'Live database checksum does not match CORRECTION_LIVE_SHA256. It changed since you measured it.',
        `  expected ${expected}\n  actual   ${actual}`,
      );
    }
    console.warn(
      `\n*** WARNING: ${scriptName} is about to modify the LIVE database ${LIVE_DB_PATH} ***\n` +
        `*** checksum verified: ${actual}\n`,
    );
  }

  // ── Gate 4: writes require --apply ───────────────────────────────────────
  if (!process.argv.includes('--apply')) {
    console.error(
      `\nREFUSED: ${scriptName}\n\n  --apply was not passed, so no data was modified.\n` +
        `  Target would have been: ${dbPath}${isLive ? '  (LIVE)' : '  (isolated)'}\n\n` +
        `  Re-run with --apply once the preconditions and the approval are in place.\n`,
    );
    process.exit(2);
  }

  return { dbPath, isLive };
}
