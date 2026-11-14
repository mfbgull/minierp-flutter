## Context

The mini-erp application supports customer credits generated from invoice returns (partial returns with `disposition: 'credit'`). When a customer has available credit, they can apply it to a new invoice via the "Use Credit" checkbox, which sets `credit_offset` on the invoice.

Four bugs were found and fixed across the frontend and backend layers:

**Frontend Bugs (Fixed):**
1. `_creditOffset` in `SalesInvoiceFormPage.initState()` was never restored from `widget.invoice?.creditOffset` — always defaulted to 0 in edit mode
2. `_printWithFormat` in `InvoicePrintPreviewPage` passed `payments: const []` instead of actual fetched payments

**Backend Bugs (Fixed):**
3. RETURN ledger entries used `todayDate` (server clock) instead of the original `invoice.invoice_date`, causing wrong balance chain ordering when returns are backdated
4. CREDIT_OFFSET entry in `customer_ledger` double-counted: the INVOICE DEBIT already increases the customer balance, and the CREDIT_OFFSET CREDIT reduced it again — net effect was the customer's balance was NOT reduced after applying credit

## Goals / Non-Goals

**Goals:**
- Ensure invoice summary displays "Cr Used" as a separate line when credit offset > 0
- Ensure payment history includes credit offset as a distinct entry
- Maintain accounting integrity: balance = total - (cash payments + credit offset)
- Prevent double-application of credit (already handled by backend validation)
- Ensure customer credit balance is correctly reduced after application

**Non-Goals:**
- Change the backend accounting model (already correct)
- Modify the database schema (column exists)
- Change API endpoints (already support credit_offset)
- Implement new credit creation logic (handled by invoice returns)

## Decisions

### 1. Root Cause Analysis — Frontend

**Bug 1 — `_creditOffset` not restored in edit mode:**
- `SalesInvoiceFormPage.initState()` reads `widget.invoice` for edit mode but never set `_creditOffset = invoice?.creditOffset ?? 0`
- This meant the "Cr Used" line in the summary and the balance calculation were wrong when viewing/editing an existing invoice
- **Fix:** Added `_creditOffset = invoice?.creditOffset ?? 0;` in `initState()` at ~line 171

**Bug 2 — Print preview passes empty payments:**
- `_printWithFormat()` in `InvoicePrintPreviewPage` used `payments: const []` when calling `service.printInvoice()`
- This meant thermal receipts from the print preview had no payment history at all
- **Fix:** Added `repo.invoicePayments(widget.invoice.id)` call and passed actual payments to `service.printInvoice()`

### 2. Root Cause Analysis — Backend

**Bug 3 — RETURN ledger date corruption:**
- The return handler used `todayDate = new Date().toISOString().split('T')[0]` for the RETURN ledger entry's `transaction_date`
- When a return is processed today for an invoice created in the past, the RETURN entry is placed AFTER future invoices in date order
- `rebuildLedgerBalances()` reorders by `(transaction_date, id)`, so a backdated return corrupts the running balance chain
- **Fix:** Changed both RETURN ledger entries (refund + credit disposition) from `todayDate` to `invoice.invoice_date`

**Bug 4 — CREDIT_OFFSET double-counting in customer_ledger:**
- When creating an invoice with `credit_offset`, the controller created BOTH:
  - An INVOICE DEBIT entry (increases customer balance by total_amount)
  - A CREDIT_OFFSET CREDIT entry (decreases customer balance by credit_offset)
- The invoice's `paid_amount` already includes the credit offset, so the CREDIT_OFFSET ledger entry was redundant
- The GL entry (Dr Customer Credit / Cr AR) via `postCreditOffsetEntry` is sufficient for the general ledger
- **Fix:** Removed the `InvoiceModel.createLedgerEntry` call for CREDIT_OFFSET from the createInvoice controller

### 3. Investigation Summary

The `creditOffset.test.ts` tests all pass (3/3). The full test suite passes (547/547). The fix was validated by asserting that `customers.current_balance` goes from -200 (credit) to 0 after applying a 200 credit offset to a 200 invoice.

## Risks / Trade-offs

- **Risk**: The backend accounting may have edge cases not covered by tests
  - **Mitigation**: Run existing `creditOffset.test.ts` and add more test cases
- **Risk**: Frontend may have multiple invoice summary components
  - **Mitigation**: Audit all invoice display components for credit offset handling
- **Risk**: Payment history may not include credit offset in some views
  - **Mitigation**: Verify `getPayments()` is called in all relevant contexts

## Migration Plan

No migration needed - database schema already supports `credit_offset`.

## Open Questions

1. Which specific UI component is showing the incorrect Paid=600, Balance Due=600?
2. Is the issue in the print preview, the invoice form, or a different view?
3. Are there other places where customer credit can be applied (e.g., POS, sales orders)?
