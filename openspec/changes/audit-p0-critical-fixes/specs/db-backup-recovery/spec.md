# Spec: db-backup-recovery (Delta)

## ADDED Requirements

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
