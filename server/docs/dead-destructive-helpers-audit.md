# Dead Destructive Helpers — Audit Report (audit task 38)

**Date:** 2026-09-27
**Scope:** helpers in `server/src` that issue raw `DELETE FROM` / hard-delete SQL, screened
for the project's append-only reversal policy (void + reversal row, no hard deletes of
accounting data).

## 1. Method

For each candidate the whole repo was searched for callers — `server/src`
(controllers, services, models, routes, `__tests__`), `server/scripts`,
`server/migrations`, `lib/` (Dart), plus any tooling dirs. `.mimosa`/`.codegraph`/
`graphify-out` baseline snapshots were excluded so that stale copies of source are
not mistaken for live call sites.

Dynamic reachability was checked explicitly: no generic `Model.delete` dispatch by
variable, no `Model[...]` index dispatch, and no reflective apply exists in
`server/src` — every `*.delete(...)` call resolves statically to a named model
method, so "no static caller" is equivalent to "unreachable".

## 2. Verdict summary

| # | Helper | Raw `DELETE FROM` | Verdict |
|---|---|---|---|
| 1 | `BOMModel.delete` | BOM.ts:340, 342 | **USED** |
| 2 | `ProductionModel.delete` | Production.ts:656, 657 | **USED** |
| 3 | `PurchaseOrderModel.delete` | PurchaseOrder.ts:619, 620 | **USED** |
| 4 | `QuotationModel.delete` | Quotation.ts:529, 530 | **USED** |
| 5 | `SalesOrderModel.delete` | SalesOrder.ts:517 block | **USED** |
| 6 | `SupplierModel.delete` | Supplier.ts:170 | **USED** |
| 7 | `forecastService` (6 sites) | forecastService.ts:594, 642, 1115, 1118, 1121, 1204 | **USED** |
| 8 | `Role.ts` (2 sites) | Role.ts:117, 136 | **USED** |
| 9 | `PhysicalCountModel.deleteCount` | PhysicalCount.ts:794, 795 | **USED** |
| 10 | `ActivityLogModel.deleteOlderThan` / `.delete` | ActivityLog.ts:345, 361 | `deleteOlderThan` **USED**; `.delete` **REMOVED** |
| 11 | owner loans controller (2 sites) | ownerPersonalLoansController.ts:334, 447 | **USED** |

**Result: exactly one dead destructive helper — `ActivityLogModel.delete` — and it has
been removed.** No other candidate is dead.

## 3. Per-candidate detail

### REMOVED — `ActivityLogModel.delete(id)` (was ActivityLog.ts:359–367)

Issued `DELETE FROM activity_log WHERE id = ?` — a hard delete of an **audit-trail
row**, the worst possible target under this project's rules (the audit trail is the
evidence layer for every reversal).

Reachability proof (all negative):
- No route: `routes/activityLog.ts` exposes only `GET` routes plus
  `POST /cleanup` (:45) — there is no `DELETE /api/activity-logs/:id`.
- No controller call: the singleton's only consumer,
  `controllers/activityLogController.ts`, calls `find`, `getStats`, `findByUser`,
  `findByEntity`, `findRecent`, `getEntityTypes`, `getActions`, `exportToCSV`,
  `getUsers` and `deleteOlderThan` (activityLogController.ts:254). It never calls
  `.delete(...)`.
- No test: `__tests__/activityLog.test.ts:1` imports only
  `localDateToUtcBound` from the model.
- No script/migration/Dart reference.

Removed in full (method + its `/** Delete a specific log entry */` doc comment).
Post-removal `grep -rn 'activityLogModel\.delete\b|ActivityLogModel\.delete\b'`
over live `*.ts/*.js/*.dart` returns **no matches**; `npx tsc --noEmit` passes.

The retention purge `deleteOlderThan(days)` (ActivityLog.ts:342) is a **different**
helper and is KEPT — it is reachable via `POST /api/activity-logs/cleanup`
(routes/activityLog.ts:45 → activityLogController.ts:254) and deletes by age under a
retention setting, which is the sanctioned way to prune the trail.

### USED — item 2 (model `delete` methods that hard-delete)

All six are wired to live, permission-gated `DELETE` routes in `app.ts`:

| Helper | Call site | Route (mounted in app.ts) |
|---|---|---|
| `BOMModel.delete` (BOM.ts:330) | `controllers/bomController.ts:137` | `DELETE /api/boms/:id` (routes/bom.ts:25, app.ts:224) |
| `ProductionModel.delete` (Production.ts:545) | `controllers/productionController.ts:127`; also `scripts/verify-reversal-rules.ts:259` | `DELETE /api/productions/:id` (routes/production.ts:14, app.ts:245) |
| `PurchaseOrderModel.delete` (PurchaseOrder.ts:607) | `controllers/purchaseOrderController.ts:161` | `DELETE /api/purchase-orders/:id` (routes/purchaseOrders.ts:15, app.ts:234) |
| `QuotationModel.delete` (Quotation.ts:518) | `controllers/salesController.ts:150` | `DELETE /api/quotations/:id` (routes/sales.ts:31, app.ts:238) |
| `SalesOrderModel.delete` (SalesOrder.ts:517) | `controllers/salesController.ts:336` | `DELETE /api/sales-orders/:id` (routes/sales.ts:62, app.ts:239) |
| `SupplierModel.delete` (Supplier.ts:169) | `controllers/suppliersController.ts:249` | `DELETE /api/suppliers/:id` (routes/suppliers.ts:20, app.ts:232) |

