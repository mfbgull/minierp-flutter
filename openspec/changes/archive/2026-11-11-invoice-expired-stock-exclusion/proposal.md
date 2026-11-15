## Why

Expired inventory must never be sellable. Today the desktop invoice form contains a deliberate expired-batch **override flow** (`_confirmExpiry` dialog → temporarily null the batch's `expiry_date` via `PATCH /inventory/stock-batches/:id` → save the invoice → restore the dates), and the server accepts `expired_batch_overrides` in `POST /api/invoices`, stamping `override_sale=1`, denormalizing `is_expired_at_sale`, and writing `expiry_notes`. This makes expired stock reachable in valid invoices through both UI and API. Additionally, the invoice item picker lists every active item with no stock/expiry filtering, so items whose only stock is expired appear fully sellable, and `findWarehouseForItem` counts expired stock as available when picking a dispatch warehouse.

## What Changes

- **BREAKING** Remove the expired-batch override flow end-to-end: frontend `_confirmExpiry` override branch, `_expiredBatchOverrides` map, the pre-save PATCH-null loop and post-save restore loop in `_save()`, the `expired_batch_overrides` request field on `POST /api/invoices`, the `override_sale` write on invoice create, and the `denormalizeExpiryInfo` override-merge that stamps `is_expired_at_sale`/`expiry_notes` from overrides. Expired stock becomes unreachable in valid invoices, so "Expired" line labels (`is_expired_at_sale` badges in PDF/print/grid) and the `override_sale` grid column are removed.
- Backend rejects any attempt to sell expired stock on every sale surface (desktop invoice create/update, POS, sales-order→invoice convert, mobile invoice submit) — all already route through `consumeFromOldestBatches`, which excludes expired batches; this change makes that rejection explicit, consistent, and surfaced as a 400 rather than a generic 500.
- Add a **sellable availability** computation (per item+warehouse: non-expired, non-halted, ACTIVE batches) and use it for (a) invoice item-picker filtering — items with zero sellable stock are not selectable, (b) `findWarehouseForItem` warehouse selection so expired stock no longer influences dispatch warehouse choice, and (c) an items endpoint query (`?sellable_only=1`) so the picker can ask the server for sellable items.
- Fix latent SQL defect in `consumeFromOldestBatches` feature-flag path (`sb` alias referenced in the location-rows query without a `stock_batches sb` join) so the FEFO location-consumption path actually executes.
- Returns/reversals keep restoring stock to the original batches (stock accuracy preserved), and the FEFO/expired filters guarantee restored expired quantity is never re-sellable; sellable availability similarly excludes it, so a returned-into-expired-batch item shows zero sellable until a fresh batch exists.

## Capabilities

### New Capabilities
- `expired-stock-sale-blocking`: Expired stock is never sellable — item selection lists exclude items with no sellable (non-expired, non-halted, ACTIVE) stock, every backend sale path rejects expired consumption, FEFO allocates only from non-expired batches, drafts revalidate expiry at save, direct API calls cannot bypass the block, and returns never make expired batches sellable again.

### Modified Capabilities
(none — `openspec/specs/` has no invoice/expiry-sale capability spec today; `inventory-batch-lot-spec` change specs are unapplied drafts, not main specs)
