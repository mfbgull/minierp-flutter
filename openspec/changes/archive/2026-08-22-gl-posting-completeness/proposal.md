# Proposal: gl-posting-completeness

## Why

The 2026-08-21 accounting-layer forensic audit (`opus5-audit-report/accounting.md`) reached an architectural verdict: **this is a subledger-authoritative system with a partially-wired, decorative General Ledger bolted on.** The GL's biggest accounts are provably wrong in production data: Inventory Asset is **negative 3,276.20** (COGS credits it on every sale, but purchases never debit it), Cash is **debit-only +4,367** while ₨27,500 of supplier payments physically left the business, AR is **negative 780**, and AP / Expenses / Tax Payable / Equity all have **zero lifetime activity** despite active operational data. The Balance Sheet cannot detect any of this because it bypasses the GL entirely — it reads `stock_batches`, `invoices.balance_amount`, and `supplier_ledger` instead. The Trial Balance (the only GL consumer) therefore disagrees with the Balance Sheet by construction, and no report in the system surfaces the gap.

Beyond missing postings, the ledger layer has integrity defects verified in code and live data: customer-ledger running balances chained by insertion order (`ORDER BY id`) instead of transaction date; every ledger row stamped `date('now')` discarding the document date; reversals implemented as hard DELETEs in three places (live evidence: `customer_ledger` ids 16–31 missing); four mutually inconsistent sources for "a customer's balance" (FACT 6: one customer shows three different balances simultaneously); invoice headers trusted verbatim from the client body while line amounts ignore discount and tax (invoice 24 confirmed: header 1,367 vs lines 1,366.80); and money handled as floats end-to-end with several posting paths bypassing `roundCurrency` entirely.

ACC-11 (the dated 2026-09-01 rollover outage) was already fixed and archived in `audit-p0-critical-fixes`. This change implements the audit's remaining remediation sequence for the accounting layer.

## What Changes

- **Post every financial event to the GL** through `AccountingService.postEntry`: direct purchases (Dr Inventory / Cr AP-or-Cash), supplier payments (Dr AP / Cr cash-per-method), expenses (Dr expense account / Cr cash), POS sales and mobile invoices (route through the shared posting sequence: revenue + COGS + payment), and SO→invoice conversion (also gains its missing `customer_ledger` row). Model each on the two paths the audit certified correct: salary payments (`employeeController.ts:229-248`) and purchase returns (`PurchaseReturn.ts`).
- **Fix update/delete lifecycle voiding**: `updateInvoice` voids and re-posts its journal lines; `Payment.delete`/`Payment.update` void `PAYMENT` lines; the dead orphan-cleanup branch in `deleteInvoice` gets a working "other allocations" predicate.
- **Stop posting POs at commitment**: move the Dr Inventory / Cr AP entry from PO submission to goods receipt; dedupe existing double-debits in `supplier_ledger`.
- **Make the ledger append-only**: add `voided`/`reversed_by` columns to `customer_ledger` and `supplier_ledger`; replace all three hard-DELETE reversal sites with reversing rows; scope ledger deletes/reversals by counterparty id.
- **One truth per balance**: rebuild `customer_ledger` chains in `(transaction_date, id)` order using real document dates; collapse `customers.current_balance` / `credit_balance` writers into one ledger-derived function.
- **Server-authoritative invoice totals**: compute line amounts including discount/tax server-side, sum the header from lines, reject client-supplied totals differing beyond tolerance.
- **GL reconciliation report**: diff every GL account balance against its operational derivation (inventory vs `stock_batches`, AR vs open invoices, cash vs payments) — makes every residual defect visible.
- **Void attribution**: `voided_at`, `voided_by`, `void_reason` on `journal_lines`.

Out of scope (deferred): full integer-cents money migration (interim: enforce rounding at write boundaries); dropping legacy `journal_entries` table unification (ACC-01); equity/drawings/year-end close (ACC-24); tax wiring (ACC-19); period-close enforcement breadth (ACC-23); Flutter client changes.

## Capabilities

### New Capabilities
- `gl-posting-matrix`: Every financial document type posts a complete, balanced journal entry at the economically correct moment, and every mutation path voids or re-posts what it invalidates.
- `ledger-append-only`: Customer and supplier ledgers never delete rows; corrections are reversing entries; balances chain in transaction-date order from real document dates.
- `balance-truth-sources`: Each exposed balance figure has exactly one authoritative derivation, and a reconciliation report proves GL agreement with operational tables.

### Modified Capabilities
<!-- None: existing specs have no requirement changes. -->

## Impact

- **Server code:** `models/Purchase.ts`, `models/Payment.ts`, `models/Expense.ts`, `controllers/posController.ts`, `models/MobileInvoice.ts`, `models/SalesOrder.ts`, `controllers/invoiceController.ts`, `utils/ledgerUtils.ts`, `services/accountingService.ts` (new `postPurchaseEntry`, `postSupplierPaymentEntry`, `postExpenseEntry`, void attribution), `models/Reports.ts` (reconciliation report).
- **Database:** additive migrations only — `voided`/`reversed_by` on both subledgers, void-attribution columns on `journal_lines`, backfill postings for historical purchases/supplier-payments/expenses as one-time scripts. No destructive schema change; existing API contracts preserved.
- **Flutter client:** none required; server now rejects client-computed invoice totals that disagree with line sums (error surfaced through existing toast handling).
- **Tests:** extend `server/src/__tests__/` with posting-matrix tests per document type (assert balanced `journal_lines` rows exist after create/update/delete/void), ledger append-only tests (no DELETE path reachable; reversal rows appear), and reconciliation-report tests on seeded fixtures.
