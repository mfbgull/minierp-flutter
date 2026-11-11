# invoice-returns (Delta)

## ADDED Requirements

### Requirement: A return cannot settle for more than it owes back
`invoice_returns.settled_amount` SHALL NOT exceed `net_amount`
(= `returned_amount − fee_amount`), enforced at the database level.

`settled_amount` is the sum of allocations, so without a ceiling a return could
settle above the amount owed. The ceiling is `net_amount` rather than
`returned_amount` because the restocking fee is money the customer keeps and must
never be payable back out.

Enforced by trigger rather than CHECK: SQLite cannot add a CHECK to an existing
table, and a ceiling needs the twelve-step table rebuild. A trigger installs in
place, so no row is ever unguarded during the change.

#### Scenario: A settlement above the net is rejected
- **WHEN** a return with `returned_amount` 600, `fee_amount` 50 and `net_amount`
      550 is settled to 600
- **THEN** the database rejects it

#### Scenario: The ceiling holds from either side
- **WHEN** `settled_amount` is raised above `net_amount`, or `net_amount` is
      lowered below an existing `settled_amount`
- **THEN** the database rejects it

#### Scenario: A settlement at or below the net is accepted
- **WHEN** a return settles exactly `net_amount`, or partially
- **THEN** the write succeeds
