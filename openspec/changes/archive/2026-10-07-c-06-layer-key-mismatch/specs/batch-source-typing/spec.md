# batch-source-typing (Delta)

## ADDED Requirements

### Requirement: Readers resolve a batch through its own namespace
A reader of `stock_batches` SHALL resolve the row by the same key its writer
stamped. For `source_type = 'GOODS_RECEIPT'`, `source_id` addresses
`goods_receipt_items.id`, so a reader holding a `purchase_order_items.id` SHALL
join through `goods_receipt_items.po_item_id` rather than comparing the id
directly. For `source_type = 'PURCHASE'`, `source_id` addresses `purchases.id`
and SHALL be compared directly.

#### Scenario: PO-source return consumes the layer the receipt created
- **WHEN** a purchase return is created against a purchase-order line that was
  received by `addReceipt`
- **THEN** the layer consumed is the one whose `source_id` equals the
  `goods_receipt_items.id` that receipt stamped
- **AND** no layer is consumed when the two sequences do not coincide

#### Scenario: Direct-purchase return keeps resolving purchases.id
- **WHEN** a purchase return is created against a direct purchase
- **THEN** the layer consumed is the one whose `source_id` equals
  `purchases.id` for the same item and warehouse

### Requirement: A layer received across several receipts is drawn down in receipt order
A return against a purchase-order line SHALL draw down every layer that line's
receipts created, in batch-id order, and SHALL NOT take more from any one layer
than it holds.
A purchase-order line may be received across several partial receipts, each
minting its own batch. Every draw SHALL be recorded in
`purchase_return_batches` so void restores exactly what was consumed.

#### Scenario: Return spanning two partial receipts
- **WHEN** a PO line received 6 units in one receipt and 4 in another is fully
  returned
- **THEN** both layers are drawn to zero
- **AND** two rows exist in `purchase_return_batches` with quantities 6 and 4

#### Scenario: Void restores every layer the return touched
- **WHEN** a return that spanned two layers is voided
- **THEN** each layer's `quantity_remaining` returns to its pre-return value and
  no other batch changes

### Requirement: Source-namespace orphans are reported, not ignored
Invariant J (`orphanSourceBatches`) SHALL assert that every `stock_batches` row
whose `source_type` is `PURCHASE`, `GOODS_RECEIPT` or `PRODUCTION` has a
`source_id` resolving to a row in the table that type addresses. It SHALL be part
of `expectAllInvariantsHold`, and its master assertion SHALL be covered by a
planted-drift guard.

`ADJUSTMENT`, `RETURN`, `OPENING`, `TRANSFER` and `RECON` rows are deliberately
out of scope: an adjustment layer created from a positive stock movement has no
source document by design, and the others legitimately reference a return header
or a sibling batch rather than a purchase or receipt.

#### Scenario: A batch pointing at a deleted receipt is reported
- **WHEN** a `GOODS_RECEIPT` batch has a `source_id` with no matching
  `goods_receipt_items` row
- **THEN** `orphanSourceBatches()` returns a violation naming the batch
- **AND** `expectAllInvariantsHold` throws

#### Scenario: Adjustment layers are not false positives
- **WHEN** a positive stock movement creates an `ADJUSTMENT` layer with a
  `source_id` that resolves to no purchase, receipt or production order
- **THEN** `orphanSourceBatches()` returns an empty array

### Requirement: Cost-layer fixtures use the production writer
A test fixture that needs a PO-received cost layer SHALL obtain it through
`PurchaseOrder.addReceipt`. It SHALL NOT hand-write a `stock_batches` row, and
it SHALL NOT rely on `goods_receipt_items.id` coinciding with
`purchase_order_items.id`.

Rationale: on a pristine database both autoincrement sequences start at 1 and
advance in lockstep, so a wrong-key reader matches by accident. Routing the
fixture through `addReceipt` alone is not sufficient — the collision still hides
the defect. A fixture SHALL deliberately desynchronise the two sequences.

#### Scenario: A wrong-key reader fails against the fixture
- **WHEN** `PurchaseReturn` is reverted to keying a PO-source layer lookup on
  `purchase_order_items.id`
- **THEN** at least one test in `purchaseReturn.test.ts` fails

#### Scenario: The correct reader passes
- **WHEN** the reader resolves through `goods_receipt_items`
- **THEN** every PO-source return test passes