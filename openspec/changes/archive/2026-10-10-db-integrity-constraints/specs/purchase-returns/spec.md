# purchase-returns (Delta)

## ADDED Requirements

### Requirement: A receipt quantity must be positive
`addReceipt` SHALL reject a `received_quantity` of zero or less, before writing
any row.

The upper-bound check alone admitted zero (creating zero-valued rows and no GL
entry, silently) and negative values (rejected only by a table CHECK, surfacing
as a 500 carrying the raw SQLite message). The guard lives at the model because
non-HTTP callers bypass the controller.

#### Scenario: A zero quantity is refused
- **WHEN** a receipt line carries `received_quantity` 0
- **THEN** it is rejected with status 400

#### Scenario: A negative quantity is refused
- **WHEN** a receipt line carries `received_quantity` -6
- **THEN** it is rejected with status 400

### Requirement: A purchase balance never goes negative
Every derived `purchases.balance_amount` SHALL be floored at zero, so
over-allocating a payment cannot report a negative amount due.

The purchase-order equivalent already floors; the purchase projection did not.

#### Scenario: Over-allocating a payment reports zero, not a negative
- **WHEN** allocations exceed a purchase's total cost
- **THEN** the derived balance is 0
