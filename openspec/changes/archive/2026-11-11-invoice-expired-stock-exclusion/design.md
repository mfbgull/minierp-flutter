## Context

All sale surfaces already route stock allocation through a single FEFO allocator, `StockMovementModel.consumeFromOldestBatches` (`server/src/models/StockMovement.ts`), which filters out expired (`expiry_date < today`), halted, and non-ACTIVE batches on both the feature-flagged `batch_stock_by_location` path and the legacy `stock_batches` path. So expired stock is *mostly* blocked — the reachable holes are:

1. **Desktop override flow** (`lib/features/sales/sales_invoice_form_page.dart`): `_confirmExpiry()` offers an "override" action; `_save()` then PATCHes each overridden batch's `expiry_date` to `null` (`updateBatchExpiry` → `PATCH /inventory/stock-batches/:id`), posts the invoice with `expired_batch_overrides`, and restores the dates in a `finally` loop. The server sets `override_sale=1`, and `denormalizeExpiryInfo` merges the override dates to stamp `invoice_items.is_expired_at_sale` and `invoices.expiry_notes` — the source of the "Expired / sold after expiry" labels in PDF/print/grid.
2. **Unfiltered item picker**: `invoiceItemsProvider` fetches all active items (`PagedRequest(limit: 10000)`); `_searchPool` filters only `isActive`. Items whose entire stock is expired are selectable.
3. **Warehouse selection counts expired stock**: `InvoiceModel.findWarehouseForItem` picks by `stock_balances.quantity`, which includes expired/halted stock.
4. **Latent SQL defect**: on the feature-flag path, the per-batch location query (`StockMovement.ts:744`) references `sb.expiry_date` without joining `stock_batches sb` — the FEFO location-consumption branch would throw.
5. **Reversal semantics**: `reverseStockForItems` restores to original batches without expiry checks (correct for stock truth), but nothing ensures restored expired quantity is excluded from *availability* — `stock_balances.quantity` counts it.

Key surfaces to touch: `invoiceController.createInvoice/updateInvoice`, `posController.createPOSSale`, `SalesOrder` invoice-convert consumption, `MobileInvoice.submitInvoice` (delegates to `recordBatchMovement` → same allocator), `ItemModel.getAll`/items endpoint, `sales_invoice_form_page.dart`, `invoice_pdf.dart`, `invoice_print_preview_page.dart`, `sales_grid_columns.dart`, i18n keys, and tests under `server/src/__tests__/`.

Constraint: accounting invariant E in `accountingInvariants.test.ts` asserts `stock_balances.quantity == Σ stock_batches.quantity_remaining` per item/warehouse — availability must be a *computed read* (SQL expression), never a mutation of stock tables.

## Goals / Non-Goals

**Goals:**
- Expired stock unreachable in valid invoices on every surface (UI + direct API).
- Items with zero sellable stock not selectable in the invoice picker.
- Consistent, explicit 400 rejection (naming item + shortfall) when a line can't be satisfied from non-expired batches.
- FEFO allocates only from non-expired batches, earliest non-expired expiry first, spanning batches when needed.
- Draft revalidation falls out of save-time re-consumption; returns restore stock truth but never sellability.
- Remove the override flow and expired-sale presentation end-to-end.
- Fix the `sb` alias SQL defect so the feature-flag FEFO path executes.

**Non-Goals:**
- Disposal/write-off workflow for expired stock (separate change).
- Changing `stock_balances.quantity` semantics or breaking invariant E — availability stays a computed read.
- The unapplied `inventory-batch-lot-spec` change (reservation/quarantine model); this change builds on current code only.
- Blocking *near-expiry* sales — near-expiry warnings stay as-is.
- Dropping the `override_sale`/`is_expired_at_sale`/`expiry_notes` columns (kept for historical rows; code stops writing them).

## Decisions

