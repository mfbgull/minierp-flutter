# Owner Capital & Withdrawals — Implementation Plan (approved; final additions incorporated)

## Accounting model
| Event | Debit | Credit |
|---|---|---|
| Capital (money in) | Cash/Bank/Wallet acct per `_cashOrBankAccountCode` | **3200 Owner Capital** |
| Cash withdrawal | **3300 Owner Drawings** | Cash/Bank/Wallet acct |
| Goods withdrawal | **3300 Owner Drawings** (Σ actual batch cost, server-calculated) | Inventory Asset acct(s) resolved by text_code `inventory_asset` |

COA protection: only writers are seed migrations (INSERT OR IGNORE); no account-create API exists ⇒ 3200/3300 provably conflict-free. Migration assigns text_codes `owner_capital`/`owner_drawings`; ALL runtime resolution by text_code, codes display-only. Post-migration boot assertion fails hard if slots occupied. Accounts parented under 3000; 3000/3100/opening_balances untouched.

## Business rules
- **Costing:** existing `consumeFromOldestBatches` (same path as sales COGS): FEFO when `has_expiry=1`, else FIFO by received_date/id; actual per-batch costs; one stock_movements row per batch.
- **Server-authoritative:** POST accepts only `{item_id, warehouse_id, quantity}`; client costs/amounts/batches/GL data rejected. Quote endpoint informational; POST always recalculates inside the write transaction.
- **Stock shortage:** blocked; atomic rollback; 400 with available-vs-required.
- **Funds check — all cash-out paths:** shared `assertSufficientFunds(db, accountId, amount, asOf)` built on the EXISTING `getAccountBalance(asOfDate)` primitive (`accountingService.ts:111`, supports dated queries) — **as-of the transaction's effective date**, matching the established balance function; no second balance model invented. Applied to expense create/update, supplier payments, owner cash withdrawals, customer refunds.
- **Sales tax:** deferred; posters multi-line capable for future output-tax line.
- **Audit trail:** GL lines reference_type/reference_id; movements doctype/docno/batch_id; soft voids only; void attribution columns (voided_at/by/reason) on journal_lines (existing) and both new tables.
- **Closed periods:** postings into closed periods rejected; edit/delete of txns dated in closed periods blocked.
- **Edit policy:** all editable/deletable; diff-based (note-only = metadata-only; money/stock changes = atomic reverse→void→re-consume→repost); delete = soft-void + compensating movements.
- **Reversal integrity:** stock_movements immutable — reversals insert POSITIVE compensating rows (sign convention verified in source: positive = inbound, e.g. SALE posts −consumed): `-5 (WD) +5 (REVERSAL) −7 (new WD) = −7`. Restore into exact original batch_ids; hard-block if batch row missing; legacy NULL-batch case (pre-batch-tracking stock @ standard_cost — verified sole source of NULL) restores via new inbound batch at original unit_cost.

## Idempotency / duplicate-posting invariant (new)
Within every write transaction, before posting: assert no current (non-voided) journal_lines exist for the reference (owner_capital|owner_withdrawal, id) and no active OWNER_WITHDRAWAL movements exist for the docno — exactly one live posting per business transaction, ever. Enforced by pre-post check (synchronous single-connection ⇒ race-free) + regression test simulating double-submit/retry-after-timeout.

## Shared-funds-check rollout protocol (new)
Per existing path (expenses → supplier payments → refunds): 1) identify its transaction boundary; 2) its payment-account resolution; 3) its existing GL posting behavior; then 4) add assertSufficientFunds INSIDE that boundary; 5) regression-test existing behavior first. No refactoring of unrelated code; refund flow handled last and most carefully.

## 1. Migration — `add-owner-equity.sql`
- COA rows + rollback file + boot assertion.
- owner_capital(capital_no UNIQUE, capital_date, amount>0, payment_method, note, status DEFAULT 'posted', voided_at/by/reason, created_by, timestamps)
- owner_withdrawals(withdrawal_no UNIQUE, withdrawal_date, kind CHECK('cash','goods'), amount server-calculated, payment_method NULL, note, status, void attribution, created_by, timestamps)
- owner_withdrawal_items(withdrawal_id FK CASCADE, item_id, warehouse_id, quantity>0) — user intent only; actual batch outcomes live in stock_movements.
- Register via runLedgered in database.ts boot.

