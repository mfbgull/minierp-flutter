"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const app_1 = __importDefault(require("./src/app"));
const database_1 = __importDefault(require("./src/config/database"));
const settingsController_1 = __importDefault(require("./src/controllers/settingsController"));
const logger_1 = __importDefault(require("./src/utils/logger"));
const activityLogger_1 = require("./src/services/activityLogger");
const backupService_1 = require("./src/services/backupService");
const PORT = parseInt(process.env.PORT || '3011', 10);
const HOST = process.env.BIND_ADDRESS || process.env.HOST || '127.0.0.1';
settingsController_1.default.initializeDefaults();
(0, backupService_1.startBackupScheduler)();
// Startup validation: check required env vars
const requiredEnvVars = ['JWT_SECRET'];
if (process.env.NODE_ENV === 'production') {
    requiredEnvVars.push('DEFAULT_ADMIN_PASSWORD');
}
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingEnvVars.length > 0) {
    logger_1.default.error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
    process.exit(1);
}
const SHUTDOWN_TIMEOUT_MS = 3000;
/**
 * Graceful shutdown (audit-remediation task 6.1 / DR-03):
 *   stop accepting connections (bounded) → flush queued activity logs →
 *   checkpoint WAL → close DB → exit.
 */
function gracefulExit(exitCode) {
    let timedOut = false;
    const forceTimer = setTimeout(() => {
        timedOut = true;
        logger_1.default.warn('Graceful shutdown timeout — forcing exit');
        database_1.default.close();
        process.exit(exitCode || 1);
    }, SHUTDOWN_TIMEOUT_MS);
    server.close(() => {
        if (timedOut)
            return;
        clearTimeout(forceTimer);
        try {
            // Flush queued audit rows BEFORE closing the DB (task 4.7).
            // disposeLogger also stops the flush timer (task 9.5).
            (0, activityLogger_1.disposeLogger)();
            // Checkpoint the WAL so the main DB file is complete on disk
            database_1.default.pragma('wal_checkpoint(TRUNCATE)');
            // Task 8.8: refresh planner statistics before closing
            database_1.default.pragma('optimize');
            database_1.default.close();
            logger_1.default.info('Graceful shutdown complete');
            process.exit(exitCode);
        }
        catch (err) {
            logger_1.default.error('Error during graceful shutdown:', err);
            process.exit(exitCode || 1);
        }
    });
}
const server = app_1.default.listen(PORT, HOST, () => {
    console.log('\n=================================');
    console.log('🚀 Mini ERP Server Started');
    console.log('=================================');
    console.log(`📍 Local:    http://localhost:${PORT}`);
    console.log(`📍 Network:  http://${getLocalIP()}:${PORT}`);
    console.log(`🗄️  Database: SQLite (./database/erp.db)`);
    console.log('=================================\n');
});
function getLocalIP() {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                return net.address;
            }
        }
    }
    return '0.0.0.0';
}
process.on('SIGTERM', () => {
    console.log('SIGTERM received. Closing server...');
    gracefulExit(0);
});
process.on('SIGINT', () => {
    console.log('\nSIGINT received. Closing server...');
    gracefulExit(0);
});
process.on('SIGHUP', () => {
    console.log('SIGHUP received. Closing server...');
    gracefulExit(0);
});
process.on('unhandledRejection', (reason) => {
    logger_1.default.error('Unhandled Rejection:', reason);
    gracefulExit(1);
});
process.on('uncaughtException', (error) => {
    logger_1.default.error('Uncaught Exception:', error);
    gracefulExit(1);
});
//# sourceMappingURL=server.js.map