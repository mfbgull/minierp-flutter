# Global Search / Command Palette — Task Breakdown

Effort in **person-days (d)**. The spec is `global-search-spec.md`.

**Dependency rationale:**
- **Phase 1–2** (backend) are fully independent of Flutter work and land first.
- **Phase 3** (Flutter UI) depends on Phase 1–2 (needs the API).
- **Phase 4** (navigation integration) depends on Phase 3 (needs the dialog).
- **Phase 5** (permissions + business rules) depends on Phase 1–2 (needs the backend action registry).
- **Phase 6** (polish + tests) depends on all prior phases.

**Sequential estimate ≈ 9.5 d. With 2 parallel streams (backend + frontend after Phase 1): ≈ 7.0 d.**

---

## Phase 0 — Shared foundations & migration (~0.5 d)

- [x] 0.1 Create `server/src/migrations/add-search-indexes.sql` with indexes on searchable columns: `customers(customer_name)`, `customers(phone)`, `suppliers(supplier_name)`, `suppliers(phone)`, `items(item_name)`, `items(barcode)` if exists, `invoices(invoice_no)`, `purchase_orders(po_no)`, `quotations(quotation_no)`, `sales_orders(so_no)`, `payments(payment_no)`, `warehouses(warehouse_name)`, `employees(first_name, last_name)`, `productions(production_no)`, `boms(bom_no)`. Use `CREATE INDEX IF NOT EXISTS`. *(0.25 d)*
- [x] 0.2 Register the migration in `server/src/config/database.ts` as `runSearchIndexesMigration()` — add the column-existence check pattern used by existing migrations (e.g., check if index exists before creating). *(0.125 d)*
- [x] 0.3 Create `server/src/types/search.ts` with TypeScript interfaces: `SearchResult`, `SearchAction`, `SearchResponse`, `PageAction`, `ActionDef`. *(0.125 d)*

---

## Phase 1 — Backend search infrastructure (~2.0 d)

### 1A — Search service core (~1.0 d)

- [x] 1.1 Create `server/src/services/searchService.ts` with the main `search(query, limit, userId)` function that orchestrates per-entity searches and returns a merged, ranked `SearchResponse`. *(0.25 d)*
- [x] 1.2 Implement `searchCustomers(query, limit, db)` — parameterized LIKE on `customer_name`, `customer_code`, `phone`, `email`, `contact_person`; ranking: exact name > starts-with name > code match > other field; filter `is_active = 1`; return `SearchResult[]` with type `customer`. *(0.125 d)*
- [x] 1.3 Implement `searchSuppliers(query, limit, db)` — same pattern as customers on `supplier_name`, `supplier_code`, `phone`, `email`, `contact_person`. *(0.125 d)*
- [x] 1.4 Implement `searchProducts(query, limit, db)` — LIKE on `item_name`, `item_code`, `category`, `description`; filter `is_active = 1`; include `current_stock`, `standard_selling_price` in metadata. *(0.125 d)*
- [x] 1.5 Implement `searchInvoices(query, limit, db)` — LIKE on `invoice_no`, JOIN `customers` for `customer_name`; include `status`, `total_amount`, `balance_amount` in metadata. *(0.125 d)*
- [x] 1.6 Implement `searchPurchaseOrders(query, limit, db)` — LIKE on `po_no`, JOIN `suppliers` for `supplier_name`; include `status`, `total_amount`. *(0.0625 d)*
- [x] 1.7 Implement `searchQuotations(query, limit, db)` — LIKE on `quotation_no`, JOIN `customers`. *(0.0625 d)*
- [x] 1.8 Implement `searchSalesOrders(query, limit, db)` — LIKE on `so_no`, JOIN `customers`. *(0.0625 d)*
- [x] 1.9 Implement `searchPayments(query, limit, db)` — LIKE on `payment_no`, `reference_no`, JOIN `customers`/`suppliers`. *(0.0625 d)*
- [x] 1.10 Implement `searchExpenses(query, limit, db)` — LIKE on `description`, `reference_no`, JOIN `expense_categories`. *(0.0625 d)*
- [x] 1.11 Implement `searchWarehouses(query, limit, db)` — LIKE on `warehouse_name`, `warehouse_code`. *(0.03 d)*
- [x] 1.12 Implement `searchEmployees(query, limit, db)` — LIKE on `first_name`, `last_name`, `employee_code`. *(0.03 d)*
- [x] 1.13 Implement `searchProductions(query, limit, db)` — LIKE on `production_no`, JOIN `items` for finished item name. *(0.03 d)*
- [x] 1.14 Implement `searchBOMs(query, limit, db)` — LIKE on `bom_no`, JOIN `items`; include `is_active`, count of `bom_items`. *(0.03 d)*

