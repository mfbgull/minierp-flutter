"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = globalTeardown;
// Global teardown — runs after all test suites
const logger_1 = __importDefault(require("../utils/logger"));
const rateLimiter_1 = require("../middleware/rateLimiter");
async function globalTeardown() {
    // Shut down rate limiter intervals
    (0, rateLimiter_1.shutdownRateLimiters)();
    // Close all Winston transports to release file handles
    logger_1.default.close();
}
//# sourceMappingURL=teardown.js.map