### D1. Availability is a computed SQL expression, shared by picker and backend
Introduce a single SQL fragment (or prepared helper, e.g. `StockMovementModel.getSellableAvailability(db, itemId?, warehouseId?)`) computing, per item+warehouse:
- feature flag ON: `SUM(bsl.quantity_available)` over locations joined to batches with `sb.halted=0 AND COALESCE(bsl.status_override,'ACTIVE')='ACTIVE' AND (sb.expiry_date IS NULL OR sb.expiry_date >= date('now'))`;
- flag OFF: `SUM(sb.quantity_remaining)` from `stock_batches` with the same non-expired/non-halted filter;
- plus legacy non-batch-tracked stock (`stock_balances.quantity` minus batch-tracked quantity, i.e. rows with no batch movements) so plain items remain sellable.

*Rationale:* one definition of "sellable" used by the items endpoint, the picker, and warehouse selection prevents picker-vs-backend disagreement (spec: "Picker list matches backend rules"). Computed read preserves invariant E; a persisted `sellable_qty` column would need event-time maintenance and could drift.
*Alternative rejected:* per-item `GET /items/:id/availability` N+1 calls from the picker — slower and still needs a list filter for the dropdown.

### D2. Items endpoint gains `?sellable_only=1` + `sellable_qty` field; picker switches to it
`ItemModel.getAll` gains a sellable-only filter and returns `sellable_qty` per item (LEFT JOIN the availability aggregate). `invoiceItemsProvider` requests the filter; `_searchPool` keeps its active filter as defense-in-depth. `Item` model in Flutter gains an optional `sellableQty` field (display only, e.g. hint in the dropdown).

*Rationale:* keeps one list endpoint (no new route), reuses pagination, and the picker's 10k-item fetch becomes smaller. UI change is minimal — no new screen.
*Alternative rejected:* client-side filtering by fetching all batches for all items — heavy and races with backend rules.

### D3. Override flow removed, not tightened
Remove `_confirmExpiry`'s override branch (keep/adjust the near-expiry warning), `_expiredBatchOverrides`, the PATCH-null/restore loops, the `expired_batch_overrides` body field, `override_sale` write, and the override-merge in `denormalizeExpiryInfo` (keep denormalizing `expiry_date` of consumed non-expired batches for info display). Backend: drop the field from the accepted body; since validation is allow-list based (zod), an unexpected field either 400s or is stripped — verify and make it explicitly rejected to fail loud. Remove "Expired" badges in PDF/print and the `override_sale` grid column; delete unused i18n keys (`overrideExpiredSale`, `overrideExpiredBody`, `batchOverrideCleared`, `soldAfterExpiry`; keep `nearExpirySaleWarning`).

*Rationale:* the override is the bypass vector; user requirement is "never sellable". Historical invoices keep their columns; only new writes stop. `expiry_date` denormalization stays because it drives legitimate near-expiry display on invoices.
*Alternative rejected:* permission-gate the override (e.g. admin-only) — still violates the invariant "expired inventory must never be sellable".

### D4. Explicit 400 with item name + shortfall; typed error surfaced by controllers
`consumeFromOldestBatches` already throws when only blocked batches exist. Standardize: define a `SellableStockUnavailableError` (item name, requested qty, sellable qty) thrown inside the transaction when a line can't be satisfied from non-expired batches. Controllers catch it and return 400 `{error: "<item>: sellable stock 60, requested 100 (expired batches excluded)"}`. Update catch blocks in `createInvoice`, `updateInvoice`, `createPOSSale`, SO-convert, and mobile submit (mobile currently surfaces model errors as its message — check its catch; ensure 400 not 500).

*Rationale:* a 500 "Failed to create invoice" hides the cause; the user must know *which* item and *why*. Typed error avoids string-matching across five catch blocks.
*Alternative rejected:* pre-validating each line before the transaction with a separate availability query — duplicate logic; the allocator's throw is the authoritative check (race-safe within the transaction).

### D5. `findWarehouseForItem` uses sellable availability
Warehouse selection order switches from `stock_balances.quantity` to the sellable-availability aggregate (same SQL fragment as D1). `MobileInvoice.findWarehouseForItem` gets the same treatment (it currently selects by `stock_balances.quantity` too).

*Rationale:* otherwise the sale may pick a warehouse whose stock is all expired, then fail with a misleading error, or worse dispatch from the wrong place.
*Alternative rejected:* leaving as-is — the error message would name a shortfall in a warehouse that never had sellable stock, confusing users.