### 1B — Action registry & permission filtering (~0.5 d)

- [x] 1.15 Define `ENTITY_ACTIONS` registry in `searchService.ts` — all 13 entity types with their actions, permissions, and status-based conditions (as specified in spec §4.9). *(0.25 d)*
- [x] 1.16 Implement `filterActions(actions, userId, db)` — look up user's `role_id`, query `role_permissions` + `permissions` for allowed `module:action` pairs, filter out unauthorized actions; admin bypass. *(0.125 d)*
- [x] 1.17 Implement `evaluateConditions(actions, entityRow)` — for each action with a `condition` function, evaluate against the entity's row data (status, is_active, etc.); remove actions whose condition returns false. *(0.125 d)*

### 1C — Page/action registry search (~0.25 d)

- [x] 1.18 Define `PAGE_ACTIONS` static registry in `searchService.ts` — all pages and actions from spec §4.11 with titles, paths, icons, keywords. *(0.125 d)*
- [x] 1.19 Implement `searchPages(query)` — case-insensitive keyword match against title + keywords; return as `SearchResult[]` with type `page`. *(0.0625 d)*
- [x] 1.20 Filter page results by user permissions — non-admins don't see `/admin`, `/integrations`; respect `reports:read` etc. *(0.0625 d)*

### 1D — Controller & route (~0.25 d)

- [x] 1.21 Create `server/src/controllers/searchController.ts` — parse `q` and `limit` from query params, call `searchService.search()`, return `{ success: true, data: { query, results, total } }`. *(0.125 d)*
- [x] 1.22 Create `server/src/routes/search.ts` — `GET /` with `authenticateToken` middleware and `validateZodQuery(searchQuerySchema)`; Zod schema: `q: z.string().min(2).max(100)`, `limit: z.coerce.number().int().min(1).max(50).optional().default(10)`. *(0.125 d)*
- [x] 1.23 Register route in `server/src/app.ts`: `app.use('/api/search', searchRoutes)`. *(0.03 d)*

---

## Phase 2 — Backend tests (~1.0 d)

- [x] 2.1 Create `server/src/__tests__/search.test.ts` — set up test DB with seed data (customers, suppliers, items, invoices, etc.); test search returns correct entity types. *(0.25 d)*
- [x] 2.2 Test customer search: by name, by code, by phone, by email; verify ranking (exact > starts-with > contains). *(0.125 d)*
- [x] 2.3 Test supplier search: by name, by code, by phone. *(0.0625 d)*
- [x] 2.4 Test product search: by name, by code, by category. *(0.0625 d)*
- [x] 2.5 Test invoice search: by invoice number, by customer name (join). *(0.0625 d)*
- [x] 2.6 Test PO, quotation, SO, payment, warehouse, employee, production, BOM search — at least one test each. *(0.125 d)*
- [x] 2.7 Test page/action search: by title, by keyword. *(0.0625 d)*
- [x] 2.8 Test ranking: verify exact matches appear before contains matches. *(0.0625 d)*
- [x] 2.9 Test actions: correct actions returned per entity type; status-based conditions work (e.g., Cancelled invoice has no `return_items` action). *(0.125 d)*
- [x] 2.10 Test permissions: unauthorized actions excluded; admin bypasses all. *(0.0625 d)*
- [x] 2.11 Test edge cases: empty query (< 2 chars) returns 400; limit bounds; no results returns empty array; `is_active = 0` entities excluded. *(0.0625 d)*

---

## Phase 3 — Flutter search UI (~2.5 d)

### 3A — Data layer (~0.5 d)

- [x] 3.1 Create `lib/data/models/search_result.dart` — `SearchResult`, `SearchAction`, `SearchResponse` models with `fromJson` factory. *(0.25 d)*
- [x] 3.2 Create `lib/data/repositories/search_repository.dart` — `search(query, limit)` method calling `GET /api/search?q=...&limit=...`; returns `ApiResult<SearchResponse>`. *(0.25 d)*

