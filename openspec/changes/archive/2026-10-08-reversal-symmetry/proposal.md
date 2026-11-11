# Reversal Symmetry — PUR-001, C-05

## What Changes

- `models/Purchase.ts` — the `PURCHASE_VOID` movement gains
  `skipAdjustmentFinancialPosting: true`, and its `movement_date` becomes the
  purchase's own date.
- `services/invoiceReturnService.ts` — the restock reversal in `reverseRestock`
  gains the same flag, and the comment that described the leg as the mechanism
  for restoring inventory is corrected.
- `__tests__/reversalSymmetry.test.ts` — new; proves both defects and the fix.
- `__tests__/invoiceReturnVoidsAndPrint.test.ts` — scenario 15 gains a global
  GL 7200 assertion beside its reference-type-scoped checks.
- `__tests__/supplierlessPurchase.test.ts` — `glTotals` documents that callers
  must assert both columns.

Deltas are recorded against `document-void-lifecycle`, `gl-posting-matrix` and
`financial-test-invariants`.

## Why

Voiding a purchase or a sales return posted a **second** inventory entry on top
of voiding the original. The second entry is an `ADJUSTMENT` movement, and every
`ADJUSTMENT` routes to `postFinancialEntryForAdjustment`, which for a removal
posts `Dr 7200 Inventory Shrinkage / Cr 1200 Inventory Asset`.

So a void:

- credited inventory **twice** — GL 1200 ended at a credit balance on a
  debit-normal asset;
- booked a shrinkage expense for goods that were returned or cancelled, not lost;
- and on the purchase path, dated the reversal "today" rather than with the
  purchase, moving the effect into a different — possibly closed — period.

The create-side twins already had this right. `Invoice.ts` and
`PurchaseReturn.ts` both pass `skipAdjustmentFinancialPosting: true`, and
`Invoice.ts` carries a long comment explaining why. The two void paths did not,
and one of them carried a comment stating the defect as if it were the design:
*"recordMovement posts its own balanced financial entry, which restores the
inventory GL."*

## Measured, before the fix

`reversalSymmetry.test.ts` against unmodified `Purchase.ts`, 10 units @ 50:

| after `Purchase.void` | value |
|---|---|
| GL 1200 | `debit 0, credit 500` — inventory reversed 200% |
| GL 7200 | `debit 500` — phantom shrinkage |
| `PURCHASE_VOID` movement_date | `2026-10-08` (today) for a `2026-01-15` purchase |
| `financial_posted` | `1` |

## Would the invariant gate have caught it?

This was the open question from Phase 0, and the answer is **yes** — the earlier
speculation that invariant H might stay green was wrong.

```
AFTER void: H = [{ glBalance: 500, batchVal: 0, legacyVal: 0, opBalance: 0, diff: 500 }]
AFTER void: E violations = 0
```

`recordMovement` decrements `items.current_stock` to zero, so H's `legacyVal`
fallback term drops out rather than cancelling the error. H reports a 500
divergence.

So the gate was never blind here — it was simply **never called on this path**.
`purchaseVoid.test.ts` contains zero `expectAllInvariantsHold` calls and never
exercised a successful void at all; its only two `PurchaseModel.void` calls
assert guard *rejections*. The one place a successful void is asserted
(`models.test.ts:793`) checks the supplier balance and the void attribution, not
GL 1200 or 7200.

That is the same shape as C-06: the guard exists and works, and nothing routes
the defect through it.

## Three blind spots, one pattern

| # | The guard | Why it was blind |
|---|---|---|
| 1 | `glTotals` (`supplierlessPurchase.test.ts:94`) | returns debit and credit separately; callers asserted `debit ≈ 0` only, satisfied while `credit` held the whole error |
| 2 | `glTotalsFor('INVOICE_RETURN', …)` (`invoiceReturnVoidsAndPrint.test.ts:76`) | scoped to two reference types; the phantom leg posts under `stock_adjustment` |
| 3 | the 9-invariant gate | fires correctly, called in 2 of 115 suites and never on a void path |

## Anti-vacuity, both directions

| state | reversalSymmetry + invoiceReturnVoidsAndPrint |
|---|---|
| both fixes reverted | **4 of 13 fail** |
| both fixes applied | 13 of 13 pass |

## Live-data impact — NOT repaired here

`server/database/erp.db` carries `journal_entry_id 45`:
`reference_type='stock_adjustment'`, `reference_id=120`,
`Dr 7200 5000 / Cr 1200 5000`, both lines `voided=0`, from
`stock_movements.id=120` (`reference_doctype='PURCHASE_VOID'`). That is the
5,000 the audit reports.

Repairing it is deliberately **not** part of this change: it must happen after
the code fix lands and its tests pass, otherwise the same bug can regenerate the
entry and there is no way to tell a held repair from a regenerated one. It is
scheduled in `live-data-repair`. Note that GL 7200 nets **7,500** live, not
5,000 — the phantom is 5,000 of it, so the post-repair figure should be 2,500,
not 0.

## Out of scope

- The live-data repair (above).
- `Period protection as a primitive property` — `period-protection-primitive`,
  already authored, covers the related `movement_date` concern from the other
  direction.
- `Production.ts:594,620` posts adjustment legs without the flag. Those are
  production consumption movements where a leg is correct; the new requirement
  asks that each call site declare its intent, which documents them rather than
  changing them.

## Risk and rollback

Low. Both changes add one flag; the `movement_date` change makes a reversal land
in its own period, which is correct but will differ from today's behaviour for
any historical void.

Rollback: revert three files. No migration, no schema change.
