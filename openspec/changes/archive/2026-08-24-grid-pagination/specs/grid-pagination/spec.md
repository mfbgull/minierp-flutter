# Grid-Wide Server-Side Pagination + Status-Strip Removal

Reference behavior: the **suppliers** screen (`lib/features/suppliers/suppliers_screen.dart`).
Suppliers is server-paginated: `GET /suppliers` returns `{ success, data: [...items...], pagination: {...} }`
— **flat**, with `data` as the item list and `pagination` a sibling of `data` (NOT nested under it;
`getPaged` in `lib/data/repositories/repository_client.dart` parses `data` as a list and reads
`pagination` off the envelope body, so a nested `{ data: { items, pagination } }` throws
`'Expected a list response'`). This is the `PagedResponse` envelope in
`lib/data/repositories/paged_request.dart`; the screen unwraps
it via `gridRowsFrom`, column sorts map to a server whitelist via `onGridSorted`, and a
`ServerPaginationBar` (`lib/widgets/pagination_bar.dart`) renders beneath the grid — "Page X of Y ·
N items", a per-page selector (10/25/50/100), and prev/next buttons. The shared mixin currently also
renders the keyboard-hint `GridStatusBar` strip above that bar, which is the "strip above the
pagination" to be removed.

Current state recap:

- The shared mixin `PlutoGridScreen` (`lib/widgets/pluto_grid_screen.dart`) already has a
  **client-side** pager (`enablePagination` + `createFooter` → `PlutoPagination`) used only by the
  Stock Movement screen (`lib/features/inventory/stock_movement_screen.dart`, with
  `showStatusBar => false`). Stock movement's pager is page-number buttons only — no item count,
  no per-page selector.
- 5 screens already paginate **server-side** with `ServerPaginationBar`: suppliers, customers,
  employees, payments, activity log (offset-paged). All still show the `GridStatusBar` strip above
  their bar.
- ~13 other mixin screens load full arrays (no pagination): items, stock balances
  (stock-by-warehouse), physical counts, sales orders, quotations, purchase orders, purchases,
  purchase returns, invoice returns, production, BOM, demand forecast, and Stock Movement (client
  pager today).
- 2 screens use PlutoGrid **directly** (no mixin) and load full arrays: Sales
  (`lib/features/sales/sales_screen.dart`, `GET /invoices`) and Expenses
  (`lib/features/expenses/expenses_screen.dart`, `GET /expenses`). The expenses endpoint is already
  server-paginated server-side but returns a snake_case `pagination` block
  (`current_page/total_pages/total_expenses/per_page`, default limit 10) that the client ignores.
- Report screens, form pages, and detail-tab grids use PlutoGrid directly for aggregates/edit
  lines — out of scope.

---

## ADDED Requirements

### Requirement: Stock movements paginate server-side like suppliers

The Stock Movement screen SHALL page through movements on the server and render the
`ServerPaginationBar` beneath the grid, replacing its current client-side `PlutoPagination` pager.

- Convert `GET /inventory/stock-movements` (`server/src/controllers/inventoryController.ts` →
  `StockMovementModel.getAll`) to the paged pattern: parse `page`/`limit` (and keep the existing
  `movement_type` filter), return the flat envelope `{ success, data: [...rows...], pagination: {
  currentPage, totalPages, totalItems, hasNext, hasPrev } }` (data = list, pagination a sibling),
  and add a sort-column whitelist.
- Client: `stockMovementsProvider` becomes a `FutureProvider.family<PagedResponse<StockMovement>, String?>`
  built on `PagedRequest`; the screen unwraps via `gridRowsFrom`, renders
  `ServerPaginationBar` (`if (page != null)`), maps column sorts server-side, and drops its
  `enablePagination`/`showStatusBar` overrides.

#### Scenario: Movements grid shows server pages

- **WHEN** the Stock Movement screen loads with more movements than the page size
- **THEN** the grid shows one page of movements with a `ServerPaginationBar` beneath it showing "Page X of Y · N movements" and a per-page selector

#### Scenario: User pages through movements

