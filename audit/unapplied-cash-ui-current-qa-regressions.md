# Independent QA regression verification

Date: 2026-10-18. Surface: mounted Flutter dialogs driven by taps and hardware-key events, with intercepted HTTP requests held by `Completer<void>`. This is widget execution, not live-server/browser execution.

Exact invocation from repository root:

```sh
flutter test test/features/customers/unapplied_cash_receive_test.dart test/features/customers/unapplied_cash_apply_test.dart test/features/customers/unapplied_cash_refund_reverse_test.dart --no-pub --reporter expanded --name 'Escape keeps|Tab traversal|Shift\+Tab'
```

Terminal session 44412 completed with exit code 0. Final output:

```text
00:28 +10: /media/fawad/26F2EFA7F2EF7987/D/minierp-flutter/test/features/customers/unapplied_cash_refund_reverse_test.dart: Tab traversal stays inside reverse (urdu=true)
00:29 +11: All tests passed!
```

Verified selection: four pending-write Escape cases (Receive, Apply, Refund, Reverse), six forward Tab containment cases (Apply, Refund, Reverse, each English and Urdu), and one English Receive Shift+Tab direction case.

Source inspection confirmed each pending-write test initiates the real dialog submit flow, pauses the POST interceptor before completion, asserts one dispatched request, presses Escape, asserts the dialog remains mounted and request count stays one, then releases the request. Apply's latest locale loop was inspected during this run; the test output explicitly included both `urdu=false` and `urdu=true` cases. Receive's reverse-direction test holds Shift while sending Tab and verifies focused semantics moves from submit to Close. Containment tests assert focused widget ancestry on each forward Tab step; they do not prove that every control is reachable or that visible focus styling is correct.

The three complete file-level test runs and analyzer run listed in the main QA matrix are executor-reported results. This reviewer independently reran only the 11 focused regressions above; full Flutter/server suites and analyzer were not duplicated. No product source, database data, or financial records were modified by this verification.

## Newer executor verification

This section records results reported by the executor after the independent 11-test run. It does not change the count or scope of that earlier run. The reviewer inspected the added test source but did not independently execute these newer cases.

Executor reports all three complete files and analyzer PASS after the additions:

```sh
flutter test test/features/customers/unapplied_cash_receive_test.dart --no-pub --reporter compact
flutter test test/features/customers/unapplied_cash_apply_test.dart --no-pub --reporter compact
flutter test test/features/customers/unapplied_cash_refund_reverse_test.dart --no-pub --reporter compact
flutter analyze --no-pub
```

Added coverage inspected in source:

- `Escape restores keyboard focus to the receive launcher (en/ur)`: Tab focuses the launcher; Enter opens Receive; Escape closes it; focused semantics returns to the launcher.
- `Escape restores keyboard focus to apply launcher (urdu=false/true)`: same keyboard-open/return sequence with Apply.
- `Escape restores keyboard focus to refund/reverse launcher (urdu=false/true)`: same sequence for each correction dialog and locale.
- `Shift+Tab moves back from submit to Close (en/ur)`: six forward Tabs first assert submit focus, then held Shift plus Tab asserts Close focus. The earlier independent run covered English only; the newer executor run also covers Urdu.

These test harnesses use explicit launcher buttons and mounted production dialogs. They establish widget focus return, not every production-page launcher's browser integration. Complete reverse loops in Apply/Refund/Reverse, visible focus appearance, picker interactions outside the English Receive case, live-browser pending-write behavior, and actual assistive-technology announcements remain unexecuted. Receive reverse coverage is the specified submit-to-Close transition; no full reverse-loop certification is implied.

### Latest executor rerun (2026-10-18)

- After QA identified a missing closed-menu assertion, the method-picker test was tightened to assert the `Bank` option disappears after Escape. The complete Receive test file then passed all 22 tests.
- `flutter analyze --no-pub` passed with no issues (51.3 seconds) after that assertion was added.
- `git diff --check` passed.
- These are executor results, not an independent reviewer rerun. The picker test covers English only. Visible-focus appearance, live-browser pending-write behavior, and real assistive-technology announcements remain open; QA's reassessment no longer requires exhaustive reverse-loop coverage.