Left untouched. Note the guards that limit the damage of these hard deletes, since
they are the reason these qualify as legitimate primitives rather than policy
violations:

- `PurchaseOrderModel.delete` refuses anything but `status = 'Draft'`
  (PurchaseOrder.ts:614) — a Draft PO has no receipts, ledger rows or GL postings,
  so nothing needs reversing.
- `BOMModel.delete` refuses a BOM already used by a `productions` row
  (BOM.ts:331–337).
- `PhysicalCountModel.deleteCount` (see below) accepts only `Draft`/`Cancelled`.
- `Quotation`/`SalesOrder` deletes are pre-conversion commercial documents (the
  sales-order *cancel* path, which does reverse stock, is a separate route:
  routes/sales.ts:64).

`SupplierModel.delete` (Supplier.ts:169–171) is the bluntest of the six — a bare
`DELETE FROM suppliers` with no guard beyond the controller's referential check. It
is live and therefore out of scope for removal here, but it is the highest-risk
survivor and is flagged for a follow-up to convert it to a soft-delete/void like
`Item.delete` (Item.ts:271) or `Employee.delete` (Employee.ts:278).

### USED — item 4 (other raw `DELETE FROM`)

- **`services/forecastService.ts`** — all six sites are reachable and legitimate:
  `:594` (`saveForecastsToDb`, called from `generateAllForecasts` at :774),
  `:642` (`saveForecastsToAccuracy`, called from `saveForecastsToDb` at :624),
  `:1115`/`:1118`/`:1121` (`applyOverride`, called from
  `controllers/forecastsController.ts:173`), and `:1204` (`deleteSeasonalEvent`,
  called from `forecastsController.ts:232` via `DELETE /api/forecasts/seasonal-events/:id`
  at routes/forecasts.ts:40). These clear **derived, recomputable forecast rows**, not
  accounting records — a delete-and-reinsert cache invalidation, which is the correct
  shape for that data.
- **`models/Role.ts`** — `:117` is `deleteRole`, reached via
  `controllers/rolesController.ts:107` (`DELETE /api/roles/:id`, routes/roles.ts:17,
  app.ts:219); it guards system roles and in-use roles (Role.ts:110, 112–115).
  `:136` is the delete-then-reinsert inside `updatePermissions` (permissions are
  pure join-table rows, not audit data).
- **`models/PhysicalCount.ts`** — `:794`/`:795` are inside
  `PhysicalCountModel.deleteCount` (:786), called from
  `controllers/inventoryController.ts` `deletePhysicalCount` via
  `DELETE /api/inventory/physical-counts/:id` (routes/inventory.ts:46). Guarded to
  `Draft`/`Cancelled` status only (PhysicalCount.ts:789) — a Draft count has posted
  no stock corrections, so nothing needs reversing.
- **`controllers/ownerPersonalLoansController.ts`** — `:334` is the `deleteLoan`
  handler (`DELETE /api/owner-equity/personal-loans/:id`, routes/ownerEquity.ts:38)
  and `:447` is the `deleteRepayment` handler
  (`DELETE .../repayments/:repId`, routes/ownerEquity.ts:42). Both are live. These
  tables are explicitly labelled "purely record-keeping, no GL impact"
  (routes/ownerEquity.ts:30) and the repayment delete restores the loan balance
  in place (ownerPersonalLoansController.ts:447–450). Hard-deleting a GL-affecting
  document here would be a violation; these are the documented exception.

## 4. Files changed

| File | Change |
|---|---|
| `server/src/models/ActivityLog.ts` | removed dead `delete(id)` method (+ doc comment), 13 lines |
| `server/docs/dead-destructive-helpers-audit.md` | this report (new) |

No inventory or stock file was read for modification, and none was modified.

## 5. Verification

- `grep -rn --include=*.ts --include=*.js --include=*.dart -e 'activityLogModel\.delete\b' -e 'ActivityLogModel\.delete\b'` over the live tree → **0 matches**.
- `npx tsc --noEmit` in `server/` → **exit 0, no errors** (no dangling imports,
  no unused exports).
- `git status --short` shows only `server/src/models/ActivityLog.ts` (modified) and
  `server/docs/dead-destructive-helpers-audit.md` (new), plus pre-existing `.omo`
  session noise unrelated to this task.
- Full test suite deliberately not run (concurrent agent); no migration or database
  file touched.
