# Customer Credit Offset

## Purpose

Customers may carry a credit (CR) balance from overpayments, credit-disposition
returns, or adjustments. This capability lets the user view that balance during
invoice creation, apply some or all of it to the new invoice, and record the
offset in accounting without cash movement. The remaining balance, if any, is
collected through the normal payment flow.

Requirements apply to invoice creation; applying credit to an already-created
invoice is covered by the store-credit apply-to-invoice operations.

## Requirements

### Requirement: Display customer CR balance on invoice creation
The system SHALL display the customer's available credit (CR) balance when creating a new invoice after customer selection.

Available credit is the sum of the store-credit pool (`credit_balance`) and any
legacy ledger credit (negative `current_balance`). The server enforces the same
sum.

#### Scenario: Customer has CR balance
- **WHEN** a user selects a customer with an existing CR balance during invoice creation
- **THEN** the invoice form displays the available credit balance amount

#### Scenario: Customer has no CR balance
- **WHEN** a user selects a customer with zero or no CR balance
- **THEN** the invoice form does not display a credit balance section

### Requirement: Apply CR balance to invoice
The system SHALL provide an option to apply the customer's CR balance to the current invoice.

#### Scenario: Apply full credit when credit >= invoice amount
- **WHEN** a user applies credit
- **AND** the customer's CR balance is greater than or equal to the invoice total
- **THEN** the full invoice amount is offset by credit
- **AND** the remaining payment amount is zero

#### Scenario: Apply full credit when credit < invoice amount
- **WHEN** a user applies credit
- **AND** the customer's CR balance is less than the invoice total
- **THEN** the full CR balance is applied to the invoice
- **AND** the remaining amount equals invoice total minus CR balance

#### Scenario: Apply partial credit
- **WHEN** a user applies a specific amount of the CR balance
- **THEN** only the specified amount is applied from the CR balance
- **AND** the remaining amount equals invoice total minus applied amount

#### Scenario: Credit application exceeds available balance
- **WHEN** a user enters an amount greater than available CR balance
- **THEN** the system limits the applied amount to the available balance
- **AND** displays a validation message

### Requirement: Calculate remaining payment after credit offset
The system SHALL calculate the remaining payment amount after credit application.

#### Scenario: Credit fully covers invoice
- **WHEN** credit application amount equals or exceeds invoice total
- **THEN** the remaining payment amount is zero
- **AND** the payment section is disabled or hidden

#### Scenario: Credit partially covers invoice
- **WHEN** credit application amount is less than invoice total
- **THEN** the remaining payment amount equals invoice total minus credit application amount
- **AND** the payment section shows the remaining balance

### Requirement: Record credit offset in accounting
The system SHALL create proper accounting entries when CR balance is applied to an invoice.

Ledger credit draws post Dr Customer Credit (1110) / Cr AR. Pool credit draws
reduce `credit_balance` and append a CREDIT row to the customer ledger. The
offset moves no cash. The offset is a ceiling guard class — see the
`INVOICE_SETTLEMENT` disposition in `docs/bugs.md` BUG-003.

#### Scenario: Credit offset entry creation
- **WHEN** a credit offset is applied to an invoice
- **THEN** the system creates balanced customer-credit and receivable entries for the same amount
- **AND** the entries post inside the same transaction as invoice creation

#### Scenario: Double-spend prevention
- **WHEN** a second invoice requests the same credit after it was consumed
- **THEN** the open-period availability recheck inside the write transaction rejects the request
