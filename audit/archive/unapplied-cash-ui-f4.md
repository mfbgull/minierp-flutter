# Unapplied customer cash UI: F4 apply existing cash

Status: F4 implemented and verified through automated and direct runtime checks;
runner/console limitations are recorded below. Plan: `.omo/plans/unapplied-customer-cash-ui.md`.

## Implemented

- Apply Cash to Invoices is a separate action in the Unapplied Cash workspace,
  gated by payments:update. The dialog also requires payments:read for capacity
  and invoices:read for selection. Missing permissions show an explanation, not
  an empty list or an invented zero balance.
- The fixed customer, operation date, date-eligible capacity, selected total and
  remaining capacity are separate. There is no payment-method or collection field.
- Eligible invoices are loaded online across every server page, excluding other
  customers, future/cancelled/deleted/paid invoices and nonpositive balances. A
  failed/incomplete page fails the entire selection read, rather than presenting
  a partial list. The repository does not use cached invoice balances.
- Desktop uses the existing Pluto-Grid primitive with labeled allocation inputs;
  narrow screens use amount cards. Search changes visibility, not allocations.
  Optional Auto Allocate prepares oldest-date/ID-first amounts for explicit review
  and confirmation, limited to 1,000 lines.
- Minor-unit validation enforces positive amounts, invoice caps, total cash cap,
  unique invoices and 1-1,000 lines. Operation-date changes refetch capacity and all
  invoice pages. Definite conflicts refresh reads while preserving entered text;
  no silent clamp or automatic resubmission occurs. Closed periods retain their
  domain explanation.
- Uncertain attempts retain the original persisted request and policy/key. The
  read-only recovery view lists original invoice IDs and allocations. Explicit
  Retry bypasses newly reduced capacity and uses the immutable original request;
  it still performs the F2 fresh server capability check. Foreign/corrupt pending
  requests cannot become new writes. Busy dialogs cannot dismiss.
- Success names amount/application ID and explicitly says no new payment was
  collected. Existing F2 success invalidation refreshes invoices, customers, cash,
  payments and report consumers. English/Urdu labels and RTL are included; cash
  grid instances follow locale and theme changes.

## Test evidence

- Initial meaningful red: 10 of 11 widget cases failed against the absent dialog;
  only the no-update/no-write negative case passed. `/tmp/minierp-f4-red.log`.
- The first implementation gate exposed test interaction with embedded grid
  editors: focus the cell by a tap before entering text, matching actual use.
  The tests retain explicit controller-text assertions and exact POST assertions.
- Focused dependency gate: 47 tests passed, exit 0, covering F4, receive UI,
  pending recovery, provider invalidation and repository contracts.
  `/tmp/minierp-f4-focused.log`.
- Expanded final F4 gate: 14 tests passed, exit 0. Cases cover all-page reads and
  exclusions; exact partial multi-invoice body; fractional/over-pool/over-invoice
  rejection; oldest-first auto allocation with no POST; stale pool and invoice
  conflicts; hidden search allocations; date-change refetch/cutoff; duplicate taps;
  immutable retry after a reduced pool; permissions; and phone English/Urdu dark.
  `/tmp/minierp-f4-final-widget.log`.
- Analyzer: no issues, exit 0, 158 seconds. Localization drift passed: 2,154 English
  / 2,099 Urdu keys, unchanged fallback gap 55 within cap 60, zero orphan keys.
  `/tmp/minierp-f4-analyze-final.log`.
- Actual browser keyboard input revealed that Pluto-Grid intercepted Ctrl+A in
  embedded allocation fields. A new widget regression failed with selection start
  5 instead of 0. Local DefaultTextEditingShortcuts now route editor keys before
  grid shortcuts. All 15 F4 tests passed after this correction, exit 0.
  `/tmp/minierp-f4-keyboard-red.log`, `/tmp/minierp-f4-keyboard-green.log`.
  The date field's redundant semantic label was removed at the same checkpoint.
- Final analyzer: no issues, 50.6 seconds.
  `/tmp/minierp-f4-analyze-verified.log`.
