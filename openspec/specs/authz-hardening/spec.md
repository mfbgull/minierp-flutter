# authz-hardening Specification

## Purpose

Hardens authorization-sensitive flows: role self-edit prevention, ownership
validation on destructive operations, safe runtime defaults, and write
permission gates on financial records.
## Requirements
### Requirement: Self-service edits cannot change own role
The user-update endpoint SHALL reject any attempt by a user to modify their own `role_id`, regardless of the target role. The guard MUST NOT be satisfiable by choosing a role whose name equals or differs from any particular value.

#### Scenario: User elevates self to Admin
- **WHEN** an authenticated user sends `PUT /api/users/:id` for their own id with `role_id` of the Admin role
- **THEN** the request fails with 400 and no field is updated

#### Scenario: User demotes self
- **WHEN** an authenticated user attempts to set their own `role_id` to any non-Admin role
- **THEN** the request also fails with 400 (own role is immutable through self-edit)

#### Scenario: Admin edits another user's role
- **WHEN** a user with `users:update` permission updates a *different* user's `role_id`
- **THEN** the update succeeds as before

### Requirement: Payment deletion requires ownership validation and audit
Invoice update SHALL only accept `deleted_payments` ids that belong to the invoice being updated (verified via allocation), and each removal MUST write an `activity_log` row containing payment id, amount, invoice, actor, and timestamp.

#### Scenario: Crafted cross-invoice payment deletion
- **WHEN** an invoice update supplies a `deleted_payments` id that is not allocated to that invoice
- **THEN** the request fails with 404/400 and no payment row is deleted

#### Scenario: Legitimate payment deletion during invoice edit
- **WHEN** an invoice update deletes one of its own payments
- **THEN** ledger entry, allocations, and payment are removed inside the existing transaction
- **AND** an audit row is written recording who deleted which payment

### Requirement: Production-safe runtime configuration defaults
The committed environment configuration MUST NOT use values that disable security middleware. `NODE_ENV` in `server/.env` SHALL be set to `production` (or equivalent safe value) so rate limiters are active.

#### Scenario: Rate limiters active with committed config
- **WHEN** the server starts using the committed `.env`
- **THEN** `NODE_ENV` is not `development`
- **AND** auth/login rate limiting is enforced on failed login attempts

### Requirement: Cash reconciliation saves require write permission
`POST /reports/cash-reconciliation` SHALL require a write permission (`reports:create`) instead of `reports:read`. The permission SHALL be seeded for administrator and manager roles when absent.

#### Scenario: Cashier cannot rewrite a bad day
- **WHEN** a user with only report read access posts counted = expected for a date showing a shortage
- **THEN** the save fails 403 and the existing variance record survives

#### Scenario: Manager can still save
- **WHEN** a manager holding `reports:create` saves a reconciliation
- **THEN** the snapshot persists as before (expected balance frozen at save time)

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

### Requirement: System report templates require admin role
Creating a system custom-report template (`user_id = 0`, visible to every user) SHALL require an administrator role, in addition to `reports:create`. Ordinary report builders MAY still create private templates. Templates loaded into the builder pass through the same expression validation as stored configs (already enforced by `report-expression-security`).

#### Scenario: Non-admin cannot plant a system template
- **WHEN** a non-admin user holding `reports:create` posts a template with `is_system = true`
- **THEN** the request fails 403 and no `user_id = 0` row is created

#### Scenario: Admin templates still publish
- **WHEN** an administrator creates a system template
- **THEN** it remains visible to every user as before

### Requirement: SQL column lists are never derived from a request body
A service that writes a row SHALL build its column list from a hardcoded
allowlist of that table's columns. It SHALL NOT derive columns from the keys of
a caller-supplied object, whether by `Object.keys`, `Object.entries`, or a
destructured rest. Values are always bound parameters; column names are never
user input.

This holds for both statement forms. `UPDATE … SET ${cols}` and
`INSERT INTO t (${cols})` are equally unsafe when `${cols}` comes from a request.

#### Scenario: An injected column name cannot reach the statement
- **WHEN** a request body carries a key that is SQL rather than a column name
- **THEN** the key is not present in the generated statement at all
- **AND** the request is rejected with 400 if the field is unknown

#### Scenario: A known column is still writable
- **WHEN** a request supplies `model_type` and `lead_time_days` for a forecast
  model config
- **THEN** both are written, and no other column is touched except `updated_at`

#### Scenario: An empty config still refreshes updated_at
- **WHEN** a request supplies no recognised field
- **THEN** the statement updates `updated_at` alone and no other column

### Requirement: Request bodies are validated by a schema that constrains shape
Every mutating route SHALL bind a schema that constrains the body's fields.
`z.object({}).passthrough()` SHALL NOT be used on a route that writes a
document. A schema that accepts any shape is not validation; it is a no-op that
reads as one.

Where a passthrough schema is retained — a partial-update endpoint whose handler
filters explicitly — the schema name SHALL appear in the
`KNOWN_PASSTHROUGH` inventory in `sqlKeyInjectionGuard.test.ts`, so adding a new
one fails a test and forces a review of its handler.

#### Scenario: Adding a passthrough schema without review fails the suite
- **WHEN** a new `z.object({}).passthrough()` schema is added to the validator
  without adding it to the pinned inventory
- **THEN** `sqlKeyInjectionGuard.test.ts` fails naming the undeclared schema

#### Scenario: An unknown field is rejected rather than silently written
- **WHEN** a body supplies a field the schema does not declare
- **THEN** the request fails with 400 and no row is written or modified

### Requirement: Numeric forecast parameters are range-bounded
Forecast tuning parameters SHALL be validated against their domain, not merely
coerced. Smoothing factors SHALL lie in `[0, 1]`, `service_level` in
`[0.5, 0.9999]`, `seasonal_periods` an integer in `[2, 60]`, `lead_time_days` an
integer in `[0, 365]`, and `bias_correction` either `0` or `1`.

#### Scenario: A smoothing factor outside [0,1] is rejected
- **WHEN** a config supplies `ses_alpha: 5`
- **THEN** the request fails with 400 and nothing is written

#### Scenario: An unknown model_type is rejected
- **WHEN** a config supplies `model_type: "not_a_model"`
- **THEN** the request fails with 400

### Requirement: The injection shape is guarded structurally
A test SHALL scan `services/`, `models/`, `controllers/` and `middleware/` for a
SQL statement whose interpolated fragment is derived from `Object.keys` or
`Object.entries`, and SHALL fail naming the file and line. The guard targets the
pattern rather than a single call site, so a future instance is caught before it
is exploited.

#### Scenario: The guard fires on a reintroduced defect
- **WHEN** `setModelConfig` is reverted to building its SET clause from
      `Object.entries(config)`
- **THEN** `sqlKeyInjectionGuard.test.ts` fails, naming the offending lines

