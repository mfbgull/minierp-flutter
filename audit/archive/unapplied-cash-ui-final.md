# Unapplied customer cash UI: final verification

Status: code-level findings are fixed; fresh current-build workspace captures
and targeted keyboard/accessibility checks are recorded. Desktop compact
Reverse accessible-name evidence is now recorded for both locales. A latest
Receive-file rerun passed all 22 tests, including keyboard date-picker and
payment-method-menu dismissal, and `flutter analyze --no-pub` passed. The POS
barcode-scanner timing defect is fixed; after the fix, the POS file passed all
12 tests and the full Flutter suite passed all 917 tests. QA and fidelity
reviewers reassessed the newer widget-level busy-write and focus evidence.
The follow-up adds explicit focused button outlines, live-region announcements
for dynamic Apply states, and regression assertions for focus styling and
pending/error announcements. The current full Flutter suite passed 919 tests,
and the analyzer and diff check passed. Actual assistive-technology speech
quality remains unverified. The earlier
pre-fix full run had 915 passed and one POS scanner failure; its isolated case
passed, and the added delay regression reproduced prefix loss before the timing
fix. A previous full rerun stopped at 719 tests and an isolated compile attempt
failed when disk space was exhausted; those are historical. Earlier full-suite
and targeted results remain recorded below. The historical guard refusal below is
superseded by the clean server rerun recorded later in this report.

## Canonical database guard baseline acknowledgement

The first F7 guarded Jest invocation refused to start because the recorded main
database fingerprint was stale. It exited 1 before launching tests:
`/tmp/minierp-f7-api-targeted.log`.

- Previous expected SHA-256: `63e61c6a77991c4b1172abfd9da7135f80cd359b70a911f9c833c0379ee9b50f`.
- Observed SHA-256: `501dad33c43ef2674aed9b92d7a74c60c18487a9b1f649c98c6638d5cc49e9df`.
- Main-file modification time: 2026-10-16 17:44:47.575 UTC, before today's F6/F7
  runs. F7's isolated fixture records and compares main/WAL/SHM fingerprints.
- The constructor guard remains installed before every fixture database import,
  rejecting canonical writes and aliases. No F7 script opens canonical data for
  writing, and no historical records were inspected, repaired or reconciled.
- The earlier writer cannot be identified from a hash and file timestamps alone;
  this acknowledgement does not claim its provenance is known.

After the refusal was reported, the user explicitly chose "Investigate and approve
a new baseline". Only the expected constant in the guarded runner was updated.
The before/after main/WAL/SHM comparison and all constructor protections remain
unchanged. Earlier audit hashes remain historical evidence, not rewritten results.

## Work in progress

- Fresh owned fixture server: `server/scripts/fixtures/unapplied-cash-ui.cjs`.
  Caller-selected DATABASE_PATH and production mode are rejected. Control routes
  run only on a separate loopback test server, never in the production app.
- Runtime test: `integration_test/unapplied_cash_flow_test.dart`, with real
  Flutter dialogs, HTTP and SharedPreferences. The fixture health marker and
  isolated XDG app-storage paths are asserted before login or financial writes.
- Fixture guard test: red (missing implementation), then 1 passed via
  `node --test scripts/unapplied-cash-fixture.test.cjs`.
- Integration analyzer initially passed with zero issues (30.7 seconds).
- `bash scripts/check-unapplied-cash-ui.sh` passed all three native Linux
  processes: journey phase 5/5, lost-response phase 1/1, and new-process resume
  phase 1/1. Logs and final status are in
  `server/.tmp-test/ui-f7-run-xpB8SN/`. The run's 12 invariant collections were
  empty, GL groups were empty with total difference 0, and
  `canonicalUnchanged` was true.
- The lost-response scenario committed one 70-unit receipt, aged its central
  idempotency key past retention, pruned that key, then resumed the original
  saved request in a separate Flutter process. Unsupported capability blocked
  a POST; after capability recovery, retry produced exactly one receipt.
- `npm test -- --runInBand src/__tests__/unappliedCashApi.test.ts` passed 26/26.
  The API regression covers reversing unused cash and rejecting later apply
  and refund attempts.
- `scripts/check.sh --quick` passed typecheck, lint, Flutter analysis and l10n
  drift checks. It reported 2188 English keys, 2133 Urdu keys, a 55-key
  fallback gap within the configured cap of 60, and no orphan keys.
- The full Flutter suite passed: 953 tests, zero failures. The integration
  journey is run separately and is not included in that count.
- The release web build completed successfully. In the built app, the browser
  journey received 500, applied 400 to invoice 1, then refunded 100. The live
  fixture showed one 500 receipt and one -100 refund, source consumed/refunded/
  remaining amounts of 400/100/0, invoice paid/balance of 400/0, customer AR
  and credit balances of 0/0, and balanced GL. Screenshots include the apply
  review, refund draft/review, and settled workspace.
- The full guarded Jest run reported 152 suites and 1387 tests passed, but the
  wrapper exited 1 because its before/after canonical database or WAL/SHM
  fingerprint differed. The database guard's baseline remains the user-approved
  `501dad33…`; after the run the main database hash was
  `27e5cc340bb5a43a1d4974f3b206ccfd05919e13a75bcefa6e16b13e5bd7bc97` with a
  modification time of 2026-10-17 09:05:53 +0500. The source of the change is
  unknown. No new baseline was recorded, and no database repair or historical
  reconciliation was performed. The concurrently running browser fixture
  consequently reported `canonicalUnchanged: false` in its final status; its
  financial and accounting invariant checks remained clean.
