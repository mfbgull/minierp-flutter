import dotenv from 'dotenv';
dotenv.config();
import { Server } from 'http';
import app from './src/app';
import db from './src/config/database';
import settingsController from './src/controllers/settingsController';
import logger from './src/utils/logger';
import { disposeLogger } from './src/services/activityLogger';
import { startBackupScheduler } from './src/services/backupService';

const PORT = parseInt(process.env.PORT || '3011', 10);
const HOST = process.env.BIND_ADDRESS || process.env.HOST || '127.0.0.1';

settingsController.initializeDefaults();
startBackupScheduler();

// Startup validation: check required env vars
const requiredEnvVars = ['JWT_SECRET'];
if (process.env.NODE_ENV === 'production') {
  requiredEnvVars.push('DEFAULT_ADMIN_PASSWORD');
}
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingEnvVars.length > 0) {
  logger.error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
  process.exit(1);
}

const SHUTDOWN_TIMEOUT_MS = 3000;

/**
 * Graceful shutdown (audit-remediation task 6.1 / DR-03):
 *   stop accepting connections (bounded) → flush queued activity logs →
 *   checkpoint WAL → close DB → exit.
 */
function gracefulExit(exitCode: number): void {
  let timedOut = false;
  const forceTimer = setTimeout(() => {
    timedOut = true;
    logger.warn('Graceful shutdown timeout — forcing exit');
    db.close();
    process.exit(exitCode || 1);
  }, SHUTDOWN_TIMEOUT_MS);

  server.close(() => {
    if (timedOut) return;
    clearTimeout(forceTimer);
    try {
      // Flush queued audit rows BEFORE closing the DB (task 4.7).
      // disposeLogger also stops the flush timer (task 9.5).
      disposeLogger();

      // Checkpoint the WAL so the main DB file is complete on disk
      db.pragma('wal_checkpoint(TRUNCATE)');
      // Task 8.8: refresh planner statistics before closing
      db.pragma('optimize');
      db.close();
      logger.info('Graceful shutdown complete');
      process.exit(exitCode);
    } catch (err) {
      logger.error('Error during graceful shutdown:', err);
      process.exit(exitCode || 1);
    }
  });
}

const server: Server = app.listen(PORT, HOST, () => {
  console.log('\n=================================');
  console.log('🚀 Mini ERP Server Started');
  console.log('=================================');
  console.log(`📍 Local:    http://localhost:${PORT}`);
  console.log(`📍 Network:  http://${getLocalIP()}:${PORT}`);
  console.log(`🗄️  Database: SQLite (./database/erp.db)`);
  console.log('=================================\n');
});

function getLocalIP(): string {
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

process.on('unhandledRejection', (reason: unknown) => {
  logger.error('Unhandled Rejection:', reason);
  gracefulExit(1);
});

process.on('uncaughtException', (error: Error) => {
  logger.error('Uncaught Exception:', error);
  gracefulExit(1);
});
