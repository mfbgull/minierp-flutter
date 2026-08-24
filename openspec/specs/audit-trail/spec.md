# Spec: audit-trail

## Purpose

Captures a complete, reconstructable audit trail of financial and privileged
operations via a unified logging service, correlation ids, and a privileged,
bounded cleanup path.

## Requirements

### Requirement: Before/after values are recorded
`activity_log` SHALL gain `old_value TEXT`, `new_value TEXT`, `reason TEXT` and `correlation_id TEXT` columns; update operations SHALL populate `old_value`/`new_value` with JSON diffs of the changed fields, deletions SHALL capture the full prior row summary, and every log row written while handling one HTTP request SHALL share that request's correlation id.

#### Scenario: Invoice amount edit is reconstructable
- **WHEN** a paid invoice's total is edited via the API
- **THEN** the resulting activity_log row contains the previous and new values of the changed fields, the acting user, and a correlation id shared with the related stock/GL log entries

#### Scenario: Delete captures prior state
- **WHEN** a document is deleted
- **THEN** `old_value` contains a summary of the deleted record sufficient to identify it (number, id, totals)

### Requirement: Catch-all logging middleware backstop
A middleware layer SHALL, after any 2xx response to a mutating verb (POST/PUT/PATCH/DELETE), write an activity_log row when the handler has not already logged the operation, using route-derived entity/action metadata; handlers MAY enrich or replace the default row via the request context flag.

#### Scenario: Unlogged controller still produces a trail row
- **WHEN** a mutating endpoint in a controller with no explicit logger calls completes successfully
- **THEN** exactly one activity_log row exists for the request with actor, method, route, entity type and status

#### Scenario: No double logging
- **WHEN** a handler explicitly logs via the activityLogger service
- **THEN** the middleware emits no additional row for that request

### Requirement: Financial document lifecycle is always logged
Invoice creation, update, deletion, cancellation and return processing SHALL each write structured activity_log rows via the unified service (typed ActionTypes, full column set), including the correlation id linking the invoice event to its stock movements, ledger entry and journal lines.

#### Scenario: Invoice delete is auditable end-to-end
- **WHEN** an invoice is deleted
- **THEN** one queryable trail row records who deleted it, when, the invoice identity, and prior totals

### Requirement: Privilege and configuration changes are logged
Role creation/update/delete, role-permission assignment changes, settings and integration updates, preferences, dashboard layout, custom report definition changes and stock-batch halt/unhalt/patch operations SHALL write activity_log rows including old/new values.

#### Scenario: Permission grant leaves a trace
- **WHEN** permissions for a role are updated
- **THEN** the log records the role, the permission delta (added/removed), and the acting user

### Requirement: Unified logging convention
All audit writes SHALL go through the activityLogger service using ActionType enum members; embedded raw `INSERT INTO activity_log` SQL in controllers/models SHALL be migrated to the service; POS sales SHALL be attributed `entity_type='INVOICE'` with the invoice id; dead ActionType members SHALL either be emitted or removed.

#### Scenario: Entity-based query finds POS sale
- **WHEN** the trail is queried by entity type INVOICE for a POS-created invoice id
- **THEN** the POS sale row appears

### Requirement: Trail cleanup is privileged and bounded
Bulk trail cleanup SHALL require a dedicated `activity_log:purge` permission, SHALL reject retention windows shorter than 365 days, and SHALL write its own SYSTEM_CLEANUP row to an append-only sink that subsequent cleanups do not remove.

#### Scenario: Reader cannot purge
- **WHEN** a user holding only `activity_log:read` calls POST /activity-log/cleanup
- **THEN** the request is rejected 403

#### Scenario: Aggressive retention window rejected
- **WHEN** cleanup is requested with days < 365 by a permitted user
- **THEN** the request fails validation stating the minimum retention

### Requirement: Log delivery survives shutdown
Queued-but-unwritten log entries SHALL be flushed synchronously during graceful shutdown before the database closes, insert failures SHALL be retried with a bounded queue rather than growing without limit, and financial-mutation log rows SHALL be written within the business transaction where technically feasible.

#### Scenario: SIGTERM flushes pending rows
- **WHEN** the server receives SIGTERM with fewer than batch-size queued log entries
- **THEN** all queued entries persist before process exit
