## 1. Investigation and Root Cause Analysis

- [x] 1.1 Trace the complete flow from frontend invoice creation to backend persistence
- [x] 1.2 Verify the backend `createInvoice` endpoint correctly processes `credit_offset`
- [x] 1.3 Verify the `InvoiceModel.getPayments()` method includes credit offset entry
- [x] 1.4 Check the frontend invoice detail fetch includes `credit_offset` field
- [x] 1.5 Identify which UI component shows the incorrect Paid=600, Balance Due=600 display

## 2. Backend Verification and Fixes

- [x] 2.1 Run existing `creditOffset.test.ts` to verify backend logic
- [~] 2.2 Add logging to `calculateInvoiceBalance()` — cancelled: superseded by actual bug fixes
- [x] 2.3 Verify customer credit balance is reduced after credit offset application (FIXED: RETURN ledger date + removed double-counting CREDIT_OFFSET entry)
- [x] 2.4 Ensure credit offset cannot exceed available customer credit
- [x] 2.5 Verify GL entries are posted correctly for credit offset

## 3. Frontend Display Fixes

- [x] 3.1 Audit invoice PDF builders to ensure "Cr Used" line appears when creditOffset > 0
- [x] 3.2 Check invoice print preview page fetches full invoice detail with creditOffset
- [x] 3.3 Verify payment panel displays credit offset breakdown correctly
- [x] 3.4 Ensure invoice summary in UI matches PDF display logic
- [x] 3.5 Test invoice detail view shows correct balance breakdown

## 4. Payment History Integration

- [x] 4.1 Verify `InvoiceModel.getPayments()` returns credit offset entry
- [x] 4.2 Check frontend payment history component displays credit entry
- [x] 4.3 Ensure credit entry shows correct payment_method='CREDIT'
- [x] 4.4 Verify credit entry amount matches invoice credit_offset

## 5. End-to-End Testing

- [x] 5.1 Test complete flow: create invoice with payment + credit offset
- [x] 5.2 Verify invoice summary shows Paid (cash), Cr Used, Balance Due=0
- [x] 5.3 Verify payment history shows both cash payment and credit entry
- [x] 5.4 Verify customer credit balance reduced by applied amount
- [x] 5.5 Test edge cases: credit offset equals total, credit offset exceeds available
- [x] 5.6 Verify refresh/reopen invoice maintains correct display

## 6. Documentation and Cleanup

- [x] 6.1 Update any relevant documentation about credit offset behavior
- [x] 6.2 Ensure test coverage for credit offset scenarios
- [x] 6.3 Verify no duplicate payment/credit transactions are created
