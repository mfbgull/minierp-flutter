# Server Operations — Backup & Restore (audit-remediation task 7.4)

## Nightly backups

The server runs an in-process backup scheduler:

- Fires shortly after boot if the last backup is older than 24h, then nightly.
- Each backup: `wal_checkpoint(TRUNCATE)` → `VACUUM INTO backups/erp-<timestamp>.db`
  → `integrity_check` on the copy → retention prune (7 daily + 4 weekly).
- A `BACKUP_CREATE` row is written to `activity_log`.

Manual backup: `cd server && npm run db:backup`

## Historical data-integrity scan (audit-remediation task 30)

Run the report-only C1/C2/C3/H10 scanner against the configured database:

```bash
cd server
npm run data:integrity
# or: npm run data:integrity -- /path/to/erp.db
```

The scanner opens SQLite read-only, uses `query_only`, and runs its checks in a
consistent read transaction. It never modifies historical data and does not
provide a repair mode. Exit code `1` means findings were reported; exit code `0`
means no findings were detected. JSON output includes each finding's document,
reference, affected quantity, affected amount, expected value, actual value,
proposed repair, and an audit log. Create a backup with `npm run db:backup`
before implementing or applying any future repair.

## Deprecated mobile invoice API

`/api/mobile-invoices/*` is retained for compatibility but is deprecated. Use
`/api/invoices/*` for new clients. Every mobile response carries:

- `Deprecation: true`
- `Warning: 299 mini-erp "..."`
- `Link: </api/invoices>; rel="successor-version"`
- `X-Deprecated-Endpoint: /api/mobile-invoices`

The deprecation middleware does not change response bodies or status codes.
Existing clients may continue using the mobile routes during the compatibility
window. Before removal, confirm that no external or mobile consumers remain,
migrate them to `/api/invoices/*`, and preserve the historical mobile migration
and backfill paths needed by existing databases.

## Restore procedure

1. **Stop the server**
   ```bash
   kill -TERM <server-pid>   # graceful: flushes audit logs + checkpoints WAL
   ```

2. **Pick a backup**
   ```bash
   ls -lt server/database/backups/
   ```

3. **Replace the database**
   ```bash
   cd server/database
   rm -f erp.db erp.db-wal erp.db-shm     # remove live DB and any WAL remnants
   cp ../backups/erp-<timestamp>.db erp.db
   ```

4. **Verify integrity before restart**
   ```bash
   sqlite3 erp.db "PRAGMA integrity_check;"
   # must output: ok
   ```

5. **Restart the server**
   ```bash
   npm start   # or the installer's launcher
   ```

6. **Restore uploads** (if lost): untar the most recent `uploads` archive back
   into `server/uploads/`. Backups of uploads are included in installer-level
   backups; the nightly DB backup covers database state only.

7. **Post-restore checks**
   ```bash
   npm run gl:check        # GL integrity: balanced entries, no orphans
   ```
   Then log in and spot-check dashboard totals against the last known figures.
