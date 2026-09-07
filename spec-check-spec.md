# Specification Check: Bulk Operations Across All PlutoGrid Screens

> **Purpose of this document.** `spec.md` ("Extend Bulk Operations to All
> PlutoGrid Screens") was checked claim-by-claim against the working tree
> (September 7, 2026). This file records the verification results, the
> decisions taken from the clarifying interview, and the corrected spec.
> `spec.md` itself has been rewritten in place with the corrected content —
> this document is the audit trail explaining *why* each correction was
> made.
>
> Baseline: current working tree (includes uncommitted changes). All facts
> below were re-verified at check time. **Update (review round, 2026-09-07):**
> every **[re-verify]** mark has since been resolved against the server
> code — see §4 for the resolutions, and §2 for decisions D22–D25 added
> during the joint spec review.

---

## 1. Verification Results

### 1.1 What the spec got right ✓

| Claim | Verified |
|---|---|
| `GridBulkSelection` notifier exists (`lib/widgets/pluto_grid_screen.dart:85`) with `syncFromManager()` / `clear()` | ✓ |
| `bulkSelectColumn()` builds the checkbox column with tri-state select-all header (`pluto_grid_screen.dart:126`) | ✓ |
| `PlutoGridScreen` mixin exposes `enableBulkSelection` (default `false`, line 409) and auto-wires the column + `onRowChecked → syncFromManager()` (line 676) | ✓ |
| Selection resets when grid rows are replaced (page/filter/refresh) — `bulkSelection.clear()` at `pluto_grid_screen.dart:564` | ✓ |
| `BulkActionBar` widget exists in `lib/widgets/screen_toolbar.dart:188` (count + actions + close button) | ✓ |
| 4 screens already use the full pattern: `sales_screen.dart` (delete+export), `items_screen.dart` (activate/deactivate/delete+undo), `customers_screen.dart` (export), `purchase_orders_screen.dart` (set status) | ✓ |
| Sales screen bulk delete guards paid invoices; selection is IDs into the currently filtered rows; export runs over the filtered selection | ✓ |
| l10n keys `bulkDeleteSelected` / `bulkExportSelected` / `bulkActivateSelected` / `bulkDeactivateSelected` exist in en+ur ARBs | ✓ |
| No DB schema changes required | ✓ (with caveats — see §1.3) |

### 1.2 What the spec got wrong ✗

| # | Spec claim | Reality | Severity |
|---|---|---|---|
| 1 | `activity_log_screen`: "bulk delete, export" | **No delete endpoint exists** for log entries. Only `POST /activity-logs/cleanup` (age-based, requires `activity_log: purge`). It is an audit trail. | High — infeasible as written |
| 2 | `purchases_screen` + `purchase_returns_screen`: "bulk delete, export" | **No DELETE endpoints.** Purchases reverse via `POST /purchases/:id/void` (GL reversal); purchase returns via `POST /purchase-returns/:id/void` (stock/batch/supplier-balance reversal). "Delete" is not a thing here. | High |
| 3 | `owner_equity/*_tab.dart` listed as mixin users | The three owner-equity tabs (capital, withdrawals, personal loans) build **raw `PlutoGrid` widgets** — they do not use the `PlutoGridScreen` mixin. `enableBulkSelection => true` is a no-op there. | High |
| 4 | `sales_orders_screen` and `sales/invoice_returns_screen` missing from the table | Both use the mixin. Sales orders have `DELETE /sales-orders/:id` (draft-only guard server-side). Invoice returns are void-based (no delete). | Medium |
| 5 | `stock_movement_screen`, `stock_by_warehouse_screen`, `demand_forecast_screen`: "bulk delete, export" | Stock movements are an **immutable ledger**; stock-by-warehouse and forecasts are **computed/derived views**. No delete endpoints, and deleting them would be wrong. | High |
| 6 | "Physical counts: bulk delete, export" | `DELETE /inventory/physical-counts/:id` exists — this one is actually fine (kept, corrected to void-in-progress guard). | Low |
| 7 | "No new API endpoints needed" | True only for a subset of screens. The undo requirement (req. 6) implies restore endpoints that mostly don't exist (see §1.3). | Medium |
| 8 | Requirement 6: "Undo pattern for bulk delete: 10s toast" | Only 3 entities support restore today: invoices (`POST /invoices/:id/restore`), items (`POST /inventory/items/:id/restore`), customers (`POST /customers/:id/restore`). Employees/users **deactivate** (`is_active = 0`, no dedicated restore route — reactivate via `PUT`). Sales orders/quotations/payments/roles are **hard deletes** (no undo possible without new endpoints). | High |
| 9 | "Payments: bulk export" (only) | `DELETE /payments/:id` exists (hard delete, GL reversal) — payments can have delete, not just export. | Low |
| 10 | "Customers: bulk delete, activate/deactivate" | Feasible: customers have soft-delete + restore + `is_active` via `PUT /customers/:id`. The spec just undersold the existing restore support. | Info |
| 11 | "Roles: bulk delete" | Feasible but heavily guarded server-side (system roles cannot be deleted; roles with assigned users cannot be deleted). Partial failures will be common — needs the failure-dialog treatment. | Medium |
| 12 | Table omits `quotations_screen` | Uses the mixin; `DELETE /quotations/:id` exists (via `sales.ts` router, quotation permission). Quotations currently have toolbar CSV export over filtered rows. | Low |

### 1.3 API reality per entity (the ground truth table)

| Entity | Delete endpoint | Delete semantics | Restore/undo support | Export builder exists |
|---|---|---|---|---|
| Invoices | `DELETE /invoices/:id` | soft (`deleted_at`) | ✓ `POST /invoices/:id/restore` | ✓ `buildInvoicesCsv` |
| Inventory items | `DELETE /inventory/items/:id` | soft (`deleted_at` + `is_active=0`) | ✓ `POST /inventory/items/:id/restore` | ✗ |
| Customers | `DELETE /customers/:id` | soft | ✓ `POST /customers/:id/restore` | ✓ `buildCustomersCsv` |
| Employees | `DELETE /employees/:id` | **deactivate** (`is_active=0`) | reactivate via `PUT /employees/:id` (update perm) | ✗ |
| Users | `DELETE /users/:id` | **deactivate** (`is_active=0`) | reactivate via `PUT /users/:id/toggle-status` | ✗ |
| Roles | `DELETE /roles/:id` | **hard** | ✗ | ✗ |
| Sales orders | `DELETE /sales-orders/:id` | **hard**, guard: Completed/Invoiced rejected (verified) | ✗ | ✓ `buildSalesOrdersCsv` |
| Quotations | `DELETE /quotations/:id` | **hard** | ✗ | ✓ `buildQuotationsCsv` |
| Payments | `DELETE /payments/:id` | **hard** (GL reversal) | ✗ | ✗ |
| Expenses | **none** (immutable: "cancel it and record a new one"); only categories deletable | n/a | ✗ | ✓ `buildExpensesCsv` |
| Purchases | `POST /purchases/:id/void` | void (GL reversal) | ✗ | ✗ |
| Purchase returns | `POST /purchase-returns/:id/void` | void (stock/batch/supplier-balance reversal) | ✗ | ✓ `buildPurchaseReturnsCsv` |
| Purchase orders | `DELETE /purchase-orders/:id` | draft-only | ✗ | ✓ `buildPurchaseOrdersCsv` |
| BOMs | `DELETE /boms/:id` | hard | ✗ | ✓ `buildBomsCsv` |
| Productions | `DELETE /productions/:id` | hard (sensitive-op limiter) | ✗ | ✓ `buildProductionsCsv` |
| Warehouses | `DELETE /inventory/warehouses/:id` | **soft** (`is_active=0`, verified) — no reactivation path until D25 extends `PUT` | ✓ after D25 | ✗ |
| Physical counts | `DELETE /inventory/physical-counts/:id` | hard, guard: Draft/Cancelled only (verified) | ✗ | ✗ |
| Stock movements | **none** (immutable ledger) | n/a | ✗ | ✗ |
| Stock by warehouse | **none** (computed view) | n/a | ✗ | ✗ |
| Demand forecast | **none** (derived data) | n/a | ✗ | ✗ |
| Activity log | **none** (audit trail; only age-based `POST /cleanup` with `purge` permission) | n/a | ✗ | ✓ `buildActivityLogCsv` |
| Invoice returns | **none** (void-based) | n/a | ✗ | ✓ `buildInvoiceReturnsCsv` |
| Owner capital / withdrawals / personal loans | `DELETE /owner-equity/capital/:id` etc. (soft void: status→voided, GL lines voided, stock restored on withdrawals — verified; optional `reason` body; `sensitiveOperationLimiter`) | void | ✗ (no unvoid endpoint) | ✓ `buildOwnerCapitalCsv` / `buildOwnerWithdrawalsCsv` (personal loans have a private `_buildCsv`) |

### 1.4 Export coverage gap

`lib/core/utils/csv_export.dart` has builders for: stock ledger, invoice
returns, purchase returns, sales orders, purchase orders, quotations,
invoices, expenses, owner capital, owner withdrawals, AR/AP aging, balance
sheet, DSO, cash flow, cash reconciliation, P&L, top debtors, customer
statements, customers, productions, BOMs, trial balance, general ledger,
batch traceability, expiry report.

**Missing builders for in-scope screens:** employees, payments, suppliers,
users, roles, warehouses, physical counts, stock movements.

**Screens with no export path at all today** (toolbar or bulk): employees,
payments, suppliers, users, roles, warehouses, physical counts, stock
movements, stock-by-warehouse, demand forecast.

### 1.5 Permission model facts

- Server: `requirePermission(module, action)` middleware; **Admin role
  bypasses all checks**; permissions live in `role_permissions` ∩
  `permissions` (module+action rows).
- Client: `AuthState` carries only `status` + `AuthUser` (which has
  `role`); **the client has no permission map today**.
- `GET /roles/permissions` (requires `roles: read`) returns the full
  permission catalog — usable as the basis for a per-user permission map.

---

## 2. Decisions (from the clarifying interview)

| # | Decision |
|---|---|
| D1 | Check type: **verify + correct**; spec.md edited in place; this file is the audit trail. |
| D2 | Baseline: **current working tree**; re-verify marked facts at implementation time. |
| D3 | **Undo only where a restore path already exists** (invoices, items, customers; reactivate-style for employees/users). No new restore endpoints in this work. Hard deletes get confirm dialogs only. |
| D4 | **Activity log: bulk export only.** No delete — audit trail; age-based cleanup with `purge` permission remains the only removal path. |
| D5 | **Owner-equity tabs: migrate onto the `PlutoGridScreen` mixin** as part of this work, then get standard bulk selection. |
| D6 | **Purchases and purchase returns: excluded from bulk scope.** Void is a heavy GL reversal; stays one-at-a-time. |
| D7 | **Sales orders and invoice returns: added to scope.** Sales orders get draft-only delete + export; invoice returns get export only. |
| D8 | **Read-only/derived grids (stock movements, stock-by-warehouse, demand forecast): export only.** |
| D9 | **Cross-page selection: required.** Selection must survive page changes within the same filter (new infrastructure). |
| D10 | **CSV formats: reuse each screen's existing column set** where a builder exists; define new column sets mirroring each grid for the 8 missing builders. |
| D11 | **Partial failures: detailed dialog** listing every failed record + reason. |
| D12 | **Permissions: hide bulk buttons client-side using a real permission map** — extend the auth payload (or a `/auth/permissions` fetch) so the client knows granted `(module, action)` pairs. Small server change, accepted. |
| D13 | **Concurrency: disable the bulk action bar while an operation is in flight**; selection survives. |
| D14 | **Select-all: current page only** (documented; no "select all matching filter" affordance). |
| D15 | **Scope: all screen groups accepted** — sales, sales orders + quotations, customers + suppliers, inventory items + warehouses, purchase orders, employees + users + roles, payments + expenses, owner-equity tabs. |
| D16 | **Phasing: per-screen increments**, starting with the 4 screens that already have bulk ops to establish the pattern, then the rest. |
| D17 | **Undo pattern canonicalized on `items_screen.dart`'s implementation**; other screens copy it (no shared helper extraction in this work). |
| D18 | **Mixed eligibility: server decides.** Send all selected IDs; ineligible rows fail with reasons; client renders the detailed failure dialog. No client-side pre-check gating the button. |
| D19 | **Admin screens: bulk delete + export** for both users and roles (server guards: not self, not last admin; not system role, no assigned users). |
| D20 | **Expenses: export only** (no delete endpoint exists; expenses are immutable by design). Payments get delete + export. |
| D21 | **Bar position: above the grid** (existing pattern), documented as the standard. |
| D22 | **Rate-limit pacing (client-side).** `sensitiveOperationLimiter` (10 req/min in production) covers the delete routes for quotations, sales orders, payments, and owner-equity voids. The bulk executor runs serially with a small inter-call delay; on 429 it waits `retryAfter` and retries once; a second 429 lands in the failure list as "rate limited — retry later". No limiter changes. |
| D23 | **Typed confirm for payments.** Bulk-deleting payments (hard, irreversible, GL reversal) requires typing `DELETE` in the confirm dialog; the button stays disabled until the text matches. |
| D24 | **Shared void reason.** Owner-equity bulk-void confirm gets an optional reason field; the same string is sent as `reason` for every voided entry (empty → omitted). |
| D25 | **Warehouse reactivation.** `PUT /inventory/warehouses/:id` gains an optional `is_active` field (one-line model/handler extension + server test) so warehouse bulk delete becomes undoable. The only server exception besides the permission map. |

---

## 3. Corrected Spec (what spec.md now says)

The rewritten `spec.md` incorporates all corrections. Summary of the
authoritative content:

### Scope

**Full bulk ops (checkbox + delete/void-equivalent + export):**
sales invoices, sales orders, quotations, customers, suppliers, inventory
items, warehouses, purchase orders, employees, users, roles, payments,
physical counts, owner-equity tabs (after mixin migration).

**Export-only bulk ops (checkbox + export, no destructive action):**
activity log, expenses, stock movements, stock-by-warehouse, demand
forecast, invoice returns.

**Excluded entirely:** purchases, purchase returns (void is a GL
reversal — stays one-at-a-time).

### Undo matrix

| Screen | Undo after bulk delete? | Mechanism |
|---|---|---|
| Invoices | ✓ | 10s toast → `POST /invoices/:id/restore` per id |
| Inventory items | ✓ | 10s toast → `POST /inventory/items/:id/restore` per id |
| Customers | ✓ | 10s toast → `POST /customers/:id/restore` per id |
| Employees | ✓ (reactivate) | 10s toast → `PUT /employees/:id` `{is_active: 1}` |
| Users | ✓ (reactivate) | 10s toast → `PUT /users/:id/toggle-status` |
| Sales orders, quotations, payments, roles, warehouses, physical counts, BOMs, productions, owner-equity | ✗ | Confirm dialog only (hard delete / void) |
| Export-only screens | n/a | — |

### New server work (the only exceptions to "no new endpoints")

1. **Permission map for the client** — extend `/auth/me` (or add
   `GET /auth/permissions`) to return the user's granted
   `(module, action)` pairs so the client can hide bulk buttons it
   cannot use (D12). Admin role → full map (mirrors the bypass).
2. Nothing else. No restore endpoints are added (D3); no activity-log
   delete (D4); no purchases/returns changes (D6).

### Cross-page selection (D9) — new client infrastructure

`GridBulkSelection` currently keys off the grid's row manager, so a page
change wipes it. Required behavior: selected IDs persist across page
changes **within the same filter state**; the bulk bar count reflects all
selected IDs (including ones not on the current page); clearing happens on
filter/search change, module switch, or explicit clear. Implementation
sketch: the notifier keeps the authoritative `Set<int>`; `syncFromManager`
becomes additive (union of page checks) instead of a mirror; the grid's
per-row checkbox renders checked when the ID is in the set even if the row
was not the source of the check. Page-token (filter signature) comparison
decides when to reset.

### Concurrency (D13)

While a bulk operation is in flight: the bulk bar's action buttons are
disabled (spinner on the active one), selection is preserved, and the
grid's checkboxes stay interactive but cannot start a second operation.
The bar itself stays visible.

### Partial failures (D11 + D18)

Server is the source of truth. The client sends every selected ID, then
renders a dialog: succeeded count at top; a scrollable list of failures
`"<record label>: <server reason>"`. For delete-with-undo screens, Undo
restores only the successfully deleted IDs.

### Permissions (D12)

Bulk action buttons render only when the user's permission map grants the
underlying action (`<module>: delete` for delete/void buttons,
`<module>: update` for activate/deactivate/set-status, `<module>: read`
for export). Admin sees everything (mirrors server bypass). The map comes
from the new permission payload (§ New server work).

### CSV (D10)

- Existing builders reused verbatim for their screens.
- New builders added (mirroring each grid's visible columns):
  `buildEmployeesCsv`, `buildPaymentsCsv`, `buildSuppliersCsv`,
  `buildUsersCsv`, `buildRolesCsv`, `buildWarehousesCsv`,
  `buildPhysicalCountsCsv`, `buildStockMovementsCsv`.
- All bulk exports run over the **selected rows** (intersected with the
  current filtered set), not the whole filtered list.

### Per-screen rollout order (D16)

1. **Phase 0 (pattern):** items, invoices, customers, purchase orders —
   already have bulk ops; align them with the corrected rules (undo
   canonical form, failure dialog, permission gating) and use them as the
   reference implementations.
2. **Phase 1 (straightforward deletes + export):** employees, users,
   roles, payments, warehouses, physical counts.
3. **Phase 2 (export-only screens):** activity log, expenses, stock
   movements, stock-by-warehouse, demand forecast, invoice returns.
4. **Phase 3 (infrastructure-heavy):** cross-page selection + owner-equity
   mixin migration + their bulk ops.
5. Each phase: `flutter analyze`, targeted tests, `flutter test`, server
   typecheck if server files touched, `graphify update .`.

### Testing requirements

- Widget tests per screen: bar appears with ≥1 selection, hides at 0,
  buttons gated by permission map, disabled during in-flight op.
- Failure-dialog test: mixed eligibility → detailed list rendered.
- Undo tests: toast appears, Undo restores only succeeded IDs, toast
  dismisses after 10s (pumped).
- Cross-page selection tests: select on page 1 → page 2 → back to page 1
  → both selections present; filter change clears.
- Fake-adapter routes for every new screen's delete/restore/toggle paths
  (same `_AuthFakeAdapter` pattern as `test/widget_test.dart`).
- Server tests for the permission-map payload.

### Out of scope (explicit)

- Purchases and purchase returns bulk anything (D6).
- New restore endpoints for hard-delete entities (D3).
- Activity-log entry deletion (D4).
- "Select all matching filter" affordance (D14 keeps page-only).
- Mobile layouts (desktop PlutoGrid screens only, per UI_RULES).

---

## 4. Former [re-verify] items — resolved during the review round

- **PO delete guard**: verified Draft-only (`PurchaseOrder.ts`: "Only Draft
  Purchase Orders can be deleted").
- **Employee reactivation**: verified — `PUT /employees/:id` accepts
  `is_active` via a COALESCE update (`Employee.update`); no dedicated
  activate action needed.
- **User toggle-status**: verified idempotent — `PUT /users/:id/toggle-status`
  takes an explicit `is_active` boolean (400 if not boolean); the not-self
  and last-admin guards apply to reactivation too.
- **Physical counts**: verified Draft/Cancelled-only delete.
- **Personal-loan CSV**: decided — promote into `csv_export.dart` in
  Phase 3 (spec.md updated).
- **Sales orders guard correction**: the original table said "draft-only";
  reality is "Completed/Invoiced rejected" (Draft, Confirmed, etc. are
  deletable). spec.md table corrected; D18 (server decides) makes the
  client-side wording non-critical.
- **Invoice returns**: still excluded from delete scope (void-based); no
  change planned. Kept as a standing note, not a re-verify item.

## 5. New risks surfaced during review (resolved by D22–D25)

- **Rate limiter vs O(n) bulk**: production `sensitiveOperationLimiter`
  allows 10 delete calls/min — bulk operations on quotations, sales
  orders, payments, and owner-equity voids would 429 mid-batch. Resolved
  by D22 (client paces serially, honors `retryAfter`).
- **Payments irreversibility**: hard delete + GL reversal + allocation
  removal + subledger reversal, and no restore. Resolved by D23 (typed
  confirm) — user re-confirmed full bulk scope with the guard.
- **Warehouse soft-delete with no reactivation**: `Warehouse.delete` sets
  `is_active=0` but `PUT` only accepts code/name/location. Resolved by
  D25 (accept `is_active` in the update handler).
