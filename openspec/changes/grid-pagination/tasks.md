# Grid-Pagination Task Breakdown (reordered + estimated)

Effort in **person-days (d)**. Assumptions: once the pilot proves the
per-screen conversion template, each additional screen is ~0.5 d of
mechanical work; server tests are folded into each batch rather than a
single end-of-change task; l10n labels land with the batch that needs
them.

**Dependency rationale (what changed in this review):**
- The **strip removal** is fully independent of server work → lands first.
- The **dead client-pager removal** is *not* independent: stock movement is
  its only consumer, so it must follow the pilot (Phase 2) that replaces
  the client pager with the server-side bar — otherwise stock movement is
  left with no pager at all.
- Phases 4–8 are **independent of each other** (each depends only on
  Phases 0–3) → parallelizable across 2–3 streams.

**Sequential estimate ≈ 11.75 d (0.5+0.25+1.5+0.25+2.0+2.25+2.0+1.75+
0.5+0.75). With 2 parallel streams after Phase 3: ≈ 9.25 calendar days
(3 streams: ≈ 7.5 d).**

---

## Phase 0 — Shared foundations (~0.5 d)

- [ ] 0.1 Confirm/extend a shared server paging helper (`server/src/utils/queryUtils.ts` — `getQueryParam`/`getQueryInteger` already exist — plus a `pagination` block builder) and add the new `*_SORT_COLUMNS` whitelists to `server/src/utils/sqlSanitizer.ts` (which already holds CUSTOMER/SUPPLIER/LEDGER/PAYMENT) so every converted handler reuses it. *(0.25 d)*
- [ ] 0.2 Confirm the client `PagedRequest`/`getPaged` helpers cover all param sets (search, sort, and per-screen extras: `movement_type`, `warehouse_code`, `low_stock`, date ranges) — extend where an endpoint needs extra query params. Converted screens use `getPaged` (customers/suppliers shape), not the employees `getRaw` pattern or `getOffsetPaged`. *(0.25 d)*

## Phase 1 — Strip removal (independent; lands first) (~0.25 d)

- [ ] 1.1 Remove the `GridStatusBar` render from `PlutoGridScreen._gridPane` and the `showStatusBar` getter; drop the Stock Movement `showStatusBar` override; delete `lib/widgets/grid_status_bar.dart` and the `commonNavigate`/`commonOpen` l10n keys (en + ur + regenerate `app_localizations*`). Verify `flutter analyze` on several mixin screens. *(0.25 d)*

## Phase 2 — Stock movement pilot: end-to-end template (~1.5 d)

- [ ] 2.1 Server: `getStockMovements` parses page/limit/sort (keep `movement_type`) → flat envelope `{ success, data: [...rows...], pagination: {...} }` (data = list, pagination a sibling — NOT nested; `getPaged` rejects the nested shape, verified live in the pilot); `StockMovementModel.getAll` returns `{ rows, total, pageNum, limitNum }`; `STOCK_MOVEMENT_SORT_COLUMNS` whitelist. *(0.5 d)*
- [ ] 2.2 Client: `stockMovementsProvider` → `FutureProvider.family<PagedResponse<StockMovement>, String?>` over `PagedRequest` (family key stays the filter); `inventory_repository.stockMovements` returns the paged result. *(0.25 d)*
- [ ] 2.3 Screen: `gridRowsFrom` unwrap; page (default 1) + limit (default 10) providers; `ServerPaginationBar` beneath `gridScreenBody` (`if (page != null)`, label `l10n.stockmovementsMovements` added here); `onGridSorted` → whitelist; filter changes reset to page 1; "back to All" invalidation preserved. *(0.5 d)*
- [ ] 2.4 Write the **per-screen conversion checklist** from this pass (server handler + model + whitelist → repo + provider → screen unwrap/bar/sort → page resets → tests) so Phases 4–8 execute it mechanically. *(0.25 d)*

## Phase 3 — Dead client-pager removal (after pilot) (~0.25 d)

- [ ] 3.1 Remove `enablePagination`, `paginationPageSize`, the `createFooter`/`PlutoPagination` branch in `_gridPane`, and the `setPage(1)`/`setPageSize` calls in `syncGridRows`/`onLoaded`; delete the Stock Movement `enablePagination` override. *(0.25 d)*

## Phase 4 — Inventory batch *(parallel with Phase 5)* (~2.0 d)

- [ ] 4.1 Items: paged `GET /inventory/items` + `low_stock=1` param; `ItemFilters.lowStock`; `ItemModel.getAll` low-stock clause + paged shape + sort whitelist; `getLowStock` delegates to `getAll({ lowStock: true })` (old route stays compatible); `itemsProvider` → `PagedResponse<Item>`; screen bar + sort mapping; drop `repo.lowStock()` and the `searchEnabled: !lowStockOnly` guard. *(0.75 d)*
- [ ] 4.2 Stock by Warehouse: paged `GET /inventory/stock-balances` with `search` + `warehouse_code`; `stockBalancesProvider` → `PagedResponse<StockBalance>`; remove client-side `_filteredRows` filtering + providers; screen bar; warehouse dropdown resets page 1. *(0.5 d)*
- [ ] 4.3 Physical Counts: paged `GET /inventory/physical-counts` with `search`; `PhysicalCountModel.getAll(db)` gains a filters arg + paged shape (today it takes only `db`); provider → `PagedResponse<PhysicalCount>`; screen bar; remove client-side search filter. *(0.5 d)*
- [ ] 4.4 Server tests for the batch (envelope, params, whitelist rejection). *(0.25 d)*

