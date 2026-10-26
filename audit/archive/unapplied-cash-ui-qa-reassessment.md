# F7 QA reassessment

Date: 2026-10-18. Recommendation: **the two evidence findings are resolved; final acceptance remains OPEN for visible-focus and announcement evidence**. This pass inspects the corrected test source and current QA artifacts. The latest Receive 22/22 result, analyzer PASS (51.3 seconds), and diff-check PASS are executor-reported; this reviewer did not independently rerun them. The prior independent 11-test execution remains separately recorded in `audit/unapplied-cash-ui-current-qa-regressions.md`.

## Resolved findings

1. **Method-picker dismissal now has a closed-state assertion.** Source inspection of `test/features/customers/unapplied_cash_receive_test.dart:365` confirms the test asserts `Bank` is present after keyboard opening and absent after Escape, while the Receive amount field remains mounted. Date-picker dismissal also explicitly asserts `DatePickerDialog` is absent. The executor reran the complete file after this correction: 22/22 PASS. This closes the prior assertion finding. The picker scenario covers English Receive only; no other locale/control scope is inferred.

2. **Final-audit coverage text is aligned.** `audit/unapplied-cash-ui-final.md` now records passing controlled-widget busy-write guards, bilingual keyboard launcher restoration, bilingual Receive submit-to-Close direction, bilingual Apply/Refund/Reverse forward containment, and English Receive picker dismissal. It retains visible keyboard focus and dynamic outcome/error announcements as acceptance gaps and explicitly records the incomplete full Flutter run. The former stale-coverage finding is closed.

## Established coverage

- Current browser captures, localized Reverse names, idle/error Escape dismissal, and English Receive forward Tab containment/launcher restoration retain their prior PASS status.
- The independent 11-test run establishes four pending-write Escape guards, six bilingual Apply/Refund/Reverse forward-containment cases, and English Receive submit-to-Close reverse direction.
- Newer executor-reported complete-file passes add eight bilingual keyboard-open/return cases and Urdu Receive submit-to-Close reverse direction. Source inspection confirms these assertions.
- The latest executor-reported 22-test Receive run includes explicit English date-picker and method-menu open/dismiss assertions. Analyzer PASS (51.3 seconds) and diff-check PASS remain executor-reported.

## Remaining coverage and recommendation

The remaining acceptance evidence is visible keyboard focus on working action/review controls and dynamic outcome/error announcements, including actual assistive-technology announcement quality. No product failure is demonstrated by those unexecuted checks.

Coverage limits remain explicit: full reverse loops in Apply/Refund/Reverse, Urdu/other-dialog picker paths, picker value selection, and live-browser pending-write behavior were not exercised by this reviewer. Receive reverse evidence is a submit-to-Close transition, not a full reverse loop. I do not require exhaustive duplicate reverse-loop or browser busy-write runs to close this focused review: the actual guarded widget paths and tested direction/containment cases already pass. These limits must not be presented as tested results.

The latest executor-reported full Flutter run supersedes the earlier incomplete 719-test run: before the scanner fix, 915 tests passed and one POS barcode-scanner case failed; that exact case passed in isolation. Follow-up diagnosis found callback-time `DateTime.now()` could exceed the scan inter-key threshold under load even when the captured hardware event times represented a fast burst. The executor changed scanner timing to use monotonic `KeyEvent.timeStamp` and added a delayed-dispatch regression, which failed before the fix. Afterward, the POS file passed 12/12 and the complete Flutter suite passed 917/917. The POS file passed again after formatter-only churn was removed; analyzer and diff-check also passed. Logs: `/tmp/pos-delay-red.log`, `/tmp/pos-screen-final.log`, `/tmp/pos-flutter-full-fixed.log`, and `/tmp/pos-analyze-final.log`. The QA reviewer did not independently rerun this follow-up. Visible-focus and announcement evidence remain open. No canonical database changes occurred.
