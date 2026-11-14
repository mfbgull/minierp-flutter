## ADDED Requirements

### Requirement: Invoice summary displays credit offset separately
The system SHALL display "Cr Used" as a separate line item in the invoice summary when a customer credit offset is applied to the invoice.

#### Scenario: Invoice with credit offset shows Cr Used line
- **WHEN** an invoice has `credit_offset` > 0
- **THEN** the invoice summary (PDF and UI) SHALL display a "Cr Used" line with the credit offset amount
- **AND** the "Paid" line SHALL show only the cash/payment amount (total paid minus credit offset)
- **AND** the "Balance Due" line SHALL show `total_amount - (cash_payments + credit_offset)`

#### Scenario: Invoice without credit offset shows no Cr Used line
- **WHEN** an invoice has `credit_offset` = 0 or null
- **THEN** the invoice summary SHALL NOT display a "Cr Used" line
- **AND** the "Paid" line SHALL show the total paid amount
- **AND** the "Balance Due" line SHALL show `total_amount - total_paid`

### Requirement: Payment history includes credit offset entry
The system SHALL include a synthetic payment entry for credit offset in the payment history of an invoice.

#### Scenario: Payment history shows credit offset as separate entry
- **WHEN** an invoice has `credit_offset` > 0
- **THEN** the payment history SHALL include an entry with:
  - `payment_no`: `CREDIT-{invoice_no}`
  - `payment_method`: `CREDIT`
  - `amount`: the credit offset amount
  - `notes`: "Customer credit applied"

#### Scenario: Payment history shows cash payments separately
- **WHEN** an invoice has both cash payments and credit offset
- **THEN** the payment history SHALL show cash payment entries and credit offset entry as separate rows
- **AND** the sum of all payment entries (cash + credit) SHALL equal the invoice's `paid_amount`

### Requirement: Customer credit balance is reduced after application
The system SHALL reduce the customer's available credit balance by the amount of credit offset applied to an invoice.

#### Scenario: Customer credit balance decreases after invoice creation
- **WHEN** a customer with available credit of X applies credit offset of Y to an invoice (where Y ≤ X)
- **THEN** the customer's `current_balance` SHALL increase by Y (credit balance becomes less negative)
- **AND** the customer's available credit SHALL decrease by Y

#### Scenario: Credit cannot exceed available balance
- **WHEN** a customer attempts to apply credit offset greater than their available credit
- **THEN** the system SHALL reject the invoice creation with an error message
- **AND** no invoice or payment records SHALL be created

### Requirement: Credit offset is persisted in invoice header
The system SHALL store the credit offset amount in the `invoices.credit_offset` column and include it in balance calculations.

#### Scenario: Invoice balance calculation includes credit offset
- **WHEN** an invoice is created with `credit_offset` > 0
- **THEN** the invoice's `paid_amount` SHALL be `cash_payments + credit_offset`
- **AND** the invoice's `balance_amount` SHALL be `total_amount - paid_amount`
- **AND** the invoice's status SHALL be calculated based on `balance_amount`

#### Scenario: Invoice balance recalculation includes credit offset
- **WHEN** `calculateInvoiceBalance()` is called for an invoice with `credit_offset` > 0
- **THEN** the function SHALL include `credit_offset` in the total paid calculation
- **AND** the updated `paid_amount` and `balance_amount` SHALL be stored in the invoice header

### Requirement: Credit offset prevents double application
The system SHALL prevent the same customer credit from being applied to multiple invoices.

#### Scenario: Credit offset is deducted from available credit
- **WHEN** a customer applies credit offset of Y to an invoice
- **THEN** the customer's available credit SHALL decrease by Y
- **AND** subsequent invoice attempts to apply credit offset greater than remaining available credit SHALL be rejected

#### Scenario: Credit offset is recorded in ledger
- **WHEN** a credit offset is applied to an invoice
- **THEN** the system SHALL create a ledger entry with type `CREDIT_OFFSET`
- **AND** the ledger entry SHALL reference the invoice number
- **AND** the customer's ledger balance SHALL be updated accordingly
