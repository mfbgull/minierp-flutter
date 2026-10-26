# Unapplied customer payments: Stage E

Status: implementation complete and verified.

## Mounted API

| Method | Path | Required permission |
|---|---|---|
| POST | `/api/customers/:id/unapplied-cash` | `payments:create` |
| POST | `/api/unapplied-cash/apply` | `payments:update` |
| POST | `/api/unapplied-cash/refund` | `payments:create` |
| POST | `/api/payments/:id/reverse` | `payments:delete` |

The existing customer/payment routers expose receive and reverse; the new
unapplied-cash router is mounted in the real Express app. Existing legacy
payment routes retain their behavior. The new reverse route only handles
UNAPPLIED_RECEIPT documents through Stage D's dependency-safe primitive.

All operations use existing JWT authentication, permission middleware,
sensitive-operation rate limiting, Zod body/parameter middleware and response
helpers. Request bodies use snake_case fields; `operation_date` is the explicit
business date. Payment methods default to Cash. IDs, currency bounds, dates,
unknown fields and allocation-list size are validated before writes.

All four endpoints require `Idempotency-Key`. Receive and reverse wrap the
service operation plus the standard replay claim in one immediate transaction;
receive replay returns the original payment ID/amount without collecting cash
again. Apply/refund pass the key to the durable Stage D application mechanism.
Key scoping, retention behavior, payloads, responses and permissions are
documented in `docs/API.md`.

Domain errors retain stable codes and 400/404/409 statuses; dependency errors
include blocked source/invoice details. Unexpected failures return the shared
generic 500 envelope, without raw diagnostics. The controller logs only the
error class, not request bodies or potentially sensitive exception messages.

## Request-boundary fixes found by red tests

- Missing invoice IDs were grouped with invalid invoices as 409. The service
  now distinguishes missing invoices with 404 `INVOICE_NOT_FOUND`; cancelled,
  deleted and future-dated invoices remain state conflicts.
- Malformed JSON reached the global error logger/handler and returned 500.
  A narrow parser-error middleware now returns safe 400 `VALIDATION_ERROR`
  immediately after JSON parsing, before raw parser diagnostics can be logged
  or returned. Other errors continue through existing handlers.
- CORS advertised only Content-Type and Authorization. Browser clients could
  not send the required retry key. Idempotency-Key is now allowed without
  changing origin restrictions, credentials, or allowed methods.

## Test evidence

Tests exercise actual HTTP POST bodies against the mounted app, with normal
authentication middleware and the real migrated isolated test database.

- Initial API red: 14/14 cases failed before routes were mounted.
- Expanded red: missing invoice returned 409 instead of 404; malformed JSON
  returned 500 instead of 400 (2 failed, 19 passed).
- Browser preflight red: allowed headers omitted Idempotency-Key.
- Focused regression gate: 6 suites / 107 tests passed, exit 0: mounted API,
  Stage D GL operations, validation, accounting invariants, payment guards,
  and closed-period immutability.
- The subsequently added non-admin permission case passed independently:
  create grants receive/refund, update grants apply, and delete grants reverse;
  unauthorized actions remain forbidden. Other cases were excluded by this
  run's name filter, not disabled.
- The complete API suite now has 23 cases, including receive/apply/refund/reverse,
  replay/conflicts, failed-attempt rollback and concurrent retries, ownership,
  source/receipt/invoice limits, duplicate invoice allocations, period locks,
  401/403 denial across all routes, missing resources, malformed input,
  safe unexpected failures, CORS preflight, and persisted payment/GL effects.
- A-N assertions run on fresh valid fixtures through the mounted lifecycle;
  these tests do not rely on repairing existing dummy records.
- Final full server suite: 150 suites / 1,372 tests passed, zero failures or
  pending tests, exit 0, in 2,897.394 seconds. All 23 mounted API cases passed.
  Results: `server/.tmp-test/stage-e-server-full.json`.
- Final `npm run typecheck` and `npm run lint`: passed, exit 0. Lint emitted
  the existing `MODULE_TYPELESS_PACKAGE_JSON` warning for `eslint.config.js`.
- Jest emitted a worker teardown warning and force-exited a worker. The suite
  passed, but this is not evidence of clean teardown; no open-handle diagnosis
  was performed in this phase.

Full gate command, from `server/`:

```bash
node scripts/run-guarded-tests.cjs --maxWorkers=2 --silent --json --outputFile=.tmp-test/stage-e-server-full.json
```

The guarded runner verifies canonical main/WAL/SHM fingerprints around Jest.
Existing dummy history was not investigated, reconciled, repaired, activated,
or used as an implementation blocker. No historical verification script was
rerun for this stage.

Flutter code is unchanged and its full suite is intentionally not rerun.
This phase adds backend endpoints; it does not implement their Flutter UI.
