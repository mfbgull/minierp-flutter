# Unapplied customer cash UI: F3 workspace and receive

Status: F3 complete. Automated gates and direct runtime checks pass; the existing
shared-grid dark serial-number contrast limitation is recorded below.

Execution plan: `.omo/plans/unapplied-customer-cash-ui.md`.

## Delivered

- Customer Detail has six tabs and separate Record Payment / Receive Advance
  actions. Receive requires `payments:create`; cash reads require `payments:read`.
  Create-only users can receive without a fabricated zero cash balance.
- The workspace keeps invoice balance, store credit and live unapplied cash
  separate. Receipt history, date-filtered activity, pagination, refresh, loading,
  empty and error states use the existing repositories and design primitives.
  Narrow layouts use a scrollable stack of cards instead of a compressed grid.
- Receive fixes the customer identity and accepts only amount, operation date and
  Cash/Bank/Easypaisa/JazzCash/Upaisa. Integer minor units validate input. Success
  identifies the amount and payment ID, and refreshes live reads without claiming
  that an invoice was paid.
- The F2 operation controller owns immutable persisted requests and duplicate-tap
  protection. Busy operations cannot be dismissed. Closing an uncertain operation
  keeps its original key/body; reopening offers explicit recovery, not a new write.
  Missing/foreign/corrupt replay state fails closed.
- English/Urdu labels, RTL layouts, semantic amount/date labels, an accessible
  calendar button and live outcome messages are included. Cash grids remount on
  locale changes because the shared grid caches its column definitions.

## Red-to-green evidence

- Initial widget red: eight failures against the absent sixth tab and receive
  implementation, followed by nine passing cases. Expanded tests exposed narrow
  date-filter and Urdu quick-stat overflows; these were corrected in the header.
- A semantic-label regression failed before labels were attached to the amount
  and date fields. The calendar action now also exposes its localized label.
- Actual web receive failed before any financial POST. A Chrome regression
  reproduced `RangeError: max must be in range 0 < max <= 2^32, was 0` in the shared
  retry-key generator: JavaScript truncates `1 << 32` to zero. Both mint paths now
  use the exact numeric literal `0x100000000`. The same Chrome test then passed.
- Changing the mounted desktop workspace from English to Urdu retained English
  grid headers. A widget regression reproduced the missing Urdu `cashRemaining`
  header before the locale-key correction.

## Actual runtime checks

The release web client used `http://127.0.0.1:4311/api`, backed only by the isolated
`server/.tmp-test/ui-f3-surface/erp.db`. The backend constructor guard was installed
before database initialization. No canonical database or historical repair was run.

- Opened Customer Detail for a clean customer with zero invoices and selected the
  sixth tab. The three independent balances initially displayed zero.
- Submitted 500.25 through the actual receive form. The server returned HTTP 201;
  the dialog displayed payment ID 1 and the workspace refreshed to cash held 500.25.
  A read-only fixture query confirmed one UNAPPLIED_RECEIPT, source remaining and
  refundable amounts 500.25, two journal lines balancing debit/credit 500.25,
  liability 500.25, unchanged customer AR/store credit zero, and zero invoices.
- Aborted the online capability request. The form retained the entered amount,
  displayed the connection message and issued no additional financial POST.
- Restored connectivity, then aborted the 100.00 receive request to exercise the
  uncertain state. The original body/key was retained in browser preferences;
  inputs locked and Retry appeared. Closed the dialog, reloaded the application,
  navigated back and reopened it: only Retry was available with the original data.
  After removing the abort rule, Retry returned payment ID 2 and cleared storage.
  The durable replay row held the exact original key. The isolated database then
  contained exactly two receipts totaling 600.25, four balanced journal lines and
  unchanged customer AR/store credit. This browser scenario aborts dispatch; the
  committed-response-loss scenario remains covered by F2/F1 regressions.
- Exercised the empty activity view, receipt cards through their final page footer,
  keyboard focus, desktop/phone sizes and both theme modes. Input labels appeared
  as `Amount` and `Operation date` in the browser accessibility snapshot.

## Validation ledger

- Focused Flutter gate before the final locale regression: 102 tests passed.
  `/tmp/minierp-f3-targeted-final.log`.
- Chrome retry-key regression: one test passed after its meaningful failure.
  `/tmp/minierp-f3-web-key-red.log`, `/tmp/minierp-f3-web-key-green.log`.
- Analyzer checkpoint: no issues, 100.7 seconds.
  `/tmp/minierp-f3-analyze-verified.log`.
- Localization drift: passed, 2,139 English / 2,084 Urdu keys, existing gap 55
  within cap 60, zero orphan keys.
- Final focused gate: 103 tests passed, exit 0, including all 14 receive/workspace
  widget cases and the locale-change regression.
  `/tmp/minierp-f3-final-focused.log`.
- Full Flutter suite: 829 passed, zero failed/skipped, success true, 1,222.768
  seconds. Command: `flutter test --no-pub --concurrency=2 --reporter=json`.
  `/tmp/minierp-f3-full-final.jsonl`. The final locale-key correction landed while
  this run was executing; its affected tests were rerun in the final focused gate
  above rather than repeating all unchanged suites.
- Final analyzer: no issues, exit 0, 78.2 seconds.
  `/tmp/minierp-f3-analyze-final-locale.log`.
- Formatting check: six touched Dart source/test files unchanged; diff whitespace
  check passed.
- Final release web build passed, exit 0, 288.7 seconds.
  `/tmp/minierp-f3-web-locale.log`. In the mounted populated workspace, changed
  Urdu to English and back without navigating away: headers and receipt statuses
  followed the selected language. Final Urdu desktop light/dark captures show
  translated columns. A subsequent theme-toggle check exposed shared-grid
  exceptions; the cash grids now also remount when brightness changes. After the
  final release rebuild (244.1 seconds, exit 0), toggled the populated workspace
  light-to-dark and back: the browser's retained error count stayed at six rather
  than increasing by three per toggle as it did before the correction. The final
  dark Urdu capture shows the translated grid and intact receipt values.
- After the brightness correction: all 14 affected widget tests passed, including
  changing the populated desktop workspace's locale and theme; analyzer found no
  issues (65.1 seconds); formatting and whitespace checks passed.
  `/tmp/minierp-f3-theme-final-tests.log`, `/tmp/minierp-f3-theme-analyze.log`.
- Server source/API contracts were unchanged in F3, so the server full suite was
  not rerun. The isolated mounted backend was exercised by the release client.

## Visual evidence

Screenshots are in `audit/screenshots/unapplied-cash-ui/`, prefixed `f3-`.
They cover desktop light empty/receive/success/receipts/activity/offline/pending/
restored/retry success, phone light focus and receipt footer, dark desktop/phone,
and Urdu layouts. These are direct visual checks, not an independent review.

The shared grid's existing serial-number renderer has low contrast in dark mode;
payment number, amounts, remaining balance and status remain readable. No claim
of a clean independent visual gate or Lighthouse score is made.

Apply, refund and reverse dialogs remain F4/F5 work, not hidden F3 controls.
