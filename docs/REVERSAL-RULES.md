# Transaction Reversal Rules (Implementation Specification)

Status: Phases 1-3 implemented. Scope: every destructive/reversal path.

This document is the single implementation specification for all delete/cancel/void/reverse operations. No destructive path may be changed without conforming to these rules. The reference implementation is Purchase.void (server/src/models/Purchase.ts).

## 1. Non-negotiable rules

1. **Financially-touched means never hard-delete.** Once a transaction has affected stock, subledger, GL, or cash, destructive operations void/reverse it and retain the original record. Hard delete is allowed only for genuinely pre-financial drafts (Draft quotations, Draft SOs, Draft POs and their line items, pre-financial salary drafts, expense categories not in use).
2. **One reversal primitive per document type.** Every path that removes/cancels a document (dedicated endpoint, parent cancel, bulk action) must consume the same primitive. Invoice cancellation has exactly one implementation; SO.cancel and cancelInvoice both call it.
3. **All-or-nothing.** A reversal performs: guards, transaction, subledger reversal, GL void by reference, exact-batch stock restore, balance rebuild, status stamp, activity log. Every step runs inside one db.transaction. Any failure rolls back everything; warn-only steps are forbidden (warn-and-continue is a partial-commit bug).
4. **Paid documents lock.** paid_amount > 0 blocks cancel/void/delete. Payments must be reversed (via their own protected paths) or explicitly unallocated first. No destructive path may leave: an active payment whose invoice is cancelled, a live allocation pointing at a cancelled invoice, or active PAYMENT GL while the sale revenue GL is voided.
5. **Returned stock locks.** returned_amount > 0 blocks cancel/void/delete. The return history must be voided first (it has its own reversal primitive), so reversal can attribute stock exactly.
6. **Append-only subledgers.** customer_ledger and supplier_ledger are never hard-deleted. Reversals append an equal-and-opposite row (with reversed_by), then rebuild the running-balance chain. Derived totals are recomputed from the chain, never patched.
7. **GL void by reference.** Canonical GL (journal_lines) is voided via voidJournalLinesByReference(db, refType, refId, attribution). Legacy GL (journal_entries) rows linked to the document (via journal_entry_id on stock_movements, or reference_type/reference_id) must be voided in the same transaction using StockMovementModel.voidJournalEntry. A reversal that only voids one GL system is incomplete (C2 root cause).
8. **Idempotency is server-side.** Every destructive endpoint re-validates status/void markers inside the transaction (already-Cancelled means error, not a second reversal). UI hiding is never the guard.
9. **Balance rebuilds throw.** rebuildLedgerBalances / recalcCustomerBalanceFromLedger / SupplierLedgerModel.rebuildBalances failures roll back the reversal. If a rebuild is currently warn-only in a path, fixing that path converts it to throw.
10. **Reporting filters follow the doctype.** COGS reversal recognition for cancelled sales must include the reference_doctype the reversal actually wrote (INVOICE_CANCEL, plus legacy SO_CANCEL). Reports that read source tables must exclude voided/cancelled rows exactly as the grid listing does.
11. **Refunds cap at collected cash.** A customer refund may never exceed what the customer actually paid on the invoice: `refundAmount = min(netReturn, PaymentModel.refundableOnInvoice(invoiceId))`. Because refundableOnInvoice sums allocations net of prior negative refund allocations, repeated partial returns cannot re-refund cash already paid out. The outstanding-AR portion of a return clears via the RETURN ledger entry + Cr AR in postInvoiceReturnEntry — it stays as a customer credit on account, never cash out. (Supplier-side mirror: SupplierRefundModel.create already rejects amounts above creditNoteRefundable.)

## 2. Reference pattern (Purchase.void shape)

    guards (exists? already voided? payments? returns? sold stock?)
    db.transaction:
      reverse supplier_ledger row(s)      -> append-only, reversed_by
      void GL journal_lines by reference   -> PURCHASE
      void legacy journal_entries links    -> journal_entry_id on movements
      exact-batch stock restore           -> stock_batches.quantity_remaining
      reversal stock movements            -> ADJUSTMENT (auto-posts its own GL at std cost)
      rebuild balances                    -> throw on failure
      stamp void attribution              -> voided_at/voided_by/void_reason
      activity log

