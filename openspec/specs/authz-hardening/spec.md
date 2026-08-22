# Spec: authz-hardening (Delta)

## ADDED Requirements

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
