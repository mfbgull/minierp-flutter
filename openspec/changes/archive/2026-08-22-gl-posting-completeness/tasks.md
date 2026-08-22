# Tasks: gl-posting-completeness

## 1. Void attribution + lifecycle voiding (ACC-08, ACC-09, ACC-21, ACC-22)

- [x] 1.1 Migration: add `voided_at TIMESTAMP`, `voided_by INTEGER REFERENCES users(id)`, `void_reason TEXT` to `journal_lines`; extend `voidJournalLinesByReference` with optional attribution args
- [x] 1.2 In `invoiceController.updateInvoice` transaction: void old INVOICE + COGS lines (attributed) and re-run `postInvoiceEntry`/`postCOGSEntry`; replace the delete-and-reinsert customer-ledger handling per task 3.x once available
- [x] 1.3 In `Payment.delete`: add `voidJournalLinesByReference(db,'PAYMENT',id)` with attribution; in `Payment.update`: void + re-post when amount changes
- [x] 1.4 Fix dead orphan-cleanup branch in `deleteInvoice`: filter `getAllocationsByPaymentId` results to allocations other than the invoice being deleted
- [x] 1.5 Tests: update re-posts with old lines voided+attributed; payment delete leaves zero non-voided PAYMENT lines; invoice delete cleans up its orphaned payment
## 2. Posting matrix completion (ACC-02, ACC-03, ACC-04, ACC-05, ACC-06, ACC-07)

- [x] 2.1 Add `AccountingService.postPurchaseEntry`, `postSupplierPaymentEntry`, `postExpenseEntry` wrappers over `postEntry`; cash-per-method resolution reuses `_cashOrBankAccountCode`
- [x] 2.2 Call `postPurchaseEntry` inside `Purchase.recordPurchase` transaction (Dr 1200 / Cr 2000 or cash); set `stock_movements.financial_posted = 1` for PURCHASE movements
- [x] 2.3 Call `postSupplierPaymentEntry` in `createSupplierPayment` (Dr 2000 / Cr cash-per-method)
- [x] 2.4 Call `postExpenseEntry` in Expense create (Dr 6000 / Cr cash-per-method)
- [x] 2.5 POS sale: add postInvoiceEntry + postCOGSEntry + postPaymentEntry inside `createPOSSale` transaction, following the salary-payment rethrow pattern
- [x] 2.6 Mobile invoice: same posting trio inside `MobileInvoice.submitInvoice`
- [x] 2.7 SO→invoice: add GL trio plus the missing `customer_ledger` INVOICE row inside `SalesOrder.convertToInvoice`
- [x] 2.8 Tests: one balanced-lines assertion per document type (purchase, supplier payment, expense, POS, mobile, SO conversion), modeled on `purchaseReturn.test.ts:238`

## 3. PO commitment removal + dedupe (ACC-16)
- [x] 3.1 Remove `postPurchaseOrderEntry` call and `PURCHASE_ORDER` supplier-ledger debit from PO submission in `PurchaseOrder.ts`
- [x] 3.2 Backfill script `gl:dedupe-po`: reverse redundant PURCHASE_ORDER supplier-ledger debits where a matching PURCHASE debit exists; idempotent via sentinel description; dry-run mode prints affected rows
- [x] 3.3 Tests: PO submission posts nothing; recordPurchase for a PO-backed receipt yields exactly one inventory/AP entry

## 4. Append-only ledgers (ACC-14, ACC-20)

- [x] 4.1 Migration: `voided BOOLEAN DEFAULT 0` and `reversed_by INTEGER` self-reference columns on `customer_ledger` and `supplier_ledger`
- [x] 4.2 Add `ledgerUtils.reverseLedgerEntry(db, table, rowId, reason)`: insert equal-and-opposite row (`REVERSAL:` type prefix, `reversed_by` set), mark original voided=1; reads/balance rebuilds exclude voided rows
- [x] 4.3 Convert hard-delete sites to reversals: `Invoice.deleteLedgerEntryByReference`, `Payment.ts:462-463`, `Purchase.ts:468`; scope all reference-number operations by counterparty id
- [x] 4.4 Tests: no DELETE reachable on ledger tables from mutation endpoints; reversal row pairs verified; colliding reference across customers affects only the owning party

## 5. Ledger chain truth (ACC-12)

- [x] 5.1 `createLedgerEntry` gains required `transactionDate`; store document date; prior-balance lookup ordered by `(transaction_date DESC, id DESC)`
- [x] 5.2 Migrate all callers to pass their document date (invoice_date, payment_date, return date, etc.)
- [x] 5.3 `rebuildLedgerBalances` adopts `(transaction_date, id)` ordering and excludes voided rows
- [x] 5.4 Backfill script `gl:backfill-ledger-dates`: repopulate historical `transaction_date` from source documents via reference_no join, then rebuild balances once; dry-run mode
- [x] 5.5 Tests: backdated insert lands in date position; statement footing equals stored balance column

## 6. Single balance writer (ACC-13)

- [x] 6.1 Add `recalcCustomerBalanceFromLedger(customerId)` (SUM(debit)−SUM(credit) over non-voided rows) in `ledgerUtils`; make it the only writer of `customers.current_balance`
- [x] 6.2 Migrate callers: `updateCustomerBalance` open-invoice sum, return-path credit_balance writes, Payment.ts balance arithmetic
- [x] 6.3 Tests: after any invoice/payment/return mutation, current_balance equals the ledger-derived figure

## 7. Server-authoritative totals (ACC-18 interim)

- [x] 7.1 Compute line amounts server-side as round(qty×price − discount) with tax applied; header total = Σ lines in createInvoice/updateInvoice/POS/mobile paths
- [x] 7.2 Reject client `total_amount` differing by > 0.01 with 400 'total_amount disagrees with line items'
- [x] 7.3 Enforce rounding at remaining bypass sites (`PurchaseOrder.ts` reduce, `posController.ts` total accumulation)
- [x] 7.4 Backfill script `gl:recompute-item-amounts`: recompute existing `invoice_items.amount` from stored qty/price/discount/tax; report header divergences without mutating them
- [x] 7.5 Tests: inflated client total → 400 with nothing written; legit Flutter-shaped totals succeed; discount/tax reflected in stored amount

## 8. Reconciliation report (ACC-10 short-term)

- [x] 8.1 Add `GET /api/accounting/reconciliation` (accounting:read): per pairing return gl_balance, operational_balance, delta — Inventory vs stock_batches, AR vs open invoices, AP vs supplier positions, Cash family vs payment sums
- [x] 8.2 Tests: seeded clean fixture reconciles within 0.01; seeded drift fixture surfaces a non-zero delta

## 9. Verification

- [x] 9.1 `npm run typecheck` and full `npm test` green in `server/`; new suites included
- [x] 9.2 Staging run on a DB copy: `db:backup` → dry-run backfills → apply → reconciliation report shows deltas shrinking to expected residual (historical float artifacts only)
