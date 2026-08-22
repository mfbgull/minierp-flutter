# Design: audit-p0-critical-fixes

## Context

Audit AUDIT-2026-08-21 (Top-20 table) confirmed four exploitable/breaking defect classes, all verified in code:

| ID | Site | Current behavior |
|---|---|---|
| ACC-11 | `server/src/services/accountingService.ts:225-238` | `postEntry` throws when no open `accounting_periods` row covers the entry date; called inside every `Invoice.create` transaction. Only period: 2026-08 → invoices fail from 2026-09-01. |
| DR-01/DR-05 | repo + `server/database/*.db*` | DB/WAL tracked & dirty in git; zero backup code (`ActionType.BACKUP_CREATE` declared, unimplemented). |
| SEC-04 | `server/src/controllers/userController.ts:84-90` | Self-role guard inverted: blocks self-demotion, *allows* self-promotion to Admin. |
| PAY-01 | `server/src/controllers/invoiceController.ts:436-452` | `deleted_payments` ids deleted by raw id — no ownership check, no audit row. |
| REP-18 | `server/src/services/reportQueryEngine.ts:285,305` | `cc.expression` interpolated raw into SELECT list; inline configs bypass validation. |
| SEC-02 | `server/.env` | Committed file sets `NODE_ENV=development`, which makes rate limiters no-ops. |

Constraints: better-sqlite3 (synchronous, serialized writes), layered routes→controllers→models architecture, no new runtime dependencies unless unavoidable, prepared statements only.

## Goals / Non-Goals

**Goals:**
- Invoice/GL posting survives calendar rollover without operator intervention.
- A restorable backup can be produced in one command; git can never revert business data.
- Close the four confirmed security holes with regression tests.
- No API contract changes; Flutter client untouched.

**Non-Goals:**
- GL posting completeness for purchases/supplier payments/expenses (separate change).
- Backup scheduling/rotation daemon (on-demand command now; scheduling later).
- Reworking boot-time mutations (MIG-05), migration ledger (MIG-02), stock transfer orchestration (INV-02).
- Full expression sandboxing beyond the validated subset.

## Decisions

**D1 — Period rollover: auto-create inside `postEntry`, not a scheduled job.**
When no open period covers the entry date, compute the calendar-month window containing `entry_date`, `INSERT ... ON CONFLICT(period_name) DO NOTHING` into `accounting_periods` with status `open`, then re-select. Because better-sqlite3 serializes access and `postEntry` runs inside the caller's transaction, idempotency and atomicity come free; a failed posting rolls back the period too. Alternatives rejected: pre-creating N future periods via cron (more moving parts, same guarantee later); requiring manual open (this is what fails today). Log a warning + write an `activity_log` row so silent auto-creation stays visible.

**D2 — Backup: better-sqlite3 `db.backup()` behind `npm run db:backup`.**
`db.backup()` produces a consistent snapshot of a live WAL database (proven against this exact DB during the 2026-08-22 data cleanup). Script writes to `server/database/backups/erp-backup-<ISO-timestamp>.db`, runs `PRAGMA integrity_check` on the result, exits non-zero on failure, keeps the newest 30 files. Alternatives rejected: `VACUUM INTO` (equivalent, but `db.backup()` retries on busy and needs no SQL string handling); filesystem copy of db+wal (unsafe mid-write).

**D3 — Git untracking: `git rm --cached` + `.gitignore`, after taking one final backup.**
Patterns: `server/database/*.db`, `*.db-shm`, `*.db-wal`, `server/database/backups/`, plus removal of the stray `server/database/Untitled Folder/` copies from the index. Files stay on disk untouched. `.gitignore` currently has no database entries (verified).

**D4 — Self-role guard: own `role_id` immutable, full stop.**
Replace the inverted check with: if `req.user.id === userId && role_id !== undefined` → 400. Alternatives rejected: allow-demotion-only (weird semantics, more branches to get wrong); comparing role names (the root cause — name comparison must go entirely).

**D5 — Payment deletion ownership: validate via `payment_allocations`.**
For each `deleted_payments` id, require an existing allocation row joining that payment to the invoice being updated (`PaymentModel.getAllocationsByPaymentId` already returns `invoice_id`). Missing join → 400, delete nothing. On success, reuse the existing activity logger with the closest declared action type for payment deletion; include payment_no, amount, actor id in metadata. No schema changes.

**D6 — Expression safety: tokenizer + allowlist in a shared module, enforced at both entry points.**
New `server/src/services/expressionValidator.ts`: tokenize → accept numeric literals, parentheses, `+ - * / %`, report-field identifiers (from the config's own field list + computed-column names), and a fixed SQL function allowlist (`ROUND, ABS, COALESCE, IFNULL, MIN, MAX, CAST`). Reject anything else — string literals, semicolons, comments, keywords (`SELECT`, `CASE`, …), unknown functions — with a 400 naming the offending token. `reportQueryEngine` calls the validator before interpolation (defense in depth even if a controller misses it), and both the persisted-config path (`customReportsController`) and any inline-config execution path call the same validator. Alternatives rejected: full SQL parser library (new dependency for a bounded problem), moving computed columns out of SQL (bigger refactor, wrong change).

**D7 — `.env`: flip committed value to `NODE_ENV=production`.**
First grep the server for `NODE_ENV` reads so nothing dev-only breaks silently; rate-limit middleware then becomes active. The JWT secret in the committed `.env` is flagged but its rotation is operational follow-up (needs redeploy coordination), not part of this code change.

## Risks / Trade-offs

- [Auto-created periods mask a genuine ops mistake (nobody opening periods deliberately)] → mitigation: warning log + activity_log row on every auto-creation.
- [Expression validator rejects a legitimate existing stored report] → mitigation: enumerate existing `custom_reports` rows in tests; error message lists the allowed grammar; validator is pure and easy to extend.
- [`git rm --cached` surprises other clones] → migration note: other machines must `git pull` and will simply stop tracking; local files unaffected.
- [NODE_ENV=production changes dev ergonomics (logging verbosity)] → verified via grep before merge; devs may override locally with uncommitted `.env.local` pattern only if such support already exists (do not add config machinery).
- [Backup retention 30 could fill disk over time] → each snapshot ≈ 1–4 MB; negligible; retention constant is one line to change.

## Migration Plan

1. Run `npm run db:backup` once and verify integrity (before any git operation).
2. Land code fixes (D1, D4–D7) — deployable independently, no schema change, no client change.
3. Untrack DB files (D3) last, in its own commit so it's easy to reason about.
4. Pre-flight before 2026-09-01: create an invoice dated 2026-09-01 on a staging copy; expect success and a September period row.
5. Rollback strategy: all changes are ordinary code reverts; DB untouched except additive period rows.

## Open Questions

- Should backups also sync off-machine (cloud/NAS)? Deferred — needs user input on infrastructure.
- Rotate the committed JWT secret as part of this change or separately with a maintenance window? Leaning separate.
