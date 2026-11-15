# authz-hardening (Delta)

## ADDED Requirements

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