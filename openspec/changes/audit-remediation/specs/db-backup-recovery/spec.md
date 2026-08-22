# Spec: db-backup-recovery (Delta)

## ADDED Requirements

### Requirement: Scheduled backups with retention
Backups SHALL run automatically on a schedule (nightly) with a retention policy (7 daily, 4 weekly), in addition to the existing on-demand command; each backup SHALL be logged via the audit trail (BACKUP_CREATE).

#### Scenario: Nightly backup occurs without operator action
- **WHEN** the server has been running across a scheduled backup time
- **THEN** a new verified backup exists under server/database/backups/ and the trail records it

#### Scenario: Retention prunes old backups
- **WHEN** more than 7 daily and 4 weekly backups exist
- **THEN** the oldest beyond the policy are deleted automatically

### Requirement: Restorability is verified and checkpointed
Every backup SHALL run `PRAGMA wal_checkpoint(TRUNCATE)` against the source before snapshotting and `PRAGMA integrity_check` against the resulting copy, treating a failed check or busy checkpoint as backup failure; the application SHALL additionally checkpoint the WAL on an interval so the WAL file does not grow unbounded.

#### Scenario: Failed verification is reported
- **WHEN** a produced backup fails integrity_check
- **THEN** the backup is not counted as successful and the failure is logged loudly

### Requirement: Backup set includes uploads
The backup set SHALL include `server/uploads/` so a restore recovers employee documents alongside the database.

#### Scenario: Restore covers uploads
- **WHEN** a backup is restored per the documented procedure
- **THEN** employee document files referenced by employee_documents rows exist on disk

### Requirement: Documented restore procedure
A restore procedure SHALL be documented (README or docs/) covering: stopping the server, replacing the database from a chosen backup, and verifying integrity afterwards; the installer SHALL create a backup of an existing installation before any wipe or upgrade, and SHALL provide an upgrade path that preserves database and uploads.

#### Scenario: Operator can restore from README alone
- **WHEN** an operator follows the documented restore steps with a nightly backup
- **THEN** the server starts against the restored data passing integrity_check

#### Scenario: Reinstall does not destroy data
- **WHEN** the installer runs over an existing installation
- **THEN** a timestamped backup of the previous database and uploads exists before any file is removed
