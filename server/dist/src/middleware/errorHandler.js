"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const logger_1 = __importDefault(require("../utils/logger"));
const apiResponse_1 = require("../utils/apiResponse");
function errorHandler(err, req, res, _next) {
    const status = err.status || 500;
    const message = err.message || 'Internal server error';
    logger_1.default.error('Unhandled error', {
        requestId: req.requestId,
        method: req.method,
        url: req.originalUrl || req.url,
        statusCode: status,
        error: message,
        stack: err.stack,
        userId: req.user?.id,
    });
    if (process.env.NODE_ENV === 'development') {
        res.status(status).json({
            success: false,
            error: {
                code: 'INTERNAL_ERROR',
                message,
                stack: err.stack,
            },
        });
    }
    else {
        (0, apiResponse_1.sendInternalError)(res);
    }
}
function notFoundHandler(req, res) {
    res.status(404).json({
        success: false,
        error: {
            code: 'NOT_FOUND',
            message: `Route not found: ${req.path}`,
        },
    });
}
exports.default = { errorHandler, notFoundHandler };
