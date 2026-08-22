# batch-source-typing Specification

## Purpose
TBD - created by archiving change inventory-integrity. Update Purpose after archive.
## Requirements
### Requirement: Disjoint source_type namespaces
`stock_batches.source_type` SHALL be constrained to a widened enum — at minimum `('PRODUCTION','PURCHASE','GOODS_RECEIPT','RETURN','ADJUSTMENT','OPENING','TRANSFER','RECON')` — and each writer SHALL use the single value matching its true origin. `goods_receipt_items.id`, `purchases.id` and reconciliation runs SHALL never share one `source_type` value.

#### Scenario: Goods receipt batch is distinguishable from direct-purchase batch
- **WHEN** `PurchaseOrder.receiveGoods` creates a batch
- **THEN** it is stored with `source_type='GOODS_RECEIPT'` and `source_id = goods_receipt_items.id`
- **AND** no query filtering `source_type='PURCHASE'` can ever match a goods-receipt batch

### Requirement: Existing rows re-stamped by migration
The widening migration SHALL rebuild the table and re-stamp all existing rows: batches whose `source_id` resolves to `goods_receipt_items` become `'GOODS_RECEIPT'`; synthetic reconciliation rows (`source_id = 0`) become `'RECON'`; direct-purchase rows remain `'PURCHASE'`.

#### Scenario: Migration is idempotent and lossless
- **WHEN** the migration runs against the live database
- **THEN** every existing batch row survives with its quantities and costs unchanged
- **AND** re-running the migration changes nothing

#### Scenario: Purchase delete lookup can no longer cross namespaces
- **WHEN** `Purchase.delete` looks up its batch with `source_type='PURCHASE' AND source_id = purchaseId`
- **THEN** only a batch genuinely created by that purchase can match, regardless of how large `goods_receipt_items` has grown