### 3B — State management (~0.25 d)

- [x] 3.3 Create `lib/features/search/search_provider.dart` — `searchQueryProvider` (StateProvider<String>), `searchResultsProvider` (FutureProvider.autoDispose), `selectedResultProvider` (StateProvider<SearchResult?>), `recentItemsProvider` (FutureProvider). *(0.25 d)*

### 3C — Recent items (~0.25 d)

- [x] 3.4 Create `lib/features/search/recent_items.dart` — `RecentItems` class with `getItems()`, `addItem()`, `clear()` using SharedPreferences; `RecentItem` model with `fromJson`/`toJson`; max 5 items; upsert by `entityType + entityId`. *(0.25 d)*

### 3D — Dialog widget (~1.0 d)

- [x] 3.5 Create `lib/features/search/global_search_dialog.dart` — `GlobalSearchDialog` as a `ConsumerStatefulWidget`; `showGlobalSearchDialog(context)` static method; centered modal with `BackdropFilter`; `Dialog` widget with fixed width 720px (desktop) or full-width minus margin (mobile); autofocus on `TextField`. *(0.25 d)*
- [x] 3.6 Implement search field with 200ms debounce — `Timer` debounce, min 2 chars, `onChanged` updates `searchQueryProvider` after debounce; cancel stale requests via `autoDispose`. *(0.125 d)*
- [x] 3.7 Implement results panel (left 60%) — `ListView` of `SearchResultGroup` widgets; each group has a header (entity type label) and list of `SearchResultTile` widgets; groups with 0 results hidden; loading spinner, empty state, error state, no-results state. *(0.25 d)*
- [x] 3.8 Implement empty query state — quick action grid (6 shortcuts: Create Invoice, Create Purchase, Add Customer, Add Supplier, Receive Payment, Make Payment) + recent items list (up to 5, with relative time). *(0.125 d)*
- [x] 3.9 Implement action panel (right 40%) — `EntityHeader` (icon, title, subtitle, metadata rows) + `ActionList` (vertical list of action buttons with labels); shows "Select a result" placeholder when nothing selected. *(0.125 d)*
- [x] 3.10 Implement mobile layout (< 768px) — single column; tapping result pushes action view with back arrow; `LayoutBuilder` or `MediaQuery` breakpoint detection. *(0.125 d)*

### 3E — Result tile & action panel widgets (~0.25 d)

- [x] 3.11 Create `lib/features/search/search_result_tile.dart` — tile widget with entity icon (from `_entityIcon` map), title, subtitle; highlighted on selection; tap handler calls `selectedResultProvider`. *(0.125 d)*
- [x] 3.12 Create `lib/features/search/search_action_panel.dart` — action panel widget with entity header and action buttons; each button calls the action callback. *(0.125 d)*

### 3F — Client-side page registry (~0.125 d)

- [x] 3.13 Create `lib/features/search/search_registry.dart` — static list of page/action definitions mirroring the backend `PAGE_ACTIONS`; used for the empty-state quick actions and client-side page search fallback. *(0.125 d)*

---

## Phase 4 — Navigation integration (~1.5 d)

### 4A — Shell tab providers (~0.25 d)

- [x] 4.1 Create `lib/features/shell/shell_tab_providers.dart` — `salesTabProvider`, `purchasingTabProvider`, `productionTabProvider`, `inventoryTabProvider` as `StateProvider<int>` with default 0. *(0.125 d)*
- [x] 4.2 Create `lib/features/shell/shell_tab_indices.dart` — `SalesTab`, `PurchasingTab`, `ProductionTab`, `InventoryTab` abstract classes with named `static const int` constants. *(0.125 d)*

### 4B — Shell integration (~0.5 d)

- [x] 4.3 Update `SalesShell` — replace local `_index` with `ref.watch(salesTabProvider)`; `onDestinationSelected` writes to provider. *(0.125 d)*
- [x] 4.4 Update `PurchasingShell` — same pattern with `purchasingTabProvider`. *(0.125 d)*
- [x] 4.5 Update `ProductionShell` — same pattern with `productionTabProvider`. *(0.125 d)*
- [x] 4.6 Update `InventoryShell` — same pattern with `inventoryTabProvider`. *(0.125 d)*

