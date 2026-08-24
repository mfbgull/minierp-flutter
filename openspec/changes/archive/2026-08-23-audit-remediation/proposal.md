# Proposal: audit-remediation

## Why

The 2026-08-22 operations audit (`opus5-audit-report/ops.md`) found 40+ defects across migrations, audit trail, backup/DR, testing and performance — including a migration that silently destroys `payments.invoice_id`, 14 classes of unconditional data mutation on every boot, an invoice hard-delete path that leaves unvoided GL rows misstating the trial balance by ₨685, and zero indexes on `invoice_items`. An earlier change (`audit-p0-critical-fixes`) already landed backup basics, gitignore hygiene, accounting-period rollover and report-expression security; this change remediates **everything that remains**, before real transaction volume makes each defect more expensive to hit.

## What Changes

- **Migration system**: replace schema-introspection guards with a `schema_migrations` ledger; run every migration in a transaction; fail startup loudly on error; fix the P0 `payments` table rebuild (lost `invoice_id`, pragma not restored in `finally`); dedupe/re-guard the FK-index runner; repair the dead performance-index file's 3 invalid columns; move all 14 boot-time data mutations into an explicit opt-in `npm run repair` (backup-first, one transaction, audited); seed permissions only once; stop re-opening/corrupting closed accounting periods at boot; gate `--rollback` behind confirmation; add missing PRAGMAs (`cache_size`, `wal_autocheckpoint`) and one canonical migration-path constant.
- **Audit trail**: add `old_value`/`new_value`/`reason`/`correlation_id` columns (**schema migration**); implement the designed-but-never-built catch-all logging middleware; retrofit invoice create/update/delete logging; unify raw-SQL logging paths onto the activityLogger service; log role/permission and settings changes; move `/activity-log/cleanup` behind a new `activity_log:purge` permission with minimum retention; flush the log queue on shutdown.
- **GL integrity**: convert invoice deletion to soft-delete so journal lines and customer-ledger rows are never orphaned; reconcile today's measured damage (12 unvoided orphaned `journal_lines` = ₨685 trial-balance misstatement, 26 dangling `journal_entry_id`s) via data-fix migration; add a scheduled reference-integrity check.
- **Backup / DR**: extend `db-backup-recovery` with scheduled nightly backups, retention policy, `PRAGMA integrity_check` verification, `wal_checkpoint(TRUNCATE)` inside the app on an interval and pre-backup, `server/uploads/` in the backup set, documented restore procedure; make the installer back up before touching an existing install and add a real upgrade path; fix graceful shutdown (`closeAllConnections` timeout, SIGHUP handler, env validation before DB import, log flush).
- **Testing**: fail-closed `DATABASE_PATH` assertion in `config/database.ts`; GitHub Actions CI (typecheck, lint, jest, flutter analyze/test); neutralize the live-DB-writing e2e Python script; add the ranked missing suites — double-entry invariant, transaction rollback, invoice-edit-after-payment, invoice-delete-no-orphans, boot idempotency, concurrency, customer partial payments, migration replay.
- **Performance**: create `invoice_items(invoice_id)`/`(item_id)` and other missing hot-path indexes; drop 12 provably redundant indexes and add 6 composites; rewrite ledger running balance as incremental update; bound dashboard cash-position queries with date floors and batch KPI fetching; hoist per-row permission checks out of global search; paginate/date-bound reports and ledgers; schedule `ANALYZE`.

## Capabilities

### New Capabilities
- `migration-ledger`: versioned, transactional, fail-fast schema migrations with no boot-time data mutation; safe rollback tooling.
- `audit-trail`: complete who/what/when/previous-value/why/correlation capture for every mutating endpoint, with append-only protections and durable delivery.
- `gl-integrity`: document deletion never orphans GL or ledger rows; existing orphans are reconciled and continuously checked.
- `graceful-shutdown`: every shutdown path drains the WAL, flushes queued audit logs, and closes the DB within a bounded timeout.
- `query-performance`: indexed hot paths, incremental ledger balances, bounded dashboards/reports/search, and maintained planner statistics.
- `financial-test-invariants`: automated money-path regression suite (double-entry balance, atomicity, boot idempotency, migration replay).

### Modified Capabilities
- `db-backup-recovery`: adds scheduled execution with retention, restorability verification (`integrity_check`), app-level WAL checkpointing, uploads in the backup set, and a documented restore procedure.
- `authz-hardening`: adds the `activity_log:purge` permission and minimum-retention floor governing trail cleanup.
- `accounting-period-rollover`: removes the boot-time period INSERT so admin period closures are durable across restarts.
- `activity-log-grid`: grid/detail surfaces old/new values, reason and correlation id.

## Impact

- **Server core**: `server/src/config/database.ts` (largest single file touched), `server/server.ts`, `src/middleware/*` (new logging middleware), `src/controllers/invoiceController.ts`, `rolesController.ts`, `settingsController.ts`, `services/activityLogger.ts`, `services/accountingService.ts`, `services/cashService.ts`, `services/searchService.ts`, `utils/ledgerUtils.ts`, `models/Dashboard.ts`, `models/Reports.ts`.
- **Database**: two new schema migrations (`activity_log` value columns; GL reconciliation data fix) plus the index additions/removals — all delivered through the new ledger mechanism.
- **Ops/tooling**: new `.github/workflows/ci.yml`, `npm run repair` script, updated `installer-stub.sh` + `tool/make_linux_setup.sh`, backup scheduler extension of `server/scripts/backup-db.js`.
- **Flutter client**: dashboard provider fan-out consolidation; activity-log grid detail fields. No API contract breaks; new endpoints are additive.
- **Risk notes**: MIG-02 fix must ship with a data-recovery pass for any DB where the rebuild already ran; removing boot mutations changes observable behavior (derived columns update only via explicit repair) — accepted per audit recommendation DR-08/MIG-05.