- **WHEN** the user clicks next/prev or a per-page size on the bar
- **THEN** the screen refetches the corresponding page from `GET /inventory/stock-movements` without dropping the active movement-type filter

#### Scenario: Movement-type filter resets paging

- **WHEN** the user changes the movement-type filter
- **THEN** the provider refetches with the filter applied and pagination restarts at page 1 (including the existing "back to All" refetch of the null-keyed family instance)

#### Scenario: Client pager removed

- **WHEN** the Stock Movement grid mounts
- **THEN** no in-grid `PlutoPagination` footer renders (replaced by the `ServerPaginationBar`)

### Requirement: Data-heavy PlutoGrid grids paginate server-side

Each of the following plain-list screens SHALL be converted to the same server-side paging pattern
(endpoint conversion + `PagedResponse` provider + `ServerPaginationBar` + server-side sort/search
per the parity requirements below):

| Screen | Endpoint | Client provider | Notes |
| --- | --- | --- | --- |
| Items | `GET /inventory/items` | `itemsProvider` (`lib/features/inventory/inventory_providers.dart`) | Already sends `search` server-side; add page/limit + sort. Keep the low-stock toggle working (see edge case below). |
| Stock by Warehouse (stock balances) | `GET /inventory/stock-balances` | `stockBalancesProvider` | Search + warehouse filter move from client-side providers to server query params (`search`, `warehouse_code`). |
| Physical Counts | `GET /inventory/physical-counts` | `physicalCountsProvider` | Client-side search moves server-side. |
| Sales Orders | `GET /sales/sales-orders` | `salesOrdersProvider` | |
| Quotations | `GET /sales/quotations` | quotations provider | |
| Purchase Orders | `GET /purchase-orders` | purchase-orders provider | |
| Purchases | `GET /purchases` | purchases provider | |
| Purchase Returns | `GET /purchases/returns` | purchase-returns provider | |
| Invoice Returns | `GET /invoices/returns` | `invoiceReturnsProvider` | |
| Production | `GET /productions` | production provider | |
| BOM | `GET /bom` | BOM provider | |
| Demand Forecast | `GET /forecasts/demand` | forecast provider | No SQL model — the handler generates forecasts in memory (`generateAllForecasts()`), filters in JS, and returns the full array. Pagination = filter-then-slice in the handler + pagination block (no `getAll`/COUNT change). |

Two models deviate from the SQL-template shape: `PhysicalCountModel.getAll(db)` and `BOMModel.getAll(db)` take only `db` today (no filters — add a filters arg + paged shape), and the stock-balances controller returns a bare array with no `{ success, data }` wrapper (the wrapper is introduced alongside paging).

Each conversion SHALL follow the suppliers template on both sides of the stack:

- Server: controller parses `page`/`limit`/`search`/sort params via the existing
  `getQueryParam`/`getQueryInteger` helpers (`server/src/utils/queryUtils.ts`) and the
  `sanitizeSortParams` whitelist sanitizer (`server/src/utils/sqlSanitizer.ts`); the model's
  `getAll` returns the **new canonical shape `{ rows, total, pageNum, limitNum }`** (Payment-style
  with a generic `rows` key — note the existing paged models vary: `SupplierModel.getAll` returns
  `{ data, total }`, `PaymentModel.getAll` returns `{ payments, total, pageNum, limitNum }`, and
  the controller owns the page math in all of them); the response carries the flat
  `{ success, data: [...], pagination: {...} }` envelope (data = list, pagination sibling — the
  shape `getPaged` parses; never nest `items`/`pagination` under `data`). Prepared statements and
  transactional reads only.
- Client: provider becomes `FutureProvider<PagedResponse<T>>` over `PagedRequest`; screen adds
  `gridRowsFrom` unwrap, `ServerPaginationBar` beneath `gridScreenBody` (`if (page != null)`), a
  page provider (default 1) and limit provider (default 10) per screen, debounced search resetting
  to page 1, and `onGridSorted` mapping to the endpoint's sort whitelist.

#### Scenario: Each converted grid pages server-side

- **WHEN** any converted screen loads more rows than its page size
- **THEN** the grid shows one page and renders `ServerPaginationBar` with the screen's localized item label

