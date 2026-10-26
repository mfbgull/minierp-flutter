# F7 latest capture and design-system review

Recommendation: **REQUEST_CHANGES**

Reviewed 2026-10-18, including the final recaptures and updated QA/manifest. Independent read-only source and artifact review. This report is the only file written; no test, financial workflow, or database operation was run. The served JavaScript bundle was fetched read-only to verify its hash. Findings refer to the exact capture hashes below, not later replacements.

## Reference and scope

The target is the customer-cash contract in `docs/DESIGN.md:495` and `.omo/plans/unapplied-customer-cash-ui.md:365`; there is no external pixel reference. Inspected current workspace source, cash-dialog token/primitives usage, shared dialog/grid diffs, reverse-tooltip regression source, prior fidelity reports, final audit and the manual-QA report. Opened all seven refreshed workspace originals listed below. This is not a new review of all 52 historical matrix frames.

## Findings by severity

### CRITICAL

None observed. Inspected surfaces use live provider-backed Flutter widgets, Material controls, `MovableDialog`, `DetailTabGrid` and reusable spacing/theme tokens. No screenshot substitution was found.

### HIGH

None remains in the refreshed workspace captures. The initially duplicated Urdu dark pair was replaced during this review. Both originals were reopened: start now shows all three balance cards; end shows receipt cards and pagination. The final distinct hashes are recorded below.

### MEDIUM

1. **Only visible-focus and announcement evidence remain open for this review's accessibility finding.** The latest manual-QA/regression packet now covers the core keyboard lifecycle in all four dialogs and both locales: keyboard opening and Escape launcher restoration, bilingual Apply/Refund/Reverse forward containment, bilingual Receive submit-to-Close Shift+Tab, and controlled pending-POST dismissal guards. Receive date/method pickers also have keyboard opening/Escape coverage. The inspected assertions and separately attributed test results resolve the earlier locale, focus-return, picker and busy-write concerns. What remains from the original focused accessibility request is evidence that keyboard focus is visibly distinguishable on the working action/review controls and that dynamic outcome/error announcements expose the intended accessible semantics. A focused current-render capture plus a semantic live-region/outcome check can satisfy this; exhaustive backward traversal of every control and a full screen-reader compatibility certification are not additional requirements of this fidelity review. No product failure is inferred from the missing evidence.

The desktop compact Reverse accessible-name blocker is resolved by the follow-up recorded under `QA-DESKTOP-LABEL-EN` and `QA-DESKTOP-LABEL-UR`. The action log now includes the 1280×900 viewport and DOM button-semantics query with two `Reverse receipt` labels in English and two `وصولی منسوخ کریں` labels in Urdu. These observations exercise the desktop grid branch corresponding to `IconButton.tooltip` at `lib/features/customers/customer_unapplied_cash_tab.dart:532`. This closure is based on the supplied browser observations and inspected source; this reviewer did not drive that browser recheck.

### LOW

No remaining documentation blocker. The latest Apply test explicitly loops English and Urdu, and QA distinguishes independent test execution from newer executor-reported runs. The prior Apply locale-coverage finding is withdrawn. The manifest records the replacement desktop's 1280×900 size and the action log supports desktop AX confirmation.

## Confirmed fixes

