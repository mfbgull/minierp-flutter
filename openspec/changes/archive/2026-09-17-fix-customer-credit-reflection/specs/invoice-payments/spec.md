## ADDED Requirements

### Requirement: Payment history includes credit offset entries
The system SHALL include credit offset applications as separate entries in the payment history of an invoice.

#### Scenario: Credit offset appears as distinct payment entry
- **WHEN** an invoice has `credit_offset` > 0
- **THEN** the payment history SHALL include an entry with:
  - `payment_no`: `CREDIT-{invoice_no}`
  - `payment_method`: `CREDIT`
  - `amount`: the credit offset amount
  - `notes`: "Customer credit applied"
- **AND** this entry SHALL be distinct from cash payment entries

#### Scenario: Payment history shows both cash and credit entries
- **WHEN** an invoice has both cash payments and credit offset
- **THEN** the payment history SHALL display cash payment entries and credit offset entry as separate rows
- **AND** the sum of all payment entries (cash + credit) SHALL equal the invoice's `paid_amount`

#### Scenario: Payment history for invoice without credit offset
- **WHEN** an invoice has `credit_offset` = 0 or null
- **THEN** the payment history SHALL NOT include a credit offset entry
- **AND** only cash payment entries SHALL be displayed

### Requirement: Payment summary includes credit offset breakdown
The payment summary section SHALL display the breakdown between cash payments and credit offset when credit is applied.

#### Scenario: Payment summary shows credit offset line
- **WHEN** viewing invoice payment summary with credit offset > 0
- **THEN** the summary SHALL display:
  - "Paid" line showing cash payment amount (total paid minus credit offset)
  - "Cr Used" line showing credit offset amount
  - "Balance Due" line showing `total_amount - (cash_payments + credit_offset)`

#### Scenario: Payment summary without credit offset
- **WHEN** viewing invoice payment summary with credit offset = 0
- **THEN** the summary SHALL display:
  - "Paid" line showing total paid amount
  - "Balance Due" line showing `total_amount - total_paid`
