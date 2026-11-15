# C-06 — Layer Key Mismatch: Tasks

## Phase 0 — Prove the defect before touching the code

- [x] 0.1 Write `c06PoReturnLayerKey.test.ts` whose every fixture goes through
      `PurchaseOrder.addReceipt`, so the batch row has the shape production
      writes. **done-when:** the suite fails on unmodified `PurchaseReturn.ts`.
- [x] 0.2 Desynchronise `goods_receipt_items.id` from
      `purchase_order_items.id` in the fixture. **done-when:** the pre-fix
      failure message is
      `Insufficient stock in the source batch for Widget: available 0, required 4`
      — verified, not assumed.
- [x] 0.3 Record the pre-fix result. **done-when:** measured at 4 of 7 failing.

## Phase 1 — Fix the reader

- [x] 1.1 Resolve a PO-source cost layer through `goods_receipt_items.po_item_id`
      instead of comparing `source_id` to a PO line id.
      **done-when:** `c06PoReturnLayerKey.test.ts` passes 7 of 7.
- [x] 1.2 Leave the `PURCHASE` branch resolving `source_id = purchases.id`
      directly, filtered by item and warehouse.
      **done-when:** all four `purchaseReturn` direct-purchase tests pass, and
      `accountingInvariants.test.ts` scenario 13 passes.
- [x] 1.3 Draw down **every** matching layer in batch-id order rather than a
      single `LIMIT 1` row, so a line received across several partial receipts is
      fully returnable.
      **done-when:** `create-then-void is a value-identity operation on inventory`
      passes with the layer snapshot byte-identical after void.
- [x] 1.4 Record each draw in `purchase_return_batches` with its own quantity
      and `location_id`.
      **done-when:** the `records which batch it consumed` test finds the draw
      and its `source_id` equals the receipt item id.

## Phase 2 — Make the old suite non-vacuous

- [x] 2.1 Replace the hand-written `stock_batches` INSERT in
      `purchaseReturn.test.ts` with a call through `addReceipt`.
      **done-when:** the fixture no longer contains `source_id` for a
      `GOODS_RECEIPT` batch.
- [x] 2.2 Add the sequence desync to that fixture.
      **done-when:** **the suite now fails when the reader is reverted** —
      measured, 1 failure. Routing through `addReceipt` alone did NOT achieve
      this; see the proposal.
- [x] 2.3 Re-prove both directions with all three files in place.
      **done-when:** buggy reader → 5 of 22 fail; fixed reader → 22 of 22 pass.

## Phase 3 — Regression guard

- [x] 3.1 Add invariant J, `orphanSourceBatches`, to
      `__tests__/helpers/accountingInvariants.ts`, asserting every
      `PURCHASE` / `GOODS_RECEIPT` / `PRODUCTION` batch resolves to a row in the
      table its type addresses.
- [x] 3.2 Call it from `expectAllInvariantsHold` and update the file header from
      "nine" to "ten" so the docstring stops overclaiming.
      **done-when:** `accountingInvariants.test.ts` passes 33 of 33.
- [x] 3.3 Prove J fires on a planted violation and stays silent on a legitimate
      `ADJUSTMENT` layer.
      **done-when:** a planted orphan batch produces a labelled violation; the
      scoped-out source types produce an empty array.
- [x] 3.4 Run J against `server/database/erp.db` read-only.
      **done-when:** 0 violations — the writer was always correct, so no data
      repair is required by this change.

## Phase 4 — Spec

- [x] 4.1 Remove the `## Known Gaps` section from
      `openspec/specs/batch-source-typing/spec.md`.
      **done-when:** the file no longer asserts a guarantee it lacks.
- [x] 4.2 Add scenarios for the two behaviours that are now guaranteed:
      PO-source resolution, multi-receipt draw-down, and invariant J.
      **done-when:** `openspec validate batch-source-typing --type spec` passes.

## Phase 5 — Verification

- [x] 5.1 `npx tsc --noEmit` — exit 0.
- [x] 5.2 `npx eslint` on the four touched files — exit 0, no warnings.
      (The repo's 1 pre-existing error is in
      `adminBackupDotfileDownload.test.ts`, untouched by this change.)
- [x] 5.3 `npx jest --silent` — 115 suites / 1000 tests green.
      Baseline was 114 / 993; the 7 new tests are this change's.
- [x] 5.4 `openspec validate --all` — 34 passed, 0 failed.
- [x] 5.5 Live database opened read-only only; `git status` shows no change to
      `database/` or `server/database/`.
- [x] 5.6 Archive via the gate — every box above is ticked.

## Recorded for the next change

A regression was introduced and caught during this work: the first version of the
`PURCHASE` branch passed the purchase id straight through as a batch id instead
of filtering `source_id = purchases.id`. It broke 13 tests in
`accountingInvariants.test.ts` (invariant E, and every planted-drift guard that
ends with a `checkF_I`). Phase 1 task 1.2 exists because of it, and it is the
reason that task names an explicit done-when rather than "suite is green".