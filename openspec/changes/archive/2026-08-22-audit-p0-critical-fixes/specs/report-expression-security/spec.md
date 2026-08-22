# Spec: report-expression-security (Delta)

## ADDED Requirements

### Requirement: Computed column expressions are safely validated
Custom report `computedColumns[].expression` values SHALL be validated against a safe grammar (column references, arithmetic operators, numeric literals, parentheses, and whitelisted SQL functions) before being used in query construction. Any expression containing identifiers not in the report's field list, string literals, semicolons, comments, or non-whitelisted keywords MUST be rejected with a 400 validation error.

#### Scenario: Injection via expression is rejected
- **WHEN** a user with `reports:create` submits a computed column whose expression contains `(SELECT password_hash FROM users)` or any subquery/keyword outside the allowlist
- **THEN** the request fails with 400 and no report config is stored
- **AND** no SQL referencing `users.password_hash` ever reaches the database

#### Scenario: Legitimate expression still works
- **WHEN** a computed column uses an allowed form such as `quantity * unit_price` or `ROUND(debit - credit, 2)`
- **THEN** the report executes and returns computed values as before

### Requirement: Inline report configs pass through identical validation
Report execution paths that accept a transient/inline report configuration (not persisted via `reports:create`) SHALL apply the exact same expression validation; there MUST be no execution path that skips it.

#### Scenario: Inline config bypass closed
- **WHEN** a malicious expression is supplied in an inline/transient report config to any report-execution endpoint
- **THEN** it is rejected with 400 exactly as a stored config would be
