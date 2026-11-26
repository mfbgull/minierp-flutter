# GLM UX Review — Recent Purchase Refund / Claim / Sales-Order Screens

Date: 2026-11-16
Scope: read-only review of the Flutter client for the recently built refund-claim,
supplier-refund, refund-receipts, write-off, void, cash-blocker and sales-order
surfaces, plus their l10n strings (en/ur).
Reviewer: GLM. No code changed.
Follow-up (2026-11-16, Task 3): confirmation tests were added and the two
blocking findings (UX-1, UX-2/UX-4) were fixed. See "Finding confirmation status"
below. That section is the only later addition; the findings above are unchanged.

## Method and limits

- Reviewed by reading code and l10n files only. No runtime rendering, no RTL
  device test, no `flutter analyze`, no `flutter test`, no full test suites
  (shared machine; per task instructions).
- Line numbers refer to the working tree at commit `a5fd4afa`. *(2026-11-18
  correction: `a5fd4afa` was a local review-time commit on the unmerged
  `glm/extract-cash-timeline` line — it is not an ancestor of `origin/main` and
  was not part of merged PR #3 (`bf96ee1f`), so those line numbers cannot be
  checked out from main.)*
- Each finding lists: location, issue, severity, suggested fix. Nothing here is
  a fix in code.

Files read:

- `lib/features/purchases/refund_claims_screen.dart`
- `lib/features/purchases/supplier_refund_dialog.dart`
- `lib/features/purchases/refund_claim_receipts_dialog.dart`
- `lib/features/purchases/refund_claim_write_off_dialog.dart`
- `lib/features/purchases/void_refund_dialog.dart`
- `lib/widgets/cash_blockers_list.dart`
- `lib/features/sales_orders/sales_order_form_dialog.dart`
- `lib/data/repositories/purchase_repository.dart` (claim repository methods)
- `lib/l10n/app_localizations_en.dart`, `lib/l10n/app_localizations_ur.dart`
- `node scripts/l10n-drift.js` — ran, passed (fallback gap 0, orphaned 0).

---

## Findings

### UX-1 — "Open only" filter is dead code — HIGH

`refund_claims_screen.dart:53`:

```dart
status: _openOnly ? null : null,
```

Both branches are `null`, so the toggle never changes the request. The
repository docstring (`purchase_repository.dart:553-554`) says the server
expects `EXPECTED` / `PARTIAL`. Filtering is then done client-side over only
the currently loaded page, so claims on later pages are invisible even when
open.

Failing scenario: user has 50+ claims, page 1 shows only `SETTLED` rows, user
toggles "Open only" and sees an empty list although open claims exist on page 2.

Severity: HIGH — users conclude money owed to them does not exist.

Suggested fix: pass `status: _openOnly ? 'EXPECTED' : null` (or the agreed
status set) to the repository call, and re-fetch on toggle. Add a widget test
that captures the repository argument.

### UX-2 — Write-off cannot succeed: missing Idempotency-Key — HIGH

`refund_claim_write_off_dialog.dart:82-84` submits through
`purchase_repository.dart:524-537` (`writeOffClaim`), which sends no headers
and has no way to add them; `postEnvelope` adds none either.

The server mandates an idempotency key for this route
(`startRequiredIdempotentRequest`, scope `SUPPLIER_REFUND_CLAIM_WRITE_OFF`).
Every write-off from the UI should fail with 400.

Failing scenario: open a claim, tap Write-off, confirm → 400 from the server,
no path to success from the UI.

Severity: HIGH — the feature is unusable end-to-end.

Suggested fix: add an optional `headers` parameter to `writeOffClaim`
(consistent with how other idempotent mutations are sent), generate the key in
the dialog, add an integration test that posts the real envelope and asserts a
non-400 response.

### UX-3 — Wrong validation messages reused from returns — MEDIUM

`supplier_refund_dialog.dart:110` and `:114` show
`purchasesReturnqtyinvalid` / `purchasesReturnqtyexceeds` for refund *amount*
errors. Both strings talk about "return quantity".

Failing scenario: user types an amount larger than the remaining claimable
amount; the error says something about return quantity.

Severity: MEDIUM — confusing, suggests the wrong form.

Suggested fix: add dedicated refund-amount strings (`refundAmountInvalid`,
`refundAmountExceeds`) in both languages.

### UX-4 — Write-off dialog: no amount, no date; server posts at claim_date — MEDIUM

`refund_claim_write_off_dialog.dart:82-84` sends only the claim id. The server
then writes off the full remaining amount at `claim_date`. Two consequences:

1. Partial write-offs are impossible from the UI (server supports them).
2. If the claim's period is now closed, the server returns 409 and the UI has
   no way to choose a different posting date; the blocker is unresolvable.

Severity: MEDIUM — silent limitation plus a dead end in period-close month.

Suggested fix: add optional amount and posting-date fields; send them when
provided; show the effective date in the confirmation.

### UX-5 — Standalone claim creation UI missing (`createClaim` has zero callers) — MEDIUM