## Phase 5 — Sales batch *(parallel with Phase 4)* (~2.25 d)

- [ ] 5.1 Sales (invoices): paged `GET /invoices`; `invoicesProvider` → `PagedResponse<Invoice>`; `sales_screen.dart` renders `ServerPaginationBar` (direct grid — no strip involved). *(0.5 d)*
- [ ] 5.2 Sales Orders: paged `GET /sales/sales-orders`; provider → `PagedResponse<SalesOrder>`; screen bar + sort mapping. *(0.5 d)*
- [ ] 5.3 Quotations: paged `GET /sales/quotations`; provider → `PagedResponse<Quotation>`; screen bar + sort mapping. *(0.5 d)*
- [ ] 5.4 Invoice Returns: paged `GET /invoices/returns`; provider → `PagedResponse<SalesReturn>`; screen bar + sort mapping. *(0.5 d)*
- [ ] 5.5 Server tests for the batch. *(0.25 d)*

## Phase 6 — Purchasing batch *(parallel)* (~2.0 d)

- [x] 6.1 Purchase Orders: paged `GET /purchase-orders`; provider → `PagedResponse<PurchaseOrder>`; screen bar + sort mapping. *(0.5 d)*
- [x] 6.2 Purchases: paged `GET /purchases`; provider → `PagedResponse<Purchase>`; screen bar + sort mapping. *(0.5 d)*
- [x] 6.3 Purchase Returns: paged `GET /purchases/returns`; provider → `PagedResponse<PurchaseReturn>`; screen bar + sort mapping. *(0.5 d)*
- [x] 6.4 Server tests for the batch. *(0.5 d)*

## Phase 7 — Production / BOM / demand forecast *(parallel)* (~1.75 d)

- [ ] 7.1 Production: paged `GET /productions`; provider → `PagedResponse<Production>`; screen bar + sort mapping. *(0.5 d)*
- [ ] 7.2 BOM: paged `GET /bom` (simpler list); `BOMModel.getAll(db)` gains a filters arg + paged shape (today it takes only `db`); provider → `PagedResponse<Bom>`; screen bar + sort mapping. *(0.25 d)*
- [ ] 7.3 Demand Forecast: paged `GET /forecasts/demand` — **no SQL model**: `getDemand` generates in memory (`generateAllForecasts()`), filters in JS (category/trend/recommendation/modelType). Add a `search` param, then filter-then-slice by page/limit and append the `pagination` block in the handler; provider → `PagedResponse<ForecastDemand>`; screen bar + sort mapping. *(0.5 d)*
- [ ] 7.4 Server tests for the batch. *(0.5 d)*

## Phase 8 — Expenses (server already paged) *(parallel)* (~0.5 d)

- [ ] 8.1 Server: `expenseController.getExpenses` pagination keys → `currentPage`/`totalPages`/`totalItems`/`hasNext`/`hasPrev` (default limit stays 10 — matches convention); tests updated in the same change. *(0.25 d)*
- [ ] 8.2 Client: `expensesProvider` → `PagedResponse<Expense>`; `expenses_screen.dart` renders `ServerPaginationBar` (direct grid). *(0.25 d)*

## Phase 9 — L10n sweep + final verification (~0.75 d)

- [ ] 9.1 Add any remaining per-screen bar labels (en + ur + regenerate localizations) missed during the batches. *(0.25 d)*
- [ ] 9.2 Run `flutter analyze`, `npm run typecheck`, `npm run lint` — zero issues. *(0.25 d)*
- [ ] 9.3 Manual pass: stock movements, items, stock balances, sales, expenses, suppliers — bar renders; paging/per-page/sort/search refetch server-side; page resets to 1 on any criteria change; no keyboard-hint strip on any grid. *(0.25 d)*

---

## Parallelization plan

| Stream | Phases | Effort |
| --- | --- | --- |
| A | 4 (inventory) + 8 (expenses) | 2.5 d |
| B | 5 (sales) + 6 (purchasing) | 4.25 d |
| C | 7 (production/BOM/forecast) | 1.75 d |

Phases 0–3 (2.5 d) gate all batches; Phase 9 (~0.75 d) closes out. With
3 streams, wall clock ≈ 0.5 + 0.25 + 1.5 + 0.25 + 4.25 + 0.75 ≈ **7.5 d**;
with 2 streams (A = 4+8, B = 5+6+7) ≈ **9.25 d**. Sequential ≈ **11.75 d**.

## Risks that affect ordering/effort

- Any screen whose endpoint has existing client-side filtering (stock
  balances, physical counts) or a family-keyed provider (stock movements)
  costs a bit more than the template (included in its estimate).
- Default page size is 10 (resolved) — matching the existing paged
  screens; the deleted client pager's 25 default is irrelevant.
- Regenerating localizations (`flutter gen-l10n`) after each label change
  is a fixed small cost folded into Phases 1, 2.3, and 9.1.
- Server tests per batch keep each PR self-contained; deferring them to
  the end (old plan) creates a risky verification cliff.
