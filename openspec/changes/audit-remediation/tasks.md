# Tasks: audit-remediation

## 1. Safety net (TEST-03, TEST-04, AUD-08)

- [x] 1.1 Add fail-closed guard at top of `server/src/config/database.ts`: throw when `NODE_ENV==='test'` and no `DATABASE_PATH` is set
- [x] 1.2 Exclude `server/src/audit-trace.ts` from tsconfig include and move it to `server/scripts/dev/` with a top-level `if (require.main === module)` guard
- [x] 1.3 Fix the 10 ESLint errors (`no-empty` ×6 in database.ts silent catches → log or pragma_table_info guards; `preserve-caught-error` ×2; test-file issues ×2)
- [x] 1.4 Create `.github/workflows/ci.yml`: server job (npm ci → typecheck → eslint zero-errors gate → jest) + flutter job (analyze → test), triggered on push/PR

## 2. Migration ledger core (MIG-01, MIG-09, MIG-10, MIG-11)

- [ ] 2.1 Add `schema_migrations` table creation (filename PK, applied_at, checksum) as first boot step; add `MIGRATIONS_DIR` single path constant resolving correctly under dist and ts-jest; replace all per-runner path joins
- [ ] 2.2 Implement ledger runner: skip-if-recorded, execute inside `db.transaction()`, record with checksum on success; abort process non-zero on failure (remove per-runner swallow for migration errors)
- [ ] 2.3 Backfill: convert each of the 47 runners into a named entry preserving its SQL body; register historical-guard results into the ledger without re-executing bodies on existing DBs
- [ ] 2.4 Replace the 6 silent `catch {}` ALTERs (database.ts:664-669) with guarded column-existence checks through the ledger mechanism
- [ ] 2.5 Add PRAGMAs after connect: `cache_size = -16000`, `wal_autocheckpoint = 400`; set `user_version` alongside ledger for cheap external inspection
- [ ] 2.6 Test: migration replay suite — apply full migration set twice to `:memory:`; assert identical sqlite_master and zero errors (financial-test-invariants)

## 3. Payments rebuild fix + boot de-mutation (MIG-02, MIG-05, MIG-06, MIG-07, MIG-03, MIG-04)

- [ ] 3.1 Fix payments table rebuild: add `invoice_id` to INSERT columns and SELECT; remove inline PRAGMA/BEGIN/COMMIT; restore `foreign_keys=ON` in finally; assert pragma===1 after
- [ ] 3.2 Add ledger-tracked data migration recovering `payments.invoice_id` from `payment_allocations` where NULL; log affected count to activity_log
- [ ] 3.3 Extract the 14 boot-time mutation blocks (database.ts :194-305, :613, :838-846, seedDefaultPermissions always-grant loop, GL-foundation period INSERT, runUnbatchedStockReconciliation, runOrphanedBatchCleanup) into `server/scripts/repair.ts` behind `npm run repair`
- [ ] 3.4 `repair.ts`: take verified `VACUUM INTO` backup first, run mutations in one transaction, write activity_log row per mutation class, print summary of rows changed
- [ ] 3.5 Change `seedDefaultPermissions` to seed only roles with empty `role_permissions`; remove "Always seed" behavior
- [ ] 3.6 Remove the accounting-period INSERT from `add-gl-foundation.sql`; make period creation posting-time only (per accounting-period-rollover spec)
- [ ] 3.7 Delete duplicate `runMissingFKIndexesMigration()` call (database.ts:1094) and re-point its guard to an index the file actually creates (e.g. `idx_invoices_customer_id`)
- [ ] 3.8 Repair `add-performance-indexes.sql` invalid columns (`purchase_orders(order_date)`→`po_date`, drop nonexistent `productions(status)`/`expenses(category_id)`), re-point its dead guard, wire `add-search-indexes.sql` into a ledger entry
- [ ] 3.9 Test: boot idempotency — snapshot row hashes of all business tables, run boot twice, assert zero changes (financial-test-invariants)

## 4. Audit trail (AUD-01 … AUD-05, AUD-07)

