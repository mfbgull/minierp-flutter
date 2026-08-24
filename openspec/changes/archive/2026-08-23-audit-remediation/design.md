# Design: audit-remediation

## Context

The 2026-08-22 ops audit (`opus5-audit-report/ops.md`) documents the mechanisms in detail; this design references its finding IDs (MIG-xx, AUD-xx, DR-xx, TEST-xx, PERF-xx) rather than restating them. Current state: `server/src/config/database.ts` runs 47 hand-guarded runner functions as import side-effects with swallowed errors and no ledger; one destructive table rebuild (`payments`) drops `invoice_id` and can leave `foreign_keys=OFF` process-wide; 14 classes of data mutation run on every boot; invoice CRUD is unlogged and hard-deleting an invoice leaves unvoided GL rows (₨685 live misstatement); there is no scheduled backup, no CI, no fail-closed test isolation; `invoice_items` has zero indexes and ledger balances are rewritten O(history) per save. An earlier change (`audit-p0-critical-fixes`, archived today) already landed: on-demand `db:backup` script, `.gitignore` patterns, `typecheck` script, accounting-period posting rollover, report-expression security, self-role guard — but git still tracks the DB, `server/.env` and `node_modules`; the boot-time period INSERT remains.

Constraints: better-sqlite3 is synchronous/single-threaded; Flutter + TanStack-equivalent Riverpod client must keep working against unchanged API contracts except additive endpoints; packaged installs get a random JWT secret via `make_linux_setup.sh`, dev/repo-checkout installs do not.

## Goals / Non-Goals

**Goals:**
- Migrations become ledger-tracked, transactional, fail-fast; boots mutate no business data.
- Every mutating endpoint produces a complete audit row (who/what/before/after/why/correlation); trail purge is privileged and bounded.
- Invoice deletion never orphans financial rows; today's measured damage is reconciled.
- Shutdown paths always drain WAL + log queue; backups run nightly, verified, with uploads.
- Money-path regressions (double-entry, atomicity, idempotent boot, migration replay) run in CI.
- Measured hot paths get indexes, incremental balance updates, bounded queries.

**Non-Goals:**
- Full server-side CSV export/import reingestion (DR-06) — deferred; nightly backup is the recovery path.
- SQLite FTS for global search (PERF-04) — only permission hoisting + parameter-binding fix now.
- Enabling `strict` TypeScript or clearing all 403 lint warnings — CI gates on zero *errors* plus typecheck.
- Rewriting the Electron-vestige comments/dead `client/dist` serving beyond the quit-hook fix.
- Splitting `widget_test.dart` (14k lines) into modules.

## Decisions

### D1 — Migration ledger wraps existing runners, does not rewrite them
Keep the 47 runners' SQL bodies; extract each into a named migration entry `{file|fn, guard-backfilled}` executed through a new `runMigrations()` that consults `schema_migrations` first. Backfill: on first boot of the new mechanism, insert ledger rows for every migration whose historical guard reports "already applied" **without executing bodies**. Rationale: rewriting 50 SQL files risks new defects; wrapping isolates behavior change to the scheduler. Alternative rejected: fresh baseline `init.sql` + replay — too risky mid-life with one live install.
Boot sequence becomes: open DB → pragmas → ensure `schema_migrations` → apply pending migrations in defined order inside transactions → any failure exits non-zero before HTTP listen. The 14 data-mutation blocks (MIG-05 list) move verbatim into `scripts/repair.ts` behind `npm run repair`, which takes a `VACUUM INTO` backup first, runs one transaction, logs each class to activity_log. `seedDefaultPermissions` stays in boot but seeds only roles with empty `role_permissions` (MIG-06).

### D2 — Payments rebuild fix + recovery pass
In-place fix of `database.ts:757-797`: add `invoice_id` to INSERT columns and SELECT; drop the raw `PRAGMA/BEGIN/COMMIT` from the SQL (transaction managed by better-sqlite3); restore `foreign_keys=ON` in `finally`; assert pragma === 1 after. Recovery pass ships as a ledger-tracked data migration: rebuild `payments.invoice_id` from `payment_allocations` where NULL, logged to activity_log (MIG-02). Because the ledger guarantees once-only execution, the recovery cannot re-run harmfully.