## 3. Phase 1 fixes (C1-C4)

### C1 - Invoice cancellation (CRITICAL)

Where: invoiceController.cancelInvoice (POST /api/invoices/:id/cancel).
Fix:
- Block when paid_amount > 0 (there is no payments-first reversal path on this endpoint).
- Block when returned_amount > 0 (void the returns first via their own primitive).
- Reverse stock inside the transaction via InvoiceModel.reverseStockForItems(db, items, invoice_no, userId, INVOICE_CANCEL).
- Void INVOICE and INVOICE_RETURN journal_lines by reference, with must-void guard when total > 0.
- Append CANCELLATION credit to customer_ledger (existing behavior), rebuild balances, throw on failure.
- Keep existing already-Cancelled guard.

### C4 - Sales Order cancellation (CRITICAL)

Where: SalesOrder.cancel (POST /api/sales/:id/cancel).
Fix:
- Extract the C1 logic into InvoiceModel.cancelInvoiceInternal(db, invoice, userId) - guards plus stock reversal plus GL void plus ledger CANCELLATION plus rebuilds - and call it from both cancelInvoice and SO.cancel.
- SO.cancel keeps its own guards (exists, not already Cancelled) and then defers to the shared primitive for the linked invoice; it no longer raw-UPDATEs invoice status or reverses stock itself.
- SO_CANCEL doctype must be added to the COGS condition (for historical rows) - see rule 10.

### C3 - Purchase Order cancellation (CRITICAL)

Where: PurchaseOrder.updateStatus (POST /api/purchase-orders/:id/status).
Fix:
- When transitioning to Cancelled from Submitted/Partially Received, append an equal-and-opposite supplier_ledger entry (credit) and rebuild balances, inside the transaction.
- The existing validTransitions matrix already blocks Cancelled-to-Submitted re-posting; the UNVERIFIED double-posting concern is resolved. No new guard needed beyond the reversal.

### C2 - Production deletion (CRITICAL)

Where: Production.delete (DELETE /api/production/:id).
Fix:
- Inside the delete transaction, find the production output stock_movement (movement_type = 'PRODUCTION', reference_docno = production_no, quantity > 0), read its journal_entry_id, and void that legacy journal_entries row via StockMovementModel.voidJournalEntry. Match on movement_type, not reference_doctype: the doctype column holds the human label ('Production'), not the enum.
- Guard: if the output movement is missing or has no journal_entry_id, skip silently only when total_batch_cost is 0; otherwise throw (must-void guard, mirroring deleteInvoice GL guard).

## 4. Phase 2 fixes (C5-C7)

### C5 - Employee loan deletion / repayment void (HIGH)

Where: employeeController.deleteLoan (DELETE /api/employees/:id/loans/:loanId), employeeController.voidLoanRepayment (POST .../repayments/:repaymentId/void).
Fix:
- deleteLoan: void LOAN_DISBURSEMENT journal_lines by reference unconditionally (pre-link-backfill loans carry journal_entry_id NULL but their GL lines exist keyed by reference_type/reference_id) inside the existing transaction, then soft-void the loan row (voided_at/voided_by/void_reason) instead of DELETE.
- deleteLoan keeps its repayment-history guard (409 when repayments exist) and adds an already-voided guard.
- voidLoanRepayment: void LOAN_REPAYMENT GL unconditionally for direct repayments (same NULL-link orphan risk), keep the balance restore, and soft-void the repayment row instead of DELETE.
- written_off restore stays as-is (no GL effect; restoreFromWriteOff only mutates the loan row).
- New columns: employee_loans.voided_at/voided_by/void_reason; employee_loan_repayments.voided_at/voided_by/void_reason (add-employee-loan-void-columns.sql).

### C6 - Payment.delete and deleteSalaryPayment hard-delete (HIGH)

