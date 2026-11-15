# Ledger Single Derivation — Tasks

## Phase 0 — Measure the live error before touching code

- [x] 0.1 Re-measure supplier AP on `server/database/erp.db`, read-only, comparing
      the as-coded query with the corrected one over the real rows.
      **done-when:** supplier 1 measures `as-coded −4000`, `corrected +1000`,
      `current_balance 1000`. The −4,000 reproduces and the fix ties exactly to
      `suppliers.current_balance`. Supplier 2 unchanged at 5,000.
- [x] 0.2 Establish that the defect is in the report, not the books, so no data
      repair is scheduled for it.
      **done-when:** the corrected figure equals `current_balance` for every
      supplier, so the ledger itself is consistent.

## Phase 1 — PUR-002 and PUR-006

- [x] 1.1 Add `reversed_by IS NULL` to both queries in `computeAPAging`.
      **done-when:** `a voided purchase leaves the correct AP` passes.
- [x] 1.2 Add `transaction_date <= asOfDate` to both queries.
      **done-when:** `a purchase dated after the as-of date is excluded` and
      `a credit dated after the as-of date does not reduce an earlier figure` pass.
- [x] 1.3 Confirm a real credit note is still counted.
      **done-when:** `a real credit note is still counted` passes — the fix does not
      over-exclude.

## Phase 2 — PUR-004 / H-04

- [x] 2.1 `getBalance` orders by `id DESC`, matching `rebuildBalances`.
      **done-when:** `tsc` clean and the existing supplier ledger suites pass.
- [x] 2.2 `getGLReconciliation`'s AP row switches from the highest-id row's stored
      `balance` to `SUM(debit) − SUM(credit)` over the filtered set.
      **done-when:** `poReceiptGl.test.ts` invariants 10 (GL AP == supplier ledger)
      and the accounting invariant suite pass.

## Phase 3 — SALES-007

- [x] 3.1 Add `deleted_at IS NULL` to `AR_OUTSTANDING`.
      **done-when:** `the shared predicate excludes deleted rows` and
      `top debtors excludes a deleted invoice` pass.
- [x] 3.2 Assert the predicate's own contents so a future edit cannot silently drop
      the clause.
      **done-when:** `the predicate still admits live invoices` passes, checking for
      `deleted_at IS NULL`, `balance_amount > 0` and the Cancelled/Draft exclusion.

## Phase 4 — ACCT-004

- [x] 4.1 Assign a NULL `due_date` to `current_amount` in `getARAgingReport`.
      **done-when:** `a balance with no due_date still lands in a bucket` passes.
- [x] 4.2 The same for `getReceivablesSummary`, which had an identical NULL-drop.
      **done-when:** `mixed dated and undated invoices still foot` passes.
- [x] 4.3 Assert footing, not just membership.
      **done-when:** both tests assert `current + 1_30 + 31_60 + 61_90 + over_90`
      equals the total.

## Phase 5 — SALES-021

- [x] 5.1 `createLedgerEntry` seeds from the last non-voided, non-reversal row in
      `id` order.
      **done-when:** full suite green; the ledger-balance suites that depend on the
      seed value still pass.

## Phase 6 — Anti-vacuity

- [x] 6.1 Revert all fixes.
      **done-when:** **12 of 12** fail across the two new suites.
- [x] 6.2 Restore.
      **done-when:** 12 of 12 pass, and the full suite is 122 / 1055 green.

## Phase 7 — Verification

- [x] 7.1 `npx tsc --noEmit` — exit 0.
- [x] 7.2 `npx jest --silent` — 122 suites / 1055 tests green.
- [x] 7.3 `openspec validate --all` — 0 failed.
- [x] 7.4 Live database opened read-only only; `git status` clean under
      `database/` and `server/database/`.
- [x] 7.5 Archive via the gate — every box above is ticked.

## Recorded, not done

- **SALES-017** — `SalesOrder.ts:645` passes `invoiceData?.due_date ?? null`, and
  the SO→invoice path also hard-codes `discount_type: 'none'` with no tax. Whether
  an explicit `null` should trigger the payment-term default is a product decision
  about payment terms, not a derived-balance defect. Left `planned` in the ledger
  rather than guessed at.
- **PUR-016** — the two live `PURCHASE_ORDER` commitment rows (3,000 supplier 1,
  1,000 supplier 2) still need human confirmation that they are duplicates.
