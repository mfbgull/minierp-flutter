# Current rebuild manual QA

Date: 2026-10-18. Scope: final review follow-up on the current Flutter release browser surface, isolated fixture. No ulw-loop plan exists (`ULW_LOOP_PLAN_MISSING`); artifacts use the caller's audit directory.

Verdict: **reviewed behavior PASS; remaining accessibility coverage OPEN**. Corrected Urdu dark phone start/end captures are distinct and visibly correct. Reverse workspace controls expose their localized accessible names in English and Urdu. All four dialogs dismiss with Escape in both languages on the live browser. English Receive forward Tab containment and launcher focus restoration pass on the live browser. An independent 11-test run verifies pending-write Escape protection for all four workflows, forward focus containment for Apply/Refund/Reverse in both locales, and English Receive submit-to-Close Shift+Tab direction. Newer executor-reported runs add keyboard opening and launcher restoration for all dialogs/locales, Receive submit-to-Close Shift+Tab in Urdu, and English Receive date-picker dismissal plus payment-method menu opening and Escape dismissal. The method-menu test asserts the `Bank` option is absent after Escape. The latest Receive-file rerun passed all 22 tests and analyzer is clean. These newer cases have not yet been independently rerun by QA. Remaining coverage is listed in ADV-FOCUS and ADV-SCREENREADER; browser pending-write interaction was not exercised.

Build identity: `/tmp/minierp-cash-review-web/main.dart.js`, 7,337,678 bytes, SHA256 `7159ca43a0aae1e37dd8b04d4596e24a516e59f2ff2db7f7b808700c1a8ed0dc`. Browser URL `http://127.0.0.1:4517/#/customers/1`; observed resource URL `http://127.0.0.1:4517/main.dart.js`. This records the served build file and observed resource origin; it is not a retroactive provenance claim for all prior screenshots.

## manualQa

### surfaceEvidence

Command prefix for all invocations: `AGENT_BROWSER_SESSION=f7fix-2d3fabc8c040 agent-browser`. Each dialog invocation is followed by `snapshot -i`, `press Escape`, `snapshot -i`. Exact refs and observed snapshots are recorded in A1; refs derive from the immediately preceding snapshot.

