# F7 current browser QA

Date: 2026-10-18. Verdict: **FAIL for final accessibility sign-off**; Escape dismissal passes.

Surface: Flutter release web client at `http://127.0.0.1:4517`, isolated fixture API on 4327/4328. Browser session `AGENT_BROWSER_SESSION=f7fix-2d3fabc8c040`, desktop viewport 1280×900, dark mode. All commands below use that session prefix. No product source files or canonical database were changed. One 500-unit receipt was created through the fixture UI for the existing fixture customer, enabling the action dialogs. No application/refund/reversal was submitted during the dismissal scenarios.

Read: `.omo/plans/unapplied-customer-cash-ui.md` and `audit/unapplied-cash-ui-final.md`. The audit still marks visual verification open; this report does not supersede its full-suite results or claim a new full-suite run.

## manualQa.surfaceEvidence

| Scenario | Criterion | Surface and exact invocation | Verdict | artifactRefs |
|---|---|---|---|---|
| ESC-UR-RECEIVE | F3/F7 keyboard dismissal | Urdu customer detail: `agent-browser click @e6`; `snapshot -i`; `press Escape`; `snapshot -i` | PASS: dialog removed, customer detail restored | UR-RECEIVE-BEFORE, UR-RECEIVE-AFTER |
| ESC-UR-APPLY | F3/F7 keyboard dismissal | Urdu cash workspace: `click @e18`; `snapshot -i`; `press Tab`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | UR-APPLY |
| ESC-UR-REFUND | F3/F7 keyboard dismissal | Urdu cash workspace: `click @e20`; `snapshot -i`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | UR-REFUND |
| ESC-UR-REVERSE | F3/F7 keyboard dismissal | Urdu workspace receipt action: `mouse move 49 554`; `mouse down`; `mouse up`; `snapshot -i`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | UR-REVERSE |
| ESC-EN-RECEIVE | F3/F7 keyboard dismissal | English cash workspace: `click @e6`; `snapshot -i`; `press Tab`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | EN-RECEIVE |
| ESC-EN-APPLY | F3/F7 keyboard dismissal | English cash workspace: `click @e18`; `snapshot -i`; `press Tab`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | EN-APPLY |
| ESC-EN-REFUND | F3/F7 keyboard dismissal | English cash workspace: `click @e20`; `snapshot -i`; `press Escape` | PASS: dialog removed, workspace restored | EN-REFUND |
| ESC-EN-REVERSE | F3/F7 keyboard dismissal | English workspace receipt action: `mouse move 1228 554`; `mouse down`; `mouse up`; `snapshot -i`; `press Escape`; `snapshot -i` | PASS: dialog removed, workspace restored | EN-REVERSE |
| AX-REVERSE | F3 screen-reader labels | English and Urdu desktop cash receipt grid: `agent-browser snapshot -i`; English `hover @e36`; `snapshot -i`; inspect DOM of button at x1206/y537 | FAIL: receipt Reverse action is an unnamed button in both locales; hover tooltip does not supply an accessible name | AX-REVERSE-DOM, EN-REVERSE |
| PHONE-CAPTURE-POSITION | F7 narrow screenshot evidence | Open the three flagged PNG files with `view_image`; calculate SHA-256 of each start/end pair | PASS for represented scroll position only: Urdu ends show receipt/pagination, English start shows balances, and pairs differ | PHONE-CAPTURES |

Refs are snapshot-local. Setup navigation used customer row action menu at x50/y176 → Urdu View `@e4`; detail cash tab `@e16`. Locale changed using user menu `@e3` → language `@e2` → English `@e1`. The English apply wait for guessed text `Choose invoice amounts` timed out; a fresh snapshot then showed the fully loaded apply dialog. No pass depends on that unsuccessful wait.

## manualQa.adversarialCases

| Scenario | Criterion | Adversarial class | Expected behavior | Verdict | artifactRefs |
|---|---|---|---|---|---|
| AX-REVERSE | F3 accessibility | Icon-only financial action | Screen reader announces the localized action | FAIL: role is button but accessible name is empty in English and Urdu | AX-REVERSE-DOM |
| ESC-LOCALES | F3 keyboard | RTL and LTR dismissal | Escape dismisses each idle cash action without confirmation/submission | PASS: all eight browser scenarios returned to underlying UI | EN-RECEIVE, EN-APPLY, EN-REFUND, EN-REVERSE, UR-RECEIVE-BEFORE, UR-RECEIVE-AFTER, UR-APPLY, UR-REFUND, UR-REVERSE |
| KEYBOARD-TRAVERSAL | F3 keyboard navigation | Full tab order and activation | All controls reachable and operable in logical order | OPEN: this attempt verifies Escape only, not full Tab traversal. `focus @e36; press Enter` did not open Reverse; programmatic DOM focus is insufficient to conclude Flutter traversal behavior | KEYBOARD-PROBE |
| CAPTURE-PROVENANCE | F7 fresh captures | Old evidence after source changes | Capture manifest binds images to current build | OPEN: the three files have corrected content, but their current-build provenance is not established by this attempt | PHONE-CAPTURES |
| BUSY-DISMISSAL | F3 safe mutation | Escape during an in-flight write | Busy transaction remains protected | OPEN: not exercised by this browser attempt; idle Escape passes must not be represented as busy-state proof | This report |

