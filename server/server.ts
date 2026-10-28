import fs from 'fs';
import dotenv from 'dotenv';
dotenv.config();
import { Server } from 'http';
import { applyPendingMigrations } from './src/config/database';
// Must stay above the `app` import: app.ts builds the route tree against the
// migrated schema. Only CommonJS emit makes statement order between imports
// significant, so reordering these lines silently boots without a schema.
applyPendingMigrations();
import app from './src/app';
import db, { dbSeedReady, dbPath } from './src/config/database';
import settingsController from './src/controllers/settingsController';
import logger from './src/utils/logger';
import { disposeLogger } from './src/services/activityLogger';
import { startBackupScheduler } from './src/services/backupService';
import { runExpiryDetection } from './src/boot/expiryDetection';
import { getLocalIP } from './src/utils/localNetwork';
import { startParentWatchdog } from './src/utils/parentWatchdog';

const PORT = parseInt(process.env.PORT || '3011', 10);
const HOST = process.env.BIND_ADDRESS || process.env.HOST || '127.0.0.1';
const PORT_FILE = process.env.PORT_FILE;
const PID_FILE = process.env.PID_FILE;

let server: Server;

/** Packaged builds run with cwd elsewhere; the launcher reads these files. */
function writeRuntimeFile(filePath: string, value: string): void {
  const tmp = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, value, { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(tmp, filePath);
}

function removeRuntimeFile(filePath: string | undefined): void {
  if (!filePath) return;
  try {
    fs.unlinkSync(filePath);
  } catch {
    // Already removed (or never written).
  }
}

function cleanupRuntimeFiles(): void {
  removeRuntimeFile(PORT_FILE);
  removeRuntimeFile(PID_FILE);
}

if (PID_FILE) {
  try {
    writeRuntimeFile(PID_FILE, String(process.pid));
  } catch (error) {
    logger.error('Failed to write PID_FILE:', error);
  }
}

settingsController.initializeDefaults();
startBackupScheduler();

// Startup validation: check required env vars.
// DEFAULT_ADMIN_PASSWORD is only needed when the admin row is first created;
// database.ts enforces it (and the password policy) at that point, so it does
// not have to stay on disk after a packaged install's first boot.
const requiredEnvVars = ['JWT_SECRET'];
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
    cleanupRuntimeFiles();
    db.close();
    process.exit(exitCode || 1);
  }, SHUTDOWN_TIMEOUT_MS);

  // Server may not be bound yet if a signal lands before the seed gate opens.
  server?.close(() => {
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
      cleanupRuntimeFiles();
      logger.info('Graceful shutdown complete');
      process.exit(exitCode);
    } catch (err) {
      logger.error('Error during graceful shutdown:', err);
      cleanupRuntimeFiles();
      process.exit(exitCode || 1);
    }
  });
}

// Packaged builds pass the Flutter app's pid; exit if it is force-quit.
startParentWatchdog(() => gracefulExit(0));

// Async seed gate (spec 2.1): the admin user is hashed off the event
// loop — hold the bind until the row exists so early logins can't race it.
void dbSeedReady.then(async () => {
  // Expired-stock boot task (plan Phase 2): migrations (including the
  // EXPIRED warehouse seed) have run inside `import db from
  // './src/config/database'`, and dbSeedReady guarantees the admin user
  // exists. Runs synchronously (better-sqlite3) BEFORE listen, so no
  // request can observe a half-swept valuation; the delay is bounded by
  // the candidate count.
  try {
    const sweep = runExpiryDetection(db);
    if (sweep.failed > 0) {
      logger.warn(`Expiry detection: ${sweep.failed} batch(es) failed and will retry on next boot`);
    }
  } catch (err) {
    // Missing EXPIRED warehouse (migration bug) or a hard sweep failure:
    // log loud and continue serving — never block the app on this task.
    logger.error('Expiry detection boot task failed:', err);
  }

  server = app.listen(PORT, HOST, () => {
    const address = server.address();
    const actualPort = typeof address === 'object' && address !== null ? address.port : PORT;
    if (PORT_FILE) {
      try {
        writeRuntimeFile(PORT_FILE, String(actualPort));
      } catch (error) {
        logger.error('Failed to write PORT_FILE:', error);
      }
    }
    console.log('\n=================================');
    console.log('🚀 Mini ERP Server Started');
    console.log('=================================');
    console.log(`📍 Local:    http://127.0.0.1:${actualPort}`);
    if (HOST !== '127.0.0.1' && HOST !== 'localhost') {
      console.log(`📍 Network:  http://${getLocalIP()}:${actualPort}`);
    }
    console.log(`🗄️  Database: SQLite (${dbPath})`);
    console.log('=================================\n');
  });
});


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
