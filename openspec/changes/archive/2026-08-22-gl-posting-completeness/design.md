# Design: gl-posting-completeness

## Context

Source: `opus5-audit-report/accounting.md` (forensic audit, 2026-08-21), findings ACC-02…ACC-22 plus remediation order in its PART 6. All line-level claims re-verified against current source on 2026-08-22 before this design was written. ACC-11 (rollover outage) is already fixed by the archived `audit-p0-critical-fixes` change and is out of scope here.

Live-data evidence motivating this change: Inventory Asset −3,276.20; Cash debit-only +4,367 vs ₨27,500 of real supplier payments; AR −780; AP/6000/2100/3000/3100 all zero-activity; `customer_ledger` ids 16–31 hard-deleted; one customer holding three different balances at once.

Constraints: better-sqlite3 synchronous single-writer, transactions nest as SAVEPOINTs (safe — audit PART 3 item 9); prepared statements only; additive migrations preferred; no Flutter changes; API contracts preserved.

## Goals / Non-Goals

**Goals:**
- Every financial document type produces a balanced GL entry at the economically correct moment.
- Every mutation path (update, delete, cancel, void) leaves no active orphaned GL lines and no deleted subledger rows.
- One derivation per exposed balance; a report that proves GL ↔ operational agreement.
- Server is authoritative over invoice money.

**Non-Goals:**
- Integer-cents storage migration (ACC-15 full fix) — interim rounding enforcement only.
- Unifying/dropping legacy `journal_entries` (ACC-01) — three writers stay but gain period checks later.
- Equity/drawings/year-end close (ACC-24), tax-rate wiring (ACC-19), period-close breadth (ACC-23).
- Any Flutter client work.

## Decisions

**D1 — Posting matrix implemented per-path inside existing transactions (no new abstraction layer).**
Each writer calls new thin wrappers on `AccountingService`: `postPurchaseEntry(db, {purchaseId, purchaseNo, totalCost, paymentMethod?, supplierId?})`, `postSupplierPaymentEntry`, `postExpenseEntry`. Each wrapper funnels into the proven `postEntry` (>=2 balanced lines, SAVEPOINT nesting). Rationale: the audit's certified reference paths (`employeeController.ts:229-248`, `PurchaseReturn.ts`) are exactly this shape — call inside transaction, persist returned group id, rethrow with context. A generic "posting engine" abstraction is refused; seven document types with genuinely different shapes would force option-bags onto the two simplest wrappers.

Posting rules (debit/credit per account codes already seeded):
| Document | Entry | Timing |
|---|---|---|
| Direct purchase | Dr 1200 / Cr 2000 (credit) or Cr cash-per-method (paid) | at `recordPurchase` commit |
| Supplier payment | Dr 2000 / Cr cash-per-method | at `createSupplierPayment` |
| Expense | Dr 6000 / Cr cash-per-method | at expense create |
| POS sale | postInvoiceEntry + postCOGSEntry + postPaymentEntry | at sale |
| Mobile invoice | same trio | at submit |
| SO→invoice | same trio + missing `ledgerUtils.createLedgerEntry` row | at conversion |

Cash-per-method resolution reuses the existing `_cashOrBankAccountCode` mapping.

**D2 — Update/delete = void + re-post, never silent divergence.**
`updateInvoice`: add `voidJournalLinesByReference(db,'INVOICE',invoiceId)` + COGS reversal before re-running `postInvoiceEntry`/`postCOGSEntry` inside the existing transaction. `Payment.delete`: add `voidJournalLinesByReference(db,'PAYMENT',id)` next to the existing subledger cleanup. `Payment.update`: void + re-post when amount changed. The dead branch in `deleteInvoice` (audit ACC-21) gets `getAllocationsByPaymentId(...).filter(a => a.invoice_id !== invoiceId)` so orphaned-payment cleanup actually runs. Alternative rejected: mutating posted lines in place — destroys the trial balance reproducibility.

**D3 — PO posting moves from commitment to goods receipt; historical double-debits deduped by backfill script.**
Remove `postPurchaseOrderEntry` + the `PURCHASE_ORDER` supplier-ledger debit from PO submission (`PurchaseOrder.ts:170-191`). `recordPurchase` becomes the sole poster. One-time script pairs each existing `PURCHASE_ORDER` supplier-ledger debit with the matching later `PURCHASE` debit for the same supplier+PO and writes a reversing credit row for the duplicate, tagging `description='PO commitment reversal (backfill)'`. Idempotent via sentinel check on that description. Alternatives rejected: keeping commitment postings + reversing at receipt (two entries where one suffices); encumbrance table (new concept, no consumer).

**D4 — Append-only ledgers via reversing rows + counterparty-scoped operations.**
Additive migration: `ALTER TABLE customer_ledger ADD COLUMN voided BOOLEAN DEFAULT 0; ADD reversed_by INTEGER REFERENCES customer_ledger(id)` (same for `supplier_ledger`). New `reverseLedgerEntry(db, table, rowId, reason)` inserts an equal-and-opposite row (`transaction_type` prefixed `'REVERSAL:'`) carrying `reversed_by = original.id`, marks the original `voided = 1`. The three hard-delete sites (`Invoice.ts:892`, `Payment.ts:462-463`, `Purchase.ts:468`) convert to reversal calls; ledger reads filter `voided = 0`; `deleteLedgerEntryByReference` gains the counterparty predicate (audit ACC-20) as defense-in-depth even though it now reverses instead of deletes. Balance-chain rebuild treats voided rows as excluded.

