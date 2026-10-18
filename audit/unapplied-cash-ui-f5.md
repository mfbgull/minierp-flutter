# Unapplied customer cash UI: F5 refund and reversal

Status: F5 complete. Plan: `.omo/plans/unapplied-customer-cash-ui.md`.

## Delivered

- Refund Cash is a distinct cash-out action requiring payments:create and live
  capacity reads. It shows the fixed customer, date-eligible refundable FIFO pool,
  amount/date/method and a separate review before explicit confirmation. There is
  no selected-receipt refund, Credit method, notes or extra API body fields.
- Reverse receipt appears only for payments:delete users. Live-unused advances
  have an enabled row/card action; used/refunded/voided receipts show a disabled
  action with an explanation. The dialog fetches the live payment kind/customer/
  void state and locates the receipt across all source pages. Only a reason is
  editable: original receipt number, amount and date remain fixed.
- Both dialogs share the correction shell and safe operation controller. Review
  locks values; Edit returns to the draft without a POST. Pending retries retain
  their immutable original body/key/policy, including when capacity later falls.
  Foreign receipt/workflow requests cannot be dispatched from another dialog.
- Funds/period errors remain actionable without local balance deduction. Raced
  reversal dependencies show typed source IDs/applied amounts and invoice links
  through the existing read-only invoice preview flow, not raw response JSON.
- Reverse recovery verifies current payment/source state. An already-voided
  receipt is described as verified current state, without another POST or a new
  claim of reversal. Busy operations disable Close and repeat actions.
- English/Urdu strings, RTL, semantic form labels, responsive scrolling and a
  persistent footer reuse the existing design system. No server schema or
  accounting logic changes were needed.

## Automated evidence

- Initial meaningful red: 14 failures / 2 negative-case passes against the absent
  dialogs. `/tmp/minierp-f5-red.log`.
- Initial dialog implementation: 16 widget tests passed. Four additional cases
  cover paginated live lookup, foreign pending receipts, edit-before-confirm and
  duplicate confirmation. The duplicate test follows the disabled pending action
  after the controller saves the request, rather than tapping a removed widget.
- Focused dependency gate: 69 tests passed, exit 0 (132 seconds), covering all
  20 F5 cases plus receive/apply/pending/provider/repository regressions.
  `/tmp/minierp-f5-focused-final.log`.
- Analyzer: no issues, 62.1 seconds. `/tmp/minierp-f5-analyze-final.log`.
- Localization drift: passed; 2,177 English / 2,122 Urdu keys, existing fallback
  gap 55 within cap 60, zero orphan keys. Formatting/whitespace checks passed.
- Final strengthened F5 widget gate: 20 passed, exit 0 (60 seconds), including
  the ordinary-receipt guard with an otherwise valid reason.
- Dependent server GL/API/replay regressions: 3 suites / 58 tests passed,
  exit 0 (376.66 seconds).
- Full Flutter suite: 865 passed, zero failures/skips, JSON reporter success true
  and process exit 0 (1,612.481 seconds). `/tmp/minierp-f5-full.jsonl`.
  The unchanged server full suite is intentionally not rerun for this UI phase.
- Release web build passed, exit 0 (534.4 seconds).

## Runtime evidence

The release client targets an isolated server on port 4313, backed only by
`server/.tmp-test/ui-f5-surface/erp.db`; the live-write constructor guard is
installed before initialization. Clean fixtures contain two refund-customer
advances (100.25 and 75.50), a second customer's 25.00 advance and a 20.00 invoice
for a dependency race. Invoice GL uses the shared accounting service; fixture
creation is transactional. No canonical data or historical gaps were repaired,
reconciled or re-audited.

### Observed browser interactions

- Desktop 1440x900: refund 50.25 via Bank reached review without a POST, then
  confirmation returned insufficient funds. The form retained amount/method,
  explained the failure and still showed the original 175.75 capacity. Changing
  method to Cash and explicitly confirming paid out 50.25 as payment ID 4.
- Reversing unused payment 2 showed its fixed original amount 75.50 and October 2
  date, accepted a reason, required separate confirmation and reported success
  while retaining the historical receipt. The partly refunded payment 1 action
  was disabled after refresh.
- Payment 3 was unused when reversal was reviewed. An independent fixture-only
  API application then allocated 10.00 to invoice 1 before confirmation. Reversal
  was blocked with source 3 / applied amount 10.00 and an Invoice #1 link; review
  was disabled and the reason remained present. The link opened INV-F5-RACE in
  the existing invoice preview. Reopening reversal freshly also blocked it.
- Phone 390x844 and desktop captures show visible review content, wrapping footer
  actions and no dialog overflow. English/light and Urdu/RTL/dark captures were
  inspected directly, including the narrow blocked-reversal state. Phone refund
  review was closed without confirming, so it produced no extra financial write.

Screenshots under `audit/screenshots/unapplied-cash-ui/`:
`f5-refund-review-desktop-light.png`, `f5-refund-insufficient-bank.png`,
`f5-refund-success.png`, `f5-reverse-review-desktop-light.png`,
`f5-reverse-success.png`, `f5-reversal-race-blocked.png`,
`f5-dependency-invoice.png`, `f5-refund-phone-light.png`,
`f5-refund-phone-dark-urdu.png`, `f5-refund-desktop-dark-urdu.png`,
`f5-reverse-phone-dark-urdu-blocked.png`.

### Persisted accounting effects

Guarded read-only queries of the isolated fixture confirmed:

- Exactly four payments: receipts 1 (100.25), 2 (75.50, voided), 3 (25.00) and
  refund 4 (-50.25). No receipt was created by the application or failed attempts.
- Source 1 refunded 50.25, remaining 50.00; source 2 voided; source 3 consumed
  10.00, remaining 15.00 and not voided by the rejected reversal.
- Customer 1 AR/store credit remained 0/0; customer 2 AR became 10.00 with store
  credit 0. Invoice 1 paid/balance became 10.00/10.00, Partially Paid.
- Active cash 75.00, unapplied liability 65.00, AR 10.00; active journal totals
  debit 205.50 = credit 205.50. The refund reduced cash and liability, not AR.

### Residual observations

The browser retained six identical shared PlutoGrid layout errors while the
workspace refreshed/resized/switched theme, in the same layout callback family
recorded during F4. No zero-console-error claim is made. Financial dialogs and
their requests completed as described; unrelated grid internals were not changed.
An external writer does not push updates into an already cached workspace:
dialog entry revalidates online and blocks stale actions, while workspace Refresh
updates its displayed values. No realtime synchronization was added in F5.

### Direct visual checks

- PASS: modal bounds, readable wrapping and persistent confirmation/footer at
  390x844 and 1440x900; no observed dialog overflow or obscured primary action.
- PASS: distinct review/confirmation, destructive reversal styling, labelled
  inputs, fixed original receipt date and actionable adjacent error messages.
- PASS: inspected English/light and Urdu/RTL/dark renders; no light-only modal
  asset or incorrectly ordered footer was observed.
- NOT MEASURED: exhaustive WCAG contrast ratios, large accessibility text/200%
  zoom and every shared workspace control. Disabled form styling is inherited
  from the existing theme; this artifact is not a blanket HIG/accessibility audit.

The isolated API/static servers and named QA browser were stopped after testing.

This is direct QA, not an independent reviewer or Lighthouse claim. Existing
legacy payment hub/detail/export integration remains F6; the new workspace offers
no generic edit/delete or unsupported un-apply/refund-reversal actions.
