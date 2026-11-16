## 1. Database Schema & Migration

- [x] 1.1 Create `locations` table and seed default warehouse locations
- [x] 1.2 Add `batch_id` surrogate key to `stock_batches` and make `batch_no` unique
- [x] 1.3 Create `batch_stock_by_location` table with `quantity_physical`, `quantity_reserved`, `quantity_available` computed, `status_override`
- [x] 1.4 Create `stock_reservations` table
- [x] 1.5 Create `invoice_return_batches` table
- [x] 1.6 Alter `stock_balances` to add `quantity_physical`, `quantity_reserved`, `quantity_available`
- [x] 1.7 Add `feature_batch_locations` setting flag
- [x] 1.8 Write idempotent backfill migration from existing `stock_batches` → master + location rows
- [x] 1.9 Add composite indexes: `batch_stock_by_location(item_id, warehouse_id, status, quantity_available)`

## 2. Backend: Core Model Updates

- [x] 2.1 Update `StockMovementModel.consumeFromOldestBatches` to read from `batch_stock_by_location`
- [x] 2.2 Update `StockMovementModel.recordTransfer` to consume/deposit per-location quantities
- [x] 2.3 Update `StockMovementModel.voidTransfer` to restore per-location quantities
- [x] 2.4 Update `PurchaseReturnModel.create` to consume from `batch_stock_by_location` and record `location_id` in `purchase_return_batches`
- [x] 2.5 Update `PurchaseReturnModel.voidReturn` to restore per-location quantities
- [x] 2.6 Update `InvoiceModel.reverseStockForItems` to restore per-location quantities and record `invoice_return_batches`
- [x] 2.7 Update `PhysicalCountModel` completion/correction to update `batch_stock_by_location` quantities
- [x] 2.8 Add `StockReservationModel` with create/release/consume/auto-release logic

## 3. Backend: API & Controller Changes

- [x] 3.1 Add batch reconciliation endpoints (`GET /inventory/batch-reconciliation`, `POST /inventory/batch-reconciliation/correct`)
- [x] 3.2 Update stock balance endpoints to return `quantity_physical`, `quantity_reserved`, `quantity_available`
- [x] 3.3 Update batch list endpoint to include location breakdown and effective status
- [x] 3.4 Update purchase return controller to pass `location_id` through to batch consumption
- [x] 3.5 Update invoice return controller to pass `location_id` through to batch restoration
- [x] 3.6 Update transfer controller to use per-location quantities
- [x] 3.7 Add reservation endpoints (create, release, list by document)

## 4. Backend: Batch Status & Allocation Logic

- [x] 4.1 Implement derived batch status function (ACTIVE/BLOCKED/QUARANTINED/EXPIRED/DAMAGED/REJECTED)
- [x] 4.2 Implement per-location status override validation (EXPIRED not overridable)
- [x] 4.3 Update FEFO/FIFO allocation to skip non-ACTIVE locations
- [x] 4.4 Add batch status admin endpoints (halt, unhalt, damage, reject, quarantine)

## 5. Frontend: Model Updates

- [x] 5.1 Update `StockBatch` model to include `locations` array, effective `status`, and deprecated `quantityRemaining`
- [x] 5.2 Update `StockBalance` model to include `quantityPhysical`, `quantityReserved`, `quantityAvailable`, and `locations` breakdown
- [x] 5.3 Update `StockMovement` model to include `location_id` and `location_name`
- [x] 5.4 Add `StockReservation` model
- [x] 5.5 Update API endpoints constants for new/changed routes

## 6. Frontend: UI Screens

- [x] 6.1 Update stock balances grid to show physical/reserved/available columns
- [x] 6.2 Update batch detail screen to show per-location quantities and status overrides
- [x] 6.3 Update item detail `stock_by_warehouse` to expand into locations
- [x] 6.4 Add batch reconciliation screen (drift list + inline correction form)
- [x] 6.5 Update purchase return form to show source batch location breakdown
- [x] 6.6 Update invoice return form to show original sale locations and allow restock location selection
- [x] 6.7 Add reservation list screen (filter by SO, transfer, QC hold)

## 7. Testing & Validation

