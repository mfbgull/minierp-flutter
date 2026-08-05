"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestLogger = requestLogger;
exports.errorLogger = errorLogger;
const crypto_1 = require("crypto");
const logger_1 = __importDefault(require("../utils/logger"));
function generateRequestId() {
    return (0, crypto_1.randomUUID)();
}
function requestLogger(req, res, next) {
    const requestId = generateRequestId();
    const startTime = Date.now();
    req.requestId = requestId;
    const requestLog = {
        requestId,
        method: req.method,
        url: req.originalUrl || req.url,
        path: req.path,
        query: req.query,
        userAgent: req.get('user-agent'),
        ip: req.ip || req.connection?.remoteAddress,
        userId: req.user?.id
    };
    logger_1.default.info('Incoming request', requestLog);
    res.on('finish', () => {
        const duration = Date.now() - startTime;
        const responseLog = {
            ...requestLog,
            statusCode: res.statusCode,
            responseTime: duration
        };
        if (res.statusCode >= 400) {
            logger_1.default.warn('Request completed with error', responseLog);
        }
        else {
            logger_1.default.info('Request completed', responseLog);
        }
    });
    res.on('error', (error) => {
        const duration = Date.now() - startTime;
        logger_1.default.error('Request failed', {
            ...requestLog,
            statusCode: res.statusCode,
            responseTime: duration,
            error: error.message,
            stack: error.stack
        });
    });
    next();
}
function errorLogger(err, req, res, next) {
    const requestId = req.requestId || generateRequestId();
    logger_1.default.error('Unhandled error', {
        requestId,
        method: req.method,
        url: req.originalUrl || req.url,
        path: req.path,
        error: err.message,
        stack: err.stack,
        userId: req.user?.id
    });
    next(err);
}
//# sourceMappingURL=requestLogger.js.map