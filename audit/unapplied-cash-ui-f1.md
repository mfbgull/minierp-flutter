# Unapplied customer cash UI: F1 backend prerequisites

Status: F1 implementation complete and verified. F2-F7 remain pending.

Execution plan: `.omo/plans/unapplied-customer-cash-ui.md`. User authorized
implementation after the receipt-replay retention review was incorporated.
This artifact covers F1 only, not completion of the Flutter UI.

## Implemented

- Customer cash summary and receipt history, with live pool totals independent
  of pagination and date-eligible capacity matching source/receipt constraints.
- Paginated application/refund activity with invoice/source lines, date filters,
  stable ordering and snapshot-consistent batched reads. No N+1 HTTP/SQL calls.
- Authentication and payments:read authorization, validated IDs/dates/pagination,
  distinct empty versus missing customers, and safe error mapping.
- Authentication-only, no-store replay capability metadata so create-only users
  can verify safe receive support without gaining financial read access.
- Migration 111 registers permanent receipt replay metadata with unique keys,
  non-cascading payment/customer references and an application-history date index.
  Existing migrations and the central 30-day cleanup policy are unchanged.
- Receive persists its replay record in the same immediate transaction as all
  financial effects. Replay precedes current balance/period checks and remains
  valid after central claim pruning or receipt reversal. Changed payloads conflict.
- Existing payment list/detail projections include kind and void state; unified
  customer refunds are cash outflows, with nullable kind on non-payment sources.
- API documentation updated. No Flutter files changed in F1.

## Evidence

- Meaningful red: receive replay after central pruning returned 201 rather than
  200; cash reads and capability returned 404. Initial read-test compilation
  failure was corrected before its separate meaningful red run (11/11 failed).
  Artifacts: `server/.tmp-test/ui-f1-red.json`, `ui-f1-read-red.json`.
- First green: 2 mounted suites / 36 tests passed, exit 0. Tests use real POST
  bodies, migrated isolated databases, real authentication and persisted effects.
  Artifact: `server/.tmp-test/ui-f1-first.json`. An initial duplicate index in the
  new unpublished migration was removed; migration 110 already supplies it.
- Mounted lost-response regression calls the real pruning function after aging
  only its fixture claim, asserts the claim is gone, and retries identical body/key.
  It checks original payment identity, one receipt/source/posting, payload conflict
  and replay after reversal. A-N assertions cover the resulting lifecycle.
- Added database-close/reopen coverage, key/FK constraints, rollback absence of
  replay metadata and concurrent duplicate requests retaining exactly one record.
- Server typecheck and lint passed, exit 0, at the initial implementation
  checkpoint; lint emitted the existing MODULE_TYPELESS_PACKAGE_JSON warning.
- Expanded targeted regression gate: 9 suites / 136 tests passed, exit 0, in
  251.568 seconds. Includes mounted reads/writes, replay persistence, migrations,
  service GL operations, cash truth, A-N invariants, period locks and payment guards.
  Artifact: `server/.tmp-test/ui-f1-targeted.json`.
- Final server typecheck and lint passed, exit 0; the existing module-type warning
  remains. `git diff --check` passed.
- Jest emitted a worker teardown warning in the focused run; passing assertions
  do not establish clean teardown. No open-handle investigation was performed.
- Full guarded server suite: 152 suites / 1,386 tests passed, zero failures or
  pending tests, exit 0, in 1,064.233 seconds. Artifact:
  `server/.tmp-test/ui-f1-server-full.json`. Jest also emitted the existing worker
  teardown warning; no claim of clean teardown is made.

All test runs use the canonical database guard. No live migration or historical
dummy-data investigation, reconciliation, repair or activation was performed.
Flutter tests are intentionally not run for this backend-only stage.
