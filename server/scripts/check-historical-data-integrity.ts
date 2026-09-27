/**
 * Historical data-integrity scanner (audit-remediation task 30).
 *
 * Report-only by design. The database is opened read-only, wrapped in
 * SQLite's query-only mode, and scanned inside a consistent read transaction.
 * No repair mode is exposed until the generated report has been reviewed and a
 * backup has been created.
 *
 * Usage:
 *   npm run data:integrity
 *   npm run data:integrity -- /path/to/erp.db
 */
import path from 'path';
import Database from 'better-sqlite3';
import { scanHistoricalDataIntegrity } from './historical-data-integrity';

function resolveDatabasePath(): string {
  const argumentPath = process.argv[2];
  if (argumentPath) return path.resolve(argumentPath);

  const configuredDatabasePath = process.env.DATABASE_PATH;
  const databaseDirectory = configuredDatabasePath || path.join(__dirname, '../database');
  return path.join(databaseDirectory, 'erp.db');
}

let db: Database.Database | undefined;
try {
  const databasePath = resolveDatabasePath();
  db = new Database(databasePath, { readonly: true, fileMustExist: true });
  db.pragma('query_only = 1');

  const report = scanHistoricalDataIntegrity(db);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = report.summary.total > 0 ? 1 : 0;
} catch (error: unknown) {
  const message = error instanceof Error ? error.message : 'Unknown scanner error';
  process.stderr.write(`Historical data-integrity scan failed: ${message}\n`);
  process.exitCode = 1;
} finally {
  db?.close();
}