Where: PaymentModel.delete, employeeController.deleteSalaryPayment.
Fix:
- Payment.delete: stop deleting the payment row and its allocations. Soft-void the payment (voided_at/voided_by/void_reason), soft-void its allocations, keep the append-only subledger reversal, GL void by reference, and convert every warn-only rebuild (invoice balance/status, customer balance, ledger chain, supplier balances) to throw so failure rolls back the whole reversal (rule 9).
- Supplier-side allocations are voided the same way: payment_allocations, purchase_allocations, and po_allocations rows are stamped voided_at (add-payment-salary-void-columns.sql), never deleted. All paid-amount reads (PurchaseOrder/Purchase/PurchaseReturn paid subqueries, receipt allocation lists in paymentsController, supplier-payment validation joins) filter voided_at IS NULL so reversed allocations stop counting toward paid amounts.
- Purchase.void's recorded-payments guard counts only non-voided allocations (AND voided_at IS NULL on po_allocations/purchase_allocations), so a voided supplier payment no longer blocks voiding the purchase it paid.
- deleteSalaryPayment: wrap in one db.transaction (GL void + soft-void salary_payments row with voided_at/voided_by/void_reason + activity log). Salary payments are money-moved (GL + cash) so they can never be hard-deleted (rule 1).
- New columns: payments.voided_at/voided_by/void_reason; salary_payments.voided_at/voided_by/void_reason (add-payment-salary-void-columns.sql).
- Reporting filters (rule 10): payments-reading reports (payment register in Reports, cashService collectFlows/till walk) must exclude voided payments exactly like the listing; salary-reading reports (cash flow, till walk) must exclude voided salary rows the same way they already exclude status='cancelled'.

### C7 - paySalary auto-advance silent GL failure (HIGH)

Where: employeeController.paySalary (overpayment advance block).
Fix:
- The advance GL catch currently logs and continues, so an advance salary row can commit with no GL posting (silent partial commit, rule 3). Rework to the same throw-on-GL-failure shape as the primary posting: advance row insert + GL post + journal_entry_id link all inside the same transaction; any GL failure throws and rolls back the whole payment.

## 5. Phase 3 (implemented) - GL unification

- journal_lines is the canonical GL. journal_entries stays as the legacy/audit header store, and rule 7 keeps voiding both stores on every reversal.
- Migration backfillGlUnification (registered after fn.backfillGlPreposting in config/database.ts) runs two idempotent passes inside one transaction: re-link orphaned or mis-linked journal_lines groups to fresh journal_entries headers, then migrate line-less legacy journal_entries rows into balanced canonical journal_lines (accounts resolved via chart_of_accounts text_code). Post-conditions throw on orphaned/mis-linked lines or unbalanced totals.
- AccountingService.postEntry now inserts the journal_entries header first and uses its AUTOINCREMENT id, so every new posting is represented in both stores.
- New stock postings go through AccountingService.postLegacyStockEntry: StockMovement adjustments and production output, plus PhysicalCount.completeCount, write the journal_entries row and the paired journal_lines atomically.
- Production.delete voids canonical lines by reference (reference_type production, reference_id = output stock_movement id) plus the legacy header when journal_entry_id is present, keeping rule 7 complete.
- getAccountBalance/getAllAccountBalances (and every report flowing through them) read journal_lines only.
- Earlier Phase 3 outline items shipped with their phases: SupplierRefund.void and the deleteSalaryPayment transaction (Phase 2), purchase grid/paid-amount voided_at filters (Phase 2), and cash-flow reads that exclude voided payments (Phase 2; C1 also blocks cancelling a paid invoice, so a cancelled invoice cannot keep active payments).

## 6. Phase 4 (in progress)