| Scenario id | Criterion reference | Surface | Exact invocation | Verdict | artifactRefs |
|---|---|---|---|---|---|
| QA-LABEL-EN | F7 screen-reader labels / Reverse finding | Browser, English dark phone cash workspace | `snapshot -i` | PASS: button `Reverse receipt` | A1, A4 |
| QA-LABEL-UR | F7 screen-reader labels / Reverse finding | Browser, Urdu dark phone cash workspace | `snapshot -i` | PASS: button `وصولی منسوخ کریں` | A1 |
| QA-DESKTOP-LABEL-EN | F7 screen-reader labels / Reverse finding | Browser, English dark desktop cash workspace, 1280x900 | AX DOM query for button semantics with exact text `Reverse receipt` | PASS: 2 compact grid buttons expose the localized accessible name | A1, A4 |
| QA-DESKTOP-LABEL-UR | F7 screen-reader labels / Reverse finding | Browser, Urdu dark desktop cash workspace, 1280x900 | AX DOM query for button semantics with localized text containing `منسوخ` | PASS: 2 compact grid buttons expose `وصولی منسوخ کریں` | A1 |
| QA-ESC-UR-RECEIVE | F7 keyboard | Browser, Urdu Receive | `click @e6`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-UR-REVERSE | F7 keyboard | Browser, Urdu Reverse error state | `click @e21`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-UR-REFUND | F7 keyboard | Browser, Urdu Refund error state | `click @e17`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-UR-APPLY | F7 keyboard | Browser, Urdu Apply error state | `find role button click --name 'نقد رقم انوائسز میں استعمال کریں'`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-EN-RECEIVE | F7 keyboard | Browser, English Receive | `click @e6`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-EN-REVERSE | F7 keyboard | Browser, English Reverse error state | `click @e22`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-EN-REFUND | F7 keyboard | Browser, English Refund error state | `find role button click --name 'Refund Cash'`; snapshots/Escape sequence | PASS: no dialog after Escape | A1 |
| QA-ESC-EN-APPLY | F7 keyboard | Browser, English Apply error state | `click @e18`; `press Tab`; activeElement inspection; Escape sequence | PASS: Tab focuses Operation date input, Escape dismisses | A1 |
| QA-FOCUS-RECEIVE | F7 keyboard/focus | Browser, English Receive dialog, 1280x900 | `find role button click --name 'Receive Advance'`; eight `press Tab` actions, inspect active node after two animation frames each; `press Escape`; wait for dialog removal; inspect active node | PASS: forward traversal wraps within dialog; Amount, Operation date input/button, Cash, Close, and Receive Advance are reachable; focus returns to Receive Advance | A1 |
| QA-BUSY-ESC-WIDGET | F7 keyboard / financial write protection | Mounted Receive, Apply, Refund, and Reverse dialogs with controlled pending POST | Exact 11-test command in A7; taps, pending request gate, Escape, mounted-dialog assertion, then release gate | PASS: all four workflows remain open during the in-flight write and dispatch only one request | A6, A7 |
| QA-KEYBOARD-TRAVERSAL-WIDGET | F7 keyboard/focus | Mounted Receive (English), Apply/Refund/Reverse (English and Urdu) | Exact 11-test command in A7; repeated `Tab`; Receive sends Shift-down + Tab + Shift-up and checks focused semantics | PASS: Apply/Refund/Reverse forward traversal stays within the dialog; Receive Shift+Tab moves focus from submit back to Close | A6, A7 |
| QA-KEYBOARD-RETURN-WIDGET | F7 keyboard/focus | Mounted Receive/Apply/Refund/Reverse in English and Urdu | Newer complete-file commands in A8; Tab to launcher, Enter to open, Escape to close, assert focused launcher semantics | PASS, executor-reported; source assertions inspected: keyboard opening and launcher focus restoration in all eight cases | A6, A8 |
| QA-RECEIVE-BACKWARD-WIDGET | F7 keyboard/focus | Mounted Receive in English and Urdu | Newer complete Receive-file command in A8; Tab to submit, hold Shift, send Tab, release Shift, assert Close focus | PASS, executor-reported for both locales; independent earlier run covered English only | A6, A8 |
| QA-SCROLL-UR | F7 narrow start/end screenshot finding | Browser, Urdu dark 390x844 workspace | `scroll down 350 --selector '#flt-semantic-node-573'`; `scroll up 2500 --selector '#flt-semantic-node-573'`; capture start; `scroll down 2500 --selector '#flt-semantic-node-573'`; capture end | PASS: visual inspection confirms top summaries versus receipt/pagination end | A1, A2, A3 |

### automatedVerification

- Latest executor-reported file-level results follow, after the keyboard-open/return additions. The independent 11-test run in A7 predates these additions; it is not evidence that the reviewer ran the newer cases. Source review confirmed the new locale loops and focused-semantics assertions; A8 records their provenance.
- `flutter test test/features/customers/unapplied_cash_receive_test.dart --no-pub --reporter compact` — PASS, 22 tests, including pending-write Escape, keyboard open/return in both locales, submit-to-Close Shift+Tab direction in both locales, and keyboard date/payment-method picker dismissal. The latest rerun completed on 2026-10-18.
- `flutter test test/features/customers/unapplied_cash_apply_test.dart --no-pub --reporter compact` — PASS, including pending-write Escape, modal focus containment, and keyboard open/return in both locales.
- `flutter test test/features/customers/unapplied_cash_refund_reverse_test.dart --no-pub --reporter compact` — PASS, including pending-write Escape, focus containment, and keyboard open/return for both workflows in both locales.
- `flutter analyze --no-pub` — PASS, no issues (latest rerun 2026-10-18, 51.3 seconds).
- Pre-fix executor-reported full Flutter run — 915 passed, 1 POS barcode-scanner failure. A delayed-event regression reproduced the missing scan-prefix symptom against the old implementation.
- Post-fix `flutter test test/features/sales/pos_screen_test.dart --no-pub --reporter compact` — PASS, 12 tests; reran after removing formatter-only churn, log: `/tmp/pos-screen-final.log`. The complete Flutter suite passed 917/917 with `flutter test --no-pub --concurrency=2 --reporter compact`; log: `/tmp/pos-flutter-full-fixed.log`.
- Post-fix `flutter analyze --no-pub` — PASS, no issues; `git diff --check` — PASS.