- `AppSpacing` drives repeated padding/gaps in the workspace and all three cash-dialog implementations. Theme typography/color, shared radii and live primitives remain in use. The previous strict spacing-token finding is resolved in the inspected scope.
- `lib/widgets/pluto_grid_screen.dart:47` uses the active cell foreground. The refreshed dark desktop original visibly shows readable row serials 1 and 2, resolving the previous source-versus-capture contrast gap.
- `lib/features/customers/customer_unapplied_cash_tab.dart:290` localizes known method names. Both Urdu end originals visibly show the localized cash method.
- English dark, Urdu light and Urdu dark phone pairs show genuinely distinct balance-card starts and receipt/pagination ends. The phone originals are 390×844.
- Current compact Reverse source has a localized tooltip; both phone and desktop AX label observations now pass in English and Urdu.
- The independently repeated English Receive forward Tab sequence stays inside the modal and reaches Amount, Operation date input/button, Cash, Close and Receive Advance; Escape restores launcher focus. Latest widget regressions cover keyboard opening/launcher restoration in every dialog and both languages, Receive submit-to-Close Shift+Tab in both languages, and forward containment in Apply/Refund/Reverse in both languages. Receive also opens/dismisses its date and method pickers using keyboard events. This reviewer inspected the production-dialog test assertions; `audit/unapplied-cash-ui-current-qa-regressions.md` accurately separates the independent 11-test run from newer executor-reported complete-file runs, including Receive 22/22 and analyzer success.
- Controlled pending-write regressions cover Receive, Apply, Refund and Reverse: Escape cannot close the dialog while the single POST remains unresolved. That safety evidence gap is closed.
- `audit/screenshots/unapplied-cash-ui/f7-review-capture-manifest.md` binds the refreshed screenshot hashes to the build/source files. I independently checked both recorded source hashes and fetched `http://127.0.0.1:4517/main.dart.js`: HTTP 200 and SHA-256 `7159ca43a0aae1e37dd8b04d4596e24a516e59f2ff2db7f7b808700c1a8ed0dc`, matching the manifest and browser resource origin recorded by QA. This is adequate provenance for the scoped refresh, not a retrospective claim for all older matrix frames.

## Evidence fingerprints

All files below are under `audit/screenshots/unapplied-cash-ui/` and were opened individually.

| File | Dimensions | SHA-256 |
|---|---|---|
| `f7-en-dark-desktop-workspace.png` | 1280×900 | `918925e5a237cf9dff5f5e66afbcac5adf203181f020f36ee265132b6ecea9a8` |
| `f7-en-dark-phone-workspace.png` | 390×844 | `f8a40a0e781bc630da324a8ab34c103d3589ffd73a8b1ad4f8b9fb3ebdc75e0e` |
| `f7-en-dark-phone-workspace-end.png` | 390×844 | `78029457987ddb598c8ba79f0b42f88a6b29ce61f2c4c44d8af1ec9bf85699c5` |
| `f7-ur-light-phone-workspace.png` | 390×844 | `0c800a2bcc572f6362d89d016388a867df320e2724e54d52ee7ed7e7ac393314` |
| `f7-ur-light-phone-workspace-end.png` | 390×844 | `e1be794fa70b0349d67e1ceeb9817a50d75fdc08a177c93f9cc6411a6d52f0a8` |
| `f7-ur-dark-phone-workspace.png` | 390×844 | `bc9eeca91d52af96e67adadf9b5d24d6aa0347c996468094a6177343229c7c22` |
| `f7-ur-dark-phone-workspace-end.png` | 390×844 | `039d661ef9185c68f1f718775f99ce96d173376b81c83a652d3b58a943fadb68` |

Additional artifacts inspected: `audit/unapplied-cash-ui-final.md`, `audit/unapplied-cash-ui-current-manual-qa.md`, `audit/unapplied-cash-ui-current-qa-actions.txt`, `audit/screenshots/unapplied-cash-ui/f7-review-capture-manifest.md`, `.omo/evidence/unapplied-customer-cash-ui-clone-fidelity.md`, `.omo/evidence/unapplied-customer-cash-ui-current-clone-fidelity.md`, `.omo/evidence/unapplied-customer-cash-ui-final-qa/f7-manual-qa.md`; source and test paths identified above; `lib/core/theme/app_spacing.dart`, `lib/widgets/movable_dialog.dart`, receive/apply/shared action dialog implementations, and `test/features/customers/unapplied_cash_payment_widgets_test.dart:285`.

## Approval blockers

Latest additional evidence inspected: `audit/unapplied-cash-ui-current-qa-regressions.md` and the updated Receive, Apply and Refund/Reverse widget-test assertions cited by its A6/A8 records.

Record the focused visible-keyboard-focus and dynamic-announcement semantics evidence described in MEDIUM 1. Do not expand this into exhaustive reverse-loop or screen-reader compatibility work solely for this review. All previously raised keyboard lifecycle, busy-write safety, picker, locale and launcher-restoration concerns are resolved by the supplied evidence. Refreshed workspace visual fidelity, spacing/theme rigor, localized receipt methods, dark serial contrast, corrected scroll positions, desktop Reverse labels and capture provenance pass. No historical dummy-data repair is requested. Existing accounting/test results were not rerun or independently certified by this reviewer.