### D6. FEFO location-consumption SQL fix
In the feature-flag path, join `stock_batches sb` into the location-rows query (or filter via the already-fetched batch row's expiry since the outer loop already holds `batch.expiry_date` — prefer filtering in the outer loop to avoid the join entirely). Covered by a dedicated test with the feature flag ON.

*Rationale:* simplest correct fix; outer-loop filter removes the aliasing bug class.

### D7. Returns: restore truth, exclude from sellable
No change to `reverseStockForItems` restoration (stock accuracy). Sellability is already excluded by the FEFO filter, and D1's availability excludes expired batches from the picker/warehouse choice. Add integration tests covering: return into a now-expired batch → availability unchanged; invoice update reverse+re-consume with a since-expired batch → 400 with invoice state intact.

*Rationale:* minimal diff; the system-level invariant (expired ⇒ not sellable) is enforced at consumption + availability, not at reversal.
*Alternative rejected:* refusing to return expired-batch goods — breaks stock truth and customer-credit flows; expiry blocking is the right layer.

### D8. Columns kept, writes stopped (no destructive migration)
`override_sale`, `is_expired_at_sale`, `expiry_notes` columns remain for historical rows; code stops writing `override_sale`/`is_expired_at_sale`/notes-from-overrides. No new migration needed (no schema change). `updateBatchExpiry` repository/route stays (legitimate batch-management use), but consider rejecting `expiry_date: null` on a batch with remaining stock — defer to implementation as a guard task (spec: no mechanism to unblock expired sales via PATCH).

*Rationale:* avoids a destructive migration and preserves audit history; AGENTS.md requires migrations only for schema changes — there are none.

## Risks / Trade-offs

- [Picker list may lag reality] availability snapshot at fetch time → acceptable: backend still rejects at save; picker refresh on provider re-fetch; error message from D4 explains.
- [Legacy non-batch-tracked stock double-count] availability adds `stock_balances` minus batch-tracked quantity — must not double count batch-tracked items → derive legacy portion as `stock_balances.quantity − Σ(all batch qty_remaining)` floored at 0, computed per item+warehouse; unit-tested both flag states.
- [Feature-flag divergence] two availability SQL paths must stay in lockstep → single helper returning both; tests run both flag states (existing `batchLocations.test.ts` pattern).
- [Removal breaks muscle memory / historical UI] users who relied on override → product decision already made (expired never sellable); PDFs of historical invoices keep labels via stored `is_expired_at_sale` values? — no: PDF renders from stored fields, so historical rows still render labels unless gated. Decide: render stored `is_expired_at_sale` only for historical rows (data-driven, keep) vs remove label entirely. **Choose: keep rendering driven by stored data** (historical truth), remove the code path that *creates* new ones. Low risk, honest history.
- [Performance] availability aggregate over `stock_batches` per items-list call → existing partial index `idx_stock_batches_expiry` plus `(item_id, warehouse_id)`; verify with EXPLAIN QUERY PLAN; list is paged.
- [Mobile submit error surfacing] mobile controller currently maps model errors to a generic shape → verify and map typed error to 400; covered in tasks.

## Migration Plan

Backend-first, single deploy (no schema change):
1. Add `SellableStockUnavailableError` + allocator hardening (D4/D6) + availability helper (D1) with tests — deployable independently, behavior-compatible.
2. Items endpoint filter/field (D2), `findWarehouseForItem` switch (D5).
3. Remove override acceptance server-side (D3) — after frontend stops sending it.
4. Frontend: picker switch, override-flow removal, label/column/i18n cleanup.
Rollback: revert commits per step; no data migration to undo. Steps are ordered so the frontend never sends a field the backend has already dropped (step 3 after 4 in the same release train, or field rejection is safe because it lands as 400 → old clients fail loud, acceptable for a deliberate BREAKING removal).

## Open Questions

- Should `PATCH /inventory/stock-batches/:id` reject setting `expiry_date` to null (or past) on a batch with remaining stock, as defense-in-depth? Leaning yes — trivial guard, closes the manual unblock vector. (Resolved during implementation; add spec scenario only if behavior becomes normative.)
