## Why

List screens in the Flutter client are inconsistent: suppliers, customers,
employees, payments, and activity log page server-side with a
`ServerPaginationBar`, stock movement pages client-side with a bare
page-number pager, and ~13 other PlutoGrid grids render one unbounded,
full-array list that grows with the dataset. On top of that, every grid
shows a keyboard-hint strip (`GridStatusBar`) beneath it — on the
server-paginated screens this strip sits *above* the pagination bar,
stacking two unrelated bottom chrome elements.

This change makes every data-heavy list grid behave like the suppliers
screen (the established in-app reference): server-side paging with
"Page X of Y · N items", a per-page selector, server-side search, and
server-side column sort — and removes the keyboard-hint strip from all
grids.

## What Changes

- **Server-side paging for data-heavy grids**: convert the list endpoints
  for stock movements, items, stock balances, physical counts, sales
  orders, quotations, purchase orders, purchases, purchase returns,
  invoice returns, production, BOM, demand forecast, invoices (sales),
  and expenses to the flat `{ success, data: [...], pagination: {...} }`
  envelope — `data` is the item list and `pagination` is a sibling of
  `data` (NOT nested under it; the client `getPaged` helper rejects the
  nested shape) — matching suppliers/customers. Each endpoint gains
  `page`/`limit` parsing, a sort-column whitelist, and a `search` param
  where missing.
- **Full suppliers parity on converted screens**: search and column sort
  run server-side (whitelisted), each screen debounces search and resets
  to page 1 on any criteria change, and `ServerPaginationBar` renders
  beneath the grid once data loads.
- **Sales & expenses**: sales gets a full endpoint conversion; expenses
  already pages server-side — its response keys are normalized to the
  `PagedResponse` convention (default limit stays 10, matching the
  app-wide page-size convention) and the client starts consuming them.
- **Strip removal**: the shared `GridStatusBar` keyboard-hint strip is
  removed from every mixin-based PlutoGrid screen (paginated or not),
  including the five already server-paginated screens — suppliers' bottom
  chrome becomes grid → `ServerPaginationBar` with no strip in between.
  The widget and its `commonNavigate`/`commonOpen` l10n keys are deleted.
- **Dead code removal**: the mixin's client-side pagination plumbing
  (`enablePagination`, `paginationPageSize`, `createFooter` →
  `PlutoPagination`) becomes unused and is removed, along with the Stock
  Movement screen's client-pager overrides.

## Capabilities

### New Capabilities
- `server-side-pagination`: data-heavy PlutoGrid list screens page server-side and render `ServerPaginationBar` (stock movements, items, stock balances, physical counts, sales, expenses, sales orders, quotations, purchase orders, purchases, purchase returns, invoice returns, production, BOM, demand forecast).
- `server-side-search`: converted endpoints filter by `search` server-side; client-side row filtering is removed.
- `server-side-sort`: converted endpoints sort by whitelisted columns; grid header sort refetches from the server.
- `remove-grid-status-strip`: the keyboard-hint strip is removed from all mixin-based grids.

### Modified Capabilities
- `stock-movement-pagination` (from `inventory-screen-improvements`): superseded — the client-side `PlutoPagination` pager is replaced by server-side paging; the existing spec for that change stays archived as-is.

## Impact

Server:

- `server/src/controllers/inventoryController.ts`, `invoiceController.ts`,
  `salesController.ts`, `purchaseOrderController.ts`, `purchaseController.ts`,
  `productionController.ts`, `bomController.ts`, `forecastsController.ts`,
  `expenseController.ts` — list handlers return the paged envelope.
- `server/src/models/*` (`Item`, `StockMovement`, `PhysicalCount`, `Invoice`,
  `SalesOrder`, `Quotation`, `PurchaseOrder`, `Purchase`, `Production`,
  `BOM`, forecasts) — `getAll`-style queries add page/limit/search/sort +
  count.
- `server/src/utils/queryUtils.ts` / sort sanitizer — shared page/limit/sort
  parsing reused across handlers.
- `server/src/__tests__/` — envelope shape and whitelist tests for converted
  endpoints.

Client:

- `lib/widgets/pluto_grid_screen.dart` — remove client pager + strip.
- `lib/widgets/grid_status_bar.dart` — deleted; `commonNavigate` /
  `commonOpen` l10n keys removed.
- `lib/widgets/pagination_bar.dart` — reused unchanged.
- ~15 screen files and their provider files — `PagedResponse` envelopes,
  page/limit/search/sort providers, `ServerPaginationBar`.
- `lib/data/repositories/*` — paged list methods via the existing
  `PagedRequest`/`getPaged` client helpers.
- `lib/l10n/*.arb` + generated `app_localizations*` — per-screen item
  labels for the bar; strip keys removed.

No DB migration or schema change.