#### Scenario: Per-page size change resets to page 1

- **WHEN** the user picks a new per-page size (10/25/50/100)
- **THEN** the screen sets page 1, refetches with the new limit, and the bar shows the new count

#### Scenario: Filters survive paging

- **WHEN** the user navigates pages while a filter/search/sort is active
- **THEN** the active criteria are re-sent with the page request and pagination continues within the filtered result set

### Requirement: Sales and expenses grids paginate

The two direct-PlutoGrid list screens SHALL also render `ServerPaginationBar` and page server-side.

- **Sales** (`lib/features/sales/sales_screen.dart`): convert `GET /invoices`
  (`server/src/controllers/invoiceController.ts`) to the paged envelope; `invoicesProvider`
  (`lib/features/sales/invoice_providers.dart`) becomes `FutureProvider<PagedResponse<Invoice>>`;
  the screen renders `ServerPaginationBar` and keeps its existing search/filter/sort behavior
  consistent with the parity requirements.
- **Expenses** (`lib/features/expenses/expenses_screen.dart`): the server already pages
  `GET /expenses` (`expenseController.getExpenses`) — change the response envelope to the
  `PagedResponse` key convention (`currentPage/totalPages/totalItems/hasNext/hasPrev`), keep the
  existing 10-row default limit (matches the app-wide convention), and have `expensesProvider`
  expose `PagedResponse<Expense>` so the screen renders `ServerPaginationBar`.

#### Scenario: Sales grid pages server-side

- **WHEN** the Sales screen loads with more invoices than the page size
- **THEN** the grid shows one page with a `ServerPaginationBar` beneath it

#### Scenario: Expenses reuse existing server paging

- **WHEN** the Expenses screen loads
- **THEN** it renders `ServerPaginationBar` driven by the endpoint's existing server-side paging (envelope keys normalized to the `PagedResponse` convention)

### Requirement: Search is server-side on converted screens

All converted screens SHALL search on the server, matching suppliers' `search` param behavior.

- Every converted endpoint accepts a `search` query param (add it where missing) filtering the
  natural text fields for that entity.
- Screens keep their existing debounced search input (350 ms pattern) but write the term to a
  provider that the paged provider watches; changing the term resets the page to 1.
- Client-side row filtering is removed from screens that do it today (stock balances search +
  warehouse filter, physical-counts search).

#### Scenario: Search runs against the server

- **WHEN** the user types in a converted screen's search box
- **THEN** the screen refetches page 1 with the `search` param (debounced) instead of filtering already-loaded rows

### Requirement: Column sort is server-side on converted screens

All converted screens SHALL sort on the server via a per-endpoint sort-column whitelist, matching
the suppliers pattern (`onGridSorted` → sort provider → reset page 1).

- Each converted endpoint defines a `*_SORT_COLUMNS` whitelist (or reuses the existing
  `sortParams` sanitizer) so only safe column names reach SQL.
- Screens implement `onGridSorted` mapping grid column fields to whitelisted server columns and
  reset the page to 1 on sort change.

#### Scenario: Column header sort refetches from the server

- **WHEN** the user clicks a sortable column header on a converted screen
- **THEN** the screen refetches page 1 ordered by that column from the server (single round-trip, no client reordering)

### Requirement: Keyboard-hint strip removed from all PlutoGrid screens

The shared `GridStatusBar` strip ("↑ ↓ ← → Navigate" / "Enter / F2 Open",
`lib/widgets/grid_status_bar.dart`) SHALL be removed from every mixin-based PlutoGrid screen —
paginated or not. The mixin's `_gridPane` stops rendering it (drop the `if (showStatusBar)`
branch and the `showStatusBar` getter). This covers all ~20 mixin screens, including the small
unpaginated ones (users, roles, warehouses) and the 5 already server-paginated ones (suppliers,
customers, employees, payments, activity log) — removing the strip that currently sits above the
suppliers/other `ServerPaginationBar`s.

- If `GridStatusBar` is no longer referenced anywhere, delete the widget file and the
  `commonNavigate`/`commonOpen` l10n keys (en + ur + generated `app_localizations*`) — verify
  they are unused first.

