# Spec: authz-hardening (Delta)

## ADDED Requirements

### Requirement: Audit trail purge is a distinct permission
Bulk activity_log cleanup SHALL require a dedicated `activity_log:purge` permission (seeded to Admin only), separate from `activity_log:read`; the permission SHALL exist in the permissions catalog and migrations SHALL add it to existing installs.

#### Scenario: Purge permission gates cleanup
- **WHEN** a user without activity_log:purge calls POST /activity-log/cleanup
- **THEN** the request is rejected 403 regardless of read access

#### Scenario: Admin retains purge capability
- **WHEN** an admin with the seeded purge permission calls cleanup with days >= 365
- **THEN** the cleanup executes and is itself recorded in the trail

### Requirement: Secrets and environment files stay out of version control
`server/.env`, `server/node_modules/`, and `server/uploads/` SHALL be untracked and git-ignored; the committed placeholder JWT secret SHALL be rotated for development use and history-scrubbed or documented for rotation on any deployed checkout.

#### Scenario: Env file is untracked
- **WHEN** `git ls-files server/.env server/node_modules server/uploads` is run
- **THEN** no files are listed

#### Scenario: Committed secret is no longer valid
- **WHEN** a token forged with the placeholder secret from git history is presented
- **THEN** the server rejects it
