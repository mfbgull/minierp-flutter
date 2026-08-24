import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { Request, Response } from 'express';
import logger from '../utils/logger';

/**
 * Rate limiter for authentication endpoints
 * Limits: 5 requests per 15 minutes per IP
 * Disabled in development to avoid blocking local testing
 */
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 5,
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'development',
  handler: (req: Request, res: Response) => {
    logger.warn(`[Rate Limit] Login attempts exceeded for IP: ${req.ip}`);
    res.status(429).json({
      error: 'Too many login attempts. Please try again later.',
      retryAfter: Math.ceil(15 * 60)
    });
  },
  keyGenerator: (req: Request) => {
    return ipKeyGenerator(req.ip || '');
  }
});

/**
 * Stricter rate limiter for password change operations
 * Disabled in development to avoid blocking local testing
 */
export const passwordChangeLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 3, // 3 attempts per hour
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'development',
  handler: (req: Request, res: Response) => {
    logger.warn(`[Rate Limit] Password change attempts exceeded for IP: ${req.ip}`);
    res.status(429).json({
      error: 'Too many password change attempts. Please try again later.',
      retryAfter: Math.ceil(60 * 60)
    });
  }
});

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

/** Shut down rate limiter stores to release timers (used in test teardown) */
export function shutdownRateLimiters() {
  // MemoryStore exposes a shutdown() method that clears the interval
  const stores = [apiLimiter, authLimiter, passwordChangeLimiter, sensitiveOperationLimiter];
  for (const limiter of stores) {
    const store = (limiter as any).store;
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
export const sensitiveOperationLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 10, // 10 requests per minute
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'development',
  handler: (req: Request, res: Response) => {
    logger.warn(`[Rate Limit] Sensitive operation rate limit exceeded for IP: ${req.ip}`);
    res.status(429).json({
      error: 'Too many requests for this operation. Please try again later.',
      retryAfter: Math.ceil(60)
    });
  }
});
