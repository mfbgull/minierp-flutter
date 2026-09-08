# Specification: Extend Bulk Operations to All PlutoGrid Screens

> **Status: all phases implemented and verified.** Every claim in the
> original draft was verified against the working tree, and every
> **[re-verify]** mark has since been resolved from the server code
> (see `spec-check-spec.md`). No unresolved fact marks remain.
>
> **Addendum (2026-09-08):** a working-tree audit found three screens
> that the "all phases complete" status had silently skipped — sales
> orders, quotations, and suppliers (they use the mixin but had no
> `enableBulkSelection`). They are now implemented per the corrected
> table below (Phase 1 scope), including the previously missing
> `buildSuppliersCsv`.

## Repository Baseline

The repository is a Flutter mini-ERP application using:
- **Flutter** + **Riverpod** for state management
- **go_router** for routing
- **Pluto-Grid** for data grids/lists
- Server-side pagination and filtering for grid data

### Existing Bulk Operation Infrastructure (verified)

1. **Reference implementations** (4 screens already do this):
   - `sales_screen.dart` — invoices: `GridBulkSelection` + checkbox column
     + `BulkActionBar`; bulk delete (soft, undo toast) + bulk export.
   - `items_screen.dart` — inventory: bulk activate/deactivate +
     delete-with-undo (the **canonical undo pattern**, D17).
   - `customers_screen.dart` — bulk export over selected rows.
   - `purchase_orders_screen.dart` — bulk set status.

2. **PlutoGridScreen mixin** (`lib/widgets/pluto_grid_screen.dart`):
   - `enableBulkSelection` getter (default `false`, line 409)
   - When `true`: auto-adds `bulkSelectColumn`, provides
     `bulkSelection` notifier, wires `onRowChecked → syncFromManager()`
   - Selection clears when grid rows are replaced (page/filter/refresh,
     line 564) — see Cross-page selection for the new requirement.

3. **Shared widgets**: `bulkSelectColumn()`, `BulkActionBar`
   (`screen_toolbar.dart:188`), `showConfirmDialog`, `saveCsv` +
   per-entity `build*Csv` builders in `core/utils/csv_export.dart`.

4. **l10n keys exist**: `bulkDeleteSelected`, `bulkExportSelected`,
   `bulkActivateSelected`, `bulkDeactivateSelected`, `commonUndo` (en+ur).

### Scope (D15, D6, D8)

**Full bulk ops (checkbox + destructive action + export):**
sales invoices, sales orders, quotations, customers, suppliers, inventory
items, warehouses, purchase orders, employees, users, roles, payments,
physical counts, owner-equity tabs (after mixin migration).

**Export-only bulk ops (checkbox + export, no destructive action):**
activity log (audit trail — D4), expenses (immutable by design — D20),
stock movements (immutable ledger), stock-by-warehouse (computed view),
demand forecast (derived data), invoice returns (void-based).

**Excluded entirely:** purchases, purchase returns — their only reversal
is `POST /:id/void` (GL reversal); stays one-at-a-time (D6).

## Implementation Delta

### Per-screen operations (corrected table)

