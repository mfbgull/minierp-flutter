// Global teardown — runs after all test suites
import logger from '../utils/logger';
import { shutdownRateLimiters } from '../middleware/rateLimiter';

export default async function globalTeardown() {
  // Shut down rate limiter intervals
  shutdownRateLimiters();
  // Close all Winston transports to release file handles
  logger.close();
}
