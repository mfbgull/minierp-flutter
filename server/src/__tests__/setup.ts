// Test environment setup — runs before all test suites
import path from 'path';
import fs from 'fs';

// 1. Set test-specific environment variables BEFORE any module imports
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-jwt-secret-for-integration-tests-only';
process.env.JWT_EXPIRY = '24h';
process.env.DEFAULT_ADMIN_PASSWORD = 'test-admin-password-secure-2026';
process.env.TEST_ADMIN_PASSWORD = 'test-admin-password-secure-2026';

// 2. Suppress express-rate-limit IPv6 console.error BEFORE importing rate limiter
const originalConsoleError = console.error;
console.error = (...args: unknown[]) => {
  const msg = String(args[0]);
  if (msg.includes('ERR_ERL_KEY_GEN_IPV6')) {
    return;
  }
  originalConsoleError.apply(console, args);
};

// 3. Create isolated temp database for tests (never touch production DB).
//
// Rooted PROJECT-LOCALLY rather than in os.tmpdir(): when the system disk
// filled up, the shell broker could not write its own logs and EVERY command
// failed — including the `rm` needed to recover. A runaway test run should
// consume a gitignored directory the agent can delete itself, not `/`.
// TEST_TMPDIR overrides the root (CI runners may prefer a bigger volume).
const testTmpRoot =
  process.env.TEST_TMPDIR || path.join(__dirname, '..', '..', '.tmp-test');
fs.mkdirSync(testTmpRoot, { recursive: true });

// Sweep leftovers from interrupted runs. Empty parent dirs occasionally
// outlive their afterAll (see the note below), so they accumulate ~1-2 per
// run; removing anything untouched for 2 hours bounds that without ever
// touching a concurrent run's live dirs.
const STALE_MS = 2 * 60 * 60 * 1000;
try {
  for (const entry of fs.readdirSync(testTmpRoot)) {
    if (!entry.startsWith('minierp-test-')) continue;
    const full = path.join(testTmpRoot, entry);
    try {
      if (Date.now() - fs.statSync(full).mtimeMs > STALE_MS) {
        fs.rmSync(full, { recursive: true, force: true });
      }
    } catch {
      // A live run may be using it; leave it alone.
    }
  }
} catch {
  // Unreadable temp root — mkdtemp below will surface the real error.
}

const testDbDir = fs.mkdtempSync(path.join(testTmpRoot, 'minierp-test-'));
process.env.DATABASE_PATH = testDbDir;

// 4. Clean up temp DB after all tests in this file complete.
// NOTE: `process.on('exit')` is unreliable under jest-worker — the worker is
// torn down without firing exit handlers, so every run leaked a minierp-test-*
// dir (~5GB/day). `afterAll` is a real Jest hook and always runs per file.
// This file runs once per test file via setupFilesAfterEnv, and each file gets
// its own temp dir + its own `db` singleton (Jest rebuilds the module registry
// per file, after this setup sets DATABASE_PATH), so deleting here can never
// break the next file in a reused worker.
const cleanupTestDb = () => {
  try {
    fs.rmSync(testDbDir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup errors
  }
};

// Backstop only: covers a run that is interrupted before afterAll fires.
// Does not fire on a normal jest-worker shutdown (see note above).
process.on('exit', cleanupTestDb);
process.on('SIGINT', () => {
  cleanupTestDb();
  process.exit(130);
});
process.on('SIGTERM', () => {
  cleanupTestDb();
  process.exit(143);
});

// 5. Apply schema, then gate the suites on the admin seed.
import { applyPendingMigrations, dbSeedReady } from '../config/database';

beforeAll(async () => {
  applyPendingMigrations();
  await dbSeedReady;
}, 15000);

// 6. Clean up rate limiter intervals and logger after all tests in this worker
import { shutdownRateLimiters } from '../middleware/rateLimiter';
import logger from '../utils/logger';
import { disposeLogger } from '../services/activityLogger';

afterAll(async () => {
  // Finish queued audit writes and stop their timer while the database and
  // logging transports are still available. Always remove the fixture files.
  try {
    disposeLogger();
  } finally {
    cleanupTestDb();
    try {
      shutdownRateLimiters();
      logger.close();
    } catch {
      // Ignore cleanup errors
    }
  }
});
