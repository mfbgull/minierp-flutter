# Flutter error handling and lint review

CODE-006 and CODE-007 implementation evidence for the remaining audit pass.
The original report counted 28 discarded-error catch sites at its snapshot;
the current review found 33. Counts alone do not establish a runtime defect.

## Error handling

| File / sites | Handling selected |
|---|---|
| core/api/api_client.dart: token read, refresh-token read, token save, token clear, refresh request, retry | Safe operation/type diagnostics. A refreshed token that cannot be saved now fails refresh, clears the session and does not retry with the old token. |
| core/auth/auth_notifier.dart: token read, access/refresh writes, token clear | Safe diagnostics. Login remains unauthenticated and clears a partial token save if either write fails; localized recovery message is visible. |
| core/utils/print_service.dart: preference read/write/clear | Safe diagnostics; preserve optional preference fallback. |
| data/repositories/repository_client.dart: cached response read and invalidation | Safe diagnostics; preserve cache-miss/network failure and in-memory cache state. |
| features/preferences/preference_providers.dart: reset, persistence, range/preset decoding | Safe diagnostics; preserve current-session values and corrupt-cache recovery. |
| features/search/recent_items.dart: decoding | Safe diagnostics; malformed recent history becomes empty. |
| widgets/grid_column_widths.dart: restore and merge decoding | Safe diagnostics; retain auto-fit or replace corrupt persisted values. |
| sales/thermal_invoice_pdf.dart and pos_thermal_receipt_pdf.dart: QR rendering | Safe diagnostics; optional QR failure does not discard the printable document. |
| core/utils/csv_export.dart: save | Existing visible error toast; retained. |
| core/utils/print_service.dart and print_utils.dart: native layout | Existing share/save-as-PDF recovery; a share failure propagates to the caller's visible handler. Retained. |
| customers/unapplied_cash_action_dialog.dart, apply_dialog.dart, operation.dart, receive_dialog.dart | Existing explicit local error/recovery-required states preserve uncertain financial outcomes. Retained. |
| payments/payment_detail_dialog.dart: print | Existing visible error toast and finally cleanup. Retained. |
| settings/settings_screen.dart: backup download | Existing visible failure message. Retained. |

Twenty-four catch sites now record diagnostics; nine already provide visible
handling or a usable recovery path. Diagnostics print a fixed operation label
and runtime error type only, excluding exception text, payloads, credentials and
stack traces. The secret-redaction unit regression verifies this boundary.

Mounted login regressions failed before the fix for both access-token and
refresh-token storage failures. The refresh-client regression observed two
refresh attempts with a stale token before the correction. The recovery subset
then passed 29 tests: login storage, HTTP refresh, diagnostic redaction,
preferences and grid persistence. Salary loan-deduction failures were addressed
separately with atomic server posting and parent-linked reversals.

## Lint policy

Keep flutter_lints and add six focused rules: avoid_void_async,
cancel_subscriptions, close_sinks, throw_in_finally, unnecessary_statements and
unawaited_futures. These check async completion, resource ownership and error
preservation without banning typed JSON maps or valid deferred initialization.
No lint suppressions or exclusions are introduced for this policy.

The first combined analyzer checkpoint before these additional rules found one
curly-brace lint in the purchase form; it was fixed.

The expanded policy then surfaced 34 findings: 32 `unawaited_futures`, one
`avoid_void_async` and one `unnecessary_import`. All 34 are fixed at the
source, with no suppression and no rule change:

- A mutation or refresh whose completion matters is now awaited (`_load()`
  after a save, `_loadDetail()` after a dialog result, `_loadBackups()` after
  a backup action, the locale write, the row delete/cancel/print helpers and
  the settlement `await`s).
- A deliberate fire-and-forget (a `go_router` `context.push`, a nested
  success dialog that must not block the form behind it, an init-time
  `_loadTargets()`) is now explicitly wrapped in `unawaited(...)` with
  `dart:async` imported where it was missing.
- `_bulkVoid` changed from `void ... async` to `Future<void> ... async`.
- The redundant `dart:typed_data` import was removed from
  `test/features/audit_financial_visual_test.dart`.

`flutter analyze --no-pub` reports "No issues found!" and no `// ignore:`,
`// ignore_for_file:` or `exclude:` entry was added anywhere. The CODE-006
diagnostic and recovery work is untouched by these fixes.
