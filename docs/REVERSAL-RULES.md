# Transaction Reversal Rules (Implementation Specification)

Status: APPROVED - Phase 1 in progress. Scope: every destructive/reversal path.

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

## 5. Phase 3-5 outlines

- Phase 3: GL unification (backfill-migrate legacy to journal_lines, forbid new legacy postings), SupplierRefund.void plus deleteSalaryPayment transaction wrappers, purchase summary voided_at filters, cash-flow cancelled-invoice payment exclusion.
- Phase 4: goods-receipt reversal or documented count-correction workflow; stock-transfer reversal primitive; status-machine validation on all updateStatus endpoints; clean 400s for FK-blocked master-data deletes.
- Phase 5: accounting-invariant regression suite (GL sum == subledger sum == source rows), double-fire concurrency tests for every destructive endpoint.
