"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sensitiveOperationLimiter = exports.apiLimiter = exports.passwordChangeLimiter = exports.authLimiter = void 0;
exports.shutdownRateLimiters = shutdownRateLimiters;
const express_rate_limit_1 = __importStar(require("express-rate-limit"));
const logger_1 = __importDefault(require("../utils/logger"));
/**
 * Rate limiter for authentication endpoints
 * Limits: 5 requests per 15 minutes per IP
 * Disabled in development to avoid blocking local testing
 */
exports.authLimiter = (0, express_rate_limit_1.default)({
    windowMs: 15 * 60 * 1000,
    max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 5,
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => process.env.NODE_ENV === 'development',
    handler: (req, res) => {
        logger_1.default.warn(`[Rate Limit] Login attempts exceeded for IP: ${req.ip}`);
        res.status(429).json({
            error: 'Too many login attempts. Please try again later.',
            retryAfter: Math.ceil(15 * 60)
        });
    },
    keyGenerator: (req) => {
        return (0, express_rate_limit_1.ipKeyGenerator)(req.ip || '');
    }
});
/**
 * Stricter rate limiter for password change operations
 * Disabled in development to avoid blocking local testing
 */
exports.passwordChangeLimiter = (0, express_rate_limit_1.default)({
    windowMs: 60 * 60 * 1000, // 1 hour
    max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 3, // 3 attempts per hour
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => process.env.NODE_ENV === 'development',
    handler: (req, res) => {
        logger_1.default.warn(`[Rate Limit] Password change attempts exceeded for IP: ${req.ip}`);
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
exports.apiLimiter = (0, express_rate_limit_1.default)({
    windowMs: 60 * 1000,
    max: process.env.NODE_ENV === 'test' ? 999999 : 100,
    standardHeaders: true,
    legacyHeaders: false,
    skip: (req) => {
        return (req.path === '/health' ||
            process.env.NODE_ENV === 'test' ||
            process.env.NODE_ENV === 'development');
    },
    handler: (req, res) => {
        logger_1.default.warn(`[Rate Limit] API requests exceeded for IP: ${req.ip}`);
        res.status(429).json({
            error: 'Too many requests. Please slow down.',
            retryAfter: Math.ceil(60)
        });
    }
});
/** Shut down rate limiter stores to release timers (used in test teardown) */
function shutdownRateLimiters() {
    // MemoryStore exposes a shutdown() method that clears the interval
    const stores = [exports.apiLimiter, exports.authLimiter, exports.passwordChangeLimiter, exports.sensitiveOperationLimiter];
    for (const limiter of stores) {
        const store = limiter.store;
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
exports.sensitiveOperationLimiter = (0, express_rate_limit_1.default)({
    windowMs: 60 * 1000, // 1 minute
    max: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development' ? 999999 : 10, // 10 requests per minute
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => process.env.NODE_ENV === 'development',
    handler: (req, res) => {
        logger_1.default.warn(`[Rate Limit] Sensitive operation rate limit exceeded for IP: ${req.ip}`);
        res.status(429).json({
            error: 'Too many requests for this operation. Please try again later.',
            retryAfter: Math.ceil(60)
        });
    }
});
//# sourceMappingURL=rateLimiter.js.map