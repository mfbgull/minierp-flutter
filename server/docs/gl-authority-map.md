# GL authority map (audit task 34)

Goal: `journal_lines` is the authoritative double-entry record. This document is
the dependency map that must exist **before** any consolidation, per the task:
identify every source of accounting truth, who creates entries, who reads them,
who calculates balances independently, and which representations are duplicated.

Line references are against the working tree at the time of writing.

## 1. Scope

- In scope: the general ledger (`journal_lines`), its writers, its readers, and
  every surface that computes an accounting balance without reading it.
- Out of scope: the sub-ledgers (`customer_ledger`, `supplier_ledger`) are
  *not* competing truths — they are the counterparty sub-ledger, reconciled
  against GL control accounts by `getGLReconciliation`. They are documented
  here as a second representation, not proposed for removal.
- Not changed by this document: behaviour. Every defect below is a
  consolidation target, not a silent fix.

## 2. Who creates entries

### 2.1 Canonical path (authoritative)

All production postings funnel through `AccountingService.postEntry`
(`src/services/accountingService.ts`), which validates ≥2 lines, debit XOR
credit per line, debits == credits, and an open accounting period, then inserts
`journal_entries` + `journal_lines`.

19 typed entrypoints call it, all in `accountingService.ts`:

| Entry point | Line | Flow |
|---|---|---|
| `postInvoiceEntry` | 424 | sales invoice (Dr AR / Cr revenue + tax) |
| `postPaymentEntry` | 484 | customer receipt (Dr cash / Cr AR) |
| `postCreditOffsetEntry` | 524 | store credit applied to an invoice |
| `postGoodsReceiptEntry` | 571 | PO receipt (Dr inventory / Cr AP) |
| `postPurchaseEntry` | 608 | direct purchase |
| `postSupplierPaymentEntry` | 648 | supplier payout (Dr AP / Cr cash) |
| `postExpenseEntry` | 688 | expense |
| `postOwnerCapitalEntry` | 795 | owner capital |
| `postOwnerWithdrawalCashEntry` | 832 | owner withdrawal, cash |
| `postOwnerWithdrawalGoodsEntry` | 873 | owner withdrawal, goods |
| `postCOGSEntry` | 997 | cost of goods sold |
| `postCOGSReversalEntry` | 1043 | COGS reversal on return |
| `postInvoiceReturnEntry` | 1101 | sales return |
| `postReturnFeeEntry` | 1175 | restocking fee |
| `postPurchaseReturnEntry` | 1217 | purchase return |
| `postRefundEntry` | 1264 | customer refund (Dr AR / Cr cash) |
| `postSalaryEntry` | 1419 | salary payment |
| `postLegacyStockEntry` | 350 | legacy stock adjustment |
| `postEntry` call sites | 452, 467, 505, 546, 590, 631, 671, 711, 815, 852, 900, 1018, 1070, 1153, 1196, 1237, 1285, 1442, 1485, 1525, 1562 | the internal calls behind the above |

### 2.2 Callers that reach the service directly (acceptable)

- `src/services/cashService.ts:415` — cash movement posting. Goes through
  `AccountingService.postEntry`, so it is canonical; it is listed only because it
  is a second *domain* posting cash.
- `src/models/SupplierRefund.ts:190` — also calls `AccountingService.postEntry`.
  Canonical, but it means a model owns GL posting (see D5).

### 2.3 Migrations (boot-only, historical)

- `src/migrations/backfillInvoiceTaxGl.ts:93` — calls `postEntry`.
- `src/migrations/backfillGlPreposting.ts:25` — inserts `journal_lines` directly
  and says so explicitly. Boot-only, one-off, guarded by migration state.

### 2.4 Writer that bypasses the authority — defect D3

`src/controllers/invoiceController.ts:819-835` runs two raw
`UPDATE journal_lines SET voided = 0 …` statements to un-void an invoice's GL
when a delete is rolled back. This is the **only** production path that mutates
`journal_lines` without `AccountingService`, so it gets none of the service's
guarantees: no period check, no void attribution, no re-validation that the rows
belong to this invoice beyond the hand-written `NOT EXISTS` scoping.

## 3. Who reads entries

### 3.1 Canonical balance primitive

`AccountingService.getAccountBalance` (`accountingService.ts:122`) is the single
balance calculator: it sums `journal_lines` only, excludes `voided = 1`, filters
`line_date <= asOfDate`, and signs the result by the account's `normal_balance`.
`getAllAccountBalances` (`:166`) maps it over the chart.

The docstring notes that legacy `journal_entries` rows are migrated into
`journal_lines` by the GL-unification boot migration, so summing both tables
would double-count — i.e. `journal_entries` is a historical table, not a live
truth.

### 3.2 Surfaces already GL-derived

