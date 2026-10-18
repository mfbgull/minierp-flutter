# Current rebuild manual QA

Date: 2026-10-18. Scope: final review follow-up on the current Flutter release browser surface, isolated fixture. No ulw-loop plan exists (`ULW_LOOP_PLAN_MISSING`); artifacts use the caller's audit directory.

Verdict: **specific checks PASS; full accessibility gate remains OPEN**. Corrected Urdu dark phone start/end captures are distinct and visibly correct. Reverse workspace controls expose their localized accessible names in English and Urdu. Receive, Apply, Refund, and Reverse dialogs dismiss with Escape in both languages. An independent live repeat also confirms English Receive forward Tab traversal stays inside the dialog and Escape restores focus to its launcher. Reverse traversal direction remains unverified. These results supersede older missing/failed evidence only for these precise scenarios.

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
| QA-SCROLL-UR | F7 narrow start/end screenshot finding | Browser, Urdu dark 390x844 workspace | `scroll down 350 --selector '#flt-semantic-node-573'`; `scroll up 2500 --selector '#flt-semantic-node-573'`; capture start; `scroll down 2500 --selector '#flt-semantic-node-573'`; capture end | PASS: visual inspection confirms top summaries versus receipt/pagination end | A1, A2, A3 |

### adversarialCases

| Scenario id | Criterion reference | Adversarial class | Expected behavior | Verdict | artifactRefs |
|---|---|---|---|---|---|
| ADV-IDLE-ESC | F7 keyboard | Escape from idle/error modal | Dismiss without invoking the financial action | PASS for observed dismissal; no submit interaction performed | A1 |
| ADV-BUSY-ESC | F7 keyboard / financial write protection | Escape while write in flight | Keep dialog and operation intact while busy | FAIL: missing executable busy-write fixture in this run; preview endpoints returned connection/retry errors. Requires working isolated preview/write responses and a controlled pending request. No pass inferred from widget tests | A1 |
| ADV-FOCUS | F7 keyboard/focus | Complete Tab/Shift+Tab loop and focus restoration | Stay inside dialog, expose visible focus, restore launcher after close | OPEN: English Receive forward Tab containment and launcher focus return pass. `press Shift+Tab` remained contained but produced forward order, so reverse direction is not verified. Urdu Receive, Apply/Refund/Reverse traversal, visible focus audit, and method/date picker interaction remain unexecuted | A1 |
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

No product source edits, canonical DB access, historical data repairs, or financial submissions occurred in this review. Full unit/integration suites were not rerun by this QA reviewer.
