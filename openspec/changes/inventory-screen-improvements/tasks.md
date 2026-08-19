## 1. Stock Movement pagination

- [x] 1.1 Add opt-in `enablePagination` flag (default false) to `PlutoGridScreen` mixin and render `PlutoPagination(stateManager)` beneath the grid once the state manager is available (use a rebuild trigger for the first frame).
- [x] 1.2 Override `enablePagination => true` in `StockMovementScreen` and pick a default page size (25).

## 2. Stock by Warehouse warehouse filter

- [x] 2.1 Add `stockBalancesWarehouseFilterProvider` (`StateProvider<String?>`, null = all) in `inventory_providers.dart`.
- [x] 2.2 Add a warehouse dropdown to `StockByWarehouseScreen`'s toolbar, options from `warehousesProvider`, defaulting to "All Warehouses".
- [x] 2.3 Filter loaded balances by the selected warehouse in `_filteredRows` (match `warehouseName`/`warehouseCode`); re-apply on dropdown change and keep Search/Refresh working.

## 3. Warehouses totals bug fix (server)

- [x] 3.1 In `inventoryController.getWarehouses`, replace `WarehouseModel.getAllActive(db)` with `WarehouseModel.getStockSummary(db)` so `total_items`/`unique_items` are returned.
- [x] 3.2 Verify the Warehouses grid shows real totals (no client grid change required).

## 4. Physical Count — New Count

- [x] 4.1 Create `new_physical_count_dialog.dart` with warehouse dropdown (from `warehousesProvider`), count-date picker, and notes; on submit call `createPhysicalCount` and show errors on failure.
- [x] 4.2 Add a "New Count" toolbar button to `PhysicalCountScreen` that opens the dialog and invalidates `physicalCountsProvider` on success.