### D3 — Audit trail: middleware backstop + explicit enrichment, values via JSON diff
New `middleware/activityLog.ts` registered globally after `auth` middleware: on 2xx POST/PUT/PATCH/DELETE, if `!req.activityLogged`, derive entity/action from route metadata table (`route → {entityType, actionType}`), write one row. Handlers call `logCRUD/logWithRequest` which sets `req.activityLogged = true`. New columns via migration: `old_value/new_value/reason/correlation_id TEXT`. Correlation id = crypto.randomUUID() stamped by middleware per request; controllers pass it into multi-row events (invoice+stock+GL). Update diffs: model layer returns pre-update row snapshot (already fetched in most handlers); logger serializes changed fields only (`JSON.stringify({field:{old,new}})`), capped at ~8KB per column. Raw inline `INSERT INTO activity_log` sites migrate to the service (AUD-02); POS rows re-attributed to `entity_type='INVOICE'`. Alternative rejected: SQLite triggers for value capture — triggers fire outside request context, can't capture user/correlation cleanly, and add hidden write cost on every statement.

### D4 — Soft-delete invoices
Add `invoices.deleted_at/deleted_by` columns; `deleteInvoice` becomes: void journal lines (existing `voidJournalLinesByReference`, now mandatory + verified affected>0), reverse stock, reverse ledger entry (insert contra entry, keep original), mark allocations/payments voided, set deleted_at. All list/get queries filter `deleted_at IS NULL`. Existing hard-delete SQL removed. One-time reconciliation migration (D5) cleans current orphans. Rationale: preserves FK-less GL↔document links (audit AUD-06 root cause) without adding polymorphic FK machinery. Alternative rejected: ON DELETE CASCADE-style triggers — hides intent, doesn't void amounts.

### D5 — Reconciliation migration for measured damage
Ledger-tracked data fix: UPDATE the 12 unvoided orphaned `journal_lines` (reference INVOICE, missing invoice) → `voided=1` with note; attach dangling `journal_entry_id`s to a synthetic reconciliation entry or null-and-log per row count; verify post-condition `SUM(debit)=SUM(credit)` over non-voided rows and abort startup if violated after applying. Scheduled check (new `scripts/check-gl-integrity.ts`, wired into nightly job alongside backup) reports orphans/imbalances loudly.

### D6 — Graceful shutdown helper centralizes teardown
`shutdown.ts` exports `gracefulExit(signal)`: stop accepting connections → `closeAllConnections()` + 3s timeout → `flushLogs()` → `wal_checkpoint(TRUNCATE)` → `db.close()` → exit 0. All four signal handlers, both rollback CLI exits, and env-validation path route through it; env validation moves to a module imported **before** `config/database` (server.ts import order). Desktop launcher: `make_linux_setup.sh` writes a PID file and traps window-close via a wrapper script that signals the Node PID before exec-ing Flutter... simpler: launcher starts server, traps EXIT/INT/TERM of the whole session and kills the server group; documented in tasks. `run.sh` keeps 5s kill -9 as backstop after graceful window.

### D7 — Backup scheduler lives beside the app process
Extend `backup-db.js` into `scripts/backup-job.ts` invoked by an in-process interval (`setInterval` at next-2am calculation) inside server.ts — not system cron — because packaged desktop installs have no cron. Job: checkpoint TRUNCATE (assert not busy), `VACUUM INTO backups/<ts>.db`, integrity_check copy, prune retention, include uploads dir via tar alongside db, log BACKUP_CREATE. Restore doc in `server/README.md`.

