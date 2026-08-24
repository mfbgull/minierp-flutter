# Spec: financial-test-invariants

## Purpose

Locks in the financial-correctness guarantees of the audit-remediation work with
regression tests covering double-entry balance, transaction atomicity, boot
idempotency, migration replay, and money-path coverage gaps.

## Requirements

### Requirement: Double-entry invariant is regression-tested
The test suite SHALL assert after every mutating scenario that SUM(debit) = SUM(credit) over non-voided journal_lines globally and grouped per (reference_type, reference_id).

#### Scenario: Invoice workflow keeps the ledger balanced
- **WHEN** create → partial pay → edit → delete flows execute in tests
- **THEN** the global and per-document balance assertions pass at each step

### Requirement: Transaction atomicity is regression-tested
Tests SHALL force a mid-transaction failure (e.g. insufficient stock on a later invoice line) and assert complete rollback: no invoice, items, stock movements, ledger entry or journal lines persist.

#### Scenario: Failed multi-line invoice writes nothing
- **WHEN** line 2 of a 3-line invoice fails validation
- **THEN** zero rows from that operation exist in any affected table

### Requirement: Boot idempotency is regression-tested
The suite SHALL snapshot row hashes of all business tables, re-run the boot sequence against the same database, and assert zero row changes.

#### Scenario: Restart is a no-op
- **WHEN** the boot sequence runs twice against one database
- **THEN** no business-table row differs between snapshots

### Requirement: Migration replay is regression-tested
The suite SHALL apply the full migration set to a fresh in-memory database twice and assert identical schemas and zero errors, catching dead guards and broken SQL.

#### Scenario: Replay is deterministic
- **WHEN** migrations apply twice to :memory:
- **THEN** sqlite_master content is identical after each run and no migration errors

### Requirement: Money-path coverage gaps are closed
The suite SHALL cover: invoice edit after payment (totals/status/stock/GL), invoice delete leaving no orphaned journal_lines or ledger rows plus an audit row, customer-side partial payment asserting payment_allocations rows, and concurrent invoice creation producing unique invoice numbers with correct stock.

#### Scenario: Edit-after-payment stays consistent
- **WHEN** a paid invoice is edited in tests
- **THEN** paid_amount, balance_amount, status, stock levels and GL postings are all correct

#### Scenario: Concurrent creation serializes numbers
- **WHEN** two invoice creations race
- **THEN** invoice numbers are unique and final stock equals expected
