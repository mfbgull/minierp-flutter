# Spec: db-backup-recovery

## Purpose

Provides consistent, restorable database backups (on-demand and scheduled with
retention), keeps live DB files out of version control, and documents a safe
restore path.

## Requirements

### Requirement: Database backup command
The system SHALL provide an on-demand backup command that creates a consistent, restorable snapshot of the ERP SQLite database (including WAL content) at `server/database/backups/<timestamp>.db`.

#### Scenario: Backup runs successfully
- **WHEN** an operator runs the backup command (`npm run db:backup`) against the live database
- **THEN** a new file exists under `server/database/backups/` that passes `PRAGMA integrity_check`
- **AND** the source database is not locked or corrupted by the operation

#### Scenario: Backup of live WAL-mode database
- **WHEN** the backup command runs while the server has the database open in WAL mode
- **THEN** the snapshot includes all transactions committed up to that point

### Requirement: Live database excluded from version control
The repository SHALL NOT track live database files (`erp.db`, `erp.db-shm`, `erp.db-wal`, and any nested copies such as `Untitled Folder/erp.db*`), and `.gitignore` SHALL exclude them so they can never be reverted by git operations.

#### Scenario: Database files ignored by git
- **WHEN** `git status --porcelain server/database/` is inspected after removing the files from the index
- **THEN** no `*.db`, `*.db-shm`, or `*.db-wal` entry appears as tracked-modified
- **AND** new runtime writes to those files never appear in `git status`

#### Scenario: Git destructive operations cannot destroy business data
- **WHEN** any `git checkout`, `git reset --hard`, `git stash`, or `git clean` is performed on the working tree
- **THEN** the live database files are unaffected because git no longer tracks them

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
