# Server Operations — Backup & Restore (audit-remediation task 7.4)

## Nightly backups

The server runs an in-process backup scheduler:

- Fires shortly after boot if the last backup is older than 24h, then nightly.
- Each backup: `wal_checkpoint(TRUNCATE)` → `VACUUM INTO backups/erp-<timestamp>.db`
  → `integrity_check` on the copy → retention prune (7 daily + 4 weekly).
- A `BACKUP_CREATE` row is written to `activity_log`.

Manual backup: `cd server && npm run db:backup`

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