- ✅ **Stock-transfer reversal primitive** — `StockMovementModel.voidTransfer` (POST /api/inventory/stock-transfers/:movementNo/void). Stock-only reversal (transfers have no GL effect): restores the source batch consumed by the OUT leg (matched by movement_no — the OUT leg's reference_docno is NULL), draws down the mirrored TRANSFER batch at the destination, and appends a TRANSFER_VOID ADJUSTMENT pair referencing the original movement. Guards inside the transaction: not-found (400), already-voided idempotency (400), and refusal when the transferred units were already consumed from the destination (400 — voiding would drive stock negative).
- ✅ **Status-machine validation** — SalesOrder.update and Quotation.update now enforce transition matrices (matching the PO updateStatus matrix from C3): SO Draft→Confirmed→Delivered→(Invoiced|Completed), terminal states locked; Quotation Draft→Sent→Accepted→Converted with Expired→Sent re-send, Rejected/Converted terminal. Direct PUT status edits can no longer bypass the conversion workflow or revive terminal documents.
- ✅ **Goods-receipt void primitive** — `PurchaseOrderModel.voidGoodsReceipt` (POST /api/purchase-orders/:id/receipts/:receiptId/void). Refuses if any of the receipt's FIFO batch layers were already consumed (400 — voiding would corrupt costing); otherwise draws down stock_balances at the receipt warehouse, zeroes the receipt's stock_batches layers (retained for audit — batches are never deleted), appends a GOODS_RECEIPT_VOID PURCHASE_RETURN movement (append-only trail), rolls back purchase_order_items.received_quantity, recomputes PO status via calculateStatus, rebuilds items.current_stock, and stamps voided_at/voided_by/void_reason (idempotency marker). No GL reversal needed: receipts post no GL of their own (PO financials post at commit/payment). Migration: add-goods-receipt-void-columns.sql.
- ✅ **FK-delete 400s for master data** — supplier delete now checks purchases (direct), non-voided payments, supplier_ledger, supplier_refunds, and purchase_returns (via source purchases) before the hard DELETE; warehouse delete now checks in-stock balances, stock movements, live stock_batches, purchases, physical_counts, goods_receipts, and productions. Both previously surfaced as opaque 500 FK violations; they now return 400 with a human-readable reference breakdown and leave state untouched. Customer/item deletes were already guarded (transaction counts + soft-delete).
- ✅ **Count-correction workflow** — `PhysicalCountModel.correctCount` (POST /api/inventory/physical-counts/:id/correct). POSTED counts are immutable: counted quantities are never edited in place. A correction reverses the original completion's effects and re-applies the recounted quantities in one transaction: voids the original journal lines by reference (`voidJournalLinesByReference`), appends equal-and-opposite CORRECTION ADJUSTMENT movements, reverses the original balance contribution, re-applies each corrected variance exactly as completeCount does (shortage consumes FIFO-oldest layers at actual costs; surplus adds an ADJUSTMENT_CORRECTION cost layer; fresh GL posts at actual consumed costs), and stamps corrected_at/corrected_by on the count (single-shot idempotency). Guards: count must be Completed; every corrected item needs a snapshot row; refusal (400) when surplus units were already consumed. Migration: add-count-correction-columns.sql.
- ⏳ Outstanding Phase 4 item: none — Phase 4 is complete.

## 7. Phase 5 ✅

- ✅ **Accounting-invariant regression suite** — `accountingInvariants.test.ts` drives a full lifecycle through real endpoints (owner capital → invoice → payment → partial return with refund-cap → leftover-payment void → cancel; purchase order → supplier payment → cancel) and asserts five invariants after every step: (A) every journal_lines reference group sums debit == credit; (B) customers.current_balance == customer_ledger sum; (C) invoices.paid_amount == non-voided allocation sum; (D) suppliers.current_balance == supplier_ledger chain balance; (E) stock_balances.quantity == Σ stock_batches.quantity_remaining.
- ✅ **Double-fire concurrency tests** — every destructive endpoint is called twice back-to-back (invoice cancel, payment delete, PO cancel, GRN void, stock-transfer void, count correction): the second attempt must return 4xx and all invariants must still hold. Exposed and fixed two real mapping gaps: `deletePayment` on an already-voided payment now returns 400 (was 500), and PO status-machine violations (`Cannot transition from …`) now return 400 (was 500) with the stale poCancelReversal expectation updated. The count-correction double-fire case also caught a real costing bug: reversing a shortage restored the stock balance but not the FIFO layers the original completion had consumed — `correctCount` now restores the consumed layer (provenance: the original adjustment movement's `batch_id`) before re-applying the corrected variance.

## 8. Audit completion status

Phases 1–5 are all implemented and green. Remaining work is maintenance: new destructive endpoints must ship with (a) server-side idempotency guards, (b) 4xx (never 5xx) for double-fire and state-machine violations, (c) a case in the invariant suite.
