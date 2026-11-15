# Settlement Cash Integrity — C-01, C-02, H-03, SALES-005

## What Changes

- `services/invoiceReturnService.ts` — `applyRefund` caps the refund at
  `PaymentModel.refundableOnInvoice(...)` (H-03); `revertSettlement`'s adjust
  branch voids the `CREDIT_OFFSET` group keyed by the **target invoice**, which
  is where a `CREDIT_APPLICATION` actually posts (C-01).
- `models/PurchaseReturn.ts` — `sourceCollected` is added, and `refund_expected`
  is refused outright when nothing has been collected, otherwise capped at the
  collected amount (C-02).
- `controllers/invoiceController.ts` — `updateInvoice` refuses a non-positive
  recomputed total on an invoice that already carries payments (SALES-005).
- `__tests__/settlementCashIntegrity.test.ts` — new, 9 tests.

Deltas recorded against `invoice-returns` and `purchase-returns`.

## Why

Four paths where a document could **claim or extract money that was never
collected**. Each one produced a *balanced* journal entry — invariants A–E stay
green — while cash appeared from nothing, or revenue was voided and reposted as
a bare credit. This is the audit's recurring failure mode in its purest form:
green suite, wrong books.

## The four

| # | Finding | Defect | Consequence |
|---|---|---|---|
| 1 | C-01 | `applyAdjust` recorded a payment but never stored its id; `revertSettlement` then voided `('PAYMENT', NULL)`, which matches zero rows | void → refund paid the supplier **twice** for one entitlement |
| 2 | C-02 | `refund_expected` refunded the **full return value** regardless of what was collected | `Dr Cash / Cr AP` fabricated from a fully unpaid purchase |
| 3 | H-03 | the spec-driven refund leg paid `args.amount` verbatim while `applyLegacyRefund` capped at collected cash | a store-credit-settled invoice (collected cash **0**, `paid_amount` > 0) was convertible to cash on return |
| 4 | SALES-005 | `postInvoiceEntry` returns `null` for a non-positive total, and `updateInvoice` voided before re-posting with no floor | editing a paid invoice to zero left a bare **Cr 1100** on a debit-normal asset |

## Two corrections made *during* this work

Both were caught by the anti-vacuity pass, and both are recorded because the
first attempt was wrong in a way that a green suite would have hidden:

1. **SALES-008 was mis-attributed and has been reverted.** The finding names
   `INVOICE_SETTLEMENT`'s ceiling in `paymentValidation.ts`. Changing it to
   `total − (returned + paid)` broke **every** paid invoice creation: that mode
   has exactly one production caller, `InvoiceCreationService.create`, which
   records the payment *in the same transaction that creates the invoice*, so
   the row is already stored as settled and `paid` double-counts. Reverted, and
   the finding is recorded `won't-fix` in the ledger with the structural reason.
2. **The first C-01 fix voided the wrong journal group.** `CREDIT_APPLICATION`
   moves no cash, so it posts no `PAYMENT` group at all — its GL is
   `CREDIT_OFFSET` keyed by the target invoice. The original
   `voidJournalLinesByReference('PAYMENT', payment_id)` matched zero rows, and
   the anti-vacuity run **passed with that line deleted**, which is what exposed
   it. The test now asserts on `('CREDIT_OFFSET', targetInvoiceId)`.

## Anti-vacuity, both directions

Each guard was neutralised in turn and its own test re-run. A guard that cannot
fail its test is not a guard.

| mutation | test result |
|---|---|
| M1 — drop the `CREDIT_OFFSET` void on adjust | **1 failed** ✓ caught |
| M2 — allow `refund_expected` with no cash collected | **1 failed** ✓ caught |
| M3 — allow a zero-total edit on a paid invoice | **1 failed** ✓ caught |
| M4 — drop the refund cash cap | **1 failed** ✓ caught |
| M5 — inject a second `INVOICE_SETTLEMENT` caller | **1 failed** ✓ caught, diff named `models/Payment.ts:366` |
| all mutations reverted, all fixes applied | 11 of 11 pass |

Every test asserts the **ledger** consequence (trial balance, net cash on
account 1000, group magnitude), not just an HTTP status. Note that a
double-entry group is always `Dr == Cr`, so `debit − credit` is 0 for a healthy
sale *and* a voided one — asserting on it is vacuous, and one test here was
rewritten for exactly that reason.

## Full verification

- `npx jest --silent` — 123 suites / 1069 tests green
- `npx tsc --noEmit` — exit 0
- `npx eslint` on all four files — 0 errors, 0 warnings
- No live-database access: every case runs on the per-run temp DB from
  `src/__tests__/setup.ts`.

## Risk and rollback

**C-02 is a behaviour change users will feel.** `refund_expected` on an unpaid
purchase previously succeeded and now returns 400. That is the point — it was
fabricating cash — but a caller that relied on it will start seeing errors. The
error names the remedy (`credit_on_account`).

**H-03** rejects refunds above collected cash on the spec-driven path. The
legacy path already behaved this way, so the two dispositions now agree; a
client that previously cash-refunded a credit-settled invoice will be refused.

**SALES-005** rejects only the non-positive total. Reducing a paid invoice while
keeping it positive is still allowed — `moneyPaths` 9.3 covers that case, and it
was failing during this work, which is how the guard's boundary was pinned down.

Rollback: revert four files. No migration, no schema change, no data change.
