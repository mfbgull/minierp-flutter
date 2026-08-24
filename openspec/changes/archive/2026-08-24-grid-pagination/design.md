## Context

Every data list screen renders a PlutoGrid through the shared
`PlutoGridScreen` mixin (`lib/widgets/pluto_grid_screen.dart`), fed by
clear+append from a Riverpod provider. Today the mixin supports an opt-in
client-side pager (`enablePagination` → `createFooter` →
`PlutoPagination`, page-number buttons only) used solely by Stock
Movement, and it always renders the `GridStatusBar` keyboard-hint strip
beneath the grid.

Current state:

- **Already server-paginated (5)**: suppliers, customers, employees,
  payments, activity log — `PagedResponse`/`OffsetPagedResponse` envelope
  + `ServerPaginationBar` (`lib/widgets/pagination_bar.dart`: "Page X of
  Y · N items", per-page 10/25/50/100, prev/next). All still render the
  `GridStatusBar` strip *above* their bar.
- **Plain full-array grids (~13)**: items, stock balances
  (stock-by-warehouse), physical counts, sales orders, quotations,
  purchase orders, purchases, purchase returns, invoice returns,
  production, BOM, demand forecast, and Stock Movement (client pager).
  Some filter client-side (stock-balances search + warehouse filter,
  physical-counts search); items already sends `search` server-side.
- **Direct PlutoGrid grids (2)**: Sales (`GET /invoices`) and Expenses
  (`GET /expenses`). The expenses endpoint already pages server-side but
  returns a snake_case `pagination` block (`current_page`/`total_pages`/
  `total_expenses`/`per_page`, default limit 10) that the client ignores;
  sales has no envelope.

The reference behavior is the suppliers screen — server-side paging with
`ServerPaginationBar`.

## Goals / Non-Goals

**Goals:**
- Stock movement pages server-side like suppliers (page/limit, sort, and
  the movement-type filter survive paging).
- All data-heavy PlutoGrid list screens page server-side with
  `ServerPaginationBar` (items, stock balances, physical counts, sales,
  expenses, sales orders, quotations, purchase orders, purchases,
  purchase returns, invoice returns, production, BOM, demand forecast).
- Search and column sort run server-side on every converted screen
  (suppliers parity).
- The keyboard-hint strip is removed from every mixin-based grid.
- Dead client-side pagination code is deleted.

**Non-Goals:**
- Pagination for small reference lists (users, roles, warehouses).
- Report screens, invoice form pages, detail-tab grids (aggregates/edit
  lines; the strip never rendered there).
- Activity log: keeps offset-based paging; strip removal only.
- Mobile/responsive layouts.
- Any DB schema change or migration.

## Decisions

### 1. Reuse the existing server-side paging pattern end to end

Server handlers parse `page`/`limit`/`search`/sort via shared helpers
(`getQueryParam`/`getQueryInteger` in `queryUtils.ts` + the
`sanitizeSortParams` whitelist sanitizer in `sqlSanitizer.ts`) and return
the **flat** envelope suppliers/customers use — `data` is the item
**list** and `pagination` is a **sibling** of `data`:
`{ success, data: [...items...], pagination: { currentPage, totalPages,
totalItems, hasNext, hasPrev } }`. The client's `getPaged` helper parses
`data` as a list and reads `pagination` off the envelope body — a nested
`{ data: { items, pagination } }` shape makes it throw
`'Expected a list response'`, so the converted endpoints must NOT nest
(verified live during the pilot: the nested shape broke the stock
movement grid). Client providers become
`FutureProvider<PagedResponse<T>>` over the existing `PagedRequest`/
`getPaged` helpers.

- **Model return shape (verified)**: existing paged models do *not*
  share one shape — `SupplierModel.getAll` returns `{ data, total }`,
  `PaymentModel.getAll` returns `{ payments, total, pageNum, limitNum }`,
  and the controller owns the page math in both. The conversions
  introduce a **canonical `{ rows, total, pageNum, limitNum }`** for new
  models (Payment-style, generic `rows` key); existing paged models are
  left untouched.
- **HTTP envelope shape (verified)**: the app already has *three*
  divergent list envelopes — customers/suppliers/payments
  (`pagination: { currentPage, totalPages, totalItems, hasNext, hasPrev }`
  via `getPaged`), activity log (top-level `total/limit/offset` via
  `getOffsetPaged`), and employees (`pagination: { page, limit, total,
  totalPages }` via a custom `getRaw` parse; server default limit 20, but
  the client always sends 10). New conversions standardize on the
  customers/suppliers shape through `getPaged` — do not copy the
  employees `getRaw` pattern. This also narrows the app's shape count over
  time.
- **Client defaults (verified)**: `PagedRequest` defaults `page = 1`,
  `limit = 10`, `sortOrder = 'ASC'`; `ServerPaginationBar.pageSizes` is
  `[10, 25, 50, 100]` with a first-option (10) fallback; all existing
  limit providers default to 10 — all consistent with Decision 8.
- **Template deviations (verified)**: `PhysicalCountModel.getAll(db)` and
  `BOMModel.getAll(db)` take only `db` today — they gain a filters arg +
  paged shape. `getStockBalances` returns a bare array with no
  `{ success, data }` wrapper — the wrapper is introduced alongside
  paging. Demand forecast has **no SQL model**: `getDemand` generates in
  memory (`generateAllForecasts()`), filters in JS, and returns the full
  array — pagination there is filter-then-slice in the handler, not a
  `getAll`/COUNT change.
- **Why**: one established HTTP contract already consumed by five
  screens; reusing it keeps the API surface consistent and the client
  plumbing (`gridRowsFrom` unwrap, page/limit providers,
  `ServerPaginationBar`) identical per screen.
- **Alternatives considered**: a new client-side pager styled like
  `ServerPaginationBar` over loaded rows — rejected (user chose server
  parity; full-array payloads don't scale); per-screen bespoke envelopes
  — rejected (divergent contracts).

### 2. Stock movement is the end-to-end pilot

Convert `GET /inventory/stock-movements` (controller + `StockMovementModel`
+ `stockMovementsProvider` + screen bar + sort mapping) first, land and
verify it, then roll the identical pattern out module by module
(inventory → sales → purchasing → production/BOM/forecast → expenses).

- **Why**: the request names this screen explicitly; a single end-to-end
  pass validates the pattern (filter + page reset + sort + bar) before
  it is repeated ~14 times.
- **Alternatives considered**: parallel conversions across all endpoints
  — rejected (harder to review and debug; one template proves out first).

### 3. Full suppliers parity: server-side search and sort

Every converted endpoint gains a `search` param (where missing) and a
sort-column whitelist; screens keep their debounced search (350 ms) and
map grid column sorts via `onGridSorted`, resetting to page 1 on any
criteria change. Client-side row filtering is removed where it exists
(stock-balances search + warehouse filter, physical-counts search).

- **Why**: user-selected "full parity"; server-side filtering is the only
  correct model once rows are paged (client-side filtering would only
  search the current page).
- **Trade-off**: adds search/sort surface to endpoints that lack it
  today; mitigated by the shared whitelist sanitizer (prepared
  statements only, unknown columns rejected).

### 4. Strip removal is a mixin + widget deletion

`PlutoGridScreen._gridPane` stops rendering `GridStatusBar` (the
`showStatusBar` flag goes away); the widget file and its
`commonNavigate`/`commonOpen` l10n keys are deleted once unreferenced.

- **Why**: the strip renders in exactly one place (the mixin), so all ~20
  screens lose it at once, including the five server-paginated ones whose
  bottom chrome becomes grid → `ServerPaginationBar`. User chose removal
  "everywhere"; sales/expenses are unaffected (direct grids never had it).
- **Alternatives considered**: hiding the strip only where a pagination
  bar renders — rejected by the user; an opt-out `showStatusBar` flag per
  screen — unnecessary once no screen wants the strip.

### 5. Dead client-pager code removed from the mixin

`enablePagination`, `paginationPageSize`, the `createFooter` →
`PlutoPagination` branch, the `setPage`/`setPageSize` calls, and Stock
Movement's overrides are deleted.

- **Why**: after task 2 every grid pages server-side; the client pager is
  unreachable and would confuse future readers (two pagination systems).
- **Trade-off**: loses the ability to client-page a screen cheaply —
  acceptable; the server pager is now the app-wide standard.

### 6. Expenses: normalize the existing envelope, don't rewrite

Keep `GET /expenses` server-side paging; rename its `pagination` keys to
the `PagedResponse` convention (default limit stays 10 — it already
matches the app-wide page-size convention, see Decision 8); the client
starts consuming the block and renders `ServerPaginationBar`.

- **Why**: the server already pages (filters, count, limit) — only the
  key naming diverges from the shared client helper.
- **Trade-off**: none beyond the key rename; the existing 10-row default
  already matches the rest of the app, so no limit behavior changes.

### 7. Serial `#` column restarts per page

No renderer change: the shared `#` column renders `ctx.rowIdx + 1`, the
index within the current page's rows, so numbering restarts at 1 per
page — identical to the suppliers screen today. Locked as expected
behavior in the spec.

### 8. Default page size is 10 everywhere (**resolved**)

All converted screens default to a page size of **10** — the established
convention: suppliers, customers, payments, and employees all use
`StateProvider<int>((ref) => 10)`, the server fallback is
`Number(limitParam) || 10` (employees is the one exception — its server
fallback is `|| 20`, though the client always sends 10),
`ServerPaginationBar.pageSizes` leads with 10, and the expenses endpoint
already defaults to 10. The per-page selector still offers 10/25/50/100.

- Client: each converted screen's limit provider defaults to 10; each
  converted endpoint's server fallback is `|| 10`.
- No per-screen overrides. Activity log keeps its 50 default
  (offset-paged, out of scope); the deleted client pager's 25 default is
  moot.
- **Why**: matches the reference screens exactly ("pagination like the
  suppliers page"); one convention, and a freshly opened dropdown lands
  on its first option (10).
- **Alternatives considered**: 25 (the deleted client pager's default) —
  rejected: diverges from every existing server-paginated screen and
  would force the expenses limit change; per-screen defaults — rejected:
  no screen has a demonstrated need, and activity log's 50 is a separate
  offset-paging path.

### 9. Items low-stock toggle routes through the paged `/items` path (**resolved**)

`itemsLowStockOnlyProvider` switches the grid to `GET /inventory/items-low-stock`
today (bare array, search box disabled in that mode). **Resolved**: route
low-stock through `GET /inventory/items` with a `low_stock=1` filter param,
so one paged handler serves both modes.

- Extend `ItemFilters` with `lowStock?: boolean`; `ItemModel.getAll` adds
  `AND current_stock < reorder_level AND reorder_level > 0` (prepared
  statement, same predicates as `getLowStock`) and gains the paged
  `{ rows, total, pageNum, limitNum }` shape + sort whitelist
  (`item_code`, `item_name`, `category`, `current_stock`, `reorder_level`).
  Search already applies — it now works in low-stock mode too.
- `getItems` parses `low_stock=1` with the other filters and returns the
  standard envelope.
- `ItemModel.getLowStock` delegates to `getAll({ lowStock: true }, db)` so
  `GET /inventory/items-low-stock` keeps working for any external consumer
  (web/mobile) with zero query duplication, and its existing tests still
  pass.
- Client: `itemsProvider` becomes `FutureProvider<PagedResponse<Item>>`
  watching search + low-stock toggle + page/limit/sort; the toggle no
  longer calls `repo.lowStock()`. The screen's `searchEnabled: !lowStockOnly`
  guard is removed — search is enabled in both modes (server-side search
  makes it a free win and keeps parity).
- **Why**: one query definition, one sort whitelist, one envelope for both
  modes; no second paged endpoint to maintain. Keeps the old route
  backward-compatible instead of deleting it (unknown external consumers).
- **Alternatives considered**: paginate `items-low-stock` separately —
  rejected (duplicate paging/search/sort plumbing for a single toggle);
  delete the old endpoint outright — rejected (may break web/mobile
  consumers of the shared server).

## Risks / Trade-offs

- **[API contract change across ~15 endpoints]** converted responses gain
  the flat `{ success, data: [...], pagination: {...} }` envelope (data =
  list, pagination sibling — NOT nested under `data`). Client and server
  must ship together per module. Mitigation: pilot first, module-sized
  PRs, exact envelope parity with the existing paged endpoints (the
  pilot exposed a nested-shape bug that `getPaged` rejects).
- **[SQL injection via new sort/search params]** search is parameterized
  (prepared statements, existing pattern); sort columns pass through the
  whitelist sanitizer only. Unknown columns are ignored, never
  interpolated.
- **[Count + page queries on large tables]** each list call runs one
  `COUNT` plus one paged `SELECT` (same as suppliers/customers today).
  Ensure indexed filter columns (`item_code`, `warehouse_id`,
  `movement_date`, `status`, etc.) — no new n+1.
- **[Client filter providers removed]** stock-balances warehouse/search
  and physical-counts search move server-side; their `StateProvider`s and
  `_filteredRows` logic are deleted. Must reset page 1 when they change,
  or users see stale pages.
- **[Stock-movement "All" filter staleness]** the existing null-keyed
  family invalidation on switching back to All must survive the envelope
  change (the family key becomes the filter, not the page).
- **[Expenses envelope key rename only]** the `pagination` block keys
  change (snake_case → `PagedResponse` convention) with no default-limit
  behavior change (stays 10) — any external consumer reading the old
  keys would need to follow the rename.

## Migration Plan

No DB schema/migration. Per module: server envelope change and client
screen/provider change land together (same PR), so no client ever reads
the old bare-array shape. Rollback per module = revert the endpoint
controller/model and the screen's provider/bar wiring. The strip removal
is client-only and independent — safe to land first. The dead-pager
cleanup depends only on the pilot and must not land before it (Phase 3),
or stock movement is left with no pager.

Suggested order (see `tasks.md` for estimates): 1) strip removal (fully
independent — lands first), 2) stock movement pilot (defines the per-
screen template), 3) dead client-pager removal (only safe after the
pilot replaces stock movement's pager), 4–8) inventory, sales,
purchasing, production/BOM/forecast, and expenses batches (independent
of each other — parallelizable), 9) l10n sweep + full verification.
Estimated ≈ 11.75 person-days sequentially, ≈ 7.5–9 calendar days with
parallel batches.

## Open Questions

- Should the superseded client-pager capability spec
  (`inventory-screen-improvements/specs/stock-movement-pagination`) be
  annotated/archived as replaced when this change ships?
