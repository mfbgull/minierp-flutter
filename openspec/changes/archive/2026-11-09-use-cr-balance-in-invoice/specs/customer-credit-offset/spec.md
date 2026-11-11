## ADDED Requirements

### Requirement: Display customer CR balance on invoice creation
The system SHALL display the customer's available credit (CR) balance when creating a new invoice after customer selection.

#### Scenario: Customer has CR balance
- **WHEN** a user selects a customer with an existing CR balance during invoice creation
- **THEN** the invoice form displays the available credit balance amount

#### Scenario: Customer has no CR balance
- **WHEN** a user selects a customer with zero or no CR balance
- **THEN** the invoice form does not display a credit balance section

### Requirement: Apply CR balance to invoice
The system SHALL provide an option to apply the customer's CR balance to the current invoice.

#### Scenario: Apply full credit when credit >= invoice amount
- **WHEN** a user checks the "Apply Credit" option
- **AND** the customer's CR balance is greater than or equal to the invoice total
- **THEN** the full invoice amount is offset by credit
- **AND** the remaining payment amount is zero

#### Scenario: Apply full credit when credit < invoice amount
- **WHEN** a user checks the "Apply Credit" option
- **AND** the customer's CR balance is less than the invoice total
- **THEN** the full CR balance is applied to the invoice
- **AND** the remaining amount equals invoice total minus CR balance

#### Scenario: Apply partial credit
- **WHEN** a user checks the "Apply Credit" option
- **AND** enters a specific amount in the credit application field
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

#### Scenario: Credit offset entry creation
- **WHEN** a credit offset is applied to an invoice
- **THEN** the system creates a debit entry to the Customer Credit account
- **AND** creates a credit entry to the Accounts Receivable account for the same amount

#### Scenario: Credit offset validation
- **WHEN** processing credit offset
- **THEN** the system validates the credit balance is sufficient before applying
- **AND** returns an error if balance is insufficient

### Requirement: Credit offset atomicity
The system SHALL process invoice creation and credit offset as a single atomic transaction.

#### Scenario: Successful credit offset and invoice creation
- **WHEN** creating an invoice with credit offset
- **THEN** both the invoice and credit offset are committed together
- **AND** if either fails, both are rolled back

#### Scenario: Concurrent credit usage protection
- **WHEN** two invoices attempt to apply the same credit balance simultaneously
- **THEN** only one succeeds and the other receives a balance insufficient error
