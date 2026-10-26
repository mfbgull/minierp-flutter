# Current F7 design-system and evidence re-review

Recommendation: REQUEST_CHANGES

Reviewed 2026-10-18. This is an independent, read-only source and artifact review; this report is the sole file written. No tests or live financial workflow were run, and no database was opened. Review scope is final visual/keyboard signoff, not financial certification. Findings describe the packet as inspected, before any subsequent executor captures.

## Reference and inspected evidence

- Target: `docs/DESIGN.md:495` through the customer-cash contract, and final verification criterion `.omo/plans/unapplied-customer-cash-ui.md:365`. There is no external pixel target.
- Prior findings: `.omo/evidence/unapplied-customer-cash-ui-clone-fidelity.md`.
- Current completion report: `audit/unapplied-cash-ui-final.md`.
- Current source: `lib/core/theme/app_spacing.dart`, the customer cash workspace, receive/apply/shared action dialog implementations, and relevant shared dialog/grid diffs. Inspected Escape regression test source in the receive, apply and refund/reverse test files. Graph discovery and coverage checks were supplemented with direct source reads.
- Opened original screenshots: `audit/screenshots/unapplied-cash-ui/f7-ur-light-phone-workspace-end.png`, `f7-ur-dark-phone-workspace-end.png`, `f7-en-dark-phone-workspace.png`, and `f7-en-dark-desktop-workspace.png`. Checked PNG dimensions, hashes and modification times for these and their paired phone workspace positions. This review does not claim a fresh inspection of all 52 matrix images.

## Resolved findings

- The three replacement phone captures now cover their intended positions. Both Urdu ends show the receipt, localized method and final pagination. The English dark start shows the three balance cards and action-area start. All are 390×844 and differ from their paired positions.
- Repeated cash-workspace/dialog spacing now consumes `AppSpacing` (`lib/core/theme/app_spacing.dart:2`). Theme typography/colors and reused `MovableDialog`, `DetailTabGrid`, cards and Material controls remain in use. The inspected implementation is a live provider-backed Flutter component tree; no raster substitution was found in these inspected surfaces.
- Receipt methods use the localized label mapping at `lib/features/customers/customer_unapplied_cash_tab.dart:290`. The replaced Urdu end captures visibly show the localized cash method.
- The serial foreground fix is present at `lib/widgets/pluto_grid_screen.dart:47`, using the active grid cell style. Its rendered result is not demonstrated by the retained desktop capture.

## Findings by severity

### CRITICAL

None found in the inspected scope.

### HIGH

1. **Final evidence still does not establish the current UI build.** The retained `audit/screenshots/unapplied-cash-ui/f7-en-dark-desktop-workspace.png` is dated 2026-10-17T04:04:07Z and visibly retains the old near-black row serial. Its SHA-256 is `68a794e9c85d360e5f3da1307f2e5b10b2de037d01e0b66344d3246966a58086`. This is an evidence gap, not a finding that the current source fix failed. The three replacement phone frames predate the final shared-dialog edit at 2026-10-18T04:08:50Z and current web bundle at 04:12:14Z. No source/build/capture manifest was present in the screenshot directory. Re-capture the changed desktop contrast surface and the required current-build dialog/keyboard evidence; record the actual served build fingerprint and source association. Unchanged historical captures may remain supporting evidence if their provenance and scope are explicitly distinguished.

### MEDIUM

2. **Workflow-wide keyboard and semantics verification remains open.** The new Escape regressions cover idle modal dismissal in English and Urdu (`test/features/customers/unapplied_cash_receive_test.dart:329`, `unapplied_cash_apply_test.dart:225`, `unapplied_cash_refund_reverse_test.dart:272`). They do not by themselves establish keyboard entry, Tab/Shift-Tab traversal, visible focus, accessible control names, confirmation/retry activation, or busy-state dismissal protection on the served build. `audit/unapplied-cash-ui-final.md:126` still explicitly marks this record pending. Record the focused Receive/Apply/Refund/Reverse checks in both locales, including the changed `MovableDialog` Escape path at `lib/widgets/movable_dialog.dart:232`, before final accessibility signoff.

### LOW

3. **The audit packet has contradictory completion statements.** `audit/unapplied-cash-ui-final.md:74` calls the matrix complete, while its header and follow-up at line 123 still identify the now-replaced phone captures as outstanding. Reconcile the report after current evidence is collected. Preserve attribution of the earlier 886-test run; it must not be presented as verification of later dialog changes unless those changes were included in a subsequent full run.

## Capture observations

| Capture | SHA-256 | Observed content |
|---|---|---|
| `f7-ur-light-phone-workspace-end.png` | `3154e1ab38ca54f5a32c3ec6cdbd0f796200a0ef1b8bda51d354d3171c3d77b1` | Light Urdu receipt and pagination |
| `f7-ur-dark-phone-workspace-end.png` | `aa8ca65ba3f86371ea561eb280209201c3fbd22155d99a0db4541215c2674b8d` | Dark Urdu receipt and pagination |
| `f7-en-dark-phone-workspace.png` | `f9bc4d27b5442877a9725611d3b10f1aec8b43b41d2ff38c5d1be945e8a521d6` | English dark balance-card start |

The inspected `/tmp/minierp-cash-review-web/main.dart.js` hash was `9544c2f270a08641fc8168c5ee117d25dfe563333412301d6dcf3abf519c56ee`. A bundle file on disk alone does not establish which bundle the browser rendered.

## Required next step

Collect current served-build evidence for the changed dark desktop grid and the focused four-workflow keyboard/semantics matrix in both languages, attach a build/capture provenance record, reconcile the final audit, and obtain a short independent re-review of those additions. Design-token rigor and the three phone positions are satisfactory in this inspection; final visual/keyboard signoff cannot yet be granted. No historical dummy-data repair is requested.