| Screen | Bulk ops | Server path | Undo? |
|---|---|---|---|
| `sales/sales_screen.dart` | delete + export (exists; align) | `DELETE /invoices/:id` | ✓ restore |
| `sales_orders/sales_orders_screen.dart` | delete + export | `DELETE /sales-orders/:id` (guard: Completed/Invoiced rejected) | ✗ |
| `quotations/quotations_screen.dart` | delete + export | `DELETE /quotations/:id` (guard: Converted rejected) | ✗ |
| `customers/customers_screen.dart` | delete + activate/deactivate + export (exists: export) | `DELETE` + `PUT /customers/:id` | ✓ restore |
| `suppliers/suppliers_screen.dart` | delete + activate/deactivate + export | `DELETE /suppliers/:id` + `PUT /suppliers/:id` | ✗ (hard) |
| `sales_orders/sales_orders_screen.dart` | delete + export | `DELETE /sales-orders/:id` (guard: Completed/Invoiced rejected — verified) | ✗ |
| `quotations/quotations_screen.dart` | delete + export | `DELETE /quotations/:id` (guard: Converted rejected — verified) | ✗ |
| `inventory/items_screen.dart` | activate/deactivate + delete + export (exists; add export) | existing + `PUT /inventory/items/:id` | ✓ restore |
| `inventory/warehouses_screen.dart` | delete + export | `DELETE /inventory/warehouses/:id` (soft: `is_active=0`) | ✓ reactivate via extended `PUT /warehouses/:id` (D25) |
| `inventory/physical_count_screen.dart` | delete + export | `DELETE /inventory/physical-counts/:id` (guard: Draft/Cancelled only — verified) | ✗ |
| `purchase_orders/purchase_orders_screen.dart` | set status (exists) + delete + export | existing + `DELETE /purchase-orders/:id` (guard: Draft only — verified) | ✗ |
| `employees/employees_screen.dart` | delete (deactivate) + export | `DELETE /employees/:id` (sets `is_active=0` — verified) | ✓ reactivate via `PUT /employees/:id` (`is_active` COALESCE — verified) |
| `admin/users_screen.dart` | delete (deactivate) + export | `DELETE /users/:id` (softDelete; guards: not self, not last admin) | ✓ reactivate via `PUT /users/:id/toggle-status` (explicit boolean → idempotent; same guards apply) |
| `admin/roles_screen.dart` | delete + export | `DELETE /roles/:id` (guards: system roles, assigned users) | ✗ |
| `payments/payments_screen.dart` | delete + export (typed confirm, D23) | `DELETE /payments/:id` (hard delete, GL reversal — irreversible) | ✗ |
| `owner_equity/*_tab.dart` (×3) | migrate to mixin first (D5), then void + export (shared reason, D24) | `DELETE /owner-equity/capital/:id`, `/withdrawals/:id`, `/personal-loans/:id` (soft void: status→voided, GL lines voided, stock restored on withdrawals; optional `reason` body) | ✗ (no unvoid endpoint) |
| `activity_log/activity_log_screen.dart` | **export only** (D4) | — (no delete; `POST /cleanup` stays the only removal) | n/a |
| `expenses/expenses_screen.dart` | **export only** (D20) | — (expenses immutable; only categories deletable) | n/a |
| `inventory/stock_movement_screen.dart` | **export only** (D8) | — (immutable ledger) | n/a |
| `inventory/stock_by_warehouse_screen.dart` | **export only** (D8) | — (computed view) | n/a |
| `forecasts/demand_forecast_screen.dart` | **export only** (D8) | — (derived data) | n/a |
| `sales/invoice_returns_screen.dart` | **export only** (D7) | — (void-based) | n/a |

### What can be reused (verified)

- `GridBulkSelection`, `bulkSelectColumn()`, `BulkActionBar`,
  `showConfirmDialog`, `saveCsv`, existing `build*Csv` builders.
- `_bulkDelete` / `_bulkExport` / `_bulkSetActive` / `_bulkSetStatus`
  patterns from the 4 reference screens.
- **Undo canonical form**: `items_screen.dart`'s delete-with-undo
  (10s toast, single Undo action restoring every deleted id). Other
  delete-with-undo screens copy this pattern (D17 — no shared helper
  extraction in this work).

### New server work (the ONLY exceptions to "no new endpoints")

1. **Permission map for the client (D12)** — extend `/auth/me` (or add
   `GET /auth/permissions`) to return the user's granted
   `(module, action)` pairs so the client can hide bulk buttons it cannot
   use. Admin role returns the full map (mirrors the server bypass in
   `requirePermission.ts`). Server tests required for the payload.
