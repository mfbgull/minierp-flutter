# Tasks: audit-p0-critical-fixes

## 1. Accounting period rollover (ACC-11 — fixes 2026-09-01 outage)

- [ ] 1.1 In `server/src/services/accountingService.ts` `postEntry`: replace the throw-on-missing-period with auto-create of the calendar-month period (`INSERT ... ON CONFLICT(period_name) DO NOTHING`, status `open`) + re-select, inside the caller's transaction
- [ ] 1.2 Log a warning and write an `activity_log` row whenever a period is auto-created
- [ ] 1.3 Add test: posting an entry dated 2026-09-01 with only the 2026-08 period present succeeds and creates exactly one September row
- [ ] 1.4 Add test: entry inside existing open period creates no new row; failed posting after rollover rolls back the period

## 2. Backup command (DR-01)

- [ ] 2.1 Create `server/scripts/backup-db.js` using better-sqlite3 `db.backup()` → `server/database/backups/erp-backup-<timestamp>.db`, run `PRAGMA integrity_check` on result, prune to newest 30, exit non-zero on failure
- [ ] 2.2 Add `"db:backup"` script to `server/package.json`
- [ ] 2.3 Add test/verification: run backup against live WAL database; snapshot passes integrity_check and includes committed data

## 3. Untrack live database from git (DR-05) — do last, own commit

- [ ] 3.1 Add to `.gitignore`: `server/database/*.db`, `*.db-shm`, `*.db-wal`, `server/database/backups/`
- [ ] 3.2 `git rm --cached` for `server/database/erp.db`, `-shm`, `-wal` and `server/database/Untitled Folder/erp.db*`; confirm files remain on disk
- [ ] 3.3 Verify `git status --porcelain server/database/` shows nothing tracked-modified after new writes

## 4. Self-role guard fix (SEC-04)

- [ ] 4.1 In `server/src/controllers/userController.ts` update handler (~line 84): reject any self-edit containing `role_id` regardless of target role name (remove role-name comparison entirely)
- [ ] 4.2 Add tests: self-promotion to Admin → 400 & no update; self-demotion → 400; admin editing another user's role → succeeds

## 5. Payment deletion safety (PAY-01)

- [ ] 5.1 In `server/src/controllers/invoiceController.ts` update handler (~line 436): before deleting, require an allocation row joining each `deleted_payments` id to the invoice being updated; otherwise 400 and delete nothing
- [ ] 5.2 Write an `activity_log` row per removed payment (payment_no, amount, invoice id, actor) using the existing logger
- [ ] 5.3 Add tests: cross-invoice payment id → rejected; own-invoice payment → deleted inside transaction + audit row exists

## 6. Report expression security (REP-18)

- [ ] 6.1 Create `server/src/services/expressionValidator.ts`: tokenizer + allowlist (field identifiers from config, numeric literals, `+ - * / % ( )`, functions ROUND/ABS/COALESCE/IFNULL/MIN/MAX/CAST); reject string literals, semicolons, comments, other keywords with token-naming 400 errors
- [ ] 6.2 Wire validator into `reportQueryEngine.ts` before expression interpolation (lines ~285/~305)
- [ ] 6.3 Wire same validator into every inline/transient config execution path in `customReportsController.ts` / route so no path bypasses it
- [ ] 6.4 Add tests: `(SELECT password_hash FROM users)` rejected on stored AND inline paths; `quantity * unit_price` and `ROUND(debit - credit, 2)` still execute; all existing stored reports validate

## 7. Environment hardening (SEC-02)

- [ ] 7.1 Grep server for all `NODE_ENV` consumers; confirm none break under `production`
- [ ] 7.2 Set `NODE_ENV=production` in committed `server/.env`; verify rate limiters active (login brute-force returns 429 in test/dev run)

## 8. Verification & pre-flight

- [ ] 8.1 Run full suite: `npm run typecheck` and `npm test` in `server/` (add `typecheck` script if missing — audit TEST-04)
- [ ] 8.2 Staging pre-flight before 2026-09-01: create invoice dated 2026-09-01 on a DB copy → succeeds, September period created, balanced journal lines present
