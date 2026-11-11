## Why

Customers may carry a credit balance (CR) from previous overpayments, returns, or adjustments. Currently, this credit is not automatically applied during invoice creation, requiring manual tracking and separate payment entries. This creates inefficiency and potential for lost credits.

## What Changes

- During invoice creation, display the customer's available CR balance
- Provide option to apply CR balance to the current invoice
- If CR balance < invoice amount, prompt for payment of the remaining balance
- If CR balance ≥ invoice amount, apply full credit with zero payment required
- Properly allocate the CR offset in accounting entries

## Capabilities

### New Capabilities

- `customer-credit-offset`: Ability to view and apply customer CR balances to invoices, with proper accounting allocation

### Modified Capabilities

- `invoice-returns`: Minor modification to ensure credit offset integrates with existing invoice lifecycle

## Impact

- **Backend**: New API endpoint or modification to invoice creation to fetch CR balance and process credit offset
- **Frontend**: Invoice creation form needs credit balance display and apply toggle/input
- **Database**: No schema changes expected; uses existing CR balance tracking
- **Accounting**: Credit offset entries must balance correctly with invoice and payment entries