| Surface | Line | Source |
|---|---|---|
| `getTrialBalance` | `Reports.ts:559` | `getAllAccountBalances` |
| `getBalanceSheet` | `Reports.ts:439` | `getAllAccountBalances` |
| `getGLReconciliation` (GL side) | `Reports.ts:1231` | `getAccountBalance` per account |
| `getAccountBalance` API | `accountingController.ts:139` | `getAccountBalance` |
| `assertSufficientFunds` | `accountingService.ts:949` | `getAccountBalance` |
| cash account totals | `cashService.ts:341` | `getAccountBalance` |
| production-output orphan check | `Production.ts:555` | existence count over `journal_lines` |

### 3.3 Reads that duplicate the query but not the truth

- `getGeneralLedger` (`Reports.ts:601`) hand-rolls `journal_lines ⋈
  chart_of_accounts` with a window-function running balance. Same source, same
  voided exclusion, different projection. Legitimate as a report shape, but it is
  a second implementation of "GL lines with a running balance".
- `voidJournalLinesByReference` (`accountingService.ts:1312`) is the single
  voiding primitive, used by `Invoice.ts:1068` and `PurchaseReturn.ts:712`.
- `getCustomerLedgerReport` (`Reports.ts:632`) reports the `customer_ledger`
  sub-ledger, not the GL.

## 4. Who calculates balances independently — the core problem

These surfaces never read `journal_lines`; they recompute accounting figures
from operational tables via the helpers in `src/utils/reportSql.ts`
(`netRevenueSum`, `NET_REVENUE_STATUS`, `cogsForPeriod`, `ACTIVE_EXPENSE_STATUS`).

| Surface | Line | Independent source |
|---|---|---|
| `getProfitLossReport` | `Reports.ts:406` | `invoices` + `stock_movements` + `expenses` |
| `getIncomeStatement` | `Reports.ts:542` | delegates to the P&L above |
| `getGrossProfit` | `Reports.ts:1081` | `invoices` + `cogsForPeriod` |
| `getTaxSummary` | `Reports.ts:1054` | `invoices` |
| `getDailySales` / `getMonthlySales` | `Reports.ts:1065` / `:1073` | `invoices` |
| `getARAgingReport` | `Reports.ts:6` | `invoices` |
| `getReceivablesSummary` | `Reports.ts:131` | `invoices` |
| `getTopDebtors` | `Reports.ts:97` | `invoices` |
| `getDSOMetric` | `Reports.ts:114` | `invoices` |
| `getCustomerStatements` | `Reports.ts:33` | `invoices` + `customer_ledger` |
| `getAPAgingReport` | `Reports.ts:393` | `supplier_ledger` |
| `getInventoryValuation` | `Reports.ts:767` | `stock_batches` / `items` |
| `getCashFlow` | `Reports.ts:857` | cash accounts (balances via the service) |

**Consequence:** the income statement and the balance sheet are computed from
different truths. The trial balance is internally balanced, and the balance sheet
satisfies the accounting identity internally, but the P&L's revenue/COGS/expenses
are *not* proven to equal the GL movements in the same accounts. Any drift
between the operational tables and the journal is invisible on the P&L while it
is visible in `getGLReconciliation`. This is defect D4 and the main
consolidation target.

## 5. Duplicate accounting representations

1. `journal_lines` — the GL (target authority).
2. `journal_entries` — legacy, text_code-keyed, migrated at boot, no longer read
   as a live truth.
3. `customer_ledger` / `supplier_ledger` — counterparty sub-ledgers with their
   own running balances; reconciled, not redundant, but they are a second
   representation of the same AR/AP facts.
4. `invoices.paid_amount` / `balance_amount` — denormalised AR state, the source
   of truth for every AR aging surface.