- [ ] 4.1 Migration: add `old_value TEXT, new_value TEXT, reason TEXT, correlation_id TEXT` to `activity_log` (+ index on correlation_id)
- [ ] 4.2 Extend activityLogger service: diff-based `logCRUD` writing old/new JSON (8KB cap), reason passthrough, correlation-id acceptance; set `req.activityLogged=true` on every service write
- [ ] 4.3 Create `middleware/activityLog.ts` backstop: route-metadata map (route→entityType/actionType); after 2xx on mutating verbs write one row if `!req.activityLogged`; stamp correlation id per request
- [ ] 4.4 Retrofit invoiceController: structured logCRUD rows for create/update/delete/cancel/return with prior-row snapshots and shared correlation id linking stock/GL events; remove raw inline SQL inserts
- [ ] 4.5 Migrate remaining raw `INSERT INTO activity_log` sites (models + POS/purchase/sales controllers) onto the service; re-attribute POS rows to entity_type INVOICE/invoice id; emit or delete dead ActionType members
- [ ] 4.6 Add logging to unlogged controllers: rolesController (incl. updateRolePermissions delta), settingsController, preferencesController, customReportsController, dashboardLayoutController, forecastsController, mobileInvoiceController, stockBatches routes, integrations route, purchaseOrder line-item handlers; remove productionController double-log
- [ ] 4.7 Shutdown flush: call `flushLogs()` in graceful shutdown before db.close(); bound the retry queue (max 1000, drop-oldest with error log); make ActivityLog.insert failures distinguishable from success
- [ ] 4.8 Add `activity_log:purge` permission (migration inserting into permissions + grant to Admin role); change `/cleanup` route to require it; enforce minimum retention 365 days; write cleanup record to a separate append-only file sink
- [ ] 4.9 Tests: middleware backstop fires exactly once per request; invoice delete writes trail row; purge 403 without permission; SIGTERM flush persists queued rows

## 5. GL integrity (AUD-06)

- [ ] 5.1 Migration: add `invoices.deleted_at TEXT, deleted_by INTEGER` columns
- [ ] 5.2 Convert `deleteInvoice` to soft-delete: mandatory void of journal lines (verify affected>0), stock reversal, contra ledger entry, void allocations/payments markers, set deleted_at/by; remove hard DELETE paths
- [ ] 5.3 Filter soft-deleted invoices from all list/get/report queries (centralize in Invoice model helpers; audit raw SELECTs)
- [ ] 5.4 Ledger-tracked reconciliation migration: void the 12 measured unvoided orphaned journal_lines; resolve 26 dangling journal_entry_id refs; post-condition assertion SUM(debit)=SUM(credit) over non-voided rows fails startup if violated
- [ ] 5.5 Create `scripts/check-gl-integrity.ts` (readonly connection, per reconcile-stock-cash.ts pattern): orphaned references, missing-ledger docs, per-document imbalance; schedule nightly alongside backup job; loud logging
- [ ] 5.6 Tests: double-entry invariant after create/pay/edit/delete flows; failed multi-line invoice leaves zero rows; invoice delete leaves no orphaned journal_lines/ledger rows (financial-test-invariants)

## 6. Graceful shutdown & lifecycle (DR-03, DR-04)

- [ ] 6.1 Create `src/utils/shutdown.ts` gracefulExit(): close server with 3s timeout + closeAllConnections, flushLogs, wal_checkpoint(TRUNCATE), db.close, exit; route SIGTERM/SIGINT/SIGHUP/unhandledRejection/uncaughtException through it
- [ ] 6.2 Move env validation before database import in server.ts import order; rollback CLI exits and env-missing exit use shutdown helper
- [ ] 6.3 Update `tool/make_linux_setup.sh` launcher: start server in tracked process group, trap session EXIT/INT/TERM to signal server gracefully; keep run.sh kill -9 as backstop after grace window
- [ ] 6.4 Test: SIGTERM with idle keep-alive client completes shutdown < timeout with checkpoint + flushed logs

## 7. Backup / DR (DR-01, DR-02, DR-05, DR-07 remainder)

