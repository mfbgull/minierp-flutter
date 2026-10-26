# F3 independent design-system and visual evidence review

Recommendation: **REQUEST_CHANGES**

Reviewed: 2026-10-18. Scope is final F3 verification for the unapplied customer cash UI, not accounting certification. No implementation, database, or test fixtures were changed. This report is the sole review artifact written.

## Reference and method

The reference is `docs/DESIGN.md:495` and the final verification criteria in `.omo/plans/unapplied-customer-cash-ui.md:364`; there is no external pixel target. Checked the current customer-detail diff, the added live widget implementations, shared theme/dialog/grid primitives, relevant test source, and reported evidence. Reviewed all nine supplied contact sheets, covering every one of the 52 required captures, then opened suspicious originals and the ten supplementary captures individually. Contact-sheet inspection is lower-resolution evidence; it is not a claim that all 52 originals were individually opened.

Filesystem checks independently found 62 F7 PNGs: all 52 expected matrix filenames and ten extras. All 62 have PNG signatures. Required desktop captures are 1440×900 and phone captures 390×844. Pixel equality checks exposed three duplicated workspace positions. No tests or running financial UI were executed by this reviewer. Prior test-pass assertions remain attributed to their reports, not independently rerun results.

## Findings by severity

### CRITICAL

None observed. The UI is implemented with live Flutter widgets and data providers. No screenshot/raster substitution was found in the four principal cash UI files inspected.

### HIGH

1. **[evidence] The nominal 52-frame matrix does not cover all required workspace positions.** `audit/screenshots/unapplied-cash-ui/f7-ur-light-phone-workspace-end.png` and `f7-ur-dark-phone-workspace-end.png` are pixel-identical to their corresponding `workspace.png` files. The opened originals show the three balance cards and the beginning of the action area; neither shows the receipt card or final pagination. Conversely, `f7-en-dark-phone-workspace.png` is pixel-identical to its `workspace-end.png`; both show the receipt/footer and omit the balance-card start. Re-capture the two Urdu workspace ends and the English dark workspace start, verify the final receipt/pagination or start balances in the actual image, and update the matrix-complete claim at `audit/unapplied-cash-ui-final.md:72`. This is a capture defect, not proof that scrolling is broken in the product.

2. **[product/design-system] Spacing is prescribed in prose but not driven by reusable spacing tokens.** Color and typography are correctly theme-based, and radii are shared; nevertheless, the new workspace and dialogs repeat literal layout values throughout: `lib/features/customers/customer_unapplied_cash_tab.dart:89`, `:179`, `:212`, `:552`; `lib/features/customers/unapplied_cash_receive_dialog.dart:195`, `:375`; `lib/features/customers/unapplied_cash_apply_dialog.dart:373`, `:500`, `:649`; and `lib/features/customers/unapplied_cash_action_dialog.dart:323`, `:580`. These mostly follow the documented 8/12/16/24 scale and are visually coherent, but a strict token-driven-design-system approval cannot call repeated `EdgeInsets.all(24)` and `spacing: 12` shared tokens. Introduce/use shared spacing definitions for these repeated semantic roles and consume them in the changed surfaces. This finding concerns the requested strict token criterion, not a visible spacing mismatch or a demand to redesign unrelated screens.

### MEDIUM

3. **[product, inherited] The shared dark-grid serial is effectively unreadable.** The original `audit/screenshots/unapplied-cash-ui/f7-en-dark-desktop-workspace.png` shows row serial “1” near black on the dark row while financial cells remain readable. `lib/widgets/pluto_grid_screen.dart:47` explicitly sets `Colors.black54` with fixed font size, reached through `lib/widgets/detail_tab_grid.dart:89` and the new receipt grid at `lib/features/customers/customer_unapplied_cash_tab.dart:318`. The same shared primitive is used by Apply. This is inherited and already acknowledged in `audit/unapplied-cash-ui-f3.md`, but it prevents an unqualified contrast pass for the new surface. Use the shared theme foreground and confirm the affected dark grids. No exact contrast-ratio measurement is claimed.

4. **[evidence] Final accessibility verification is incomplete.** The final matrix demonstrates visible input focus in Receive, readable ordinary text/totals, wrapped footer actions, and disabled review fields. Source inspection confirms receive amount/date semantics (`test/features/customers/unapplied_cash_receive_test.dart:304`), allocation labels (`lib/features/customers/unapplied_cash_apply_dialog.dart:306`), and live outcome announcements. It does not establish keyboard traversal/focus visibility and assistive labels across all four workflows in both languages on the final build. `audit/unapplied-cash-ui-f6.md:114` explicitly excludes exhaustive contrast/text-scaling checks. Supply a focused current-build keyboard and semantics evidence record for receive/apply/refund/reverse, including modal entry/exit and confirm/retry actions. This is an evidence limitation, not a claim that every control is inaccessible; exhaustive unrelated-shell WCAG certification is outside this review.

5. **[product/localization] Receipt method names bypass localized labels.** `lib/features/customers/customer_unapplied_cash_tab.dart:275` uses `receipt.method` directly. Urdu desktop workspace captures show the English value `Cash`, while Receive/Refund localize the same method to Urdu. Map known method values through existing localized payment-method labels consistently. Identifiers, fixture customer names, and brand names are not translation defects.

### LOW