#### Scenario: No strip on any grid

- **WHEN** any mixin-based grid screen renders
- **THEN** no keyboard-hint strip appears beneath the grid (regardless of whether the screen has a pagination bar)

#### Scenario: Suppliers bottom chrome is clean

- **WHEN** the Suppliers screen renders
- **THEN** the bottom of the screen shows the grid followed directly by the `ServerPaginationBar` with no hint strip between them

### Requirement: Serial number restarts per page

The shared `#` column renderer uses the row's index within the currently rendered (page) rows, so
with server-side paging the serial restarts at 1 on every page — matching the suppliers screen's
current behavior. No renderer change is required; this requirement locks the behavior in for all
converted screens.

#### Scenario: Serial numbering on later pages

- **WHEN** the user navigates to page 2 of any paginated grid
- **THEN** the `#` column numbers restart at 1 for that page's rows

### Requirement: Dead client-side pagination code removed

After all screens page server-side and the strip is gone, the mixin's client-side paging feature
becomes unused and SHALL be removed: `enablePagination`, `paginationPageSize`, the
`createFooter`/`PlutoPagination` branch in `_gridPane`, the `setPage(1)`/`setPageSize` calls, and
the Stock Movement screen's `enablePagination`/`showStatusBar` overrides. `pluto_grid` import stays
(columns/rows still use it); only the pagination plumbing goes.

#### Scenario: Mixin has no client pager surface

- **WHEN** the codebase is searched for `enablePagination` / `PlutoPagination` / `showStatusBar`
- **THEN** no references remain outside the `pluto_grid` package itself

---

## Non-goals / Out of scope

- Report screens (~16 aggregated summary tables), sales-invoice form pages, and detail-tab grids
  (editable/sub grids) — no pagination, no strip (the strip never rendered there).
- Users, roles, and warehouses lists: no pager (small reference lists); they only lose the strip.
- Activity log: keeps its offset-based paging (`OffsetPagedResponse`) — only the strip is removed.
- Mobile layout: grid screens are desktop-oriented today; no responsive work.
- The "Fix Balances" / export actions already on screens keep working unchanged. The items
  low-stock toggle keeps working but routes through the paged `/items` path (its search box is
  enabled in low-stock mode — see the resolved edge case).

## Edge cases and open decisions

- **Items low-stock toggle** (**resolved**): low-stock routes through `GET /inventory/items` with a
  `low_stock=1` filter param (shared paged path). `ItemModel.getLowStock` delegates to the same
  query so the old `/inventory/items-low-stock` endpoint stays backward-compatible for external
  consumers. Side effect (accepted): the items grid's search box is enabled in low-stock mode too
  (server-side search applies to both modes).
- **Stock-balances warehouse filter**: the endpoint gains a `warehouse_code` (or `warehouse_id`)
  param; the screen's existing warehouse dropdown writes to a provider that resets page 1.
- **Per-screen default limit** (**resolved**): default 10 everywhere, matching
  suppliers/customers/payments/employees (client `StateProvider` default and server `|| 10`
  fallback) and the expenses endpoint as-is; the per-page selector still offers 10/25/50/100.
- **Item labels**: `ServerPaginationBar` needs a localized plural label per screen (e.g.
  `l10n.stockmovementsMovements`); add missing `*_Movements`/`*_Items`-style l10n keys where absent.
- **Debounce timing**: keep the existing 350 ms search debounce on screens that have one.
- **Empty results**: bar renders only when the provider has a value (`if (page != null)`), so
  loading/error states show no bar (matches suppliers).

## Verification

- `flutter analyze` and `npm run typecheck`/`npm run lint` pass with zero issues.
- `server/src/__tests__` updated for the converted endpoints (envelope shape, page/limit/search/sort
  params, whitelist rejection of unknown sort columns).
- Manual pass: stock movements, items, stock balances, sales, expenses, suppliers — each shows the
  `ServerPaginationBar`, paging + per-page + sort + search refetch from the server, page resets to 1
  on any criteria change, and no keyboard-hint strip on any grid.
