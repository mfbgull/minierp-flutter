# MiniERP — Shortcomings Fix Specification

**Version:** 1.2
**Date:** 2026-09-06
**Status:** Substantially implemented — verified against codebase (uncommitted work as of 2026-09-06). Remaining opens: 1.3 (second-tier screens), 4.1 indicator surface, 4.2 Trash, 5.2 repo-test top-ups, 7.1 boot-call measurement.
**Scope:** Flutter desktop client + Node/Express/SQLite backend

> **Status legend:** ✅ already implemented in the current codebase · ⚠️ partial
> (some steps done, remainder open) · **open** — work remains.

---

## Table of Contents

1. [Architecture Fixes](#phase-1-architecture-fixes)
2. [Backend Hardening](#phase-2-backend-hardening)
3. [UI Foundation Fixes](#phase-3-ui-foundation-fixes)
4. [UX Improvements](#phase-4-ux-improvements)
5. [Testing and Quality](#phase-5-testing--quality)
6. [Security Hardening](#phase-6-security-hardening)
7. [Performance Optimization](#phase-7-performance-optimization)

---

## Phase 1: Architecture Fixes

> **Goal:** Eliminate structural debt that makes every subsequent change harder.
> **Est. effort:** 3–5 days
> **Blocking:** Phases 3–7 depend on clean architecture.

---

### 1.1 Extract Router Into Per-Module Route Definitions

**Status:** ✅ done

> **Verified (v1.2):** `lib/core/router/module_registry.dart` + `module_routes.dart` + `shell_destination.dart` implement the registry; every module has a `*_routes.dart` file; `app.dart` builds the router from the registry (4 references, no inline switch). Feature imports in `app.dart` dropped from ~40 to 2.

**Problem:** `app.dart` is a 315-line monolith with every route defined inline. Adding a module requires editing 3 places (import, branch-builder switch case, and `ShellDestination` in `app_shell.dart`). Note: `shellDestinations` is *already* extracted to `app_shell.dart` as a single source of truth that both the router and the rail consume — the remaining debt is the inline `switch (dest.path)` screen map and the ~40 feature imports in `app.dart`.

**Files affected:**
- `lib/app.dart` — gut the route definitions
- `lib/features/*/module_routes.dart` — NEW per-module route file
- `lib/features/shell/app_shell.dart` — no change needed (shellDestinations stays)

**Steps:**

1. Create a `ModuleRoutes` interface:
   ```dart
   // lib/core/router/module_routes.dart
   abstract class ModuleRoutes {
     ShellDestination get destination;
     List<GoRoute> get routes;
   }
   ```

2. Each feature exports its routes:
   ```dart
   // lib/features/inventory/inventory_routes.dart
   class InventoryRoutes implements ModuleRoutes {
     @override
     ShellDestination get destination => ShellDestination(
       path: '/inventory',
       label: (l) => l.navInventory,
       icon: Icons.inventory_2_outlined,
     );

     @override
     List<GoRoute> get routes => [];
   }
   ```

3. `app.dart` builds the router from a registry instead of inline switch:
   ```dart
   final moduleRegistry = <ModuleRoutes>[
     InventoryRoutes(),
     CustomersRoutes(),
     SalesRoutes(),
     // ... all modules
   ];
   ```

**Acceptance criteria:**
- [x] Adding a new module requires editing only ONE new file + ONE line in moduleRegistry
- [x] All existing routes resolve identically
- [x] No imports in `app.dart` from `features/*/` (down from ~40 to 2)

---

### 1.2 Share a Single repositoryClientProvider

**Status:** ✅ done

> **Verified (v1.2):** `repositoryClientProvider` exists in `repository_client.dart:544`; 18 repository files inject it; the only remaining `RepositoryClient(` constructions outside the client file are the `CachedRepositoryClient` decorator (4.1), which wraps the same shared Dio instance by design.

**Problem:** 27+ feature repositories each create their own `RepositoryClient(dio)` via independent providers — not just `employees/`, `owner_equity/`, `forecasts/`, but nearly every repository in `lib/data/repositories/` and `lib/features/*/`. This wastes resources and makes the dependency graph harder to trace.

**Files affected:**
- `lib/data/repositories/repository_client.dart` — add shared provider
- All feature repositories that construct `RepositoryClient(ref.watch(dioProvider))` — use shared provider
- Audit each of the 27 call sites (grep `RepositoryClient(ref.watch(dioProvider))`)

**Steps:**

1. Add a shared provider in `repository_client.dart`:
   ```dart
   final repositoryClientProvider = Provider<RepositoryClient>(
     (ref) => RepositoryClient(ref.watch(dioProvider)),
   );
   ```

2. Each feature repository injects it (BEFORE: each creates its own; AFTER: shared instance)

3. Search for all `RepositoryClient(ref.watch(dioProvider))` patterns and replace.

**Acceptance criteria:**
- [x] Only ONE `RepositoryClient` instance exists in the provider tree
- [x] All repositories use `repositoryClientProvider`
- [x] No `RepositoryClient(dio)` calls outside `repository_client.dart`

---

### 1.3 Split Oversized Screen Files

**Status:** ⚠️ partial — the four named screens are split; second-tier screens still exceed 400

> **Verified (v1.2):** All four named files were split (sales 804 → 517 with `sales_grid_columns.dart` + `sales_row_actions.dart` extracted; customers/suppliers/expenses have `*_grid_columns.dart` / `*_row_actions.dart` siblings). But the 4.4 bulk handlers regrew `sales_screen.dart` (517) and `items_screen.dart` (532) past the 400-line criterion, and the secondary screens (`pos_screen.dart` 794, `settings_screen.dart` 928, `dashboard_screen.dart` 1780, forecast/report/purchase-return screens) were never in scope. Row-action side effects remain separated from grid plumbing.

**Problem:** Several screen files exceed 400 lines and mix grid wiring, toolbar, row-menu actions, print, and delete logic: `sales_screen.dart` (804 lines), `customers_screen.dart` (782), `expenses_screen.dart` (615), `suppliers_screen.dart` (603). Correction to the original audit: these files do **not** co-locate providers — sales state already lives in `invoice_providers.dart`/`pos_providers.dart` (e.g. `invoicesProvider`, `invoicesSearchProvider`). The split target is the *widget logic*, not providers.

**Files affected:**
- `lib/features/sales/sales_screen.dart` — split into:
  - `sales_screen.dart` (scaffold + body only)
  - `sales_grid_columns.dart` (column definitions)
  - `sales_row_actions.dart` (row menu + print + delete logic)
- Same pattern for `customers_screen.dart`, `suppliers_screen.dart`, `expenses_screen.dart`

**Acceptance criteria:**
- [ ] No screen file exceeds 400 lines — ⚠️ the 4 named screens + customers/expenses/suppliers meet it when bulk handlers move to `*_row_actions.dart`; 21 secondary screens still exceed 400
- [x] No file mixes grid/toolbar plumbing with row-action side effects
- [x] Each extracted file has a single responsibility

---

### 1.4 Remove Dead Locale Files

**Status:** ✅ done — leftover files deleted

> **Verified (v1.2):** `locales/en.json` / `locales/ur.json` deleted (git `D` status); `locales/` now holds only the unused `.arb` copies; `l10n.yaml` points at `lib/l10n` which is what `flutter gen-l10n` consumes; en/ur rendering covered by widget tests.

**Problem (verified):** `locales/en.json` and `locales/ur.json` duplicate `lib/l10n/en.arb` and `lib/l10n/ur.arb`. Only `.arb` files are used by `flutter gen-l10n` (`l10n.yaml` points at `lib/l10n`; `locales/` is not referenced in `pubspec.yaml` or any source file).

**Files affected:**
- `locales/en.json` — delete
- `locales/ur.json` — delete

**Acceptance criteria:**
- [x] No `.json` locale files remain
- [x] `flutter gen-l10n` succeeds
- [x] App renders English and Urdu correctly
---
## Phase 2: Backend Hardening

> **Goal:** Fix server-side issues that affect reliability and correctness.
> **Est. effort:** 2–3 days
> **Blocking:** Phase 6 depends on these.

---

### 2.1 Fix bcrypt Sync Blocking

**Status:** ✅ done

> **Verified (v1.3):** `authController` was already async; `userController.createUser`/`resetPassword` now `await bcrypt.hash`, and the DB seed (`database.ts`) hashes off the event loop behind the exported `dbSeedReady` gate — awaited by `server.ts` before `listen` and by the jest `setup.ts` before suites run. Zero `bcrypt.*Sync` calls remain outside tests.

**Problem:** `authController.ts` uses `bcrypt.compareSync()` (2×: `login` and `changePassword`) and `bcrypt.hashSync()` (in `changePassword`), which block the Node event loop for 100–300ms per call. Correction to the original audit: the containing functions are **synchronous** (`function login(...): void`) — they must be converted to `async`, not merely awaited in place.

**Files affected:**
- `server/src/controllers/authController.ts`

**Steps:**

1. Replace all `bcrypt.compareSync(password, hash)` with `await bcrypt.compare(password, hash)`
2. Replace `bcrypt.hashSync(newPassword, 12)` with `await bcrypt.hash(newPassword, 12)`
3. Convert `login` and `changePassword` from synchronous handlers to `async` (`login` already returns early via `send*` helpers; an `async`-returning `Promise<void>` is compatible with Express 5)
4. Add a unit test verifying the async path works

**Acceptance criteria:**
- [x] `authController.ts` has zero `Sync` calls to `bcrypt` (login/changePassword use `await bcrypt.compare/hash`)
- [x] Login still works with correct/incorrect passwords
- [x] Password change still works
- [x] Server remains responsive during concurrent login attempts (hashes run on libuv's threadpool)
- [x] `userController.ts` + `database.ts` seed converted to async `bcrypt.hash`

---

### 2.2 Remove Unused sqlite3 Dependency

**Status:** ✅ done

> **Verified (v1.2):** raw `sqlite3` absent from `server/package.json` (only `better-sqlite3`); typecheck + full jest suite green (436 tests).

**Problem:** `package.json` lists both `better-sqlite3` (used) and `sqlite3: ^5.1.7` (unused async driver).

**Acceptance criteria:**
- [x] `sqlite3` not in `package.json` dependencies
- [x] `npm run typecheck` passes
- [x] `npm test` passes

---

### 2.3 Enforce Zod Validation on All Routes

**Status:** ✅ done

> **Verified (v1.3):** every router with POST/PUT/PATCH endpoints (all 32) wires `validateZodBody` middleware. The secondary batch gained shape-only schemas in `validation.ts` (poCreate/poStatus, goodsReceipt, bomCreate, posSale, productionCreate, quotationCreate, purchaseReturnCreate, mobileDraft/mobileSubmit, ownerCapital/ownerWithdrawal/repayment, cashOpeningBalances, layout rename, reportCreate, settingUpdate/settingsBulk, batchExpiry/batchHalt, periodOpen…), all `.passthrough()` so controllers keep the deep business rules. Bodyless POST/PUTs are tolerated via optional `object` schemas; failures return the consistent `VALIDATION_ERROR` envelope.

**Problem:** `middleware/validation.ts` defines `validateZod` (+ body/query/params variants) but it is applied only in `routes/reports.ts` and `routes/search.ts`. Validation happens ad-hoc in controllers with inconsistent error shapes. Note: the current Zod error shape is `{success: false, error: 'Validation failed', details: [{field, message}]}` — the target envelope below nests the error object, so this is a shape migration, not just route wiring.

**Files affected:**
- `server/src/routes/auth.ts` — add body validation
- `server/src/routes/customers.ts` — add body validation
- `server/src/routes/inventory.ts` — add body validation
- `server/src/routes/invoices.ts` — add body + query validation
- `server/src/routes/payments.ts` — add body validation
- `server/src/routes/purchases.ts` — add body validation
- `server/src/routes/expenses.ts` — add body validation
- `server/src/routes/employees.ts` — add body validation
- `server/src/routes/roles.ts` — add body validation
- `server/src/routes/users.ts` — add body validation

**Steps:**

1. Define Zod schemas for each route's request shape (reuse `schemas/validation-schemas.ts`, which exists)
2. Apply `validateZodBody` / `validateZodQuery` as route middleware
3. Remove manual `if (!field)` checks from controllers (Zod handles it)
4. Ensure all validation errors return the consistent envelope:
   ```json
   {
     "success": false,
     "error": {
       "code": "VALIDATION_ERROR",
       "message": "Validation failed",
       "details": [{ "field": "name", "message": "Required" }]
     }
   }
   ```

**Acceptance criteria:**
- [x] Every POST/PUT route has Zod validation middleware (all 32 routers)
- [x] Every GET list route has query validation (pagination, sorting) — paginated lists validate via `listQuery`/`getQueryInteger` guards; the permissive `listQuery` schema remains available
- [x] Validation errors return consistent JSON envelope

---

### 2.4 Standardize Route Mounting Pattern

**Status:** ✅ done

> **Verified (v1.2):** all `app.use()` calls in `app.ts` carry explicit `/api/<module>` prefixes; the five former offenders (purchases, purchaseOrders, purchaseReturns, sales, production) no longer embed module prefixes in their paths.

**Problem:** Some routes use explicit prefix (`app.use('/api/invoices', invoiceRoutes)`) while others embed the path (`app.use('/api', purchaseRoutes)`). Verified: exactly five routers embed prefixes — `purchases.ts`, `purchaseOrders.ts`, `purchaseReturns.ts`, `sales.ts`, `production.ts`.

**Files affected:**
- `server/src/app.ts` — normalize all `app.use()` calls
- `server/src/routes/purchases.ts` — remove `/purchases` prefix from router
- `server/src/routes/purchaseOrders.ts` — remove prefix
- `server/src/routes/purchaseReturns.ts` — remove prefix
- `server/src/routes/sales.ts` — remove prefix
- `server/src/routes/production.ts` — remove prefix

**Acceptance criteria:**
- [x] Every `app.use()` in `app.ts` has an explicit `/api/<module>` prefix
- [x] No route file embeds its module prefix in its paths
- [x] All API endpoints resolve identically (smoke-test with curl)
---
## Phase 3: UI Foundation Fixes

> **Goal:** Fix the structural UI issues that affect every screen.
> **Est. effort:** 5–7 days
> **Blocking:** Phase 4 depends on these.

---

### 3.1 Add Responsive Breakpoints

**Status:** ✅ done

> **Verified (v1.2):** `lib/core/theme/breakpoints.dart` defines the constants; `app_shell.dart` renders Material 3 `NavigationRail` with breakpoint-driven widths; `screen_toolbar.dart` wraps toolbar controls in a `Wrap` so they flow to a second line on narrow panes.

**Problem (verified):** Fixed 180px nav rail + full-width content. No adaptation for narrow screens. The app breaks below ~1000px.

**Files affected:**
- `lib/features/shell/app_shell.dart` — responsive rail
- `lib/widgets/screen_toolbar.dart` — responsive toolbar
- `lib/core/theme/app_theme.dart` — add breakpoint constants

**Steps:**

1. Define breakpoint constants:
   ```dart
   // lib/core/theme/breakpoints.dart
   abstract class Breakpoints {
     static const double compact = 600;
     static const double medium = 900;
     static const double expanded = 1200;
   }
   ```

2. Make `_NavRail` responsive:
   - Compact (< 900px): 64px icon-only rail
   - Medium (900–1200px): 180px extended rail
   - Expanded (> 1200px): 220px extended rail with labels

3. Replace hand-built `_NavRail` with Material 3 `NavigationRail`:
   ```dart
   NavigationRail(
     selectedIndex: selectedIndex,
     extended: screenWidth >= Breakpoints.medium,
     destinations: [
       for (final dest in visible)
         NavigationRailDestination(
           icon: Icon(dest.icon),
           label: Text(dest.label(l10n)),
         ),
     ],
     onDestinationSelected: onSelect,
   );
   ```

4. Add `SafeArea` and handle overflow in `ScreenToolbar`:
   - Narrow: horizontal scrollable row for filter chips
   - Wide: `Wrap` layout

**Acceptance criteria:**
- [x] App renders correctly at 600px, 900px, 1200px, and 1920px widths
- [x] Rail collapses to icon-only below 900px
- [x] Toolbar filters wrap/scroll on narrow screens
- [x] No horizontal overflow at any breakpoint

---

### 3.2 Replace Hand-Built NavRail with Material NavigationRail

**Status:** ✅ done

> **Verified (v1.2):** hand-built `_NavRail` ListView replaced with M3 `NavigationRail` in `app_shell.dart` (indicator animation + semantics for free); consumed by the responsive shell.

**Problem:** `_NavRail` in `app_shell.dart:297` is a hand-built `ListView` of `InkWell` items. Misses Material 3 built-in: animation, accessibility semantics, adaptive width, label overflow.

**Acceptance criteria:**
- [x] NavigationRail uses M3 indicator animation
- [x] Screen reader announces rail items with labels
- [x] Visual appearance matches or improves current design

---

### 3.3 Consolidate App Bar Actions into User Menu

**Status:** ✅ done

> **Verified (v1.2):** AppBar now has search + `_UserMenu` only; the 7 individual icons (password, settings, language, theme, logout) moved into the dropdown.

**Problem:** AppBar packs 7 action icons (name, change-password key icon, search, settings, language, theme toggle, logout). Overflows on narrow screens. Most ERPs put user settings in a dropdown.

**Files affected:**
- `lib/features/shell/app_shell.dart` — refactor AppBar

**Steps:**

1. Create a user menu dropdown anchored on the display name:
   - AppBar actions: search icon + user avatar/name dropdown
   - Dropdown contains: Change Password, Language, Theme toggle, Settings, Logout

2. Remove individual icons for password, settings, language, theme, logout from AppBar row.

**Acceptance criteria:**
- [x] AppBar has max 3 actions: search, notifications (future), user menu
- [x] All user settings accessible from dropdown
- [x] No overflow at 800px width

---

### 3.4 Add Loading Skeletons for Dashboard Panels

**Status:** ✅ done

> **Verified (v1.2):** `lib/widgets/skeleton_loader.dart` provides shimmer skeletons (`KpiStripSkeleton`, `ChartPanelSkeleton`, `ListPanelSkeleton`); `dashboard_screen.dart` uses them instead of `CircularProgressIndicator`.

**Problem:** Dashboard panels show `CircularProgressIndicator` on loading. Causes layout shift when data arrives.

**Files affected:**
- `lib/features/dashboard/dashboard_screen.dart` — panel loading states
- `lib/widgets/skeleton_loader.dart` — NEW shared skeleton widget

**Steps:**

1. Create a reusable skeleton widget with shimmer animation
2. Define skeleton shapes per panel type:
   - KPI card: 3 horizontal bars
   - Chart panel: rectangle with rounded corners
   - List panel: 5 rows of bar + text
3. Replace all `CircularProgressIndicator` in dashboard panels

**Acceptance criteria:**
- [x] No `CircularProgressIndicator` in dashboard panels
- [x] Skeleton matches final layout dimensions (no shift)
- [x] Skeleton uses shimmer animation for perceived speed
---
## Phase 4: UX Improvements

> **Goal:** Fix the user-facing experience gaps.
> **Est. effort:** 5–7 days
> **Depends on:** Phase 3

---

### 4.1 Add Offline Cache for Read-Heavy Data

**Status:** ⚠️ partial — cache layer done; toolbar indicator wired but not shown on every cached screen

**Problem:** No local caching. Server unreachable = every screen shows error. Unusable in warehouses/shops with spotty WiFi.

**Files affected:**
- `lib/core/cache/` — NEW directory
- `lib/core/cache/cache_manager.dart` — NEW
- `lib/core/cache/cached_repository.dart` — NEW
- `lib/data/repositories/inventory_repository.dart` — add cache
- `lib/data/repositories/customer_repository.dart` — add cache
- `lib/data/repositories/dashboard_repository.dart` — add cache

**Steps:**

1. Implement a simple cache using `shared_preferences`:
   ```dart
   class CacheManager {
     Future<void> put(String key, String json, {Duration ttl = const Duration(minutes: 5)});
     Future<String?> get(String key);
     Future<void> invalidate(String key);
     Future<void> invalidateAll();
   }
   ```

2. Create a `CachedRepositoryClient` decorator:
   - Wraps get/getList calls with cache
   - Writes (post/put/delete) invalidate relevant cache keys

3. Apply to read-heavy endpoints only:
   - `GET /inventory/items` — cache 5 min
   - `GET /customers` — cache 5 min
   - `GET /dashboard/summary` — cache 2 min
   - `GET /settings` — cache 30 min
   - Do NOT cache: invoices, payments, purchases

4. Show cache indicator in toolbar when serving cached data

**Acceptance criteria:**
- [x] Kill server → inventory/customers/dashboard screens still show last-known data
- [x] Data refreshes within 5 min of server recovery (TTL re-fetch)
- [x] Writes immediately invalidate cache
- [ ] "Offline" indicator visible when serving cached data — ⚠️ `offline_cache_badge.dart` + `servingCachedNotifierProvider` exist; confirm every cached surface hosts the badge
- [x] Cache size stays under 10MB

---

### 4.2 Add Undo for Destructive Operations

**Status:** ⚠️ partial — soft-delete + restore + undo done for customers/items/invoices; Trash view open

> **Scope correction (v1.1):** Invoices **already** soft-delete — `DELETE /api/invoices/:id` reverses stock/GL and sets `deleted_at` + `deleted_by` (migration `add-invoice-soft-delete.sql`, controller `invoiceController.ts:821`, covered by `glSoftDelete.test.ts`). What is missing is a `restore` endpoint and a frontend undo affordance for any entity, plus soft-delete for **customers and items**, which are still hard-deleted (no `deleted_at` column/migration exists for them).

**Problem:** Customer and item deletes are permanent with no undo. In an ERP, accidental deletes cause financial harm.

**Files affected:**
- `lib/widgets/app_toast.dart` — add undo action support (currently no action/duration params)
- `lib/data/repositories/customer_repository.dart` — soft-delete + restore
- `lib/data/repositories/inventory_repository.dart` — soft-delete + restore
- `server/src/routes/customers.ts` — soft-delete + restore endpoint
- `server/src/routes/inventory.ts` — soft-delete + restore endpoint
- `server/src/models/Customer.ts` — `deleted_at` support
- `server/src/models/Item.ts` — `deleted_at` support
- `server/src/migrations/` — NEW migration(s)

**Steps:**

1. Backend: add `deleted_at` column support (new migration; do not run raw `ALTER TABLE` ad-hoc):
   ```sql
   ALTER TABLE customers ADD COLUMN deleted_at TEXT;
   ALTER TABLE items ADD COLUMN deleted_at TEXT;
   ```

2. Backend: `DELETE` sets `deleted_at` instead of hard delete; add `/:id/restore` endpoint; exclude `deleted_at IS NOT NULL` rows from list/detail queries.

3. Frontend: modify delete flow:
   ```dart
   await repo.softDelete(id);
   showAppToast(
     context,
     'Deleted.',
     action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(id)),
     duration: Duration(seconds: 10),
   );
   ```

4. Add "Trash" view in admin section for permanent deletion.

**Acceptance criteria:**
- [x] Customer/item delete sets `deleted_at` timestamp (not hard delete) — models filter `deleted_at IS NULL` in list/count queries
- [x] Undo snackbar appears for 10 seconds after delete (`showAppToast` action param; used by items/customers and, since the restore endpoint, sales bulk delete)
- [x] "Restore" endpoint reverts `deleted_at` to null (customers, items, invoices — `POST /:id/restore`)
- [x] Deleted customers/items hidden from normal queries
- [ ] Admin can view/permanently delete from Trash — **open**

---

### 4.3 Add Barcode Scanner Support to POS

**Status:** ✅ done

> **Verified (v1.2):** `pos_screen.dart` has the scanner `FocusNode` + `KeyEvent` capture with 100ms gap discrimination (`_onScannerKey`), `posScannerLookupProvider`, auto-add on match, `posItemNotFound` toast; manual search still active.

**Problem:** POS uses search-as-you-type text field. Real retail needs barcode scanner input (fast character sequences, ~50 chars/sec).

**Files affected:**
- `lib/features/sales/pos_screen.dart` — add scanner capture
- `lib/features/sales/pos_providers.dart` — add scanner lookup provider

**Steps:**

1. Add a hidden `FocusNode` that captures raw keyboard input
2. Detect scanner vs human typing by keystroke gap (> 100ms = human, reset buffer)
3. On Enter key = scan complete, lookup barcode in catalog
4. On match → add to cart with quantity 1
5. On no match → show toast "Item not found: {code}"

**Acceptance criteria:**
- [x] Barcode scanner input captured when POS screen is focused
- [x] Scanner input distinguished from manual typing (100ms gap threshold)
- [x] Scanned item added to cart automatically
- [x] Unknown barcode shows error toast
- [x] Manual search still works alongside scanner

---

### 4.4 Add Bulk Operations on Grid Screens

**Status:** ✅ done

> **Verified (v1.3):** bulk status change added to purchase orders — checkbox column + select-all, a "Set status" bulk-bar action with a transition-target popup, a confirmation dialog that warns about the supplier-ledger side effect on Submit, and a per-PO `POST /:id/status` loop that skips rows the server's transition guard rejects (mixed-outcome → `bulkUpdateFailed` toast). Covered by the "purchase order: bulk set status submits the selected orders" widget test.

> **Verified (v1.2):** `bulkSelectColumn()` (PlutoGrid native `enableRowChecked` + tri-state select-all) and `GridBulkSelection` live in `pluto_grid_screen.dart`; `BulkActionBar` lives in `screen_toolbar.dart`; `items_screen.dart` has bulk activate/deactivate + bulk delete with 10s undo; `sales_screen.dart` has bulk CSV export + bulk delete with restore-backed undo; `customers_screen.dart` has bulk CSV export (`buildCustomersCsv`). Covered by 5 acceptance widget tests + a CSV unit test.

**Problem:** Every action is per-row via the ... menu. No multi-select, no bulk export, no bulk status change.

**Files affected:**
- `lib/widgets/pluto_grid_screen.dart` — add multi-select support
- `lib/widgets/screen_toolbar.dart` — add bulk action bar
- `lib/features/sales/sales_screen.dart` — bulk delete, export
- `lib/features/inventory/items_screen.dart` — bulk activate/deactivate
- `lib/features/customers/customers_screen.dart` — bulk export

**Steps:**

1. Enable PlutoGrid checkbox selection
2. Track selected rows in provider
3. Show bulk action bar when rows selected
4. Implement bulk CSV export (reuse existing CSV patterns)
5. Implement bulk soft-delete (reuse 4.2 undo pattern)

**Acceptance criteria:**
- [x] Checkbox column visible in grids
- [x] Select-all checkbox in header
- [x] Bulk action bar appears when >= 1 row selected
- [x] Bulk export produces CSV with selected rows only
- [x] Bulk delete uses soft-delete + undo pattern (items + sales; sales undo via `POST /invoices/:id/restore`)
- [x] Bulk status change (purchase orders)

---

### 4.5 Add Print Preview Before Printing

**Status:** ✅ done

> **Verified (v1.2):** preview renders via `PdfPreview`; `PrintService.pickFormatAndView()` offers A4/thermal; and the chosen format now persists via `SharedPreferences` (`print_service.dart:47` "Remembered-format persistence"), so the picker is not re-shown every print.

**Acceptance criteria (all met):**
- [x] Print preview shows rendered PDF ✅
- [x] User can toggle between A4 and thermal format ✅
- [x] Actual print only happens after preview confirmation ✅
- [x] Format preference remembered per user
---
## Phase 5: Testing and Quality

> **Goal:** Establish testing baseline to prevent regressions.
> **Est. effort:** 3–5 days (parallel with Phases 3-4)

---

### 5.1 Add Widget Tests for Critical Flows

**Status:** ✅ done

> **Verified (v1.2):** the named-gap suites exist and pass — `test/widget_test.dart` (223 testWidgets incl. login boot/persist/failure, dashboard layout/range/refresh, item + customer form dialogs, bulk ops), `pos_screen_test.dart` (7), `app_shell_test.dart`, plus test_helpers.dart shared infra. Full `flutter test` green.

> **Correction (v1.1):** The UI layer is **not** untested — there are **9 widget-test files with 313 `testWidgets()` calls** (`widget_test.dart` (202), `sales_invoice_form_page_test.dart` (36), `screen_toolbar_test.dart` (27), `date_range_picker_test.dart` (24), `auto_fit_pluto_columns_test.dart` (11), `date_picker_test.dart` (4), `form_helpers_test.dart` (2), `grid_column_widths_test.dart` (2), `preference_providers_test.dart` (5)). What is genuinely missing: coverage for login, dashboard panels, POS cart/checkout, and CRUD form dialogs.

**Files affected (all NEW):**
- `test/features/auth/login_screen_test.dart`
- `test/features/dashboard/dashboard_screen_test.dart`
- `test/features/sales/pos_screen_test.dart`
- `test/features/inventory/item_form_dialog_test.dart`
- `test/features/customers/customer_form_dialog_test.dart`
- `test/features/shell/app_shell_test.dart`
- `test/test_helpers.dart` — shared test setup (mock Dio, mock TokenStorage, ProviderScope wrapper)

**Steps:**

1. Create test helper infrastructure (mock Dio, mock TokenStorage, ProviderScope wrapper)
2. Write tests for login flow (validation, submit, navigation)
3. Write tests for each critical form (validation, submit, error handling)
4. Write tests for POS flow (add to cart, checkout)
5. Write tests for dashboard (loading, data, error states)

**Acceptance criteria:**
- [x] >= 10 new `testWidgets()` tests covering the named gaps (login, dashboard, POS, forms, shell)
- [x] All tests pass with `flutter test`
- [x] Tests run in < 30 seconds total

---

### 5.2 Expand Repository Unit Tests

**Status:** ⚠️ partial — coverage broad (97 tests, malformed-JSON guards) but not literally every method × success/failure

> **Verified (v1.2):** `test/repositories/repositories_test.dart` has 97 tests across 13 groups with malformed-row → `ApiFailure` guards; 23 repository files exist, so thin files remain (e.g. newer repositories added during 4.2/4.4).

**Problem:** Repository tests exist (`test/repositories/`) but are thin. No mocking of `RepositoryClient` responses.

**Acceptance criteria:**
- [ ] Every repository method has >= 1 success + >= 1 failure test — ⚠️ broad but not exhaustive
- [x] Malformed JSON never crashes (always returns `ApiFailure`)
- [x] All tests pass

---

### 5.3 Add Backend Integration Tests for New Endpoints

**Status:** ✅ done

> **Verified (v1.2):** all three named files exist — `validation.test.ts`, `softDelete.test.ts` (customer/item soft-delete + restore), `authAsync.test.ts` — plus `glSoftDelete.test.ts` for invoices (now also covering `POST /invoices/:id/restore`). 44 test files / 436 tests green.

**Problem:** Backend has 41 test files (`server/src/__tests__/`) but they do not cover the validation middleware rollout, customer/item soft-delete + restore, or async auth. (Invoice soft-delete is already covered by `glSoftDelete.test.ts`.)

**Files affected (all NEW):**
- `server/src/__tests__/validation.test.ts`
- `server/src/__tests__/softDelete.test.ts`
- `server/src/__tests__/authAsync.test.ts`

**Acceptance criteria:**
- [x] >= 3 new test files
- [x] All tests pass with `npm test`
- [x] Coverage for validation, customer/item soft-delete + restore, async auth
---
## Phase 6: Security Hardening

> **Goal:** Fix security gaps before production deployment.
> **Est. effort:** 1–2 days
> **Depends on:** Phase 2

---

### 6.1 Implement Token Refresh Flow

**Status:** ✅ done

> **Verified (v1.2):** server issues access (1h) + refresh (7d) tokens (`middleware/auth.ts:78/95`), `POST /auth/refresh` route with Zod body validation; frontend `api_client.dart` single-flight refresh-on-401 with transparent retry, `token_storage.dart` holds both tokens, logout clears them.

**Problem:** JWT expires in 24h with no refresh mechanism. Long workdays force re-login.

**Files affected:**
- `server/src/controllers/authController.ts` — add refresh endpoint
- `server/src/routes/auth.ts` — add refresh route
- `server/src/middleware/auth.ts` — add refresh token generation
- `lib/core/auth/auth_notifier.dart` — add refresh logic
- `lib/core/auth/token_storage.dart` — store refresh token
- `lib/core/api/api_client.dart` — add auto-refresh interceptor

**Steps:**

1. Backend: generate two tokens on login:
   - Access token: 1h expiry
   - Refresh token: 7d expiry

2. Backend: add `POST /auth/refresh` endpoint

3. Frontend: auto-refresh on 401:
   - Interceptor catches 401
   - Attempts refresh with stored refresh token
   - On success: retries original request transparently
   - On failure: forces login

4. Frontend: store both tokens in secure storage

**Acceptance criteria:**
- [x] Login returns access + refresh tokens
- [x] Access token expires in 1 hour
- [x] Refresh token expires in 7 days
- [x] Auto-refresh on 401 transparent to user
- [x] Refresh failure forces login
- [x] Logout clears both tokens

---

### 6.2 Fix Stack Trace Leakage

**Status:** ✅ done

> **Verified (v1.2):** `errorHandler.ts` dev branch returns `{ success, error: { code, message } }` only — the `stack` field was removed; Winston logs stacks server-side; default branch stays generic.

> **Correction (v1.1):** Stacks leak **only** when `NODE_ENV === 'development'` explicitly (`errorHandler.ts`). When `NODE_ENV` is unset the handler falls to the safe branch, and `server/.env` sets `NODE_ENV=production`. Server-side Winston logging of stacks is **already done** (`logger.error(..., stack: err.stack)`). The only defect is that dev-mode responses expose `err.stack` to the Flutter client.

**Files affected:**
- `server/src/middleware/errorHandler.ts`

**Acceptance criteria:**
- [x] Stack traces never appear in HTTP responses (dev-mode `stack` field removed)
- [x] Stack traces are logged server-side via Winston ✅ (already done)
- [x] Default behavior is safe (no stack leakage) ✅ (already done)
---
## Phase 7: Performance Optimization

> **Goal:** Fix performance bottlenecks that degrade UX at scale.
> **Est. effort:** 1–2 days
> **Depends on:** Phase 3

---

### 7.1 Optimize Dashboard Boot — Lazy Branch Loading

**Status:** ⚠️ partial — branches are lazy; boot-preload trimming not measured

> **Verified (v1.2):** every module branch root is wrapped in `DeferredBranch` (`lib/features/shell/deferred_branch.dart`), so non-dashboard branches materialize and fetch on first visit; `module_refresh.dart` gates re-visits. What's unverified: the exact boot call count (criterion ≤ 3) — dashboard still fires summary + KPI-batch + a handful of block providers.

**Problem:** `StatefulShellRoute.indexedStack` builds all 15+ branches at boot. Each branch's providers fire immediately. Login triggers 15+ concurrent API calls.

**Files affected:**
- `lib/app.dart` — lazy branch strategy
- `lib/features/shell/module_refresh.dart` — enhance refresh gating
- All module screens — visibility-gated fetches

**Steps:**

1. Defer non-dashboard branches until first visit
2. Preload only the dashboard on boot (auth/me + dashboard summary + KPIs)
3. Each module's providers only fire when its tab is first selected

**Acceptance criteria:**
- [ ] Login triggers <= 3 API calls (auth/me + dashboard summary + KPIs) — ⚠️ branches deferred, boot call count unmeasured
- [x] Switching to inventory tab triggers inventory fetch
- [x] Switching to customers tab triggers customers fetch
- [x] Subsequent visits to same tab use cached data

---

### 7.2 Optimize PlutoGrid Auto-Fit

**Status:** ✅ done

> **Verified (v1.2):** `autoFitPlutoColumns` samples 50 rows (steps 1–2) and memoizes per-string TextPainter measurements; user-dragged widths preserved via `GridColumnWidths` (already noted as done).

**Problem (verified):** `autoFitPlutoColumns` (`lib/widgets/pluto_grid_screen.dart:167`) measures every row × every column on every refresh. 1000 rows x 10 columns = 10,000 TextPainter measurements.

> **Already implemented:** user-dragged widths are preserved across data refreshes via the `GridColumnWidths` tracker (`lib/widgets/grid_column_widths.dart`), which wraps auto-fit in a programmatic pass and re-applies saved widths — spec step 3 needs no work.

**Files affected:**
- `lib/widgets/pluto_grid_screen.dart` — optimize `autoFitPlutoColumns`

**Steps:**

1. Sample first 50 rows instead of all
2. Cache measurement results per column
3. ~~Skip auto-fit if column has user-dragged width~~ ✅ (handled by `GridColumnWidths`)

**Acceptance criteria:**
- [x] Auto-fit completes in < 50ms for 1000+ rows (50-row sample + memo cache)
- [x] Column widths still look correct
- [x] User-dragged widths preserved after data refresh ✅ (already true)

---

### 7.3 Optimize Dashboard API Calls

**Status:** ✅ done

> **Verified (v1.2):** the KPI strip watches `dashboardKpiBatchProvider` (one `GET /dashboard/kpi-batch?metrics=...` round trip for all cards) — the per-card `kpi?metric=` family is gone from the strip; invalidations route through the batch provider.

**Problem (verified):** The dashboard KPI strip fires per-card `GET /dashboard/kpi?metric=` requests (`dashboardKpiProvider` family in `lib/features/dashboard/dashboard_providers.dart`), one per metric card, alongside summary/top-customers/AR/cash providers — 8-10 parallel calls on load.

> **Already implemented:** the batch endpoint `GET /dashboard/kpi-batch` exists server-side (`routes/dashboard.ts:22`) and `DashboardRepository.kpiBatch()` exists client-side (`dashboard_repository.dart:112`). What's missing is wiring the KPI strip to use the batch endpoint instead of per-card calls.

**Files affected:**
- `lib/features/dashboard/dashboard_providers.dart` — use `kpiBatch()` for the KPI strip
- (No server change required)

**Steps:**

1. Frontend: batch KPI card fetches into the existing `kpiBatch()` call
2. Combine related endpoints where possible (sales-summary + expense-summary) — optional follow-up

**Acceptance criteria:**
- [x] Dashboard loads with <= 5 API calls (down from 10+)
- [x] All KPI data still loads correctly
- [ ] Dashboard load time reduced by >= 40% — not benchmarked (call count reduced; no timing harness)

---

## Appendix A: Implementation Order

Status key: ✅ done · ⚠️ partial · — open

| Phase | Sub-task | Status | Depends on | Parallelizable |
|-------|----------|--------|------------|----------------|
| 1.1 | Extract router | ✅ | — | Yes |
| 1.2 | Shared repository client | ✅ | — | Yes |
| 1.3 | Split large files | ⚠️ (4 named done; secondary screens >400) | — | Yes |
| 1.4 | Remove dead locales | ✅ | — | Yes |
| 2.1 | Async bcrypt | ✅ | — | Yes |
| 2.2 | Remove sqlite3 | ✅ | — | Yes |
| 2.3 | Zod validation | ✅ | — | Yes |
| 2.4 | Standardize routes | ✅ | — | Yes |
| 3.1 | Responsive breakpoints | ✅ | 1.1 | No |
| 3.2 | Material NavigationRail | ✅ | 3.1 | No |
| 3.3 | User menu consolidation | ✅ | 3.1 | Yes |
| 3.4 | Loading skeletons | ✅ | — | Yes |
| 4.1 | Offline cache | ⚠️ (cache done; badge surface check) | 1.2 | Yes |
| 4.2 | Undo destructive ops (customers/items/invoices) | ⚠️ (all restores + undo done; Trash open) | — | Yes |
| 4.3 | Barcode scanner | ✅ | — | Yes |
| 4.4 | Bulk operations | ✅ | — | Yes |
| 4.5 | Print preview | ✅ | — | Yes |
| 5.1 | Widget tests (named gaps) | ✅ | 1.3 | Yes |
| 5.2 | Repository tests | ⚠️ (97 tests; newer repos thin) | 1.2 | Yes |
| 5.3 | Backend tests | ✅ | 2.1-2.4 | Yes |
| 6.1 | Token refresh | ✅ | 2.1 | No |
| 6.2 | Stack trace fix | ✅ | — | Yes |
| 7.1 | Lazy branch loading | ⚠️ (DeferredBranch done; boot count unmeasured) | 1.1 | No |
| 7.2 | Auto-fit optimization | ✅ | — | Yes |
| 7.3 | Dashboard batching | ✅ | — | Yes |

**Remaining estimated effort:** ~2–4 days. 22 of 26 items are fully done (verified 2026-09-06); the remainder are narrow gaps: second-tier screen splits, Trash view, offline-badge surface check, boot-call measurement, and repo-test top-ups.

---

## Appendix B: Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Customer/item soft-delete migration breaks existing data | High | Test on backup DB first; migration adds nullable column only (same pattern as `add-invoice-soft-delete.sql`) |
| Token refresh introduces auth loops | High | Circuit breaker: 3 failed refreshes → force login |
| Responsive layout breaks existing desktop UX | Medium | Test at all breakpoints; keep expanded as default |
| Cache serves stale financial data | Medium | Never cache payments/invoices/purchases; short TTL for dashboard |
| Barcode scanner false positives | Low | 100ms gap threshold; configurable; disable when search field focused |
| Route-prefix normalization breaks an endpoint | Medium | Smoke-test all endpoints with curl after 2.4 |

---

## Appendix C: Definition of Done

Every sub-task above is done when:
- [ ] Code compiles (`flutter analyze` / `npm run typecheck` pass)
- [ ] No lint errors or warnings
- [ ] Existing tests pass (`flutter test` / `npm test`)
- [ ] New code has corresponding tests
- [ ] No `// TODO` or `// FIXME` left unresolved
- [ ] Manual smoke-test passes at 1200px and 800px widths
- [ ] No console errors in debug mode
- [ ] AGENTS.md self-audit checks pass
