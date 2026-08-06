## ADDED Requirements

### Requirement: Payment panel with record-payment and existing payments
The invoice form SHALL include a payment panel to the right of the items grid. It SHALL offer a record-payment toggle, a payment date and notes, a list of payment methods (each with method, amount, reference), optional per-method rows, and a Record button. Existing payments for the invoice SHALL be listed with edit/delete; deletions in edit mode are tracked for submission as `deleted_payments`. All payment flows report success/failure via the app's toast pattern with no silent failures.

#### Scenario: Record a payment
- **WHEN** record-payment is toggled on and the user enters a positive amount ≤ remaining balance and submits
- **THEN** the payment is posted via the invoice payments endpoint per method (sequentially for multiple methods) and the invoice is created/updated in the same transaction as the invoice (server-side)

#### Scenario: Validate payment amount
- **WHEN** the amount is not > 0
- **THEN** submission is blocked with an error toast
- **WHEN** the amount exceeds the remaining balance
- **THEN** submission is blocked with `doesPaymentExceedBalance`/`isValidPaymentAmount` logic and an error toast

#### Scenario: Edit-mode existing payments
- **WHEN** loading an existing invoice for edit
- **THEN** an existing payments are fetched from `GET /invoices/:id/payments` and listed in the panel with edit/delete affordances
- **WHEN** the user removes a payment and saves
- **THEN** the removed payment id is included in the update payload as `deleted_payments`