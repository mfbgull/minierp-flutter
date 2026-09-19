// Test environment setup — runs before all test suites
import path from 'path';
import fs from 'fs';
import os from 'os';

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

// 3. Create isolated temp database for tests (never touch production DB)
const testDbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-test-'));
process.env.DATABASE_PATH = testDbDir;

// 4. Clean up temp DB after all tests complete
const cleanupTestDb = () => {
  try {
    fs.rmSync(testDbDir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup errors
  }
};

// Register cleanup on process exit
process.on('exit', cleanupTestDb);
process.on('SIGINT', () => {
  cleanupTestDb();
  process.exit(130);
});
process.on('SIGTERM', () => {
  cleanupTestDb();
  process.exit(143);
});

// 5. Async seed gate (spec 2.1): the admin user is bcrypt-hashed off the
// event loop now, so hold the suites until the seeded row is committed.
import { dbSeedReady } from '../config/database';

beforeAll(async () => {
  await dbSeedReady;
}, 15000);

// 6. Clean up rate limiter intervals and logger after all tests in this worker
import { shutdownRateLimiters } from '../middleware/rateLimiter';
import logger from '../utils/logger';

afterAll(async () => {
  try {
    shutdownRateLimiters();
    logger.close();
  } catch (err) {
    // Ignore cleanup errors
  }
});