## 2. Backend
- accountingService.ts: 3 poster statics (multi-line), expose isPeriodOpen, add assertSufficientFunds.
- OwnerCapital.ts / OwnerWithdrawal.ts: CAP-/WD- numbering in-transaction (+UNIQUE); db.transaction everywhere; diff-based edit; soft-void delete; duplicate-posting invariant pre-check; overdraft check in-transaction (single-process better-sqlite3 ⇒ serialized).
- Routes/controller mirroring expenses.ts conventions (authenticateToken, requirePermission('owner_equity', read/create/edit/delete) — verified admin-bypass no-op today — sensitiveOperationLimiter, try/catch structured responses, audit logCRUD).
- Endpoints: GET/POST /capital; PUT/DELETE /capital/:id; GET/POST /withdrawals(?kind=); PUT/DELETE /withdrawals/:id; POST /withdrawals/quote; GET /summary {totalCapitalIn, totalWithdrawnCash, totalWithdrawnGoods, netContributions}; GET /payment-method-options.
- Mount /api/owner-equity before SPA catch-all.

## 3. Frontend
- endpoints.dart consts; models/owner_equity.dart; repositories/owner_equity_repository.dart.
- features/owner_equity/: owners_equity_shell.dart (purchasing_shell clone; cards: Total Capital In / Total Withdrawn / Net Contributions); capital tab + withdrawals tab (expenses-screen clones; toolbar search/date/kind filter/refresh/CSV/New; PlutoGrid; pagination; error panel; voided hidden; double-tap goods row → batch breakdown dialog).
- Capital dialog: date/amount/method/note; edit/delete parity with expenses.
- Withdrawal dialog: Cash/Goods selector; goods lines = item + qty + explicit warehouse (no WH-001 hard-code); live quote preview (per-batch costs, total = cost not retail); calculated amount disabled; server insufficient-stock/funds errors shown inline.
- Nav: ShellDestination('/owners-equity', Icons.savings_outlined) + app.dart case + module_refresh registration; l10n en.arb + ur.arb; flutter gen-l10n.

## 4. Report fix (verified real bug)
sumType('equity') sums normal-signed balances raw ⇒ debit-normal drawings would increase equity. Negate debit-normal equity accounts in Reports.ts equity calc (pattern exists for contra-revenue 4100). Split balance-sheet equity display: Owner Capital / Retained Earnings / Owner Drawings (negative).

## 5. Tests & self-audit
New tests (models.test.ts temp-DB pattern):
- Accounting equation after every op (per-entry ΣDr=ΣCr + whole-ledger).
- Zero-profit regression: capital +100k / cash WD −10k / goods WD −5k ⇒ Assets Δ+85k, Equity: Capital+100k, Drawings−15k, Revenue=Expenses=Profit=0.
- Mixed-batch + multi-item withdrawal: batches @100/@120 consumed FEFO; Dr Drawings = Σcost; Cr inventory line(s) per resolved account; **Σ inventory credits = Drawings debit**; exercises multi-line GL + text_code resolution.
- Duplicate-posting invariant (retry simulation); overdraft 400 incl. expenses/supplier payments paths; insufficient-stock 400; closed-period blocks; edit/delete restores exact batches/costs; quote-vs-POST consistency; void preserves audit trail.
- Run FULL existing test suite, not just new tests.

Implementation directives: reuse established services/conventions — no redesign of accounting/inventory architecture; no unrelated refactoring; POST recalculates costing always; never trust client-supplied cost/amount/batch/GL data; never mutate historical movements/journals; atomicity across record+inventory+GL+audit preserved everywhere.

Final gate: npm run typecheck && npm run lint (server), flutter analyze — clean; manual verification pass; `graphify update .`.

## Affected files (~25)
Backend: add-owner-equity.sql(+rollback), database.ts, accountingService.ts, Expense.ts/payment/refund paths (funds check only), OwnerCapital.ts*, OwnerWithdrawal.ts*, ownerEquityController.ts*, routes/ownerEquity.ts*, app.ts, Reports.ts.
Frontend: endpoints.dart, owner_equity.dart*, owner_equity_repository.dart*, features/owner_equity/ (5)*, app_shell.dart, app.dart, module_refresh.dart, en.arb, ur.arb. (*new)