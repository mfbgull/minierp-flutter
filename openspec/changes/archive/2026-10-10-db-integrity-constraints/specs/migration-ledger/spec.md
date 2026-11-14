# migration-ledger (Delta)

## ADDED Requirements

### Requirement: Every applied migration is checksum-verified, including inline runners
`verifyMigrationChecksums` SHALL compare a stored checksum against a freshly
computed one for **every** row in `schema_migrations`, and SHALL abort the boot on
a mismatch. A row SHALL NOT be skipped merely because its checksum reads
`'inline'`.

A `fn.*` ledger key names a FUNCTION, not a file, so hashing the file path could
only ever yield `'inline'` — and a skip on that value meant the edit-detection
the gate exists to provide applied to almost none of the ledger. The body is
hashed from its own source instead, so an inline migration edited after it ran
aborts the boot exactly as a file migration does.

#### Scenario: An edited inline migration aborts the boot
- **WHEN** a `fn.*` migration's body changed after it was applied
- **THEN** the recomputed body hash differs from the stored checksum
- **AND** verification throws, failing the boot before HTTP listen

#### Scenario: A missing or unreadable body still does not fail the boot
- **WHEN** an inline function's source cannot be read
- **THEN** its checksum falls back to `'inline'`
- **AND** the row is skipped with a warning rather than aborting

### Requirement: Pre-existing unverifiable rows adopt a baseline instead of aborting
Verification SHALL adopt the CURRENT body as the baseline for any row whose stored
checksum is `'inline'`, and SHALL log how many rows it adopted.

Those rows recorded no hash, so there is nothing to compare against. Aborting on
them would fail the boot of every database created before body hashing existed.

#### Scenario: A legacy ledger upgrades without going offline
- **WHEN** a database whose ledger rows all read `'inline'` is verified
- **THEN** each such row is re-stamped with the current body hash
- **AND** the count is logged
- **AND** verification passes

#### Scenario: Enforcement still applies from the next boot
- **WHEN** an inline migration is edited after its baseline was adopted
- **THEN** two real hashes disagree
- **AND** verification throws