`createClaim` in the repository has no callers in the UI, although
`refundClaimStandalone` strings exist in l10n. Claims can only be created from
the refund flow.

Severity: MEDIUM — advertised capability not reachable; unused l10n strings.

Suggested fix: either build the standalone claim screen or remove the strings
until it exists.

### UX-6 — Raw enums and ISO dates embedded in sentences — MEDIUM

- `purchasesRefundClaim` (en/ur) interpolates the raw status enum.
- `refundBlockedRow` (`cash_blockers_list.dart:57-60`) interpolates the raw
  blocker type and an ISO date, in both languages.

Failing scenario: user sees `purchasesRefundClaim: PARTIAL` or
`receipt_overpayment · 2026-11-15`.

Severity: MEDIUM.

Suggested fix: map status/type enums to localized labels; format dates with
`intl` per locale.

### UX-7 — Urdu write-off wording uses "forgiveness" — MEDIUM

`app_localizations_ur.dart:2066` (`refundClaimWriteOff`, `...AdminOnly`)
translates write-off as معاف کریں / معافی (forgive/forgiveness). Write-off is
an accounting write-down, not forgiveness of the claim.

Severity: MEDIUM — an accountant reading the Urdu UI may misread what the
operation posts.

Suggested fix: use اکتساب/وصولی سے دستبرد or a finance-approved term agreed
with Gull; keep the accounting meaning.

### UX-8 — Success toast says "Cancel claim" (not past tense) — LOW

`refund_claims_screen.dart:342` shows a message using the imperative
"Cancel claim" after the action succeeded.

Severity: LOW.

Suggested fix: use the existing past-tense pattern ("Claim cancelled").

### UX-9 — Refunds-due banner error state shows only the title — LOW

`refund_claims_screen.dart:371`: when the banner fetch fails, the widget shows
only the title with no message and no retry.

Severity: LOW.

Suggested fix: show a short error line plus a retry button, matching the
pattern used elsewhere.

### UX-10 — Receipts dialog: fixed limit 100 with no hint — LOW

`refund_claim_receipts_dialog.dart`: list is capped at 100 rows with no count
or "showing first 100" hint.

Severity: LOW.

Suggested fix: show total count or a truncation notice.

### UX-11 — Sales-order dialog: providers hide loading and errors — MEDIUM

`sales_order_form_dialog.dart:340`, `:532-536`: providers are watched with
`valueOrNull ?? []`, so initial load and failure both render as an empty list.
The user sees blank pickers with no spinner and no error, and a failed fetch
looks identical to "no data".

Severity: MEDIUM.

Suggested fix: use `AsyncValue.when` and render loading/error/empty states
separately.

### UX-12 — Sales-order dialog: two adjacent "Amount" labels — LOW

`sales_order_form_dialog.dart:437` and `:458`: two fields in sequence are both
labelled "Amount" without unit context (price vs discount vs total).

Severity: LOW.

Suggested fix: "Unit price" / "Line total" or equivalent.

### UX-13 — Flat discount not validated against line total — MEDIUM

`sales_order_form_dialog.dart`: a flat discount larger than the line total is
accepted locally and fails (or posts a negative) at the server.

Severity: MEDIUM.

Suggested fix: validate discount <= line total; show the computed total live.

### UX-14 — Sales-order dialog: `_error` rendered below the fold — LOW

`sales_order_form_dialog.dart:697-705`: submit errors render at the bottom of
a long form; on a small window the user sees nothing happen.

Severity: LOW.

Suggested fix: render the error above the submit button, or scroll to it.

### UX-15 — Sales-order dialog: non-directional alignments — LOW

`sales_order_form_dialog.dart:461`, `:668`: `Alignment.centerLeft` /
`AlignmentDirectional` mismatch (hard-coded left in at least one spot).

Severity: LOW; matters for Urdu/RTL.

Suggested fix: use `AlignmentDirectional.centerStart` consistently.

### UX-16 — Sales-order dialog: unused `label` parameter in `_dateField` — LOW

`sales_order_form_dialog.dart`: `_dateField` takes `label` but never uses it;
callers think a label renders.

Severity: LOW.

Suggested fix: remove the parameter or use it.

### UX-17 — Supplier-refund idempotency key omits `treat_excess_as_advance` — LOW (consistency)

`supplier_refund_dialog.dart:137-144`: the idempotency key payload hashes
fields but not `treat_excess_as_advance`. A retry with the toggle flipped
reuses the key and silently replays the first choice.

Severity: LOW — user-visible only on retry-after-failure with a changed toggle.

Suggested fix: include the toggle in the payload hash.

---

## Urdu / RTL summary

- Strings exist for ur in all reviewed flows; drift check passes.
- Risks: UX-7 (wording), UX-6 (raw enums/dates render identically in ur),
  UX-15 (hard-coded left alignment).
- Not rendered at runtime; no RTL screenshot review was performed.

## Finding confirmation status (2026-11-16)

Task 3 asked for a failing test or an explicit "unconfirmed" mark for every
MEDIUM+ finding. Red tests are committed failing on purpose; the branch must not
merge without fixing them or deleting them deliberately.