- Final web propagation correction: native widget regression passed, but actual
  web input still let ancestor grid shortcuts consume browser editing keys. A
  web-only Focus boundary now returns skipRemainingHandlers for editing keys,
  retaining Tab/Escape traversal and native DefaultTextEditingShortcuts behavior.
  All 15 affected tests passed again, exit 0; final analyzer had no issues
  (81 seconds). `/tmp/minierp-f4-keyboard-final-tests.log`,
  `/tmp/minierp-f4-final-analyze.log`.
- Dependent server regression: three suites / 58 tests passed, exit 0, including
  unapplied-cash GL, mounted API and durable replay tests (419.981 seconds).
  `/tmp/minierp-f4-server-regression.log`.
- Full Flutter suite: 844 passed, zero failed/skipped, reporter success true,
  1,483.289 seconds. `flutter test --no-pub --concurrency=2 --reporter=json`;
  `/tmp/minierp-f4-full.jsonl`. The command wrapper returned SIGTERM/143 after
  the reporter's successful `done` event; this is not a clean process-exit claim.
  The final embedded-editor keyboard corrections
  landed after this full-run snapshot; their affected widget tests were rerun
  rather than repeating unchanged suites. The unchanged server full suite is intentionally not repeated for this
  Flutter-only phase; relevant accounting invariant collectors run with the
  unapplied-cash GL regression.

## Runtime evidence

The client uses an isolated server on port 4312, backed by
`server/.tmp-test/ui-f4-surface/erp.db`. The live-database constructor guard is
installed before initialization. Clean fixtures contain one existing 100.25
receipt and two invoices (60.10 and 80.20), posted through the shared accounting
service. Starting AR is 140.30 and store credit is zero. Historical dummy records
and the canonical database are not repaired, reconciled or re-audited.

Opened the actual customer workspace and Apply dialog. Auto Allocate filled
60.10 / 40.15 and selected total 100.25 without a POST. Invalid fractional input
showed the validation explanation without dispatch. Explicit confirmation sent
one `POST /api/unapplied-cash/apply`, HTTP 200; the success dialog named application
1 and amount 100.25 and stated that no new payment was collected.

The live workspace refreshed to AR 40.05 / store credit zero / unapplied cash
zero. Activity showed the application and both invoice numbers; the Invoices tab
showed the first invoice Paid and the second Partially Paid with remaining 40.05.
A read-only isolated-database query confirmed:

- Exactly one original payment, amount 100.25, kind UNAPPLIED_RECEIPT: applying
  cash did not create a second receipt or collect cash again.
- Invoice 1 paid 60.10, balance zero, Paid; invoice 2 paid 40.15, balance 40.05,
  Partially Paid. Customer AR 40.05 and store credit zero.
- One APPLY application, total 100.25, payment_id null. Source consumed 100.25,
  remaining zero; unapplied liability zero.
- Journal debits and credits both total 340.80, including the clean initial
  invoice postings and receipt plus this application.

Screenshots in `audit/screenshots/unapplied-cash-ui/` prefixed `f4-` cover the
desktop dialog/draft/error/success, refreshed activity/invoices, phone light/dark,
phone scrolled end, and Urdu RTL phone/desktop. The settled responsive captures
were visually inspected. The final release build passed, exit 0, 267.3 seconds
(`/tmp/minierp-f4-web-keyboard.log`). In that build, typed 20 in the remaining
invoice's amount field, pressed Ctrl+A, then typed 10 using raw keyboard events:
the result was 10, not appended text. After the application had exhausted cash,
confirming this new draft showed validation and issued no second financial POST.
The date field's accessibility label appears once.

The browser retained three Pluto-Grid runtime errors across the earlier resize,
theme and grid-refresh exercise. The final dialog close/reopen did not increase
that count. This is not a zero-console-error claim; the shared grid also retains
the dark serial-number contrast limitation recorded in F3. The application and
persisted accounting effects above were verified independently of the console.

Direct visual assessment is recorded here; no independent reviewer or Lighthouse
score is claimed. F5 refund and reversal dialogs remain outside this phase.
