## ADDED Requirements

### Requirement: Return generates CR balance for credit offset
The system SHALL generate a CR balance credit during the return process that can be used in credit offset during invoice creation.

#### Scenario: Return creates CR balance
- **WHEN** a user processes a return with "Credit" disposition
- **THEN** the system creates a CR balance entry for the customer
- **AND** the CR balance is available for credit offset during future invoice creation

#### Scenario: Credit disposition tracking
- **WHEN** a return with credit disposition is completed
- **THEN** the CR balance entry includes reference to the original return
- **AND** the balance amount matches the return credit value