- The original visual matrix produced 52 screenshots across English/Urdu,
  light/dark, desktop/phone, workspace, receive, apply, scrolled apply, refund,
  and reversal review. Review later found several workspace screenshots did not
  show their claimed scroll positions; those specific captures have been
  replaced from the current release build. Do not treat the historical 52-image
  matrix as proof that every image is current or valid.
- The pending browser screenshot uses a browser-level aborted POST, so it
  records the client's persisted uncertain request without claiming that this
  browser capture committed. The native lost-response test above is the
  committed-request and process-restart evidence.
- A fresh browser fixture started after the guarded Jest run reported
  `canonicalUnchanged: true`; its fixture GL difference was 0 and all 12
  invariant collections were empty. Its capture-only customer had a 500-unit
  unused receipt and a 400-unit invoice; the closed-period attempt and aborted
  request added no customer-3 payment. This confirms the screenshot session
  itself did not change the canonical database.
- The earlier full guarded Jest run passed all 152 suites and 1387 tests, but
  failed its post-run fingerprint check. The then-current canonical DB hash was
  `27e5cc34…`; no WAL/SHM change was present. Do not treat that earlier run as
  green.
- Follow-up trace confirmed Jest's shared setup assigns each suite a dedicated
  temporary `DATABASE_PATH`; the canonical-path test helper opens its target
  read-only. The mismatch is the main DB (`27e5cc34…`), not WAL/SHM, and the
  guard resolves to the same `server/database/erp.db` path as the inspected
  file. No process held that file open before the clean rerun. The earlier
  writer cannot be attributed conclusively, but the test setup and source trace
  did not identify a suite writing to the canonical DB.
- The approved baseline was updated to `27e5cc340bb5a43a1d4974f3b206ccfd05919e13a75bcefa6e16b13e5bd7bc97`.
  A fresh full guarded rerun then passed all 152 suites and 1387 tests in
  1454.969 seconds, with the canonical DB/WAL/SHM fingerprints unchanged. The
  guard now prints exact changed paths and before/after hashes if this recurs.
  The current canonical DB remains unchanged at that approved fingerprint.

## Review findings follow-up

- Added `AppSpacing` tokens for the prescribed 4–48 px scale and replaced
  repeated layout spacing literals throughout the customer cash workspace,
  receive, apply, and shared action dialogs.
- The shared Pluto serial-number cell now uses its active grid theme foreground
  instead of hardcoded `Colors.black54`, fixing dark-mode contrast for cash
  grids as well as other detail grids.
- Receipt methods now normalize known values and reuse the existing localized
  method labels; unknown server values remain visible unchanged. Added an Urdu
  receipt-method regression test and dark-grid serial foreground test.
- `AppSpacing` tokens now cover the shared customer-cash layout scale, the
  serial-number cell follows its active grid theme, and compact Reverse buttons
  expose the localized tooltip as an accessible name. Added the Reverse tooltip
  widget regression test and retained the Urdu receipt-method regression.
- `flutter analyze --no-pub` passed with no issues. The complete
  `unapplied_cash_payment_widgets_test.dart` file passed 15 tests; all eight
  English/Urdu Escape widget tests passed. New controlled-pending Escape tests
  passed for Receive, Apply, Refund, and Reverse. Forward focus containment
  passed for Apply, Refund, and Reverse across English/Urdu; Receive's forward
  and Shift+Tab direction test passed in English. Before the scanner timing fix,
  the full Flutter rerun completed with 915 passed and one failed: the scanned-
  code cart assertion in `test/features/sales/pos_screen_test.dart`
  (`Cart (1 items)` not found). The exact test passed alone, but a new delay
  regression reproduced prefix loss before the fix. Logs:
  `/tmp/f7-flutter-full-final.log`, `/tmp/f7-pos-isolated.log`, and
  `/tmp/pos-delay-red.log`.
  After changing scan timing to use monotonic `KeyEvent.timeStamp` rather than
  callback-time `DateTime.now()`, the complete POS test file passed 12/12 and
  the full Flutter suite passed 917/917. The POS file was rerun after removing
  formatter-only churn and still passed 12/12; final analyzer and whitespace
  checks passed. Logs: `/tmp/pos-screen-final.log`,
  `/tmp/pos-flutter-full-fixed.log`, and `/tmp/pos-analyze-final.log`.
  The earlier full rerun stopped at 719 tests, and its isolated compile attempt
  failed because the root filesystem was full. Those are historical results.
- Current-build browser evidence is in
  `audit/unapplied-cash-ui-current-manual-qa.md`; capture provenance, hashes,
  and dimensions are in
  `audit/screenshots/unapplied-cash-ui/f7-review-capture-manifest.md`. The
  current run manually confirmed Receive Escape in English and Urdu and Reverse
  Escape in Urdu. Widget regressions now cover busy-write Escape protection for
  all four workflows, keyboard launcher restoration for all dialogs/locales,
  bilingual Receive submit-to-Close Shift+Tab, and forward containment for
  Apply/Refund/Reverse in both locales. Latest English Receive tests also cover
  date-picker dismissal and payment-method menu dismissal.
- The current desktop Reverse action has a localized accessible name in both
  locales, confirmed in browser semantics; the widget test asserts the
  localized compact-action tooltip. English Receive has independently
  verified forward Tab containment and focus restoration. Follow-up tests assert
  the shared filled-button focus outline and the custom
  destructive confirmation outline. Apply pending and refund error regressions
  assert live-region semantics. Read errors and permission notices now use live
  regions too. Actual browser-rendered outline contrast and screen-reader speech
  quality remain unverified; no full assistive-technology certification is
  claimed. The QA reassessment describes the state before this follow-up.
