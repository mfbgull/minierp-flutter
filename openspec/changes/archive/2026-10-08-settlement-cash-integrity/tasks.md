# Settlement Cash Integrity — Tasks

## Phase 0 — Reproduce each defect before touching code

- [x] 0.1 Reproduce C-01: an adjust settlement records a payment but stores
      `payment_id = NULL`, so `revertSettlement` matches zero rows.
      **done-when:** `settlements[0].payment_id` is read back as `null` for an
      adjust leg, confirming the id never reaches the settlement row.
- [x] 0.2 Reproduce C-02: `refund_expected` on a fully unpaid purchase pays out
      the full return value in cash.
      **done-when:** net cash on account 1000 rises by the return value where the
      collected amount was 0.
- [x] 0.3 Reproduce H-03: the spec-driven refund leg pays `args.amount` verbatim,
      while `applyLegacyRefund` caps at `refundableOnInvoice`.
      **done-when:** an invoice settled entirely by store credit (collected cash
      0, `paid_amount` > 0) accepts a cash refund.
- [x] 0.4 Reproduce SALES-005: `postInvoiceEntry` returns null for a non-positive
      total, so the void-then-repost leaves nothing behind.
      **done-when:** editing a paid invoice to zero leaves `Dr 1100` voided with
      no replacement, i.e. a bare `Cr 1100`.

## Phase 1 — C-01 (the adjust settlement must record and reverse its payment)

- [x] 1.1 `applyAdjust` captures the payment id returned by the single payment
      writer and stores it on the settlement row.
      **done-when:** `payment_id` is non-null for an adjust leg that moved money.
- [x] 1.2 `revertSettlement`'s adjust branch voids the allocation by payment id
      AND the GL group the credit application actually posted.
      **done-when:** `('CREDIT_OFFSET', targetInvoiceId)` reads 0/0 after the
      void, and the target has no live allocation.
- [x] 1.3 A second void of the same settlement is rejected, not silently re-run.
      **done-when:** `voiding twice does not re-run the reversal` passes.

## Phase 2 — C-02 (a purchase refund cannot exceed what was collected)

- [x] 2.1 Add `sourceCollected`, mirroring `sourceUnpaidBalance`.
      **done-when:** `tsc` clean.
- [x] 2.2 `refund_expected` is refused when the collected amount is 0.
      **done-when:** `refund_expected is refused when nothing was ever paid`
      returns >= 400 naming the remedy, and net cash is unchanged.
- [x] 2.3 Otherwise the refund is capped at the collected amount.
      **done-when:** `a partially paid purchase refunds at most the collected
      amount` — a 250 return against 100 collected moves exactly <= 100.01 of cash.
- [x] 2.4 `credit_on_account` on the same unpaid purchase still succeeds and
      moves no cash.
      **done-when:** `credit_on_account on an unpaid purchase is still accepted
      and moves no cash` passes.

## Phase 3 — H-03 (a customer refund cannot exceed what was collected)

- [x] 3.1 Cap `applyRefund` at `PaymentModel.refundableOnInvoice(...)`, at the
      chokepoint every refund leg passes through.
      **done-when:** `refunding a store-credit-settled invoice is refused` returns
      400 and net cash is unchanged.
- [x] 3.2 A refund within the cap is still accepted.
      **done-when:** `a partially cash-settled invoice refunds only its cash
      portion` — 400 requested is refused, 100 is accepted.

## Phase 4 — SALES-005 (an edit that cannot be re-posted is refused)

- [x] 4.1 Guard `updateInvoice` before any write when the recomputed total is
      non-positive and payments already exist.
      **done-when:** `zeroing a paid invoice returns 400 and leaves the original
      entry live` — the INVOICE group keeps its original magnitude and
      `total_amount` is unchanged.
- [x] 4.2 The floor is non-positive, NOT "below what was paid".
      **done-when:** `reducing a paid invoice while keeping it positive is still
      allowed` passes — 400 paid, edited to 200, payment untouched. This is the
      case `moneyPaths` 9.3 already covers, and an over-broad guard fails it.

## Phase 5 — Anti-vacuity

- [x] 5.1 Neutralise each guard in turn and re-run its own test.
      **done-when:** M1–M4 each produce **1 failed**. A guard whose test still
      passes when the guard is deleted is not a guard.
- [x] 5.2 Fix the two vacuous assertions this exposed.
      **done-when:** the C-01 test asserts `('CREDIT_OFFSET', targetInvoiceId)`
      rather than an always-empty `('PAYMENT', paymentId)` group, and the SALES-005
      test asserts the group's magnitude rather than `debit - credit`, which is 0
      for both a healthy and a voided double-entry group.
- [x] 5.3 Restore all four guards.
      **done-when:** 11 of 11 pass; all four guard conditions verified present; no
      mutation leftovers.
- [x] 5.4 Enforce SALES-008's unreachability instead of documenting it.
      **done-when:** a source scan asserts exactly one production caller of
      `INVOICE_SETTLEMENT` (`services/InvoiceCreationService.ts:256`) and pins the
      ceiling expression to `total - returned`. Injecting a second caller into
      `models/Payment.ts` (mutation M5) fails the guard, and the failure diff names
      `models/Payment.ts:366`. A docstring is not a guard — the finding is recorded
      `won't-fix` precisely because this structural fact, not a code change, is what
      makes it unreachable.

## Phase 6 — Verification

- [x] 6.1 `npx tsc --noEmit` — exit 0.
- [x] 6.2 `npx jest --silent` — 123 suites / 1069 tests green.
- [x] 6.3 `npx eslint` on the four changed files — 0 errors, 0 warnings.
- [x] 6.4 No live-database access; every case runs on the per-run temp DB.
- [x] 6.5 Ledger updated: C-01, C-02, H-03, SALES-005 landed; summary recount
      foots to 65 (18 landed / 43 planned / 1 deferred / 3 won't-fix).
- [x] 6.6 Archive via the gate — every box above is ticked.

## Recorded, not done

- **SALES-008** — mis-attributed at first. `INVOICE_SETTLEMENT` has exactly one
  production caller, `InvoiceCreationService.create`, which records the payment in
  the same transaction that creates the invoice, so the row is already stored as
  settled and subtracting `paid` double-counts. The prescribed
  `max(0, balance_amount)` fix would reject every fully-paid invoice at creation.
  Reverted and recorded `won't-fix` in the ledger with the structural reason. The
  residual risk it names — a future caller widening this mode — is now enforced by
  the source-scan guard in task 5.4, not left to a docstring.
- **SALES-017** — landed under `ledger-single-derivation`'s surface after the
  owner decided due dates derive from customer payment terms: `resolveDueDate`
  reads `customers.payment_terms_days`, falls back to the active default
  `payment_terms` row, then to zero days, and `InvoiceCreationService` derives
  when `due_date` is null. Covered by `arSurfaceConsistency.test.ts`.