- [ ] 7.1 Untrack from git index: `server/database/**`, `server/.env`, `server/node_modules`, `server/uploads`; extend `.gitignore` for `server/.env`, `server/node_modules/`, `server/uploads/`, recursive `*.db*`
- [ ] 7.2 Rotate dev JWT secret: new generated value in local `.env.example` guidance; document rotation steps for deployed checkouts in ops doc
- [ ] 7.3 Extend backup script into scheduled job: nightly in-process timer (fire-on-boot if last backup >24h), pre-backup wal_checkpoint(TRUNCATE) with busy detection, VACUUM INTO copy, integrity_check on copy, retention prune 7 daily/4 weekly, uploads tar inclusion, BACKUP_CREATE trail row
- [ ] 7.4 Write restore procedure doc (`server/README.md`): stop server → replace db from chosen backup → integrity_check → restart; include uploads restore
- [ ] 7.5 Installer: back up existing `$DIR` database+uploads before any removal; add upgrade path preserving database/uploads/.env; sync heredoc copy in make_linux_setup.sh; handle -wal/-shm when removing shipped db files
- [ ] 7.6 Test: backup produced while WAL holds committed txns passes integrity_check and contains those rows on restore into fresh file

## 8. Performance (PERF-01 … PERF-07 targeted)

- [ ] 8.1 Index migration (ledger-tracked): create `invoice_items(invoice_id)`, `invoice_items(item_id)`, `customers(customer_name)`, `suppliers(supplier_name)`, `settings(key)`, `invoices(due_date)`, `invoices(status, invoice_date)`, `customer_ledger(customer_id, transaction_date, id)`, `customer_ledger(customer_id, id)`, `stock_movements(item_id, warehouse_id, movement_date)`; drop the 12 redundant indexes listed in PERF-07; EXPLAIN QUERY PLAN assertions for hot paths
- [ ] 8.2 Rewrite `rebuildLedgerBalances` → incremental `updateBalancesFrom(customerId, fromEntryId)` using `(customer_id,id)` index; update all four call sites; correctness test vs old algorithm on seeded history
- [ ] 8.3 Cash position: add date-floor param to cashService queries (default 90d), rewrite account aggregation as grouped UNION SQL removing JS filtering; lazy stock valuation only for stock metrics in Dashboard.getKPI
- [ ] 8.4 Add `GET /dashboard/kpi-batch?metrics=` endpoint returning multiple KPIs in one round trip
- [ ] 8.5 Flutter: batch KPI provider replacing per-card requests; scope invalidation to visible cards; remove calls to nonexistent `/reports/expiry` and `/dashboard/expiry-alerts` (implement expiry-alerts endpoint server-side or drop the panel)
- [ ] 8.6 Search: hoist getUserPermissions above fan-out; thread permission set through filterActions; bind missing role_id parameter at searchService.ts:158-163
- [ ] 8.7 Shared `paginate(req)` helper; apply to customer/supplier ledger+statement, /stock-batches, /accounting/accounts/balances, /pos/transactions, custom-report runs, and routed reports; default date windows on unbounded reports; sargable AR/AP aging with due_date index
- [ ] 8.8 Wire `PRAGMA optimize` into graceful shutdown; ANALYZE in nightly job
- [ ] 8.9 Tests: statement-count bounds (dashboard ≤ fixed N, search constant-per-request), pagination metadata present, incremental balance equals full-recompute result

## 9. E2E hygiene & money-path suites (TEST-01, TEST-02)

- [ ] 9.1 Harden `e2e_expiry_override_test.py`: try/finally cleanup scoped to created ids, refuse execution without explicit `E2E_TARGET` env, document temp-DB server launch; never blind-delete by invoice_no substring
- [ ] 9.2 Customer-side partial payment suite asserting payment_allocations rows and paid/balance/status fields
- [ ] 9.3 Invoice-edit-after-payment suite: totals/status/stock/GL correctness
- [ ] 9.4 Concurrency suite: parallel invoice creates → unique numbers, correct final stock
- [ ] 9.5 CI green end-to-end: both jobs pass; wire jest `--forceExit` removal once leaked handles fixed

## 10. Verification & self-audit

- [ ] 10.1 Run `cd server && npm run typecheck && npx eslint .` — zero errors
- [ ] 10.2 Run `flutter analyze` and `flutter test` — clean (requires flutter toolchain available)
- [ ] 10.3 Boot live-schema copy twice; confirm zero business-row changes and ledger populated
- [ ] 10.4 Trial balance query on reconciled copy: SUM(debit)=SUM(credit), zero orphaned non-voided journal_lines
- [ ] 10.5 Simulated power-cut check: kill -9 server mid-writes → reopen → integrity_check ok → last backup restorable