5. `items.current_stock` vs `stock_batches` — inventory has two representations
   (task 35's subject).
6. `cash_reconciliations.counted_balance` — a physical count, compared against
   the GL-derived cash balance.

## 6. Defects found

| ID | Defect | Location |
|---|---|---|
| D1 | `getTrialBalance`'s `note` claims the report unions `journal_lines` with legacy `journal_entries` matched by `text_code`. That union no longer exists; `getAccountBalance` reads `journal_lines` only. The note is actively misleading. | `Reports.ts:594-597` |
| D2 | Same stale "journal_lines ∪ legacy journal_entries" claim in the balance-sheet comment. | `Reports.ts:441-443` |
| D3 | Raw `UPDATE journal_lines` outside `AccountingService` (invoice delete rollback), bypassing the period guard and void attribution. | `invoiceController.ts:819-835` |
| D4 | Income statement is not GL-derived, so the accounting identity does not hold *across* statements by construction. | `Reports.ts:406`, `:542` |
| D5 | A model (`SupplierRefund.ts:190`) posts to the GL, so GL posting is not exclusively a service concern. | `SupplierRefund.ts:190` |

## 7. Consolidation plan (incremental)

Each step is independently revertible and must leave every reconciliation
invariant at zero.

1. **Measure, don't assume** — an invariant suite that asserts (a) trial balance
   debits == credits, (b) `getAccountBalance` equals an independent
   `journal_lines` aggregation for every account (proving one balance model), and
   (c) the drift between GL-derived revenue/COGS/expenses and the P&L's
   operational figures. Step 4 is only safe if (c) is zero.
2. **Fix the misleading documentation** (D1, D2) — zero behaviour change.
3. **Move the un-void behind the authority** (D3) — give the service a
   `restoreJournalLinesByReference` primitive so the period guard and attribution
   rules apply on rollback too.
4. **GL-derive the income statement** (D4) — only if step 1(c) measured zero
   drift, so reported numbers do not move. The per-category expense breakdown has
   no GL dimension and must be preserved from the operational table as
   presentation detail, with the total taken from the GL.
5. **Leave D5** unless a second model starts posting; note it as an accepted
   exception rather than churn a working module.

## 8. Invariants that must remain zero

- Trial balance: `|Σdebit − Σcredit| < 0.01`.
- `getGLReconciliation`: every `delta` (inventory, AR, AP, cash) is `0`.
- GL-derived vs operational revenue/COGS/expenses drift: `0`.
- For every account: `getAccountBalance` equals a direct `journal_lines`
  aggregation — i.e. exactly one balance model exists.

## 9. What was consolidated in this pass

Steps 1–4 of the plan above are done. Step 5 was deliberately left alone.

**Step 1 — measured, not assumed.** `src/__tests__/glAuthority.test.ts` asserts
the trial balance is balanced, that `getAccountBalance` equals an independent
`journal_lines` aggregation for *every* account (a deliberately different query,
so it is a real cross-check and not a tautology), and that GL-derived revenue,
COGS and operating expenses equal the operational figures. The scenario covers a
fully-paid invoice, a 10%-tax invoice, a sales return, a credit purchase and an
expense. Drift measured **zero** in every case, which is what made step 4 safe.

**Step 2 — misleading documentation corrected (D1, D2).** `getTrialBalance`'s
`note` and the `getBalanceSheet` comment both claimed the report unions
`journal_lines` with legacy text_code-keyed `journal_entries`. That union has not
existed since the GL-unification boot migration; summing both would double-count.
Both now state the journal_lines-only source.

**Step 3 — the bypass writer is gone (D3).** `AccountingService.restoreJournalLinesByReference`
is the new inverse of `voidJournalLinesByReference`, and the invoice-delete
rollback calls it instead of issuing raw `UPDATE journal_lines`. `journal_lines`
now has exactly one production mutator: the accounting service (plus boot-only
migrations). The `owningInvoiceId` option preserves the id-space collision
guard the hand-written SQL had.

**Step 4 — the income statement is GL-derived (D4).** `getProfitLossReport` (and
therefore `getIncomeStatement`, which delegates to it) now reads revenue
(`4000` net of debit-normal contra `4100`), COGS (`5000`) and operating expenses
(`6000`) from `journal_lines` through the new
`AccountingService.getPeriodMovement` primitive, instead of re-deriving them from
`invoices`, `stock_movements` and `expenses`. Reported figures are unchanged —
the pre-conversion drift measurement was zero — but the income statement and the
balance sheet now read the same store, so the accounting identity holds across
statements by construction rather than by coincidence.

The per-category expense breakdown has no dimension in the GL (6000 postings
carry only a description), so the breakdown array stays operational while the
authoritative *total* comes from the journal. `glAuthority.test.ts` fails if the
two ever diverge, so drift becomes a build failure instead of a silent number.

**Step 5 — not done, on purpose.** `SupplierRefund.ts:190` posts to the GL from
a model. It goes through `AccountingService.postEntry`, so it is canonical
already; moving it would churn a working module for no accounting gain. Recorded
as an accepted exception.

**Still open, for a future pass** (all measured and documented, none urgent):

- `getGrossProfit` (`Reports.ts:1081`) still derives revenue and COGS from the
  operational tables, exactly as the P&L did. It should adopt
  `getPeriodMovement` too; it was left out to keep this pass's blast radius on
  the statements under audit.
- The AR/AP/tax/sales surfaces in §4 remain operational by design — they report
  the sub-ledger view, and `getGLReconciliation` is what proves the two agree.
  Making them GL-derived would change their semantics, not just their source.
- `getGeneralLedger` (`Reports.ts:601`) still hand-rolls its window-function
  running balance. Same source, different projection, so this is duplication of
  query rather than of truth.
- `items.current_stock` vs `stock_batches` (inventory's two representations) is
  audit task 35's subject.
