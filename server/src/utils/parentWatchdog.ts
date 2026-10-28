import logger from './logger';

const CHECK_INTERVAL_MS = 5000;

/** True when the pid exists. EPERM means it exists but belongs to another user. */
export function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === 'EPERM';
  }
}

/**
 * Packaged desktop builds start the server as a child of the Flutter app.
 * If the app is force-quit (or crashes) the child would be orphaned and keep
 * the SQLite WAL open. When MINIERP_PARENT_PID is set, exit gracefully once
 * that process disappears.
 */
export function startParentWatchdog(onOrphaned: () => void): void {
  const raw = process.env.MINIERP_PARENT_PID;
  if (!raw) return;

  const parentPid = Number(raw);
  if (!Number.isInteger(parentPid) || parentPid <= 0) {
    logger.warn('MINIERP_PARENT_PID is not a valid pid; parent watchdog disabled');
    return;
  }

  const timer = setInterval(() => {
    if (isProcessAlive(parentPid)) return;
    clearInterval(timer);
    logger.warn(`Parent process ${parentPid} is gone; shutting down`);
    onOrphaned();
  }, CHECK_INTERVAL_MS);
  timer.unref();
}
