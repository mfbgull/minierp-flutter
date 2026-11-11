## 1. Backend availability core

- [x] 1.1 Add `getSellableAvailability` helper to `StockMovementModel` (per item+warehouse SUM over non-expired `expiry_date >= date('now') SQL fragment`, non-halted, ACTIVE batches; both feature-flag paths + legacy non-batch-tracked portion `stock_balances.quantity − Σ batch qty_remaining`, floored at 0) — computed read only, prepared statements, no table mutation
- [x] 1.2 Extend `ItemModel.getAll` with `sellable_only` filter and return `sellable_qty` per item; wire `?sellable_only=1` through `GET /api/items` route + controller + zod query schema
- [x] 1.3 Switch `InvoiceModel.findWarehouseForItem` and `MobileInvoice.findWarehouseForItem` to order warehouses by sellable availability instead of `stock_balances.quantity`

## 2. Backend sale rejection

- [x] 2.1 Define `SellableStockUnavailableError` (item name, requested qty, sellable qty) in a shared server types/errors module; throw it from `consumeFromOldestBatches` (replacing/augmenting the generic throw) when batch stock exists but is all expired/halted/blocked, and when shortfall remains
- [x] 2.2 Map the typed error to HTTP 400 `{error: "<item>: sellable stock X, requested Y (expired batches excluded)"}` in `invoiceController.createInvoice` catch block
- [x] 2.3 Same 400 mapping in `invoiceController.updateInvoice` catch block
- [x] 2.4 Same 400 mapping in `posController.createPOSSale` catch block (verify current catch; today it 500s)
- [x] 2.5 Same 400 mapping in `salesController`/`SalesOrder` SO→invoice convert path
- [x] 2.6 Same 400 mapping in `mobileInvoiceController.submitInvoice` (verify current error envelope; keep mobile error shape but message from typed error)

## 3. Backend override-flow removal

- [x] 3.1 Remove `expired_batch_overrides` from `createInvoice` accepted body/destructuring and the `override_sale` computation passed to `InvoiceModel.createInvoice` (always 0)
- [x] 3.2 Remove the `expiryOverrides` parameter and override-merge from `InvoiceModel.denormalizeExpiryInfo`; keep denormalizing `expiry_date` of consumed batches (drop `is_expired_at_sale` writes and `expiry_notes` generation)
- [x] 3.3 Add guard in `PATCH /inventory/stock-batches/:id` handler: reject `expiry_date` null or past-date on a batch with `quantity_remaining > 0` with 400 (closes manual unblock vector; keep legitimate future-date edits)
- [x] 3.4 Verify zod body schema for invoice create strips/unknown-handles `expired_batch_overrides` so old clients sending it get a deterministic, logged 400 or safe ignore — no override behavior

## 4. FEFO location-path SQL fix

- [x] 4.1 Fix `StockMovement.ts` location-rows query (~line 744): remove the `sb.`-aliased predicates (outer loop already holds the batch row and its `expiry_date`); filter expired batches in the outer batch selection, keep location rows filtered only by `status_override`/`quantity_available`
- [x] 4.2 Add regression test: feature flag ON + FEFO item with expired batch → consumption skips it and succeeds from non-expired batch (exercises the previously-broken query path)

## 5. Frontend picker filtering

- [x] 5.1 Update `invoiceItemsProvider` to request the sellable filter (reuse the same endpoint; add `sellable_only` param support through the repository `PagedRequest`/query builder)
- [x] 5.2 Add optional `sellableQty` to the Flutter `Item` model (`fromJson`, no `toJson` write needed for picker) and show it as a hint in the item select (e.g. "sellable: N")
- [x] 5.3 Keep `_searchPool` active-item filter as defense-in-depth; refresh picker data when the form reopens (existing provider invalidation)

## 6. Frontend override-flow removal

- [x] 6.1 Remove the override branch from `_confirmExpiry` (retain/adjust near-expiry warning flow; expired batches now surface via backend 400)
- [x] 6.2 Remove `_expiredBatchOverrides` field, the pre-save PATCH-null loop and post-save restore loop in `_save()`, and the `expired_batch_overrides` entry in `_buildBody()`
- [x] 6.3 Remove `override_sale` column from `sales_grid_columns.dart` and its references in `sales_screen.dart`
- [x] 6.4 Remove expired-sale labeling: `isExpiredAtSale`-driven red "Expired (sold after expiry)" text in `invoice_pdf.dart` and `invoice_print_preview_page.dart` — keep rendering only when stored historical data says so (data-driven, no new writes produce it); keep plain expiry-date display
- [x] 6.5 Remove now-unused i18n keys (`overrideExpiredSale`, `overrideExpiredBody`, `batchOverrideCleared`, `soldAfterExpiry`) from arb files; keep `nearExpirySaleWarning`

## 7. Tests — the 7 scenarios

- [x] 7.1 Scenario 1 (only expired stock): items endpoint with `sellable_only=1` excludes item whose batches are all expired; item included once a non-expired batch exists (mixed scenario 2) with correct `sellable_qty` (60 not 260 when 60 non-expired + 200 expired)
- [x] 7.2 Scenario 3 (FEFO multi-batch): sale spanning two non-expired batches consumes earliest-expiry batch first (40 then 10 of 50) — extend existing FEFO tests in `models.test.ts`
- [x] 7.3 Scenario 4 (insufficient non-expired): invoice create with qty 100 when only 60 non-expired + 200 expired → 400 naming item/shortfall, stock unchanged, no movements/ledger/GL rows
- [x] 7.4 Scenario 5 (expiry mid-draft): create draft invoice line against batch expiring before save date → update/save returns 400; simulate via backdated `expiry_date` update then invoice update re-consume
- [x] 7.5 Scenario 6 (API bypass): direct `POST /api/invoices` and `POST /api/pos/sale` with only-expired stock → 400; `expired_batch_overrides` payload does not bypass (rejected or inert)
- [x] 7.6 Scenario 7 (returns): return sale whose batch expired after sale → stock restored to batch, sellable availability unchanged, new invoice line for that qty rejected; invoice update reverse+re-consume with since-expired batch → 400, invoice state intact
- [x] 7.7 Guard test: `PATCH /inventory/stock-batches/:id` with null/past `expiry_date` on batch with remaining stock → 400; allowed when `quantity_remaining = 0`
- [x] 7.8 Both feature-flag states for availability + consumption tests (ON via `batchLocations` test pattern, OFF default) — no divergence between paths
- [x] 7.9 Accounting invariant E still passes (`stock_balances.quantity == Σ stock_batches.quantity_remaining` per item/warehouse) — run `accountingInvariants.test.ts` unchanged

## 8. Verification

- [x] 8.1 `cd server && npm run typecheck && npm run lint` — zero errors
- [x] 8.2 `cd server && npx jest` (or configured test command) — full suite green including new scenario tests (2026-11-11: 265/265 suites, 2108/2108 tests passed)
- [x] 8.3 `flutter analyze` — zero issues (2026-11-11: No issues found)
- [x] 8.4 `flutter test` — green (update any widget tests referencing removed override UI/columns/i18n keys) (2026-11-11: 1138 passed, 1 skipped)
- [x] 8.5 Manual smoke via node script from `server/`: seed item with one expired batch → `GET /api/items?sellable_only=1` excludes it; `POST /api/invoices` 400s on attempt to sell it (DB queries via node only, no sqlite3 CLI, per project memory)
