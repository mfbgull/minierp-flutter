## Context

The Flutter inventory client (`lib/features/inventory/*`) renders the
Stock Movement, Stock by Warehouse, Warehouses, and Physical Count lists as
read-only PlutoGrids built on the shared `PlutoGridScreen` mixin
(`lib/widgets/pluto_grid_screen.dart`). Each grid loads a full list from a
Riverpod provider and clears+appends rows through `syncGridRows`.

Current state per request:

- **Stock Movement** (`stock_movements_provider`, keyed by movement-type):
  returns the full bare array; the grid renders all rows with no paging.
- **Stock by Warehouse** (`stock_balances_provider`): returns every
  item×warehouse balance; toolbar has client-side Search + Refresh only.
- **Warehouses** (`warehouses_provider`): columns bind `w.totalItems` /
  `w.uniqueItems`, but the server `getWarehouses` handler selects
  `SELECT * FROM warehouses` via `WarehouseModel.getAllActive`, which omits
  the aggregate columns — so totals arrive as `0`. The correct aggregate
  query `getStockSummary` already exists on the model.
- **Physical Count** (`physical_counts_provider`): toolbar has Search +
  Refresh only. `inventoryRepository.createPhysicalCount` and
  `POST /inventory/physical-counts` already exist; the client has no create
  dialog/button.

## Goals / Non-Goals

**Goals:**
- Page the Stock Movement grid client-side.
- Let Stock by Warehouse narrow to one warehouse via a toolbar dropdown.
- Show real Total/Unique Items in the Warehouses grid.
- Add a New Count entry point to Physical Count.

**Non-Goals:**
- Server-side pagination of stock movements (no pagination envelope on the
  endpoint; the grid is read-only and fully loaded).
- A new server filter param for stock balances (client-side filtering of
  already-loaded balances is sufficient).
- Editing/deleting counts, audit logging, or batch count creation.

## Decisions

### 1. Client-side pagination via pluto_grid's `PlutoPagination`
Add an opt-in `bool get enablePagination => false` to `PlutoGridScreen`.
When true, `_gridPane` renders a `PlutoPagination(stateManager)` widget
beneath the `PlutoGrid`. Stock Movement overrides it to `true`.
- **Why**: `pluto_grid` 8.1.0 ships `PlutoPagination` for client paging;
  the list is already fully loaded, so no provider/endpoint change is
  needed and the pattern is reusable by any grid.
- **Alternatives considered**: server-side paging (new `page`/`limit`
  envelope + `getPaged` plumbing) — rejected as heavier than a read-only
  grid warrants.

### 2. Warehouse dropdown = client-side filter of loaded balances
Add `stockBalancesWarehouseFilterProvider` (`StateProvider<String?>`; null =
all). The dropdown options come from the existing `warehousesProvider`
(dropdown is independent of loaded balances, so warehouses with zero
balances still appear). `StockByWarehouseScreen._filteredRows` also filters
on `b.warehouseName`/`b.warehouseCode` when a warehouse is selected. Search
and Refresh stay as-is.
- **Why**: `getStockBalances` already returns per-warehouse rows; filtering
  client-side avoids a new endpoint param and a server change.
- **Alternatives considered**: server warehouse query param — rejected as
  unnecessary added surface.

### 3. Warehouses totals: swap one server query (root cause)
In `inventoryController.getWarehouses`, change
`WarehouseModel.getAllActive(db)` → `WarehouseModel.getStockSummary(db)`.
- **Why**: root cause is the missing aggregate columns; `getStockSummary`
  already joins `stock_balances` and computes `total_items` /
  `unique_items`, returning a superset of the current row shape
  (`w.*` + totals, active only). The client grid needs no change — its
  columns already bind the fields.
- **Trade-off**: `getStockSummary` excludes inactive warehouses (matches
  grid intent). No migration: it is a pure SELECT.

### 4. New Count: reuse existing create path
Add a "New Count" `FilledButton` to `PhysicalCountScreen`'s toolbar that
opens a new `new_physical_count_dialog.dart` (warehouse dropdown +
count-date picker + notes). On submit it calls
`ref.read(inventoryRepositoryProvider).createPhysicalCount({...})` and, on
success, invalidates `physicalCountsProvider`.
- **Why**: the repository method and `POST` endpoint already exist; only
  the UI was missing.

## Risks / Trade-offs

- **[Pagination mounts before grid]** `gridStateManager` is `null` on the
  first frame, but `PlutoPagination` needs the manager → expose the manager
  via a `ValueNotifier`/rebuild so the pagination widget mounts once the
  grid `onLoaded` fires. Mitigation: render pagination inside a
  `StatefulBuilder` keyed on manager availability.
- **[getStockSummary shape]** returns active warehouses only; if a screen
  later needs inactive warehouses this would change — out of scope here.
- **[Client-side warehouse filter]** only filters already-loaded balances;
  acceptable since the full balance set is always fetched.

## Migration Plan

No schema/migration. Deploy server change (query swap) and client build
together; the response shape is backward-compatible (superset). Rollback =
revert the controller line (totals revert to `0`).

## Open Questions

- Default page size for Stock Movement pagination (propose 25).