| Finding | Severity | Test | Status |
|---|---|---|---|
| UX-1 ("Open only" filter sent `status: null` in both chip states) | High | `test/features/refund_claims_screen_filter_test.dart` + server test in `supplierRefundClaims.test.ts` | **CONFIRMED and FIXED (green).** Red first (`Actual: <null>`), then fixed: the screen sends `EXPECTED,PARTIAL` when the chip is on and no status when off. Server `SupplierRefundClaimModel.list` now takes a comma-separated whitelisted status set (IN clause from placeholders only; unknown status → 400). Also fixed the invalidate-args mismatch at the old line 350. Server 18/18, Flutter test green. |
| UX-2 (write-off dialog sent no `Idempotency-Key`) | High | `test/features/refund_claim_write_off_idempotency_test.dart` | **CONFIRMED and FIXED (green).** Red first with `Idempotency-Key: <null>` on the wire — this proves the earlier "no keyless caller exists" report WRONG. `writeOffClaim` now requires the key; the dialog sends it and rotates it when the amount or date is edited. |
| UX-4 (write-off dialog could not set a partial amount or the posting date) | Medium | same test as UX-2 | **CONFIRMED and FIXED (green).** The dialog now carries an amount field (prefilled with the remainder) and a write-off date (prefilled with the claim date); the "edited amount rotates key" assertion pins it. |
| UX-3 (refund-amount errors reuse return-quantity strings) | Medium | `test/features/supplier_refund_message_test.dart` | **CONFIRMED, parked, tagged** (`skip: true`, `RED-BY-DESIGN … UX-3`). Fails unmarked: `Expected: no matching candidates / Actual: Found 1 widget with text containing quantity`. |
| UX-6 (cash-blocker rows render the raw `reference_type` enum and raw ISO date in both languages) | Medium | `test/widgets/cash_blockers_localization_test.dart` | **CONFIRMED, parked, tagged** (`skip: true`, `RED-BY-DESIGN … UX-6`). Fails unmarked: `Found 1 widget with text containing receipt_overpayment`. |
| UX-11 (failed option fetch renders as an empty picker, no message) | Medium | `test/features/sales_order_form_loading_test.dart` | **CONFIRMED, parked, tagged** (`skip: true`, `RED-BY-DESIGN … UX-11`). Fails unmarked: `Expected: at least one matching candidate / Actual: Found 0 widgets with text containing Failed`. |
| UX-13 (flat discount above the line total passes local validation) | Medium | `test/features/sales_order_discount_validation_test.dart` | **CONFIRMED, parked, tagged** (`skip: true`, `RED-BY-DESIGN … UX-13`). Fails unmarked: `Expected: not null / Actual: <null>` on the discount field's `errorText`. |
| UX-5 (product gap — standalone claim creation UI missing, `createClaim` has zero callers) | Medium | — | **UNCONFIRMED** — product decision (build the screen or remove the strings), not a defect. **(2026-11-18 correction: row label aligned with the UX-5 heading above; the earlier "wording of the write-off explanation" label described a different item — the write-off wording finding is UX-7.)** |
| UX-7 (Urdu wording) | Medium | `test/features/refund_claim_write_off_urdu_wording_test.dart` | **RESOLVED 2026-11-26 by Gull — Option B (دستبرد).** The four `ur.arb` write-off strings said معاف / معافی (forgive / forgiveness), which tells an Urdu-reading accountant the wrong thing: a write-off posts Dr 7300 Refund Write-offs / Cr AP, it does not forgive the claim. They now say دستبرد ("removal from the books"). Red first: the new test failed with `refundClaimWriteOff still reads as forgiveness: "معاف کریں"`, and passes 3/3 after the change. Five dependent widget/repository suites (12 tests) green, `flutter analyze` zero errors/warnings, `l10n-drift` exit 0. Evidence in `audit/DECISIONS.md`. |

*(2026-11-18 correction to the four "parked, tagged" rows above: UX-3, UX-6, UX-11
and UX-13 were fixed and un-parked by the merged UX-review line — PR4, head
`ea8f79cd`, merged as `d1075cd2` on 2026-11-17. Verified on current main
`1f6a2905`: no `skip: true` or `RED-BY-DESIGN` marker remains anywhere under
`test/`, and all four tests run as ordinary passing regressions. The
"CONFIRMED, parked, tagged" cells above are the historical review-time state.)*

## What was not run

- `flutter analyze`, `flutter test` — not run (out of scope for this read-only
  review; per shared-machine instructions).
- Any runtime UI: screens were not launched; findings are reasoned from code
  and l10n files.
- RTL rendering check on device or emulator.
- Server behavior of the write-off idempotency requirement was confirmed from
  code, not by an HTTP round-trip.

## Suggested follow-up order

1. UX-1 and UX-2 (both block core workflows).
2. UX-4, UX-11, UX-13 (wrong or missing data handling).
3. Wording and l10n items (UX-3, UX-6, UX-7, UX-8).
4. LOW polish items.
