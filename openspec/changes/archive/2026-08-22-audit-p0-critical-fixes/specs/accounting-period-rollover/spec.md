# Spec: accounting-period-rollover (Delta)

## ADDED Requirements

### Requirement: GL posting must not fail at period rollover
`AccountingService.postEntry` SHALL automatically create the missing accounting period when the entry date falls after the last existing period (or before the first), instead of throwing `No open accounting period covers <date>`. The created period SHALL cover one calendar month containing the entry date and SHALL be `open`.

#### Scenario: Invoice posted in a month with no period
- **WHEN** an invoice is created on 2026-09-01 while the only accounting period is 2026-08-01 → 2026-08-31
- **THEN** a period covering September 2026 is created with status `open`
- **AND** the invoice transaction commits successfully

#### Scenario: Entry inside an existing open period
- **WHEN** an entry date falls within an already-open period
- **THEN** no new period row is created
- **AND** posting behaves exactly as before

#### Scenario: Period creation is idempotent under concurrency
- **WHEN** two concurrent postings both trigger rollover for the same missing month
- **THEN** exactly one period row exists for that month (UNIQUE constraint respected) and both postings succeed

### Requirement: Rollover stays inside the caller's transaction
Automatic period creation MUST execute within the same SQLite transaction as the GL insert, so that a failed posting never leaves an orphaned auto-created period behind.

#### Scenario: Posting fails after rollover
- **WHEN** period creation succeeds but the subsequent journal insert fails
- **THEN** the auto-created period is rolled back with the rest of the transaction
