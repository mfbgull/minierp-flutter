## Context

The audit (`opus5-audit-report/reports.md`) found 26 defects across reporting, the custom-reports engine and global search. Four are already fixed by in-flight work (SRCH-01 bind param, REP-06 mobile FIFO cost, REP-15 void-on-delete, REP-18 expression validator) and are excluded. The rest reduce to three root problems:

1. **No single accounting truth.** The balance sheet assembles assets/liabilities/equity from unrelated transactional tables while the trial balance reads the GL — inventory disagrees by ₨95,015 between two screens; cash disagrees by ₨23,100 between dashboard (cashService aggregation) and balance sheet (GL `cash` account only). Historical documents predate live GL posting (gl-posting-completeness landed going forward only), so GL data itself is absurd until backfilled.
2. **Duplicated formulas.** Revenue appears as ≥3 SQL variants (Cancelled/returns handling differs), COGS SQL is pasted three times with a divergent `'OUT'` term, tax is re-derived from a possibly tax-inclusive column.
3. **Search trusts authentication alone.** Any authenticated user reads all entity rows; permissions gate only action buttons; per-row permission lookups make each keystroke ~650×3 queries; cancelled/inactive records surface.

Verified live scale keeps everything proportionate: ~45 searchable rows total, 1 user, tiny financial history — full backfill is cheap, FTS5 is unwarranted.

## Goals / Non-Goals

**Goals**
- One source of truth per money figure: GL for accounting statements, shared fragments for revenue/COGS/tax.
- Trial balance, balance sheet, dashboard cash, reconciliation and cash-flow all agree by construction.
- Global search enforces row-level read permissions with bounded query cost.
- Delete dead formulas so they cannot resurface.

**Non-Goals**
- No new report screens or KPI redesign (product decisions).
- No FTS5/trigram search infrastructure at this scale.
- No change to posting logic itself (gl-posting-matrix already governs it) — only backfill of what predates it.
- No client-side recomputation introduced; Flutter screens stay pure presentation (verified correct today).

## Decisions

### 1. The GL is canonical — not cashService
`balance-truth-sources` and `gl-posting-matrix` (already deployed specs) committed to GL-per-method-cash-accounts architecture; the trial balance is also the document an accountant files. Reversing (making cashService canonical and demoting the GL) would invalidate those capabilities. The balance sheet therefore reads `getAllAccountBalances` grouped by `chart_of_accounts.type`, and cash = sum of accounts 1000–1040.

### 2. Backfill history; reject a cutover date
Live financial history is tiny (5 invoices, 3 POs, 9 payments, 1 expense). A one-time idempotent migration posts balanced entries for pre-posting documents (purchases → 1200/2000, supplier payments → 2000/cash-X, customer payments lacking GL lines → cash-X/1100, expenses → 6000/cash-X) plus a single Owner's Equity entry absorbing the residual so the sheet balances exactly. Entries marked `reference_type='BACKFILL'`; second run is a no-op. A cutover date would leave every historical statement permanently unexplainable for zero engineering savings.

### 3. cashService becomes a GL reader for balances, keeps classification for flows
Its bucket/normalize logic (`normalizeCashMethod`, unclassified handling) survives for flow breakdowns and reconciliation counting; only expected/opening/closing *balances* switch from independent aggregation to GL account balances. This kills the −20,100 vs +3,000 split without rewriting consumers — dashboard card, cash-flow, reconciliation and drill-downs keep their API.

### 4. Shared formula fragments live in one server module
New `server/src/utils/reportSql.ts`: exported `netRevenueExpr` (SQL fragment constant) and `cogsForPeriod(db, from, to)`. All call sites (P&L, gross profit, income statement via delegation, balance-sheet YTD, Dashboard COGS, daily/monthly sales, DSO, statements) consume them. The balance-sheet-only `'OUT'` movement term is dropped **after** verifying zero `'OUT'` rows exist in live data (audit UNVERIFIED #3); if rows exist the helper includes them and a follow-up normalizes the writers.

### 5. Tax moves to stored per-line columns with a dual-interpretation backfill
Add `invoice_items.tax_amount` / `net_amount`. Backfill recomputes both interpretations (tax-exclusive vs tax-inclusive) per line; where the stored `amount` matches the inclusive form within 0.01, use it; otherwise use the exclusive form. Unresolvable lines fall back to current behaviour and are written to a review list surfaced in the migration log — no silent guessing. `getTaxSummary` sums `tax_amount`.

### 6. Statements rebuilt from customer_ledger, not invoices
`getCustomerStatements` switches to ledger rows (which carry dates, debits, credits and the running balance) with explicit opening carry-forward; date predicates move out of WHERE so childless customers survive; closing = opening + Σdebits − Σcredits. This replaces the invoice-balance-column approach whose WHERE/ON branches disagree.

### 7. Search: resolve permissions once, gate rows, keep navigation-only actions
The permission Set resolves once per request (admin early-exit preserved) and is passed to every entity search and to `filterActions`. An entity search runs only if the caller holds its `<module>:read`. Status hygiene (`is_active = 1`; Cancelled invoices excluded), per-entity cap 10, dead `rankClause`/`rankParams` deleted. LIKE stays; no index changes beyond dropping unusable ones.

### 8. Expiry endpoints get implemented, not removed
Removing user-facing screens is a product decision; the default is the minimal backend: `/reports/expiry` lists batches by `expiry_date` window, `/dashboard/expiry-alerts` returns soon-expiring counts. Both additive, behind existing permissions.

### 9. Dead code deletion is import-gated
The ~17 unrouted `Reports.ts` exports are deleted only after grepping the whole repo for references outside `routes/`/`controllers/` (the audit left this unverified) plus `npm run typecheck` green. Same gate for `activityLogger.getStats` (its only wired caller uses `ActivityLog.getStats`).

## Risks / Trade-offs

- **cashService rewrite has the widest blast radius** (dashboard, reconciliation, cash-flow, drill-downs). Mitigation: parity harness comparing old vs new outputs on a copy of the live DB before switching consumers; consumers flip in the same commit so there is no mixed-truth window.
- **Backfill correctness on odd historical states** (voided/partial docs). Mitigation: skip voided documents, assert debits = credits after run, snapshot DB first, run twice in CI fixture to prove idempotence.
- **Tax backfill ambiguity** on legacy lines. Mitigation: dual-interpretation match + review list; worst case some lines keep today's (documented-imperfect) numbers rather than newly wrong ones.
- **Search payloads shrink** for restricted users — intended security outcome, may surprise single-admin deployments not at all (admin sees everything).
- **Dropping search indexes** removes perceived safety nets. Mitigation: check each index for non-search query usage before dropping; keep those.

## Migration Plan

Ledgered migrations (existing `runLedgered` pattern), applied in order on boot:

1. `add-invoice-item-tax-columns.sql` — columns + backfill + review-list logging.
2. `backfill-gl-preposting.sql` — document postings + opening equity, `BACKFILL` marker.
3. `drop-search-indexes.sql` — verified-unused index drops.

Verification sequence mirrors financial-audit task 6.2: restore DB copy → boot (migrations apply once) → reboot (no-op) → compare balance sheet / trial balance / dashboard cash / AR/AP aging against pre-change captures → jest suite green.

## Open Questions

- **Expiry screens**: implement (chosen default) vs remove screens — trivial to reverse if product prefers removal.
- **`movement_type='OUT'`**: treat as COGS-equivalent in `cogsForPeriod` or drop the term — decided at implementation by checking live row distribution (expected: zero rows).