**D5 — Ledger chain ordered by (transaction_date, id) with real dates.**
`createLedgerEntry` gains a required `transactionDate` parameter (callers pass the document date they already hold: invoice_date, payment_date). Insert computes prior balance via `SELECT ... ORDER BY transaction_date DESC, id DESC LIMIT 1`. One-time backfill repopulates `transaction_date` from source documents joined on `reference_no`, then rebuilds all stored balances in `(transaction_date, id)` order. `rebuildLedgerBalances` adopts the same ordering. Window-function-at-read-time (the audit's preferred end state) is deferred — the stored column stays because three screens read it directly.

**D6 — Single customer-balance writer.**
New `recalcCustomerBalanceFromLedger(customerId)` in `ledgerUtils` = `SUM(debit) - SUM(credit)` over non-voided rows; `customers.current_balance` updated only by it. Return-time `credit_balance` writes are removed (credit memos remain visible as ledger credits). Callers of `Customer.recalculateBalance` (open-invoice sum) and the `Payment.ts:228-240` arithmetic path migrate to the one function. Status-string fragility (silent zeroing on unknown status) disappears with the open-invoice-sum basis.

**D7 — Server-authoritative invoice totals.**
Line amount: `roundCurrency(qty × unit_price − discountAmount)` then tax applied per line; header total = Σ lines, computed in the controller before the transaction. If client `total_amount` differs by > 0.01 → 400 `total_amount disagrees with line items`. Same enforcement added to POS and mobile-invoice totals. Historical `invoice_items.amount` recomputed by backfill script; divergent invoice headers get a reconciliation listing rather than silent mutation.

**D8 — Reconciliation report endpoint `GET /api/accounting/reconciliation`.**
Per account pair: GL balance (existing `getAccountBalance`) vs operational derivation (Inventory ← `stock_batches` cost value; AR ← Σ open-invoice balances; AP ← Σ latest supplier_ledger balance; Cash family ← payments-side sum), each row returning both figures and the delta. Read-only, `accounting:read` gated. This is the audit's "highest-value single addition": it makes every residual defect measurable without changing behavior.

**D9 — Void attribution columns on `journal_lines`.**
Migration adds `voided_at TIMESTAMP`, `voided_by INTEGER REFERENCES users(id)`, `void_reason TEXT`; `voidJournalLinesByReference` gains optional attribution args, populated by all mutation-path callers added in D2. Existing voids keep NULL attribution (historical fact).

## Risks / Trade-offs

- [Backfill scripts mutate production data] → every script is idempotent (sentinel descriptions / `financial_posted` flags), runs inside transactions, prints a dry-run summary first, and `npm run db:backup` is documented as the mandatory preceding step (mechanism shipped in `audit-p0-critical-fixes`).
- [POS/mobile refactors touch high-traffic paths] → postings are pure additions inside existing transactions; failure rethrows like the salary reference path, rolling back atomically. No request-shape changes.
- [Removing PO-commitment postings changes supplier balances] → dedupe backfill restores ledger correctness; suppliers page reads rebuilt balances; release note flags the one-time shift.
- [Stored `balance` column kept (D5) rather than window functions] → read-time computation is cleaner long-term but breaks three direct readers today; column stays, ordering fixed, deferred note recorded.
- [Client-supplied totals now rejected] → legitimate clients already send line-derived sums (Flutter form computes them); tolerance 0.01 absorbs display rounding. Mismatch is either a bug or ACC-18's fraud scenario — rejecting is the point.
- [Scope pressure toward ACC-01 unification] → explicitly resisted; dual-table UNION reads are correct today (audit PART 3 item 5) and unification risks 44 legacy rows for zero user-visible gain.

## Migration Plan

1. Land additive schema migrations (voided/reversed_by columns; journal_lines attribution columns) — deployable independently.
2. Land code fixes in dependency order: D9 attribution → D2 lifecycle voiding → D1 posting wrappers per document type (purchase, supplier payment, expense, POS, mobile, SO) → D4 append-only conversions → D5 chain/date fixes → D6 single balance writer → D7 server-authoritative totals → D8 reconciliation endpoint.
3. Backfill scripts last, each behind its own npm alias (`gl:backfill-purchases`, `gl:dedupe-po`, `gl:backfill-ledger-dates`): backup → dry-run → apply → verify via reconciliation report.
4. Rollback strategy: code reverts are ordinary; migrations are additive; backfill effects are auditable reversing rows, not deletions.

## Open Questions

- Should the reconciliation report also be surfaced in the Flutter dashboard as a health widget, or API-only for now? (Leaning API-only — client scope is frozen.)
- Expense-category→account mapping: single 6000 account for v1 (audit minimum) or mapping table now? (Leaning 6000-only; mapping table needs product input on categories.)