### D8 — Performance fixes are surgical, query-plan verified
- Indexes: one ledger migration creates the 10 missing hot-path indexes and drops the 12 redundant ones (exact list from PERF-07); `PRAGMA optimize` on graceful shutdown + weekly ANALYZE in backup job.
- Ledger balances (PERF-02): replace `rebuildLedgerBalances(customerId)` full rewrite with `updateBalancesFrom(customerId, fromEntryId)`: compute starting balance as SUM over rows < fromEntryId (indexed by new `(customer_id, id)` index), then update forward only from first affected row. Same correctness, O(affected tail).
- Dashboard (PERF-03): cash-position queries gain `payment_date >= ?` lookback param (default 90d, configurable); account aggregation rewritten as grouped SQL UNION per source instead of 5 JS-filtered scans; stock-value KPIs computed lazily only for stock metrics; new `GET /dashboard/kpi-batch?metrics=a,b,c` endpoint; Flutter `dashboard_providers.dart` uses one batched provider; remove the two nonexistent expiry-endpoint calls (wire to real endpoint added server-side).
- Search (PERF-04): hoist `getUserPermissions` above the fan-out, pass permission set into `filterActions`; bind the missing role_id parameter.
- Reports (PERF-06): shared `paginate(req)` helper (LIMIT/OFFSET/count metadata) applied to ledgers/statements/stock-batches/account-balances/custom-report-run; default date windows (current FY) on unbounded reports; AR/AP aging switch to `date('now') - due_date <= n*days` sargable form with `invoices(due_date)` index.

### D9 — CI and test isolation
`.github/workflows/ci.yml`: matrix job [server (npm ci → typecheck → eslint --max-warnings=∞ gate on errors → jest), flutter (flutter analyze → flutter test)] on push/PR. Fail-closed guard as first statements of `config/database.ts`: if `NODE_ENV==='test'` and no `DATABASE_PATH`, throw. e2e Python script: wrap in try/finally, cleanup scoped to ids captured at creation time, refuse to run unless `E2E_TARGET=http://localhost:PORT` env explicitly set, and document temp-DB launch command. New test suites follow `purchaseReturn.test.ts` migration-replay pattern into `:memory:`.

## Risks / Trade-offs

- [Ledger backfill misclassifies an unapplied migration as applied] → Backfill uses each runner's own historical guard predicate; anything ambiguous (pattern D files) records only after verifying sentinel objects exist; boot-idempotency test guards regression.
- [Removing boot mutations changes derived-column freshness] → Documented: totals/status now maintained transactionally by write paths (they already are; boot rewrite was masking drift). `npm run repair` exists for drift correction; release notes call it out.
- [Soft-delete changes query semantics everywhere invoices are read] → Single model-layer filter point (`Invoice.ts` getAll/getById helpers) + grep-audited raw SELECTs; integration suite asserts deleted invoices invisible yet GL intact.
- [Reconciliation migration mutates financial rows] → Runs once via ledger, inside transaction, preceded by automatic backup step in same boot when pending data-migrations exist; post-condition assertion fails startup if imbalance introduced.
- [Middleware double-logging or missing routes] → `req.activityLogged` contract tested per controller in coverage task; backstop dedupes by construction.
- [Interval-based backup missed if machine off at 2am] → Job fires on next boot if last backup > 24h old (checked at startup after migrations).
- [git history still contains erp.db/.env] → History purge (filter-repo) is operator-executed, not automated here; spec requires untracking + rotation; scrub steps documented in restore/ops doc.
- [WAL checkpoint busy under load] → Checkpoint failures degrade to logged warning; autocheckpoint pragma raised as safety net (`wal_autocheckpoint=400`).

## Migration Plan

Deploy order within the change: (1) safety net — CI, fail-closed guard, shutdown helper; (2) ledger + payments fix + repair extraction; (3) audit trail schema + middleware + retrofit; (4) soft-delete + reconciliation; (5) backup scheduler + installer; (6) performance migrations; (7) test suites fill-in. Each phase lands green in CI. Rollback: revert code commit; DB forward-migrations are additive (columns/indexes/ledger rows) and safe to leave; the two data migrations (reconciliation, payment-link recovery) are idempotent-by-construction and recorded, so re-running older code against them is harmless.

## Open Questions

- Whether to history-scrub git in this change or hand the operator a script — defaulting to script + docs.
- Exact dashboard KPI batch endpoint shape (one POST with metric list vs GET with csv param) — decide during implementation against existing provider patterns.
