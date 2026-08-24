# Tasks: reporting-search-remediation

Effort in **person-days (d)**. Phases 0–1 are the P0 chain (GL truth);
2–5 are independent of each other after Phase 1's helper module lands
(parallelizable across 2 streams). Server tests fold into each phase.

**Sequential estimate ≈ 8.75 d. With 2 parallel streams after Phase 1:
≈ 6.5 calendar days.**

---

## Phase 0 — GL truth foundation (REP-01/02/03) (~2.25 d)

- [x] 0.1 Capture pre-change outputs on a DB copy: balance sheet, trial balance, dashboard cash, reconciliation, AR/AP aging — the diff baseline for every later step *(0.25 d)*
- [x] 0.2 Migration `backfill-gl-preposting.sql`: balanced entries for pre-posting direct purchases (1200/2000), supplier payments (2000/cash-X), customer payments missing GL lines (cash-X/1100), expenses (6000/cash-X); skip voided docs; `reference_type='BACKFILL'` marker; single opening-equity (3000) entry absorbing the residual; assert debits=credits at end of run; idempotent second run inserts nothing *(0.75 d)*
- [x] 0.3 Rebuild `getBalanceSheet` from `AccountingService.getAllAccountBalances` grouped by `chart_of_accounts.type`; cash = sum of accounts 1000–1040; delete the transactional assembly and the `balanced` identity check between unrelated quantities *(0.5 d)*
- [x] 0.4 `cashService`: expected/opening/closing balances read from GL cash accounts; keep `normalizeCashMethod`, bucket classification and flow breakdown; consumers (dashboard card, cash-flow, reconciliation, drill-downs) unchanged API *(0.5 d)*
- [x] 0.5 Flutter: remove the "Out of Balance" red badge path only when `balanced === true`; add the "provisional — do not file" banner behind a server flag until 0.3 ships *(0.25 d)*
- [x] 0.6 Tests: sheet account == trial-balance account for every shared code; dashboard cash == sheet cash; backfill idempotence; voided documents skipped *(0.5 d)* — folds into 6.1 suite

## Phase 1 — Formula consolidation (REP-05/07 + concepts a/b residue) (~1.75 d)

- [x] 1.1 New `server/src/utils/reportSql.ts`: `netRevenueExpr` fragment (`total_amount − COALESCE(returned_amount,0)` − return fees, `status != 'Cancelled'`) + `cogsForPeriod(db,from,to)`; verify zero `movement_type='OUT'` rows live before dropping the term *(0.5 d)*
- [x] 1.2 Apply `cogsForPeriod` to P&L, gross profit, balance-sheet YTD, Dashboard COGS (delete three duplicated SQL blocks); apply `netRevenueExpr` to daily/monthly sales, DSO denominator, statements revenue sites *(0.5 d)*
- [x] 1.3 Migration `add-invoice-item-tax-columns.sql`: `tax_amount`/`net_amount` columns; dual-interpretation backfill with review list in migration log; writers stamp both on insert (all creation paths); `getTaxSummary` sums stored `tax_amount` *(0.5 d)*
- [x] 1.4 Tests: returned invoice contributes 0 to daily/monthly/DSO; P&L COGS == BS YTD COGS byte-equal; tax summary matches stored tax_amount for quotation-sourced lines *(0.25 d)*

## Phase 2 — Report correctness (REP-04/08/12/13/14-residue/16/17) (~2 d)

- [x] 2.1 Real `getGeneralLedger` from `journal_lines ⋈ chart_of_accounts` (`voided=0`, account code/name, debit/credit, running balance); rename old query `getCustomerLedgerReport`; route/screen contract unchanged *(0.5 d)*
- [x] 2.2 Rebuild `getCustomerStatements` from `customer_ledger`: opening carry-forward, date predicates out of WHERE (LEFT JOIN survives), closing = opening + debits − credits *(0.5 d)*
- [x] 2.3 `todayLocal(db)` helper; replace six UTC defaults in `reportsController.ts`; align `ledgerUtils.ts` `transaction_date` writes *(0.25 d)*
- [x] 2.4 `Customer.ts` getStatement opening-balance lookup gains `, id ASC/DESC` tiebreaker *(0.125 d)*
- [x] 2.5 Implement `GET /reports/expiry` + `GET /dashboard/expiry-alerts` over `stock_batches.expiry_date` (permission-gated); client calls unchanged *(0.375 d)*
- [x] 2.6 Delete `activityLogger.getStats` + `getActivityStats` re-export (import sweep first) *(0.125 d)*
- [x] 2.7 Flutter: add general-ledger, income-statement, tax-summary pairs to `_reportRangePairs` in `report_providers.dart` *(0.125 d)*

## Phase 3 — Search hardening (SRCH-02/03/04/05) (~1.25 d)

- [x] 3.1 Resolve permission Set once per request in `search()` (admin early-exit kept); pass down to entity searches and `filterActions`; remove per-row `getUserPermissions` + role re-query *(0.5 d)*
- [x] 3.2 Gate each entity search on `<module>:read`; add module permissions to permissionless `PAGE_ACTIONS` entries *(0.25 d)*
- [x] 3.3 Status hygiene: invoices exclude Cancelled; warehouses/employees `is_active = 1` *(0.125 d)*
- [x] 3.4 Cap per-entity limit at 10 (controller + route schema); delete dead `rankClause`/`rankParams` *(0.125 d)*
- [x] 3.5 Tests: non-admin fixture (the SRCH-01 lesson); permissionless user gets zero rows; payments-only user sees no expenses; limit=50 → ≤10/entity *(0.25 d)*

## Phase 4 — Custom reports authz (REP-19) (~0.25 d)

- [x] 4.1 Admin-role gate on system-template create (`routes/customReports.ts` + controller check); non-admin system-template attempt → 403; private templates unaffected *(0.25 d)*

## Phase 5 — Dead code + index hygiene (REP-09/10/11, SRCH-07) (~0.5 d)

- [x] 5.1 Repo-wide import sweep, then delete ~17 unrouted `Reports.ts` functions; `typecheck` green *(0.25 d)*
- [x] 5.2 Migration `drop-search-indexes.sql`: drop each plain search index verified unused by non-search queries (grep query planner usage); keep any that serve other reads *(0.25 d)*

## Phase 6 — Verification + cleanup (~0.75 d)

- [x] 6.1 `npm run typecheck` + `npm run lint` zero errors; full jest suite green *(0.25 d)*
- [x] 6.2 Boot against live DB copy: migrations apply once, second boot no-op; diff Phase 0 baseline — sheet balances, trial balance sane, one cash number across four surfaces; expiry endpoints 200 *(0.25 d)*
- [x] 6.3 `flutter analyze` clean; range-pair behaviour verified on general ledger / income statement / tax summary screens; desktop + mobile spot-check *(0.125 d)*
- [x] 6.4 Remove residual dead code flagged during phases; confirm no unused imports; update graphify *(0.125 d)*
