# Proposal: audit-p0-critical-fixes

## Why

The 2026-08-21 system audit identified 20 P0 defects. Three classes are time-critical or actively exploitable today: (1) invoice creation **fails outright on 2026-09-01** because only one accounting period exists (`2026-08`) and `AccountingService.postEntry` throws outside it; (2) the live SQLite database and its WAL are tracked in git with **no backup mechanism at all**, making any `git checkout`/`reset` an unrecoverable data-loss event; (3) confirmed security holes — SQL injection via custom-report expressions, a privilege-escalation path to Admin via an inverted self-role guard, an ownership-less payment-deletion path, and rate limiters silently disabled by `NODE_ENV=development` in the committed `.env`.

## What Changes

- Auto-create accounting periods when a GL entry date falls beyond the last open period, removing the 2026-09-01 invoice outage (~10-line fix in `AccountingService.postEntry`).
- Add a database backup mechanism (`VACUUM INTO`-based snapshot command + npm script) and stop git-tracking `erp.db`, `-shm`, `-wal`.
- Fix the inverted self-role guard in the users route so a user cannot elevate their own record to Admin.
- Require ownership validation before a payment is moved to `deleted_payments`, and write an audit row for the action.
- Validate/allowlist custom-report `computedColumns[].expression` so it can no longer inject SQL or read `users.password_hash`; close the inline-config bypass.
- Set `NODE_ENV` to a production-safe value in the committed `.env` template so rate limiters are active.
- Out of scope (deferred to follow-up changes): full GL posting for purchases/supplier payments/expenses, balance-sheet rebuild, stock-transfer server orchestration, physical-count batch handling, boot-time mutation rework (MIG-05), migration ledger (MIG-02), index/perf work.

## Capabilities

### New Capabilities
- `db-backup-recovery`: Scheduled/on-demand SQLite backups plus keeping live DB/WAL files out of version control so restores are always possible.
- `accounting-period-rollover`: GL posting must never fail because the calendar crossed into a month with no pre-created accounting period; periods are created on demand within defined rules.
- `authz-hardening`: Self-service user edits cannot escalate roles; destructive payment operations verify ownership and are audited; security-sensitive runtime configuration defaults are production-safe.
- `report-expression-security`: Custom report computed-column expressions are validated against a safe grammar and executed without raw SQL interpolation, uniformly across stored and inline configs.

### Modified Capabilities
<!-- None: existing specs (activity-log-grid, invoice-returns, purchase-returns) have no requirement changes. -->

## Impact

- **Server code:** `server/src/services/accountingService.ts` (period lookup/create), `server/src/routes/users.ts` (self-role guard), `server/src/routes/payments.ts` (deletion ownership + audit), `server/src/services/reportQueryEngine.ts` + `server/src/routes/customReports.ts` (expression safety).
- **Ops/config:** new `server/scripts/backup-db.(js|ts)` + `backup` npm script; `.gitignore` additions for `server/database/*.db*`; `server/.env` review.
- **Database:** no schema changes expected (uses existing `accounting_periods`, `activity_log`, `custom_reports` tables); therefore no migration.
- **API contracts:** unchanged — all fixes are internal enforcement; no Flutter client changes required.
- **Tests:** extend the existing security regression suite (`server/tests`) with cases for each closed hole; add a rollover test posting an entry dated after the last period.
