# Server Operations — Backup & Restore (audit-remediation task 7.4)

## Nightly backups

The server runs an in-process backup scheduler:

- Fires shortly after boot if the last backup is older than 24h, then nightly.
- Each backup: `wal_checkpoint(TRUNCATE)` → `VACUUM INTO backups/erp-<timestamp>.db`
  → `integrity_check` on the copy → the copy is wrapped in an encrypted
  container `backups/erp-<timestamp>.db.enc` and the plain file is removed
  (see "Backup encryption" below) → a sibling `backups/erp-<timestamp>.uploads/`
  copy of `server/uploads/` (D7), so a restore recovers employee document files
  as well as rows → retention prune (7 daily + 4 weekly).
- A `BACKUP_CREATE` row is written to `activity_log`.

Manual backup: `cd server && npm run db:backup`

Set `BACKUP_DIR` (for example to an external drive or a synced folder) to store backups somewhere other than
`server/database/backups/`; both the scheduler and `npm run db:backup` honour it. Backups made by the
CLI (`erp-backup-<timestamp>.db.enc`) and by the scheduler (`erp-<timestamp>.db.enc`) are listed, downloadable and
subject to the same retention rules. A backup taken while no key was configured keeps the plain
`.db` name, and stays listed, downloadable and deletable next to the encrypted ones.

## Backup encryption (audit D29, option B)

Option B protects the database copy only. The uploads snapshot beside it stays plain.

- **Key:** `BACKUP_ENCRYPTION_KEY` in `server/.env`. Generate it with
  `openssl rand -base64 48`. The scheduler, `npm run db:backup` and all three
  restore tools read the same value.
- **Format:** AES-256-GCM container, magic `ERPENC01`, with a fresh random salt
  per backup. The file is not a database: open it with `decrypt-backup.js`.
- **Without a key:** the backup is still taken, as a plain `.db`, and the server
  logs `NOT encrypted: BACKUP_ENCRYPTION_KEY is not set`. A missing backup is
  worse than an unprotected one, so the backup never silently disappears.

> **LOST KEY = LOST BACKUPS. PERMANENT.**
> There is no back door, no reset and no recovery. If the key is lost, every
> `.db.enc` file becomes unreadable noise forever, and so does every backup
> copied from those files. Keep a copy of the key offline and separate from the
> machine — paper in a locked drawer is a valid answer. Rotating the key does
> not re-encrypt old backups: each file stays locked with the key that wrote it.
> Backups taken before encryption (plain `.db`) are not affected by key loss.

Tools:

```bash
cd server
# decrypt a container to a plain database (verifies integrity, writes 0600)
npm run db:decrypt -- database/backups/erp-<timestamp>.db.enc
# verify a backup is restorable — accepts .db and .db.enc
node scripts/verify-backup.js database/backups/erp-<timestamp>.db.enc
# open a copy and read core row counts — accepts .db and .db.enc
node scripts/restore-smoke.js database/backups/erp-<timestamp>.db.enc
```

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
   A name ending in `.db.enc` is an encrypted container. A plain `.db` is
   readable as it is.

3. **Make the restore file** (the old files are kept until the restore is verified)
   ```bash
   cd server
   # encrypted container -> plain database alongside it
   # (needs BACKUP_ENCRYPTION_KEY in server/.env; see "Backup encryption")
   npm run db:decrypt -- database/backups/erp-<timestamp>.db.enc

   cd database
   # backups live in server/database/backups/ - NOT ../backups/
   cp backups/erp-<timestamp>.db erp.restore.tmp
   ```
   A plain backup from before encryption needs no decrypt step: copy it
   directly.

4. **Verify the copy before swapping it in**
   ```bash
   sqlite3 erp.restore.tmp "PRAGMA integrity_check;"   # must output: ok
   mkdir -p pre-restore
   mv erp.db erp.db-wal erp.db-shm pre-restore/ 2>/dev/null   # keep the old DB aside
   mv erp.restore.tmp erp.db
   ```
   `npm run db:verify-backup -- <backup>` runs the fuller check (schema, GL
   balance, stock batches) and accepts either form. Do not leave a stale
   `erp.db-wal` or `erp.db-shm` beside the new file.
   Only delete `pre-restore/` once the restored system has been checked.

5. **Restart the server**
   ```bash
   npm start   # or the installer's launcher
   ```

6. **Restore uploads** (if lost): copy the snapshot taken with that same backup
   back over `server/uploads/`. Every backup has a sibling named from it with
   `.db` or `.db.enc` replaced by `.uploads` — for example
   `erp-<timestamp>.db.enc` pairs with `erp-<timestamp>.uploads/` — so the
   pairing is by name:
   ```bash
   cd server
   # list what is available
   ls -d database/backups/*.uploads/
   # restore employee documents alongside the database you just swapped in
   rm -rf uploads.pre-restore && mv uploads uploads.pre-restore 2>/dev/null
   cp -r database/backups/erp-<timestamp>.uploads uploads
   ```
   If the snapshot is missing (it is only written when a backup runs, and an
   uploads copy failure never fails the database backup), fall back to the most
   recent installer-level `uploads` archive and log the gap.

7. **Post-restore checks**
   ```bash
   npm run gl:check        # GL integrity: balanced entries, no orphans
   ```
   Then log in and spot-check dashboard totals against the last known figures.
