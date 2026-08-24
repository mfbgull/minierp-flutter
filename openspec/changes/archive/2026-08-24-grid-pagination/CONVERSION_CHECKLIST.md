# Per-Screen Pagination Conversion Checklist

Source: extracted from the stock-movement pilot (`stock_movement_screen.dart`) and the Phase 4-8 batch. Use as the mechanical template for any future screen that moves from client-side paging to `ServerPaginationBar`.

---

## 1. Server handler

- [ ] Endpoint parses `page`, `limit`, `sortBy`, `sortOrder` query params (use `getQueryParam` / `getQueryInteger` from `server/src/utils/queryUtils.ts`).
- [ ] Handler calls `sanitizeSortParams(sortBy, sortOrder, *_SORT_COLUMNS, defaultColumn, defaultOrder)` before building SQL.
- [ ] Model `getAll` (or equivalent) returns `{ rows, total, pageNum, limitNum }`.
- [ ] Response uses the **flat envelope**: `{ success: true, data: [...rows...], pagination: { currentPage, totalPages, totalItems, hasNext, hasPrev } }`.
  - `data` is a list at the top level; `pagination` is a sibling, not nested.

## 2. Model layer

- [ ] `getAll(db, filters)` accepts an optional filters object (page, limit, sortBy, sortOrder, plus screen-specific extras like `movement_type`, `warehouse_code`, `low_stock`, date ranges).
- [ ] SQL applies `LIMIT ? OFFSET ?` and `ORDER BY <whitelisted column> ASC|DESC`.
- [ ] Count query (`getCount`) applies the same filters minus pagination/sort and returns the total.
- [ ] Sort column is validated against the model-specific `*_SORT_COLUMNS` whitelist in `server/src/utils/sqlSanitizer.ts`.

## 3. Repository

- [ ] Repository method returns `PagedResponse<T>` (defined in `lib/data/repositories/paged_request.dart`).
- [ ] Method calls `getPaged<T>(endpoint, queryParams)` (the flat-envelope parser used by customers/suppliers/employees screens).
- [ ] Any screen-specific extra params (`low_stock`, `movement_type`, `warehouse_code`, date range) are passed as query string keys.

## 4. Provider

- [ ] Provider is `FutureProvider.family<PagedResponse<T>, String?>` (or `PagedRequest`) if the screen has a filter family key; otherwise `FutureProvider<PagedResponse<T>>`.
- [ ] Provider reads filter/sort/page providers and passes them as query params.
- [ ] Provider calls the repository method and returns the `PagedResponse<T>` directly to the screen.

## 5. Screen unwrap

- [ ] Screen listens to the provider: `ref.listen(provider, (_, next) => _applyX(next));`.
- [ ] `_applyX` handles `isLoading` (show/hide loading overlay), `hasValue` (clear + append rows via `manager.appendRows([...])`), and `hasError` (show error panel).
- [ ] Grid `onLoaded` calls `watchGridProvider(provider)` so PlutoGrid knows the data source.

## 6. ServerPaginationBar

- [ ] `ServerPaginationBar` sits directly beneath the grid body (no strip, no `GridStatusBar`).
- [ ] Bar reads `pagination` from the unwrapped `PagedResponse`.
- [ ] Bar label uses the screen-specific l10n key (e.g., `l10n.stockmovementsMovements`).
- [ ] Bar `onPageChanged` writes to the page provider.

## 7. Sort mapping

- [ ] Screen sort dropdown calls `sanitizeSortParams` (or the model-level equivalent) before writing to `*_sortProvider`.
- [ ] Dropdown `onChanged` resets page to 1 when the sort column changes.
- [ ] Sort state is held in a `StateProvider<XSort?>` (nullable; null means default sort).

## 8. Page resets

- [ ] Every filter/sort change resets the page provider to 1 (except when the user explicitly picks a page via the bar).
- [ ] Refresh (`onRefresh`) calls `ref.invalidate(provider)`.

## 9. Tests

- [ ] **Model test**: `getAll` returns paged rows + total count; filters narrow correctly; default sort is sane.
- [ ] **Sort whitelist test**: `sanitizeSortParams` rejects SQL-injection strings and falls back to the default column.
- [ ] **Integration test**: endpoint returns `{ success, data, pagination }`; `sortBy` injection returns 200/400 without dropping tables.

## 10. L10n

- [ ] Add a `paginationBarLabel` (or equivalent) l10n key for the bar label in `en.arb` and `ur.arb`.
- [ ] Run `flutter gen-l10n` and verify the key resolves.
