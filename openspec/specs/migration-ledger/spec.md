# Spec: migration-ledger

## Purpose

Makes schema migrations deterministic and observable: a recorded ledger of
applied migrations, atomic execution, fail-closed startup, and a boot sequence
that performs no unconditional data mutation.

## Requirements

### Requirement: Applied migrations are recorded in a ledger
The system SHALL maintain a `schema_migrations` table (filename TEXT PRIMARY KEY, applied_at, checksum) recording every applied migration; a migration file SHALL execute at most once per database, determined by the ledger rather than schema introspection; the existing 47 guard-style runners SHALL be backfilled into the ledger on first boot of the new mechanism.

#### Scenario: Migration runs exactly once
- **WHEN** the server boots twice against the same database
- **THEN** each migration file's body executes only on the first boot and is skipped via the ledger on the second

#### Scenario: Ledger backfill
- **WHEN** the new mechanism first starts on an existing installation
- **THEN** all previously-applied migrations are recorded with checksums without re-executing their bodies

### Requirement: Migrations are atomic
Every multi-statement migration SHALL run inside a single transaction (via `db.transaction()` or explicit BEGIN/COMMIT in the SQL file); a failure SHALL roll the database back to the pre-migration state.

#### Scenario: Mid-file failure leaves no partial state
- **WHEN** a statement in a migration file raises an error
- **THEN** no statement from that file persists and the ledger records nothing for it

### Requirement: Migration failure stops startup
A failed migration SHALL abort server startup with a loud error exit; startup SHALL NOT continue serving requests after swallowing a migration error.

#### Scenario: Broken migration blocks serving
- **WHEN** a migration fails during boot
- **THEN** the process exits non-zero with the migration filename and error, and no HTTP server starts

### Requirement: Boot performs no unconditional data mutation
The boot sequence SHALL apply schema changes only; all data-repair mutations currently executed on every start (derived invoice totals/status rewrites, stock balance recomputation, ledger narration rewrites, supplier balance sync, permission reseeding, synthetic batch reconciliation, orphaned batch cleanup, legacy table drops) SHALL be moved into an explicit opt-in `npm run repair` command that creates a verified backup first, runs inside one transaction, and writes an activity_log row per mutation class performed.

#### Scenario: Second boot changes zero rows
- **WHEN** the server restarts against an unchanged database
- **THEN** no row in any business table is modified (boot idempotency snapshot test)

#### Scenario: Repair is deliberate and audited
- **WHEN** an operator runs npm run repair
- **THEN** a backup file exists predating the repair, and the trail records which mutation classes ran

### Requirement: The payments table rebuild preserves invoice linkage and pragma safety
Any table-rebuild migration SHALL copy every column it declares — including `payments.invoice_id` — restore `PRAGMA foreign_keys=ON` in a finally path regardless of statement success, and re-assert foreign_keys === 1 before proceeding; installations whose payments were already rebuilt by the defective version SHALL receive a one-time recovery pass restoring payment→invoice links from `payment_allocations`.

#### Scenario: Rebuild retains links
- **WHEN** the payments rebuild executes on a database with linked payments
- **THEN** every pre-existing payment→invoice pair survives identically

#### Scenario: Failure cannot leave FKs off
- **WHEN** any statement in the rebuild throws
- **THEN** the process never continues with foreign_keys disabled

### Requirement: Rollback tooling is safe by default
Rollback files SHALL be syntactically valid SQLite, transaction-wrapped, paired with their forward migrations where feasible, and executable only behind an explicit interactive confirmation requiring a backup; a bare `--rollback` flag SHALL NOT trigger destructive execution without confirmation.

#### Scenario: Rollback requires confirmation
- **WHEN** the process is started with --rollback in non-interactive mode without --force and a fresh backup
- **THEN** rollback is refused with usage guidance

### Requirement: Single canonical migration path
Migration files SHALL be resolved through one shared path constant valid in both compiled (dist) and test (ts-jest) layouts; no runner SHALL hardcode its own relative segment.

#### Scenario: Tests resolve migrations
- **WHEN** the jest suite replays migrations into an in-memory DB
- **THEN** every .sql file resolves and applies without path errors
