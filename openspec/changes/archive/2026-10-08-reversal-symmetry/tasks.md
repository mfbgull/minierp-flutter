# Reversal Symmetry — Tasks

## Phase 0 — Prove the defect before changing anything

- [x] 0.1 Write `reversalSymmetry.test.ts` with a fixture that records a real
      purchase through `PurchaseModel.recordPurchase`, so the GL group and the
      batch are genuine.
      **done-when:** the suite fails on unmodified `Purchase.ts`.
- [x] 0.2 Stub `ledgerUtils.reverseLedgerEntry`, which is bound to the global
      database and cannot run against an in-memory fixture.
      **done-when:** the stub is declared with a comment naming the suite that
      really covers the ledger reversal (`models.test.ts:793`), so the gap is
      recorded rather than hidden.
- [x] 0.3 Record the measured pre-fix state.
      **done-when:** GL 1200 `debit 0 / credit 500`; GL 7200 `debit 500`;
      movement_date `2026-10-08` for a `2026-01-15` purchase;
      `financial_posted = 1`.

## Phase 1 — Answer the open question from Phase 0

- [x] 1.1 Determine empirically whether `expectAllInvariantsHold` would have
      caught PUR-001, by running the invariant E and H collectors' formulas
      against the defective fixture.
      **done-when:** measured. H reports
      `{ glBalance: 500, batchVal: 0, legacyVal: 0, diff: 500 }` — it fires.
      The Phase 0 hypothesis that H might stay green is refuted.
- [x] 1.2 Record the reason: `recordMovement` decrements `items.current_stock` to
      zero, so H's `legacyVal` term drops out instead of cancelling the error.

## Phase 2 — PUR-001

- [x] 2.1 Add `skipAdjustmentFinancialPosting: true` to the `PURCHASE_VOID`
      movement in `Purchase.void`.
      **done-when:** `after void, GL 1200 is zero on BOTH sides and GL 7200 is
      untouched` passes.
- [x] 2.2 Pass `movement_date: purchase.purchase_date` instead of
      `new Date().toISOString().split('T')[0]`.
      **done-when:** `reversal is dated with the purchase, not with today`
      passes.
- [x] 2.3 Assert the reversal movement carries no financial value.
      **done-when:** `the stock_adjustment pair written by the void carries no
      financial value` passes — `financial_posted` falsy, `journal_entry_id`
      null, `financial_value` 0.

## Phase 3 — C-05

- [x] 3.1 Add `skipAdjustmentFinancialPosting: true` to the restock reversal in
      `reverseRestock` (`invoiceReturnService.ts`).
- [x] 3.2 Correct the comment that stated the defect as the design — *"recordMovement
      posts its own balanced financial entry, which restores the inventory GL"* —
      which is the sentence that made the bug look intentional.
      **done-when:** the comment names the voided `INVOICE_RETURN` group as the
      thing that restores inventory.
- [x] 3.3 Add a global GL 7200 assertion to
      `invoiceReturnVoidsAndPrint.test.ts` scenario 15, alongside its existing
      reference-type-scoped checks.
      **done-when:** scenario 15 passes, and the new assertion fails when 3.1 is
      reverted.

## Phase 4 — Close the three blind spots

- [x] 4.1 Document on `glTotals` (`supplierlessPurchase.test.ts`) that callers
      MUST assert both columns, naming PUR-001 as the reason.
- [x] 4.2 Add a test that demonstrates the single-sided assertion passing on the
      defective books.
      **done-when:** `the historical single-sided assertion passes on the
      defective books` passes while `gl('1200').credit` is 500.
- [x] 4.3 Assert the affected accounts globally wherever a void is checked by
      reference type, so a second posting under another `reference_type` is
      visible.
      **done-when:** done for the sales-return void; documented as a requirement
      for the others.

## Phase 5 — Anti-vacuity, both directions

- [x] 5.1 Revert both fixes.
      **done-when:** 4 of 13 tests fail across `reversalSymmetry` and
      `invoiceReturnVoidsAndPrint`.
- [x] 5.2 Restore both fixes.
      **done-when:** 13 of 13 pass.

## Phase 6 — Verification

- [x] 6.1 `npx tsc --noEmit` — exit 0.
- [x] 6.2 `npx eslint` on all five touched files — exit 0, no warnings.
- [x] 6.3 `npx jest --silent` — 118 suites / 1034 tests green.
- [x] 6.4 `openspec validate --all` — 0 failed.
- [x] 6.5 Live database not modified. `git status` shows no change under
      `database/` or `server/database/`.
- [x] 6.6 Archive via the gate — every box above is ticked.

## Recorded, not done

The live 5,000 phantom (`journal_entry_id 45`) is **not** repaired here. It is
scheduled in `live-data-repair` and must run after this change's code fix
lands. The post-repair expectation is GL 7200 = 2,500, not 0 — the account nets
7,500 today and only 5,000 of that is phantom.