### adversarialCases

| Scenario id | Criterion reference | Adversarial class | Expected behavior | Verdict | artifactRefs |
|---|---|---|---|---|---|
| ADV-IDLE-ESC | F7 keyboard | Escape from idle/error modal | Dismiss without invoking the financial action | PASS for observed dismissal; no submit interaction performed | A1 |
| ADV-BUSY-ESC | F7 keyboard / financial write protection | Escape while write in flight | Keep dialog and operation intact while busy | PASS via independently rerun controlled-pending-POST widget regressions for Receive, Apply, Refund, and Reverse. Live browser pending-write behavior was not exercised because the preview/API fixture was unavailable. | A6, A7 |
| ADV-FOCUS | F7 keyboard/focus | Complete Tab/Shift+Tab loop and focus restoration | Stay inside dialog, expose visible focus, restore launcher after close | OPEN for visible-focus audit. English Receive date-picker dismissal and method-menu opening/dismissal are covered in the latest 22-test file run; other picker locales/controls are not claimed. Launcher restoration is covered for all four dialogs in both locales. Receive submit-to-Close reverse direction passes in both locales; this is a single backward transition, not a complete reverse-loop claim. Other tested forward containment and browser restoration remain PASS on the surfaces above | A1, A6, A7, A8 |
| ADV-SCREENREADER | F7 screen-reader labels | Announcement quality | Dialog title, fields, errors, and controls announced clearly in both locales | FAIL: AX snapshots verify exposed labels only; assistive-technology announcement pass remains unexecuted | A1 |
| ADV-HISTORICAL | User dummy-data constraint | Legacy accounting repair | No repair/re-audit of historical dummy gaps | not_applicable: this browser label/keyboard/capture review performs no data repair | A1 |

### artifactRefs

| id | kind | description | path |
|---|---|---|---|
| A1 | browser action log | Exact executed commands, semantic observations, build and capture hashes, scope limitations | `audit/unapplied-cash-ui-current-qa-actions.txt` |
| A2 | browser screenshot | Corrected Urdu dark phone workspace start, 390x844 | `audit/screenshots/unapplied-cash-ui/f7-ur-dark-phone-workspace.png` |
| A3 | browser screenshot | Corrected Urdu dark phone workspace end, 390x844 | `audit/screenshots/unapplied-cash-ui/f7-ur-dark-phone-workspace-end.png` |
| A4 | browser screenshot | English workspace captured during current Reverse-label verification | `audit/screenshots/unapplied-cash-ui/f7-qa-en-reverse-labels.png` |
| A5 | browser accessibility observation | Desktop compact Reverse button semantics in both locales, 1280x900 | `audit/unapplied-cash-ui-current-qa-actions.txt` |
| A6 | Flutter widget regression tests | Controlled in-flight Escape guards across all workflows; forward focus containment across Apply/Refund/Reverse locales; Receive submit-to-Close reverse direction; file-level results listed above | `test/features/customers/unapplied_cash_receive_test.dart`, `test/features/customers/unapplied_cash_apply_test.dart`, `test/features/customers/unapplied_cash_refund_reverse_test.dart` |
| A7 | Independent test execution record | Exact focused invocation, inspected assertions, selected scenarios, and terminal exit result | `audit/unapplied-cash-ui-current-qa-regressions.md` |
| A8 | Newer executor-reported verification | Later complete test-file/analyzer results and added keyboard-open/return and bilingual Receive reverse-direction coverage; separated from the independent run | `audit/unapplied-cash-ui-current-qa-regressions.md`, section `Newer executor verification` |

No product source edits, canonical DB access, historical data repairs, or financial submissions occurred in this review. Full unit/integration suites were not rerun by this QA reviewer.

Latest QA reassessment: `audit/unapplied-cash-ui-qa-reassessment.md`. It confirms the evidence scope above and leaves final acceptance open for visible-focus and outcome/error announcement coverage; no product defect was demonstrated.
