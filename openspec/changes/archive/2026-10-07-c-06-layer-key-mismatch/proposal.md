# C-06 — PO-source purchase returns resolve the wrong cost layer

## Why

A purchase return against a purchase order failed 100% of the time. The reader
looked up the cost layer with `source_id = purchase_order_items.id`, while
`PurchaseOrder.addReceipt` stamps every batch with the
`goods_receipt_items.id` it just inserted. Those are independent autoincrement
sequences.

The audit (C-06, CRITICAL) also records that the suite was green throughout.
That part is now understood and is the more interesting half of this change.

## Why the suite was green

`purchaseReturn.test.ts` hand-wrote its own `stock_batches` row using
`source_id = poItemId` — a shape production never writes. The fixture asserted
against itself.

Replacing that fixture with a call through `addReceipt` was **not sufficient**.
On a pristine in-memory database both sequences start at 1 and advance in
lockstep, so `source_id = 1` still matched `goods_receipt_items.id = 1`. The
suite passed against the unfixed reader. Only after deliberately
desynchronising the sequences did the defect appear.

That is `known-issues.md` §"a green suite bounds the questions it asks" in its
narrowest form: the fixture encoded the assumption that made the bug invisible.

## Measured

Both directions, run against this working tree:

| state | `c06PoReturnLayerKey.test.ts` | `purchaseReturn.test.ts` |
|---|---|---|
| reader reverted to `source_id = poItem_id` | 4 of 7 fail | 1 fails |
| reader fixed | 7 pass | 15 pass |

Pre-fix failure message, verbatim:

```
Insufficient stock in the source batch for Widget: available 0, required 4.
Goods already sold cannot be returned to the supplier.
```

## Live-data finding

Invariant J run against `server/database/erp.db` (read-only) reports **0
violations** — every `GOODS_RECEIPT` batch resolves to a real receipt item, so
the writer has always been correct and no data repair is needed.

However, **both** live `GOODS_RECEIPT` batches have a `source_id` that also
happens to be a valid `purchase_order_items.id` (batches #47 and #51, both
`source_id` colliding with a PO line). The audit predicted *"where ids
coincidentally collide, it silently consumes another receipt's layer (saved only
by the item_id guard)"*. On this data the old lookup would have thrown rather
than consumed a wrong layer, because both layers are already at zero
`quantity_remaining` — but the collision is real, and it means the defect's
failure mode on any given database is data-dependent rather than guaranteed.

## What changes

- `models/PurchaseReturn.ts` — resolve a PO-source layer by joining
  `goods_receipt_items` on `po_item_id`, and draw down every matching layer in
  batch-id order instead of a single `LIMIT 1` row.
- `__tests__/purchaseReturn.test.ts` — obtain the layer through `addReceipt`,
  and desynchronise the two id sequences.
- `__tests__/c06PoReturnLayerKey.test.ts` — new; proves the defect and the fix.
- `__tests__/helpers/accountingInvariants.ts` — invariant J,
  `orphanSourceBatches`, added to the master gate.
- `specs/batch-source-typing/spec.md` — the guarantee is now true end-to-end.

## Out of scope

- The `## Known Gaps` note this change closes was added in Phase 0; it is
  removed and replaced by real scenarios.
- PUR-007 (a receipt naming another PO's line item) is a separate defect on the
  same file and is tracked in `cross-document-reference-guards`.
- `inventory-batch-lot-spec` is a BREAKING rewrite of the batch substrate. This
  change deliberately does **not** touch `batch_stock_by_location`; it fixes the
  legacy-path key only.

## Risk and rollback

Risk is low: the reader resolves to the same layer the writer named, and the
`PURCHASE` branch is unchanged in behaviour. The behavioural widening is that a
PO-source return may now consume **several** layers in one go instead of one.

Rollback is a single-file revert of `models/PurchaseReturn.ts`. No migration, no
schema change, no data change.

## Verification

- `npx jest --silent` — 115 suites / 1000 tests, all green
- `npx tsc --noEmit` — exit 0
- `npx eslint` on the four touched files — exit 0, no warnings
- `openspec validate --all` — 34 passed, 0 failed
- Invariant J against `server/database/erp.db` — 0 violations