## Why

Customer credit generated from invoice returns (e.g., partial returns with `disposition: 'credit'`) is not properly reflected when applied to new invoices. The backend stores `credit_offset` and calculates balances correctly, but the frontend invoice summary and payment history do not display the credit offset as a separate component. This leads to incorrect balance display and potential accounting discrepancies.

## What Changes

- Ensure the invoice detail view (PDF and UI) shows "Cr Used" as a separate line item when credit offset is applied.
- Ensure the payment history includes a synthetic "CREDIT" entry for the credit offset.
- Verify the backend correctly persists and calculates `credit_offset` in invoice balances.
- Ensure the customer's available credit is reduced by the applied amount.
- Prevent double-application of the same credit.

## Capabilities

### New Capabilities
- `customer-credit-reflection`: Ensures customer credit offsets are properly displayed and persisted in invoice summaries and payment histories.

### Modified Capabilities
- `invoice-returns`: The return process creates customer credits; ensure those credits are correctly linked and usable on subsequent invoices.
- `invoice-payments`: Payment history should include credit offset entries as separate line items.

## Impact

- **Backend**: `server/src/controllers/invoiceController.ts`, `server/src/models/Invoice.ts`, `server/src/utils/ledgerUtils.ts`
- **Frontend**: `lib/features/sales/invoice_pdf.dart`, `lib/features/sales/thermal_invoice_pdf.dart`, `lib/features/sales/payment_panel.dart`, `lib/features/sales/sales_invoice_form_page.dart`
- **Database**: No schema changes (column `credit_offset` already exists)
- **API**: No endpoint changes; existing endpoints already support `credit_offset`
