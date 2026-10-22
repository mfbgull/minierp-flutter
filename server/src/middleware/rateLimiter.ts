import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { Request, Response } from 'express';
import logger from '../utils/logger';

type SensitiveOperationPolicy = {
  readonly windowMs: number;
  readonly max: number;
  readonly logAction: string;
  readonly error: string;
};

function sensitiveOperationOptions(policy: SensitiveOperationPolicy) {
  return {
    windowMs: policy.windowMs,
    max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : policy.max,
    standardHeaders: true as const,
    legacyHeaders: false,
    skip: () => process.env.NODE_ENV === 'development',
    handler: (req: Request, res: Response) => {
      logger.warn(`[Rate Limit] ${policy.logAction} for IP: ${req.ip}`);
      res.status(429).json({
        error: policy.error,
        retryAfter: Math.ceil(policy.windowMs / 1000),
      });
    },
  };
}

/**
 * Rate limiter for authentication endpoints
 * Limits: 5 requests per 15 minutes per IP
 * Disabled in development to avoid blocking local testing
 */
export const authLimiter = rateLimit({
  ...sensitiveOperationOptions({
    windowMs: 15 * 60 * 1000,
    max: 5,
    logAction: 'Login attempts exceeded',
    error: 'Too many login attempts. Please try again later.',
  }),
  keyGenerator: (req: Request) => {
    return ipKeyGenerator(req.ip || '');
  }
});

/**
 * Stricter rate limiter for password change operations
 * Disabled in development to avoid blocking local testing
 */
export const passwordChangeLimiter = rateLimit(sensitiveOperationOptions({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  logAction: 'Password change attempts exceeded',
  error: 'Too many password change attempts. Please try again later.',
}));

/**
 * General API rate limiter for all routes
 * Limits: 100 requests per minute per IP
 */
export const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: process.env.NODE_ENV === 'test' ? 999999 : 100,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req: Request) => {
    return (
      req.path === '/health' ||
      process.env.NODE_ENV === 'test' ||
      process.env.NODE_ENV === 'development'
    );
  },
  handler: (req: Request, res: Response) => {
    logger.warn(`[Rate Limit] API requests exceeded for IP: ${req.ip}`);
    res.status(429).json({
      error: 'Too many requests. Please slow down.',
      retryAfter: Math.ceil(60)
    });
  }
});

/**
 * Shut down rate limiter stores to release timers (used in test teardown).
 *
 * rateLimit() returns a RateLimitRequestHandler, which does not expose the
 * backing store even though the RateLimit instance has one. Only MemoryStore
 * implements shutdown(), so that is the only method required here.
 */
type LimiterWithStore = {
  store?: { shutdown?: () => void };
};

export function shutdownRateLimiters() {
  // MemoryStore exposes a shutdown() method that clears the interval
  const stores = [apiLimiter, authLimiter, passwordChangeLimiter, sensitiveOperationLimiter];
  for (const limiter of stores) {
    const store = (limiter as LimiterWithStore).store;
    if (store && typeof store.shutdown === 'function') {
      store.shutdown();
    }
  }
}

/**
 * Aggressive rate limiter for sensitive operations
 * (e.g., data exports, bulk operations)
 * Disabled in development
 */
export const sensitiveOperationLimiter = rateLimit(sensitiveOperationOptions({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  logAction: 'Sensitive operation rate limit exceeded',
  error: 'Too many requests for this operation. Please try again later.',
}));
