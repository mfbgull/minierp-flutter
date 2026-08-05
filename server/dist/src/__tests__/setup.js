"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// Test environment setup — runs before all test suites
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const os_1 = __importDefault(require("os"));
// 1. Set test-specific environment variables BEFORE any module imports
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-jwt-secret-for-integration-tests-only';
process.env.JWT_EXPIRY = '24h';
process.env.DEFAULT_ADMIN_PASSWORD = 'test-admin-password-secure-2026';
process.env.TEST_ADMIN_PASSWORD = 'test-admin-password-secure-2026';
// 2. Suppress express-rate-limit IPv6 console.error BEFORE importing rate limiter
const originalConsoleError = console.error;
console.error = (...args) => {
    const msg = String(args[0]);
    if (msg.includes('ERR_ERL_KEY_GEN_IPV6')) {
        return;
    }
    originalConsoleError.apply(console, args);
};
// 3. Create isolated temp database for tests (never touch production DB)
const testDbDir = fs_1.default.mkdtempSync(path_1.default.join(os_1.default.tmpdir(), 'minierp-test-'));
process.env.DATABASE_PATH = testDbDir;
// 4. Clean up temp DB after all tests complete
const cleanupTestDb = () => {
    try {
        fs_1.default.rmSync(testDbDir, { recursive: true, force: true });
    }
    catch {
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
// 5. Clean up rate limiter intervals and logger after all tests in this worker
const rateLimiter_1 = require("../middleware/rateLimiter");
const logger_1 = __importDefault(require("../utils/logger"));
afterAll(async () => {
    try {
        (0, rateLimiter_1.shutdownRateLimiters)();
        logger_1.default.close();
    }
    catch (err) {
        // Ignore cleanup errors
    }
});
//# sourceMappingURL=setup.js.map