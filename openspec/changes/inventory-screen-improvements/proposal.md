## Why

The inventory/stock screens in the Flutter client are missing a few
expected interactions and have one data bug, all of which block normal
daily workflows:

- The Stock Movement list can grow long with no paging, forcing the user
  to scroll an unbounded grid.
- The Stock by Warehouse screen cannot be narrowed to a single warehouse,
  so the user must read across every warehouse at once.
- The Warehouses grid shows empty Total Items / Unique Items columns even
  though the columns are defined and the data model carries the fields —
  a server query omits the aggregates.
- The Physical Count screen has no way to start a new count; the create
  endpoint and repository method already exist but the client exposes no
  entry point.

## What Changes

- **Stock Movement pagination**: split the loaded movement rows into
  client-side pages (pluto_grid's `PlutoPagination`) so the grid no longer
  renders one unbounded list.
- **Stock by Warehouse filter**: add a warehouse dropdown to the toolbar
  (populated from the warehouses list) with Search and Refresh buttons.
  Selecting a warehouse filters the grid to that warehouse's balances;
  an "All Warehouses" entry (default) shows every warehouse.
- **Warehouses totals bug fix**: the `GET /inventory/warehouses` endpoint
  returns `SELECT *` (no aggregate columns), so `total_items` /
  `unique_items` always arrive as `0`. Switch the controller to the
  existing `getStockSummary` query that joins `stock_balances` and computes
  the totals. No client grid change needed — the columns already bind the
  fields correctly.
- **Physical Count — New Count**: add a "New Count" toolbar button that
  opens a create dialog (warehouse, count date, notes) and POSTs via the
  existing `createPhysicalCount` repository method, then refreshes the grid.

## Capabilities

### New Capabilities
- `stock-movement-pagination`: Stock Movement grid paginates its loaded rows client-side.
- `stock-by-warehouse-filter`: Stock by Warehouse toolbar exposes a warehouse dropdown (incl. "All Warehouses") that filters the grid; Search and Refresh remain.
- `warehouse-grid-totals`: Warehouses grid displays per-warehouse Total Items and Unique Items.
- `physical-count-create`: Physical Count screen provides a New Count action that creates a count via the existing API.

### Modified Capabilities
<!-- None — no existing specs to amend. -->

## Impact

- `lib/widgets/pluto_grid_screen.dart`: opt-in client pagination support
  added to the shared grid mixin (off by default).
- `lib/features/inventory/stock_movement_screen.dart`: enable pagination.
- `lib/features/inventory/stock_by_warehouse_screen.dart`: warehouse
  dropdown + filter provider; Search/Refresh already present.
- `lib/features/inventory/physical_count_screen.dart`: add New Count
  button; new `lib/features/inventory/new_physical_count_dialog.dart`.
- `server/src/controllers/inventoryController.ts`: `getWarehouses` uses
  `WarehouseModel.getStockSummary(db)` instead of `getAllActive(db)`.
- `server/src/models/Warehouse.ts`: no change (the aggregate query already
  exists).
- `lib/data/repositories/inventory_repository.dart`: reuse existing
  `createPhysicalCount` (no change).
- No DB migration or schema change. No API contract change (response shape
  is a superset of the current `warehouses` row).