### 4C — Route resolution (~0.5 d)

- [x] 4.7 Create `lib/features/search/search_navigation.dart` — `resolveNavigation(result, action)` function with the full switch expression mapping all entity+action pairs to `NavigationTarget`; `NavigationTarget` class with `path`, `extra`, `tabIndex`, `dialog`, `dialogParams`, `fetchFirst`. *(0.25 d)*
- [x] 4.8 Implement `_setShellTab(ref, path, tabIndex)` helper — maps GoRouter path to its tab provider and sets the index. *(0.125 d)*
- [x] 4.9 Implement `_executeAction(context, ref, result, action)` — close dialog, set tab provider if needed, navigate via `context.go()` or `context.push()` with extra; handle `fetchFirst` by calling API before navigating; invoke dialog via `addPostFrameCallback` if needed. *(0.125 d)*

### 4D — Keyboard shortcut & search icon (~0.25 d)

- [x] 4.10 Register `Ctrl+K` in `AppShell` — add `Focus` + `onKeyEvent` handler to detect `LogicalKeyboardKey.keyK` with `isControlPressed`; call `showGlobalSearchDialog(context)`. Register independently from `screen_shortcuts.dart`. *(0.125 d)*
- [x] 4.11 Add search icon button to `AppShell` AppBar — `IconButton(icon: Icon(Icons.search), tooltip: 'Search (Ctrl+K)')`; visible on all screens including mobile. *(0.125 d)*

---

## Phase 5 — L10n + accessibility (~0.25 d)

- [x] 5.1 Add search-related l10n keys to `app_en.arb` — `searchHint`, `searchNoResults`, `searchLoading`, `searchError`, `searchQuickActions`, `searchRecent`, `searchSelectResult`, `searchClearRecent`, `searchClose`. *(0.125 d)*
- [x] 5.2 Regenerate localizations (`flutter gen-l10n`). *(0.03 d)*
- [x] 5.3 Add `Semantics` labels to search dialog, result tiles, and action buttons for screen reader support. *(0.0625 d)*

---

## Phase 6 — Final verification (~0.25 d)

- [x] 6.1 Run `npm run typecheck` and `npm run lint` on server — zero issues. *(0.0625 d)*
- [x] 6.2 Run `flutter analyze` — zero issues. *(0.0625 d)*
- [x] 6.3 Run `npm test` (Jest) — all existing + new search tests pass. *(0.0625 d)*
- [x] 6.4 Manual verification: Ctrl+K opens dialog from any screen; search returns grouped results; selecting result shows actions; clicking action navigates correctly; mobile layout works; recent items persist; empty state shows quick actions + recents; error states display correctly. *(0.0625 d)*

---

## Parallelization plan

| Stream | Phases | Effort |
| --- | --- | --- |
| **Backend** | 0 + 1 + 2 | 3.5 d |
| **Frontend** | 3 + 4 + 5 | 4.25 d |
| **Verification** | 6 | 0.25 d |

Phases 0–2 (backend, 3.5 d) can start immediately. Phase 3 (frontend, 2.5 d) can start in parallel once Phase 1 API is stable (after ~1.5 d of backend work). Phase 4 depends on Phase 3. Phase 5 is lightweight and can land with Phase 3. Phase 6 closes out.

**Sequential estimate ≈ 9.5 d. With 2 streams (backend + frontend in parallel): ≈ 7.0 d.**

---

## Risks

- **Entity detail dialogs** (product, invoice, PO, etc.) — many entities have dialog-only detail views, not GoRouter sub-routes. The search navigates to the shell tab and invokes the dialog; this requires the shell to be mounted before the dialog can open. The `addPostFrameCallback` approach handles this, but timing may need adjustment.
- **Invoice print** requires fetching the full `Invoice` object before navigation — adds an API call latency. Consider prefetching or caching.
- **SalesInvoiceFormPage** has no `customerId` param — "Create Invoice for Customer X" navigates to the form without pre-filling. This is a known limitation documented in the spec.
- **Tab provider reset** — when the user navigates away from a shell and back, the tab index persists (Riverpod StateProvider). This is correct behavior but may surprise users who expect the default tab.