- [x] 7.1 Unit tests: `batch_stock_by_location` CRUD, computed `quantity_available`
- [x] 7.2 Unit tests: reservation create/release/consume idempotency
- [x] 7.3 Unit tests: batch status derivation and overrides
- [x] 7.4 Unit tests: FEFO/FIFO skips non-ACTIVE locations
- [x] 7.5 Integration tests: purchase return consumes and voids per-location quantities
- [x] 7.6 Integration tests: invoice return restores per-location quantities
- [x] 7.7 Integration tests: transfer void restores source and destination locations
- [x] 7.8 Integration tests: physical count correction updates location quantities
- [x] 7.9 Backfill validation test: existing single-warehouse data produces one location row per batch
- [x] 7.10 End-to-end test: feature flag off → old behavior; feature flag on → new behavior

## 8. Migration & Rollout

- [x] 8.1 Deploy schema migration with feature flag off
- [x] 8.2 Run backfill job and verify via reconciliation endpoint
- [x] 8.3 Deploy backend code with feature flag off; run smoke tests
- [x] 8.4 Flip feature flag on in staging; run full integration suite
- [x] 8.5 Flip feature flag on in production (single-machine deployment: dev database is the live DB; flag on, 0 drift)

Staging smoke (DB clone, flag on): login, batch reconciliation (0 drift),
per-location batch list, reservation create/release, legacy-stock
consumption (no-batch fallback), transfer consume + void (both sides
restored exactly). Fixed during smoke: 6 controllers used never-set
`req.app.get('db')` — now use the imported singleton; flag-on gate no
longer blocks legacy no-batch stock.
- [ ] 8.6 Remove old schema columns (`stock_batches.warehouse_id`, `stock_balances.quantity`) in next release. **Depends on BUG-013** (`docs/bugs.md`). The `feature_batch_locations` flag must first be safe to enable: backfill `batch_stock_by_location` from `stock_batches`, write location rows regardless of the flag, add a drift check, and pass a "legacy DB with batches, flip the flag on, sales still work" test. Only then are the new columns the sole source of truth. Removing the old columns earlier leaves no fallback if the flag is turned on.

  **Deferred 2026-11-14. Preconditions are not met. Do not tick this box
  and do not drop the columns yet.** 8.5 marked the production flip done,
  but that flip is a per-database row, not a code change. The state was
  re-checked on 2026-11-14 by reading each database directly:

  | Database | `feature_batch_locations` |
  |---|---|
  | `database/erp.db` (live dev DB) | `'1'` — on |
  | `build/setup-stage/minierp/data/database/erp.db` (shipped stage) | `'0'` — off |
  | `add-batch-location-model.sql:24` (fresh-DB seed) | `'0'` — off by default |

  So one database has it on, and the migration default still creates new
  databases with it off. The flag default is deliberately left alone here;
  changing it is a separate change with its own plan (drift check, backfill,
  rollback).

  Code still needs the old columns:

  - `StockMovement.resolveAvailableQuantity` reads `stock_balances.quantity`.
    With the flag on, legacy stock that predates batch costing has no
    `batch_stock_by_location` rows, so `quantity_available` is 0 while
    `quantity` holds the real on-hand amount. Dropping the column would stop
    that stock from being consumable. The no-coverage fallback prices it at
    standard cost with `batchId` null and is load-bearing, not dead code.
  - The same column is still read by `Dashboard.ts` (lines 153, 560),
    `PhysicalCount.ts` (380, 392), `Production.ts` (272, 334, 521) and
    `Item.ts` (311) — every one outside the flag-on branch.
  - `CompanyReport.ts:154` reads `stock_batches.warehouse_id`
    (`sb.warehouse_id <> @expiredWarehouseId`) to exclude the EXPIRED
    pseudo-warehouse from sellable stock. Its guard is
    `columnExistsSafe(db, 'stock_batches', 'warehouse_id')`, so it sees the
    column even when the flag is on. That query would break the moment the
    column is dropped.

  Exit criteria before this task can be started:

  1. `feature_batch_locations` is `'1'` in every database, and the seed in
     `add-batch-location-model.sql` is raised to `'1'`.
  2. `GET /inventory/batch-reconciliation` reports zero drift rows on each
     database.
  3. Zero legacy stock without per-location coverage remains, so the
     no-coverage fallback in `resolveAvailableQuantity` is never reached.
  4. No code reads `stock_batches.warehouse_id` or `stock_balances.quantity`;
     the `CompanyReport` sellable-stock query, `Dashboard`, `PhysicalCount`,
     `Production` and `Item` all move to `batch_stock_by_location` or
     `quantity_physical` first.

  **Separate finding — flag defaults (recorded 2026-11-14, no change made):**
  `feature_batch_locations` is `'0'` in two places, so "the flag is on" is not
  a property of the codebase:

  - `add-batch-location-model.sql:24` seeds new databases with `'0'`. Every
    fresh install therefore starts with the batch-location model off, and
    task 8.1–8.5's rollout has to be repeated per database.
  - `build/setup-stage/minierp/data/database/erp.db` holds `'0'` — the
    packaged/stage database shipped to users. Only `database/erp.db` (the dev
    DB) holds `'1'`.

  This is recorded, not repaired. Raising the seed to `'1'` is its own change
  with its own plan (drift check, backfill, rollback) and must land before the
  exit criteria above can be met.

  **BUG-013 update (2026-11-16, head `f4088c6f`).** The code half of the
  precondition is now done. What is fixed:

  - Six write sites no longer gate on the flag; every write moves BOTH sources
    in every flag state (see `docs/bugs.md` BUG-013). The shared fix is
    `StockMovement.mirrorBatchLocationDelta`.
  - The flag-on sellable query reads covered AND uncovered batches (UNION ALL),
    and the residual deduction is per unit, split by the same two attributions
    as the branch, and unfiltered. Three double-count / vanish defects fixed.
  - Migration `127_backfill_batch_stock_by_location.sql` backfills
    `batch_stock_by_location` (and repairs stale rows and the `stock_balances`
    mirrors) on an existing database.
  - A structural guard fails any future write to the batch tables placed behind
    the flag (`batchLocationWriteGuard.test.ts`, zero exceptions).
  - A legacy database upgrades through migration 127 and then sells, returns,
    transfers and voids with invariants A–J holding and zero per-bin drift
    (`bug013LegacyUpgradeRehearsal.test.ts`).

  The full server suite is green in both flag states on the final head:
  **282/282 suites, 2261/2261 tests**. What is still open:

  1. The flag default stays **OFF**. The seed at
     `add-batch-location-model.sql:24` is still `'0'`.
  2. Exit criterion 1 (flag `'1'` in every database and in the seed) is NOT met.
  3. Exit criterion 2 (zero drift on each database) is not verified on the live
     databases, only on the rehearsal fixture. Run
     `GET /inventory/batch-reconciliation` after migration 127 reaches each DB.
  4. Exit criterion 3 (no legacy stock without per-location coverage) is not
     verified on the live databases.
  5. Exit criterion 4 (no code reads `stock_batches.warehouse_id` or
     `stock_balances.quantity`) is NOT met. `CompanyReport.ts:154`,
     `Dashboard.ts`, `PhysicalCount.ts`, `Production.ts` and `Item.ts` still
     read the old columns.

  So do not drop the columns and do not tick this box. The remaining work is
  operational (run the migration, then flip the flag per database) plus the
  read-site migration of exit criterion 4.

Rollout procedure (verified on the dev database):

1. Boot the server once with `feature_batch_locations` unset (off). The
   ledgered chain applies `add-batch-location-model.sql` →
   `fn.runPurchaseReturnBatchesLocationMigration` →
   `fn.backfillBatchLocations` automatically and idempotently.
2. Verify with `GET /inventory/batch-reconciliation` — zero drift rows
   means the backfill is complete. Correct any drift via
   `POST /inventory/batch-reconciliation/correct`.
3. Run the jest suites (`batchLocations`, `batchLocationIntegration`,
   `purchaseReturn`, `physicalCountBatchSync`, `stockTransfer`) — all green
   with the flag off and on.
4. Enable: `UPDATE settings SET value='1' WHERE key='feature_batch_locations'`
   (staging first, then production after smoke tests).
5. Rollback: set the value back to `'0'`; all consumption paths revert to
   legacy `stock_batches.quantity_remaining` behavior, and
   `batch_stock_by_location` rows stay for the next enable.
6. `stock_batches.warehouse_id` / `stock_balances.quantity` removal is a
   later release task — they are still written for backward compatibility.