2. **Warehouse reactivation (D25)** — extend the existing
   `PUT /inventory/warehouses/:id` handler to accept `is_active` (the
   model's `Warehouse.update` gains one optional field). This is what
   makes warehouse bulk delete undoable; without it the soft-deactivated
   row is unreachable. Server test for the reactivation path.

Nothing else. No restore endpoints are added (D3); no activity-log
delete (D4); no purchases/returns changes (D6); no schema changes.

### CSV export (D10)

- Existing builders reused verbatim for their screens.
- **New builders added** (Phase 1 + Phase 3):
  `buildEmployeesCsv`, `buildPaymentsCsv`, `buildUsersCsv`,
  `buildRolesCsv`, `buildWarehousesCsv`, `buildPhysicalCountsCsv`,
  `buildStockMovementsCsv`, `buildStockByWarehouseCsv`,
  `buildDemandForecastCsv`, `buildPersonalLoansCsv`,
  `buildSuppliersCsv` (added with the suppliers screen in the
  2026-09-08 addendum).
- Every bulk export runs over the **selected rows** (intersected with the
  current filtered set), not the whole filtered list.
- Owner-equity personal loans: private `_buildCsv` promoted to
  `csv_export.dart` as `buildPersonalLoansCsv` during Phase 3.

## Business Rules and Invariants

1. **Cross-page selection (D9 — new infrastructure).** Selected IDs must
   survive page changes **within the same filter state**. The bulk bar
   count reflects all selected IDs including ones not on the current
   page. Selection clears on filter/search change, module switch, or
   explicit clear. Sketch: the notifier keeps the authoritative `Set<int>`;
   `syncFromManager` becomes additive (union of page checks) instead of a
   mirror; row checkboxes render checked when their ID is in the set; a
   filter-signature comparison decides when to reset.
2. **Select-all is current-page only (D14).** The header checkbox checks
   the rows loaded on the current page. No "select all matching filter"
   affordance.
3. **Read-only grid**: bulk selection is opt-in via checkboxes; it never
   modifies grid data directly.
4. **Server-side enforcement**: the server remains the source of truth
   for every guard; the UI is a convenience wrapper.
5. **Mixed eligibility — server decides (D18).** The client sends every
   selected ID without pre-checking statuses. Ineligible rows fail
   server-side with reasons; the client renders the detailed failure
   dialog (below).
6. **Rate-limit pacing (D22).** `sensitiveOperationLimiter` (10 req/min
   in production) sits on the delete routes for quotations, sales orders,
   payments, and owner-equity voids. The bulk executor therefore runs
   **serially** for every entity (one call at a time, no parallelism)
   with a small inter-call delay, and on a 429 response waits
   `retryAfter` seconds and retries that record before continuing. No
   server limiter changes; pacing is purely client-side. Non-limited
   entities (customers, suppliers, items, warehouses, employees, users,
   roles, physical counts) may use the same serial executor for
   uniformity — one code path.
7. **Typed confirm for irreversible bulk deletes (D23).** Payments bulk
   delete requires typing `DELETE` in the confirm dialog (case-sensitive)
   before it runs. This is the only entity with a typed confirm; other
   destructive bulks keep the standard `showConfirmDialog`.
8. **Shared void reason (D24).** The owner-equity bulk-void confirm
   dialog gets an optional reason field; the same reason string is sent
   as the `reason` body for every voided entry (empty → omitted, matching
   single-entry behavior).
9. **Empty selection**: the bar hides at `count == 0` (existing
   `ValueListenableBuilder` guard).
10. **Bar position (D21)**: above the grid, between toolbar and grid —
   the existing reference-screen placement, now the documented standard.

## Edge Cases & Error Handling

1. **Partial failures (D11)**: dialog with the succeeded count at top and
   a scrollable list of failures — `"<record label>: <server reason>"`
   (e.g. "INV-102: Cannot delete a paid invoice"). One line is not
   enough; the list is the requirement.
2. **Undo after partial failure**: Undo restores only the successfully
   deleted IDs; failed records remain with their error entries.
3. **Concurrency (D13)**: while an operation is in flight, the bulk
   bar's action buttons disable (spinner on the active one), selection
   is preserved, and a second operation cannot start. The bar stays
   visible.
4. **429 handling (D22)**: a rate-limited record is retried after
   `retryAfter`; if it 429s again after the retry, it lands in the
   failure list as "rate limited — retry later". The operation never
   aborts the whole batch because of the limiter.
5. **Filter/reset interaction**: selection clears on filter/search change
   and module switch (page changes no longer clear — see D9).
6. **Permission changes mid-session**: the permission map is fetched at
   boot with `/auth/me`; a role change takes effect on next login/refresh
   (documented limitation, matches the server's JWT claims).

## UI / UX Changes

1. Checkbox column: first column, select-all header (current page),
   per-row checkboxes.
2. Bulk action bar above the grid; appears on selection, hides when empty.
3. Action buttons per the corrected table; destructive actions styled
   with the error color (existing pattern).
4. **Permission gating (D12)**: delete/void buttons require
   `<module>: delete`; activate/deactivate/set-status require
   `<module>: update`; export requires `<module>: read`. Buttons the user
   lacks permission for are hidden, not disabled. Admin sees all.
5. Undo toast: 10s, single Undo action (canonical items pattern).
6. **Typed confirm (D23)**: payments bulk delete shows a dialog with a
   text field; the Delete button stays disabled until the field equals
   `DELETE`.
7. **Reason field (D24)**: owner-equity bulk-void confirm dialog gains an
   optional single-line reason input, sent verbatim to every void call.
8. l10n: reuse existing bulk keys; add new keys for any new action labels,
   the typed-confirm prompt, and the reason field (en + ur).

## Performance

- Bulk operations iterate selected IDs — O(n) API calls, one per record
  (matches existing screens; no batch endpoint exists or is added).
- Export builds one CSV string from in-memory selected rows; no extra
  fetches.
- Cross-page selection adds a Set lookup per row render — negligible.

## Testing

- **Widget tests per screen**: bar appears with ≥1 selection, hides at 0,
  buttons gated by the permission map, disabled during in-flight op.
- **Failure-dialog test**: mixed eligibility → detailed list rendered
  with per-record reasons.
- **Undo tests**: toast appears; Undo restores only succeeded IDs; toast
  auto-dismisses after 10s (pumped).
- **Pacing tests (D22)**: fake adapter records inter-call timing/sequencing
  for a rate-limited entity; a 429 response triggers a retry that
  succeeds; a second 429 lands in the failure list.
- **Typed-confirm test (D23)**: payments bulk delete is a no-op until the
  field equals `DELETE`; wrong text keeps the button disabled.
- **Reason test (D24)**: OE bulk void sends the shared reason body to
  every call; empty reason omits the field.
- **Cross-page selection tests**: select on page 1 → page 2 → back to
  page 1 → both selections present; filter change clears.
- **Fake-adapter routes** for every new delete/restore/toggle path (the
  `_AuthFakeAdapter` pattern in `test/widget_test.dart`).
- **Server tests** for the permission-map payload.
- Every phase: `flutter analyze`, targeted tests, full `flutter test`,
  server `tsc --noEmit` + jest when server files change, `flutter build
  linux`, `graphify update .`.

## Phasing (D16 — per-screen increments)

1. **Phase 0 (pattern alignment): ✅ COMPLETE.** items, invoices, customers,
   purchase orders — already have bulk ops; aligned with these rules (undo
   canonical form, failure dialog, permission gating, export over selection).
   Treated as the reference implementations.

2. **Phase 1 (straightforward deletes + export): ✅ COMPLETE.** employees,
   users, roles, payments, warehouses, physical counts. Includes the new CSV
   builders for these screens.

3. **Phase 2 (export-only screens): ✅ COMPLETE.** activity log, expenses,
   stock movements, stock-by-warehouse, demand forecast, invoice returns.
   Includes `buildStockMovementsCsv` and the physical-counts builder.

4. **Phase 3 (infrastructure-heavy): ✅ COMPLETE.** cross-page selection
   (D9: additive `syncFromManager`, `resetIfFilterChanged`, `recheckRows`),
   owner-equity mixin migration (D5: all 3 tabs migrated to PlutoGridScreen),
   bulk void/delete + export for owner-equity tabs, CSV promotion for
   personal loans (`buildPersonalLoansCsv`).

5. **Phase 4 (permission map + server additions): ✅ COMPLETE.** permission-map
   payload returned from `/auth/me` (D12: admin gets all permissions, non-admin
   gets role-based permissions), warehouse `is_active` reactivation via
   `PUT /warehouses/:id` (D25), client permission gating — all 19 screens with
   bulk ops now hide buttons the user lacks permission for (export: `{module}:read`,
   delete/void: `{module}:delete`, activate/deactivate/set-status: `{module}:update`).

6. **Addendum phase (2026-09-08): ✅ COMPLETE.** sales orders, quotations, and
   suppliers — the three Phase 1 screens the earlier passes skipped — now have
   bulk selection + delete + bulk export (suppliers also activate/deactivate),
   permission-gated, with `buildSuppliersCsv`, fake-adapter routes, and widget
   tests (per-screen delete coverage + D11 failure-dialog tests).

## Migration & Backward Compatibility

- `enableBulkSelection => true` is additive per screen; screens not yet
  migrated keep their current behavior.
- No breaking API changes; the only server additions are the permission
  map payload (backward-compatible: older clients ignore it) and the
  warehouse `is_active` field (backward-compatible: absent field means
  "don't change", matching the existing COALESCE-style handlers).
- No DB schema changes.

## Out of Scope (explicit)

- Purchases and purchase returns bulk operations (D6).
- New restore/undo endpoints for hard-delete entities (D3) — the
  warehouse `PUT` extension (D25) is a field addition to an existing
  endpoint, not a new endpoint.
- Rate-limiter changes (D22 keeps the limiter; the client paces).
- Activity-log entry deletion (D4).
- "Select all matching filter" (D14).
- Mobile layouts — desktop PlutoGrid screens only (UI_RULES).
- Shared undo-helper extraction (D17 documents the canonical pattern
  instead).

## Decision Index (complete)

D1 verify+correct · D2 edit spec.md in place · D3 undo only where restore
endpoints exist · D4 activity log export-only · D5 owner-equity migrates
to mixin · D6 purchases/returns excluded (void-only) · D7 invoice returns
export-only · D8 read-only/derived grids export-only · D9 cross-page
selection (new infra) · D10 add all missing CSV builders, canonicalize
items · D11 detailed per-record failure list · D12 permission map from
server, hide unauthorized buttons · D13 disable bar during in-flight op ·
D14 select-all is current-page · D15 full scope per the corrected table ·
D16 per-screen increments (5 phases) · D17 reuse per-screen undo pattern,
no shared helper · D18 server decides eligibility · D19 above-grid bar ·
D20 expenses export-only (immutable) · D21 bar above grid · D22 client
paces rate-limited calls, honors retryAfter · D23 typed `DELETE` confirm
for payments · D24 shared optional reason for OE voids · D25 warehouse
PUT gains `is_active` (undo enabler).