## manualQa.artifactRefs

Unless absolute, paths are relative to `.omo/evidence/unapplied-customer-cash-ui-final-qa/`. All listed screenshot files were checked to exist with nonzero bytes.

| ID | Kind | Description | Path |
|---|---|---|---|
| UR-RECEIVE-BEFORE | screenshot | Urdu receive dialog before Escape | `/home/fawad/.agent-browser/tmp/screenshots/screenshot-1792297385092.png` |
| UR-RECEIVE-AFTER | screenshot | Underlying detail after Escape | `/home/fawad/.agent-browser/tmp/screenshots/screenshot-1792297388162.png` |
| UR-APPLY | screenshots | Urdu apply before and after Escape | `ur-apply-before.png`, `ur-apply-after-escape.png` |
| UR-REFUND | screenshots | Urdu refund before and after Escape | `ur-refund-before.png`, `ur-refund-after-escape.png` |
| UR-REVERSE | screenshots | Urdu reversal before and after Escape | `ur-reverse-before.png`, `ur-reverse-after-escape.png` |
| EN-RECEIVE | screenshots | English receive before and after Escape | `en-receive-before.png`, `en-receive-after-escape.png` |
| EN-APPLY | screenshots | English apply before and after Escape | `en-apply-before.png`, `en-apply-after-escape.png` |
| EN-REFUND | screenshots | English refund before and after Escape | `en-refund-before.png`, `en-refund-after-escape.png` |
| EN-REVERSE | screenshots | English reversal before and after Escape, latter includes visible tooltip | `en-reverse-before.png`, `en-reverse-after-escape.png` |
| KEYBOARD-PROBE | screenshot | Workspace after focusing reverse semantics node and Enter | `en-reverse-keyboard.png` |
| AX-REVERSE-DOM | captured DOM / AX excerpt | Direct browser inspection below | `f7-manual-qa.md` (next section) |
| PHONE-CAPTURES | screenshots | Corrected content; build provenance pending | `audit/screenshots/unapplied-cash-ui/f7-ur-light-phone-workspace-end.png`, `audit/screenshots/unapplied-cash-ui/f7-ur-dark-phone-workspace-end.png`, `audit/screenshots/unapplied-cash-ui/f7-en-dark-phone-workspace.png` (repo-relative) |

## AX-REVERSE-DOM captured browser output

English and Urdu `snapshot -i` both returned the receipt action as `- button [ref=e36]` with no name. English DOM query:

`agent-browser eval 'JSON.stringify([...document.querySelectorAll("[role=button]")].filter(e=>{const r=e.getBoundingClientRect();return r.x>1190&&r.y>530&&r.y<580}).map(e=>({outerHTML:e.outerHTML,rect:e.getBoundingClientRect().toJSON()})))'`

Returned element:

```html
<flt-semantics id="flt-semantic-node-393" role="button" tabindex="0" flt-tappable="" style="position: absolute; overflow: visible; pointer-events: all; width: 48px; height: 34px; transform-origin: 0px 0px 0px; transform: matrix(1, 0, 0, 1, 8, 0);"></flt-semantics>
```

Its bounding rectangle was x1206/y537/width48/height34. A subsequent `hover @e36; snapshot -i` still returned an unnamed button. The screenshot shows a visual `Reverse receipt` tooltip, making the missing accessible name independently distinguishable from absence of the control itself.

Phone image SHA-256 observed in this review:

- Urdu light end: `3154e1ab38ca54f5a32c3ec6cdbd0f796200a0ef1b8bda51d354d3171c3d77b1`.
- Urdu dark end: `aa8ca65ba3f86371ea561eb280209201c3fbd22155d99a0db4541215c2674b8d`.
- English dark start: `f9bc4d27b5442877a9725611d3b10f1aec8b43b41d2ff38c5d1be945e8a521d6`.
