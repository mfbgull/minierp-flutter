"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const winston_1 = __importDefault(require("winston"));
const path_1 = __importDefault(require("path"));
const { combine, timestamp, json, errors, printf } = winston_1.default.format;
const logFormat = printf(({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level.toUpperCase()}]: ${message}`;
    if (Object.keys(metadata).length > 0) {
        msg += ` ${JSON.stringify(metadata)}`;
    }
    return msg;
});
const isTest = process.env.NODE_ENV === 'test';
const logger = winston_1.default.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    defaultMeta: {
        service: 'mini-erp-api',
        environment: process.env.NODE_ENV || 'development'
    },
    format: combine(timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }), errors({ stack: true }), json()),
    transports: isTest
        ? [new winston_1.default.transports.Console({ silent: true })]
        : [
            new winston_1.default.transports.Console({
                format: combine(timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }), logFormat)
            }),
            new winston_1.default.transports.File({
                filename: path_1.default.join(process.cwd(), 'logs', 'error.log'),
                level: 'error',
                maxsize: 5242880,
                maxFiles: 5
            }),
            new winston_1.default.transports.File({
                filename: path_1.default.join(process.cwd(), 'logs', 'combined.log'),
                maxsize: 5242880,
                maxFiles: 5
            })
        ],
    exitOnError: false
});
exports.default = logger;