6. **[evidence] The final evidence header contradicts its later ledger.** `audit/unapplied-cash-ui-final.md:3` still calls the matrix incomplete and the database guard failed, while later paragraphs report a complete matrix and successful guarded rerun. Reconcile the headline with the actual verified outcome after the blockers above are addressed. The ledger contains artifact paths, so this is not an unsupported assertion that no evidence exists.

## F3 criterion verdicts

| Criterion | Verdict | Evidence and limits |
|---|---|---|
| Real component tree and reusable primitives | PASS | Live `ConsumerStatefulWidget`, `MovableDialog`, `FormFieldShell`, Material buttons/cards, `DetailTabGrid`; Refund and Reverse share `UnappliedCashActionDialog`. No raster stand-ins found in inspected UI files. |
| Token-driven colors/type/radii | PASS | `Theme.of(context).colorScheme` and `textTheme`; `lib/core/theme/app_theme.dart:18` supplies component themes and `AppBorderRadius`. |
| Token-driven spacing | FAIL | HIGH finding 2. Values follow the documented scale but are repeated literals. |
| Layer/layout structure | PASS for visible captures | Fixed customer identity, scrollable dialog body and persistent action footer; desktop grids and narrow cards match the project contract. |
| English/Urdu and RTL | PARTIAL | Mirrored dialogs and fields, wrapped long customer/invoice identifiers, no visible Urdu glyph loss in inspected originals. Receipt method localization gap remains. |
| Narrow/wide fit and wrapping | PASS for captured positions; coverage FAIL | All four dialogs fit 390×844; desktop grids fit 1440×900. Two Urdu ends and one English start are absent despite filenames. |
| Totals and financial meaning | PASS for visible captures | Invoice balance/store credit/cash held separate; Apply shows 500/400/100; Refund says cash out; reversal identifies original receipt/date. No financial-runtime certification inferred from screenshots. |
| Light/dark and contrast | PARTIAL | Themes and principal financial text work; dark serial column fails visibly. Disabled review values are intentionally subdued; refund confirmation repeats relevant values in ordinary text. |
| State differentiation | PASS for inspected states | Empty, editable draft, locked review, error, pending/busy, and success captures are visibly distinguishable with text/icons. Pending extra is a busy frame, not settled recovery proof. |
| Accessibility | UNVERIFIED in full | Receive label regression/source semantics and visible focus are useful partial evidence; final workflow-wide keyboard/semantics record absent. |
| Legacy invoice-payment behavior | PARTIAL / no observed regression | Customer Detail still calls the existing record-payment flow separately. `test/features/customers/unapplied_cash_payment_widgets_test.dart:230` and `:252` cover permitted/denied ordinary receipt controls. This reviewer inspected test source but did not run those tests or execute a legacy payment journey. |
| Capture freshness | PARTIAL provenance | Captures are newer than inspected hand-written cash UI sources. `build/web/main.dart.js` is dated 2026-10-17 08:47:17 +0500; generated Urdu localization source is dated 08:48:48. This may be identical regeneration, but the packet lacks a source/build hash manifest proving it. No stale-content defect is inferred solely from that timestamp. |

## Evidence inspected

- Reference: `.omo/plans/unapplied-customer-cash-ui.md`, `docs/DESIGN.md`, `CODING_STANDARDS.md`.
- Reports: `audit/unapplied-cash-ui-final.md`, `audit/unapplied-cash-ui-f3.md`, relevant `audit/unapplied-cash-ui-f6.md` sections.
- All contact sheets: `/tmp/f7-final-visual/en-dark-desktop.png`, `en-dark-phone.png`, `en-light-desktop-0.png`, `en-light-desktop-1.png`, `en-light-phone.png`, `ur-dark-desktop.png`, `ur-dark-phone.png`, `ur-light-desktop.png`, `ur-light-phone.png`.
- Individually opened matrix originals under `audit/screenshots/unapplied-cash-ui/`: `f7-ur-dark-phone-workspace-end.png`, `f7-ur-light-phone-workspace-end.png`, `f7-ur-dark-phone-apply.png`, `f7-en-dark-desktop-workspace.png`, `f7-ur-dark-phone-reverse.png`.
- Individually opened all ten extras in that directory: `f7-browser-apply-review.png`, `f7-browser-receive-70-success.png`, `f7-browser-refund-draft.png`, `f7-browser-refund-review.png`, `f7-browser-settled-workspace.png`, `f7-closed-period-error.png`, `f7-empty-desktop-light-en.png`, `f7-en-light-desktop-receive-fresh.png`, `f7-lost-response-pending.png`, `f7-receive-500-success.png`.
- Source: customer-detail diff, `customer_unapplied_cash_tab.dart`, `unapplied_cash_receive_dialog.dart`, `unapplied_cash_apply_dialog.dart`, `unapplied_cash_action_dialog.dart`, refund/reverse entry wrappers; `app_theme.dart`, `detail_tab_grid.dart`, `movable_dialog.dart`, serial renderer in `pluto_grid_screen.dart`; focused receive/payment widget-test source.
- Graph discovery and coverage checks returned no recorded gaps for cited principal Dart paths; direct source inspection remained authoritative.

## Approval blockers

Correct the three workspace captures; satisfy the strict reusable spacing-token criterion; resolve or explicitly obtain acceptance of the inherited serial-contrast limitation; provide final keyboard/semantics evidence and build provenance; localize receipt method values and reconcile the final report. Re-capture any surface changed by fixes before a fresh review. No dummy historical data repair is requested or relevant.
