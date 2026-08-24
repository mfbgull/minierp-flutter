## MODIFIED Requirements

### Requirement: Cash reconciliation saves require write permission
`POST /reports/cash-reconciliation` SHALL require a write permission (`reports:create`) instead of `reports:read`. The permission SHALL be seeded for administrator and manager roles when absent.

#### Scenario: Cashier cannot rewrite a bad day
- **WHEN** a user with only report read access posts counted = expected for a date showing a shortage
- **THEN** the save fails 403 and the existing variance record survives

#### Scenario: Manager can still save
- **WHEN** a manager holding `reports:create` saves a reconciliation
- **THEN** the snapshot persists as before (expected balance frozen at save time)
