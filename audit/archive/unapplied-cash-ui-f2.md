# Unapplied customer cash UI: F2 client foundation

Status: F2 implementation complete; focused tests and analyzer pass. Full Flutter
suite completed with one unrelated scanner failure that passed on isolated rerun.
This is not a green full-suite claim. Customer screens/dialogs remain F3-F6 work.

Execution plan: `.omo/plans/unapplied-customer-cash-ui.md`.

## Implemented

- Typed cash capabilities, receipt/capacity summaries, paginated activity and
  invoice/source lines, operation requests and nullable payment/application results.
  Form calculations use integer minor units; input rejects nonfinite/nonpositive,
  excessive and more-than-two-decimal amounts, duplicate allocation lines,
  invalid dates and unsupported payment methods.
- Receive/apply/refund/reverse repository requests use exact Stage E paths,
  snake_case bodies and per-operation Idempotency-Key headers. They do not call
  legacy payment creation for unallocated cash.
- Financial reads and capability checks bypass offline repository caching.
  Successful cash writes await dependent cache invalidation and refresh customer,
  invoice, payment, dashboard and relevant report providers. Cash date/history
  providers also observe the existing customer mutation version.
- Payment DTOs preserve payment kind and void state; unified payments preserve
  nullable kind. Shared error parsing retains optional domain codes and typed
  dependency blockers, including error envelopes returned with HTTP 200, while
  retaining compatibility with legacy string errors. Parse failures are generic.
- A single operation controller per server/user scope serializes submissions.
  It saves the immutable normalized body, key, first dispatch time and original
  replay policy to the existing preferences store before any financial POST.
  No auth tokens are persisted, and another server/user cannot resume the record.
- Restore reads pending state without a POST. Explicit resume requires the
  original policy plus a fresh online capability response. Receive uses durable
  receipt replay; apply/refund use permanent application replay. Legacy/missing
  policies, corrupt storage, unsupported servers and unavailable status fail closed
  into recovery without replacing the request or inventing a new key.
- Reversal recovery checks the current payment and unused-source state online.
  An already-voided receipt is reported as current state, not attributed to this
  request. A used/inaccessible receipt cannot be blindly resubmitted.
- Confirmed success clears pending state. Definite validation/permission rejection
  of a first attempt allows correction; an uncertain earlier attempt remains
  retained even if a later retry is denied. Intentional repeats after confirmed
  success receive a new key. Session/server changes before dispatch block POST.

## Evidence

- Initial meaningful red: payment metadata was lost and structured error codes
  were dropped. Repository contract tests then failed against explicit interface
  stubs before endpoint wiring. Pending-operation tests failed before persistence
  and dispatch were implemented. Provider-refresh assertions failed before the
  invalidation hook was wired.
- A fresh-read regression caught an unnecessary Cache-Control request header
  that the existing CORS policy does not permit; it was removed. Online-only
  behavior is enforced by bypassing the offline cache, not by adding blocked headers.
- Focused gate: 168 tests passed, exit 0, including the three new F2 test files,
  existing repository tests and model tests. Output: `/tmp/minierp-f2-focused.log`.
- Pending tests cover lost committed response, immutable same-key restart retry,
  more-than-30-day recovery, original/missing replay guarantees, unsupported
  capabilities, user/server isolation, duplicate taps, storage failure/corruption,
  session changes, reversal status/dependencies, denied uncertain retries and
  distinct keys for intentional new receipts. Actual server key pruning and GL
  effects remain covered by the completed F1 mounted regression.
- Repository tests exercise real Dio request/interceptor handling, exact methods,
  URLs, query parameters, headers/bodies, nullable IDs, minor-unit arithmetic,
  structured/legacy errors, cache invalidation and offline-cache refusal.
- ProviderContainer test drives the real controller/repositories and observes
  refetches in both operation-date views, activity and customer consumers.
- `flutter analyze --no-pub`: no issues, exit 0 (48.1 seconds).
- `node scripts/l10n-drift.js`: passed; existing Urdu fallback gap 55, cap 60,
  zero orphan keys. No UI/localization files changed in this stage.
- `git diff --check`: passed at the implementation checkpoint.
- Full Flutter suite: 814 passed / 1 failed / 0 skipped, exit 1, in 1,110.537
  seconds. Command: `flutter test --no-pub --reporter json`; machine-readable
  output: `/tmp/minierp-f2-full.jsonl`. All F2 cases passed within this run.
- The sole failure was `scanned code adds the matching item to the cart` in
  `test/features/sales/pos_screen_test.dart:152`: expected `Cart (1 items)`,
  found none. The scanner uses wall-clock timing in
  `lib/features/sales/pos_screen.dart:81`; its fixture overrides catalog and
  warehouse providers rather than using the changed cash repositories. Neither
  scanner code nor its tests changed. Timing under suite load is the likely cause,
  not a proven root-cause diagnosis.
- Direct rerun: `flutter test --no-pub test/features/sales/pos_screen_test.dart
  --reporter expanded`: all 11 tests passed, exit 0, including the failed scan.
  Output: `/tmp/minierp-f2-pos-recheck.log`. The test was not changed, skipped or
  weakened; no unrelated scanner fix or second full-suite run was performed.

Server code/API contracts are unchanged in F2, so its full suite was intentionally
not rerun. F1 already passed all 152 server suites / 1,386 tests. No live database
or historical dummy-data repair/reconciliation was involved. No new UI surface
exists yet, so this stage makes no visual-QA or end-to-end screen completion claim.
