# Purchase Returns Redesign — Spec

Request short name: `purchase-returns`
Status: **Draft — gathered via user interview + codebase investigation**
Date: 2026-08-17

---

## 1. Background / Finding

The request was "check the codebase for purchase return process. if not found then
implement." **Investigation found the purchase return process already exists**, end to
end, for *direct purchases*:

- **Server**
  - `GET /purchases/returns` — paged return history (`purchaseController.getReturnHistory`,
    flat `{success, data, pagination}` envelope).
  - `POST /purchases/:id/return` — `purchaseController.returnPurchaseItems`: transactional
    stock return + GL reversal (`AccountingService.postPurchaseReturnEntry` → Dr AP, Cr
    Inventory). Rejects non-positive qty; caps at returnable quantity via
    `Purchase.returnPurchaseItems`.
  - `POST /purchase-orders/:id/return-receipt` — `purchaseOrderController.returnReceiptItems`:
    multi-item `{items: [{po_item_id, return_quantity}], reason}`, transactional, same GL
    posting. **No Flutter UI calls this today.**
  - Migration `server/src/migrations/add-purchase-return-fields.sql`: adds
    `returned_quantity` to `purchases` and `purchase_order_items`, plus
    `idx_stock_movements_return_ref` index.
- **Flutter**
  - `PurchaseReturnsScreen` — read-only, server-paginated grid (search, sort, CSV export,
    row detail; hosted as the "Purchase Returns" tab of the purchasing shell).
  - `ProcessReturnDialog` — qty + reason → `POST /purchases/:id/return`; opened **only**
    from the purchase detail dialog ("Process Return" action, hidden when
    `returnableQty <= 0`).
  - `PurchaseReturnDetailDialog` — read-only detail rendered from the grid row (there is no
    per-return endpoint).
  - `purchase_return_providers.dart` — search/page/limit/sort providers + paged provider.
  - `PurchaseReturn` model + `purchase_return_type.dart` (`PURCHASE_RETURN` / `PO_RETURN`
    badges).

### What the user decided

During the interview the user chose **"Re-examine and redesign"**: the current process is
not good enough. The concrete pains are:

1. **No PO-receipt return UI** — the server supports PO returns but the app cannot do them.
2. **Entry flow is too hidden** — the only way to start a return is inside a purchase's
   detail dialog; no direct actions on the lists or the returns screen.

---

## 2. Scope

### In scope

- **Purchase return redesign** covering both direct purchases and PO receipts:
  - Return entry points (returns screen "New Return", PO row menu, purchase row menu).
  - Source-document picker + multi-line return entry form.
  - Selectable restock warehouse and return date.
  - Dedicated `purchase_returns` table as source of truth (redesign of the current
    stock-movement-only model).
  - Supplier credit note document + supplier ledger posting (beyond the plain GL reversal).
  - Void/cancel of a return with **full reversal + audit trail**.
  - Role-permission gating for create/void return actions.
  - Mobile compact card list for purchase returns (per UI rules, < 768px).
- **Activity log grid fix** — the grid is currently empty; restore data visibility.

### Out of scope

- Invoice returns (3-dot menu + detail action) — left to the pending openspec change
  `add-return-workflows-and-fix-activity-log` / a separate change.
- Redesign of the general purchase / PO / supplier-credit domain beyond what returns need.
- New reporting or audit systems beyond the return audit trail.

### Relationship to existing openspec change

There is a pending, unimplemented openspec change
`openspec/changes/add-return-workflows-and-fix-activity-log` whose unchecked tasks overlap
this spec (new-return action, PO/purchase menu return, activity log fix). This spec
**supersedes the purchase-returns + activity-log-grid portions** of that change; its
invoice-returns portion remains untouched. Do not double-implement.

---

## 3. Confirmed decisions (interview summary)

| Topic | Decision |
| --- | --- |
| Goal | Re-examine and redesign; current process is too hidden / incomplete |
| Sources | Both direct purchases and PO receipts |
| Scope boundary | Purchase returns + activity log fix; **no invoice returns** |
| Partial returns | Allowed (any qty up to remaining returnable) |
| Restock warehouse | **User-selectable**, defaulting to the document's original warehouse |
| Accounting | GL reversal **plus** a dedicated supplier credit note doc + supplier ledger entry |
| Entry UX | Source picker first → pre-filled return form |
| Multi-line | Yes — multiple source lines in one return transaction |
| Return date | User-selectable (defaults to today) |
| Grid records | Read-only (no inline editing) + View + **Void/cancel** action |
| Void semantics | Full reversal (stock + GL + credit note), mark voided, activity-log audit |
| Activity log | Grid is empty — fix data path so rows render |
| Mobile | Include compact card list for purchase returns |
| Permissions | Gate create/void by role permission |
| Return model | Dedicated `purchase_returns` table as source of truth (linked to stock movements + credit note) |
| Acceptance | Typecheck + lint + targeted unit/widget/server tests |
| Open questions | All resolved — see §13 (numbering, old endpoints, backfill, mobile model, permissions, filters) |

---

## 4. Current state (reference inventory)

### Server

| Endpoint | Controller fn | Notes |
| --- | --- | --- |
| `GET /purchases/returns` | `purchaseController.getReturnHistory` | Paged; filters `search`, `start_date`, `end_date`, `item_id`, `sortBy/sortOrder` |
| `POST /purchases/:id/return` | `purchaseController.returnPurchaseItems` | Body `{quantity, reason?}`; transaction + GL reversal; 400 on invalid qty / over-return |
| `POST /purchase-orders/:id/return-receipt` | `purchaseOrderController.returnReceiptItems` | Body `{items: [{po_item_id, return_quantity}], reason?}`; transaction + GL reversal |
| Migration | `add-purchase-return-fields.sql` | `returned_quantity` on `purchases` + `purchase_order_items`; return-ref index |

Current return model: returns are **negative stock movements**
(`quantity < 0`, `reference_doctype` = `PURCHASE_RETURN` | `PO_RETURN`,
`reference_docno` = source doc number). The returns grid reads
`Purchase.getReturnHistory`.

### Flutter

| File | Role |
| --- | --- |
| `purchase_returns_screen.dart` | Read-only paged grid (search, sort, CSV, row actions = View) |
| `process_return_dialog.dart` | Qty + reason → `POST /purchases/:id/return` |
| `purchase_return_detail_dialog.dart` | Read-only detail from the grid row |
| `purchase_return_providers.dart` | Search/page/limit/sort providers + paged provider + CSV full-list provider |
| `data/models/purchase_return.dart` | `PurchaseReturn` row model (`returnQty = quantity.abs()`) |
| `core/utils/purchase_return_type.dart` | `PURCHASE_RETURN` / `PO_RETURN` badge colors + labels |
| `purchases_screen.dart` | Purchases grid — row menu currently only View |
| `purchase_detail_dialog.dart` | Has the sole "Process Return" entry point today |
| `purchasing_shell.dart` | Hosts Purchases + Purchase Returns tabs |

Shared infra to reuse: `PlutoGridScreen` mixin, `ScreenToolbar`, `ServerPaginationBar`,
`GridRowAction`, `PagedRequest`/`PagedResponse`, `ApiResult` (`ApiSuccess`/`ApiFailure`),
`showAppToast`, form widgets (`FormFieldShell`, `formInputDecoration`, `ErrorBanner`,
`submitOnEnter`), `StatusBadge`, `DetailTiles`/`DetailInfoRows`, `AppLocalizations`
(l10n keys under `purchases*`).

### Activity log

`activityLogsProvider` (`FutureProvider<OffsetPagedResponse<ActivityLog>>`) feeds
`ActivityLogScreen` (Pluto grid). **Symptom: grid is empty.** A recent change added an
explicit `ScreenErrorPanel` path for provider errors, so errors are no longer silent — but
the empty-grid data path still needs diagnosis (likely query/data-binding mismatch between
the repository response shape and `gridRowsFrom`).

---

## 5. Goals / Non-Goals

### Goals

- Every return type (direct purchase, PO receipt) is creatable from the returns screen and
  from the source document's own list.
- Returns are first-class records (`purchase_returns`) that carry qty, unit cost,
  warehouse, date, reason, source reference, status, and audit fields — linked to their
  stock movement(s) and credit note.
- A return optionally posts a supplier credit note document; voiding a return fully
  reverses stock, GL, and the credit note, all with an audit trail.
- The purchase returns grid shows accurate, current data and is usable on desktop (grid)
  and mobile (compact cards).

### Non-Goals

- Changing invoice return behavior.
- Changing purchase / PO creation flows.
- Introducing an approval workflow beyond role-permission gating.

---

## 6. Data model design

### New table: `purchase_returns`

Source of truth for a return. One row per return header; one-or-more linked lines.

```sql
CREATE TABLE purchase_returns (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  return_no     TEXT NOT NULL UNIQUE,          -- e.g. PR-2026-0001
  return_date   TEXT NOT NULL,                 -- user-selectable (default today), YYYY-MM-DD
  return_type   TEXT NOT NULL,                 -- 'PURCHASE_RETURN' | 'PO_RETURN'
  source_type   TEXT NOT NULL,                 -- 'PURCHASE' | 'PURCHASE_ORDER'
  source_id     INTEGER NOT NULL,              -- purchases.id | purchase_orders.id
  source_no     TEXT NOT NULL,                 -- denormalized doc number
  warehouse_id  INTEGER NOT NULL,              -- restock target (user-selectable)
  reason        TEXT,
  status        TEXT NOT NULL DEFAULT 'POSTED',-- 'POSTED' | 'VOIDED'
  total_qty     NUMERIC(15,3) NOT NULL,
  total_amount  NUMERIC(15,3) NOT NULL,
  credit_note_id INTEGER REFERENCES credit_notes(id),  -- NULL until credit posted
  voided_at     TEXT,
  voided_by     INTEGER,
  voided_reason TEXT,
  created_by    INTEGER NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### New table: `purchase_return_items`

```sql
CREATE TABLE purchase_return_items (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_return_id INTEGER NOT NULL REFERENCES purchase_returns(id),
  source_item_id  INTEGER NOT NULL,            -- purchases.id | purchase_order_items.id
  item_id         INTEGER NOT NULL,
  item_name       TEXT NOT NULL,               -- denormalized
  unit_cost       NUMERIC(15,3) NOT NULL,
  quantity        NUMERIC(15,3) NOT NULL,      -- positive magnitude
  amount          NUMERIC(15,3) NOT NULL
);
```

### New table: `credit_notes` (supplier credit)

Dedicated credit note document per the interview decision.

```sql
CREATE TABLE credit_notes (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  credit_no    TEXT NOT NULL UNIQUE,           -- e.g. CN-2026-0001
  credit_date  TEXT NOT NULL,
  supplier_id  INTEGER NOT NULL REFERENCES suppliers(id),
  source_type  TEXT NOT NULL,                  -- 'PURCHASE_RETURN'
  source_id    INTEGER NOT NULL,               -- purchase_returns.id
  amount       NUMERIC(15,3) NOT NULL,
  status       TEXT NOT NULL DEFAULT 'POSTED', -- 'POSTED' | 'VOIDED'
  posted_by    INTEGER NOT NULL,
  posted_at    TEXT NOT NULL DEFAULT (datetime('now')),
  voided_at    TEXT,
  voided_by    INTEGER
);
```

Plus a supplier-ledger transaction row (see existing `SupplierLedgerModel`) referencing the
credit note. A migration file is required for all schema changes (DATABASE rules) and the
GL posting for the credit side must reuse `AccountingService` conventions.

### Linkage

- Return header → stock movement(s) (negative, `reference_doctype` =
  `PURCHASE_RETURN`/`PO_RETURN`, `reference_docno` = `return_no`) so history grids keep
  working. Add a nullable `stock_movements.purchase_return_id` FK column in the migration
  so movements point back at their return header (mirrors the existing
  `journal_entry_id` column pattern).
- Return header → `credit_notes` (1:1) → supplier ledger entry.
- `purchase_returns.status` drives grid filtering; VOIDED rows shown with a voided badge,
  excluded from open totals.

### Document numbering (resolved)

- Reuse the shared `generateDocNo(db, prefix, padLength = 4)` utility in
  `server/src/utils/sequence.ts` — it atomically issues `PREFIX-YYYY-NNNN` via the
  `settings` table (`INSERT … ON CONFLICT`), exactly like `PURCH-`, `PO-`, `GR-`, `INV-`,
  `SO-` today.
- `return_no` → `generateDocNo(db, 'PR')` → `PR-2026-0001`.
- `credit_no` → `generateDocNo(db, 'CN')` → `CN-2026-0001`.
- Stock movements keep `StockMovementModel.generateMovementNo` → `STK-2026-0001`.
- The legacy backfill (see §13) must issue `return_no` values through the same sequence
  so there are no collisions.

---

## 7. API design

All changes follow existing conventions: flat paged envelope for lists, bare objects for
detail/create, `{success, message, data}` for actions, prepared statements, transactional
writes, `requirePermission` for gated actions.

### New / changed endpoints

| Method + path | Notes |
| --- | --- |
| `GET /purchase-returns` | Paged list of return headers+lines (replaces reading stock movements for the grid). Filters: `search`, `start_date`, `end_date`, `type`, `status`, `warehouse_id`, sort. |
| `GET /purchase-returns/:id` | Bare return detail (header + items + credit note ref). |
| `POST /purchase-returns` | Create return. Body: `{return_date, source_type, source_id, warehouse_id, reason, items: [{source_item_id, quantity}]}`. Transactionally: validate returnable qty per source line, deduct `returned_quantity`, post negative stock movement(s), post GL reversal, create credit note + supplier ledger entry, generate `return_no`. |
| `POST /purchase-returns/:id/void` | Full reversal: reverse stock + GL + credit note (mark voided), set status VOIDED, audit via activity log. Body: `{reason}`. Permission-gated. |
| `GET /purchases/returns` | Removed once the grid + CSV re-point to `GET /purchase-returns` (see “Old endpoints — removal” below). |

### Old endpoints — removal (resolved)

- `POST /purchases/:id/return` and `POST /purchase-orders/:id/return-receipt` are
  **removed in the same change** that lands `POST /purchase-returns`. Rationale: the only
  in-repo client is the Flutter app — `ProcessReturnDialog` (and its widget-test mock at
  `test/widget_test.dart:1343`) is the sole caller of the purchases endpoint and nothing
  calls the PO endpoint — so there is no external consumer to keep compatible, and
  leaving two creation paths is exactly the drift this redesign eliminates.
- `GET /purchases/returns` is superseded by `GET /purchase-returns`; remove it once the
  grid + CSV re-point (same change). The backfill migration preserves legacy history, so
  no dual-read is needed.
- Delete `ProcessReturnDialog` and the purchase-detail "Process Return" button together
  with the old endpoints; update `test/widget_test.dart` and
  `server/src/__tests__/api.integration.test.ts` accordingly.

### Validation rules

- `quantity > 0` per line; sum per line ≤ remaining returnable (`source quantity −
  returned_quantity`), same cap the current flow enforces.
- `return_date` required, valid ISO date.
- `warehouse_id` required.
- `source_type`/`source_id` must resolve; only *received* PO items are returnable.
- Void rejected if status != POSTED; void of an already-voided return → 400.

---

## 8. Flutter design

### 8.1 Return entry points

1. **Purchase Returns tab — "New Return"** primary action in `ScreenToolbar`
   (`primaryActions`, mirroring `purchasesScreen` "New Purchase").
2. **Purchases grid row menu** — add a `Return` `GridRowAction` (icon
   `Icons.assignment_return_outlined`, label `l10n.purchasesReturn`) alongside View.
3. **Purchase Orders grid row menu** — add a `Return` `GridRowAction` (see
   `purchase_orders_screen.dart`), enabled for POs with returnable quantity.

All three open the **source picker** pre-seeded where applicable (purchases/PO rows
pre-select that document; the returns-tab action opens an empty picker).

### 8.2 Source picker

- New dialog: pick **source type** (Direct Purchase | Purchase Order) then a searchable
  document list (existing paged providers can drive it), then confirm.
- On confirm → open the return entry form pre-filled from that document's items.

### 8.3 Return entry form (multi-line)

- New `purchase_return_form_dialog.dart` (+ provider-backed state).
- Header: source type/doc number (read-only), return date (default today, selectable),
  restock warehouse (defaults to the document's warehouse, dropdown).
- Lines: one row per source line with item, original qty, already-returned qty,
  returnable qty, and an editable return qty + read-only unit cost; totals update live.
- Reason field (optional).
- Submit → `POST /purchase-returns`; on success invalidate returns grid, purchases/PO
  grids, purchase/PO detail providers, and the credit-note/ledger views; toast with the
  return amount (mirror current `ProcessReturnDialog` success behavior).
- Error banner for API failures (no silent failures).

### 8.4 Returns grid (desktop)

- Re-point to the new endpoint (`PagedRequest` with search/sort/date/type/status).
- Keep existing columns; add `status` column (VOIDED badge via `StatusBadge`).
- Row actions: **View** (existing detail dialog) + **Void** (with confirmation dialog
  asking for a reason, then `POST /purchase-returns/:id/void`; hidden/disabled when already
  VOIDED).
- `PurchaseReturn` model updated for the new fields (status, warehouseId, returnDate,
  creditNoteNo, etc.); detail dialog shows the credit note reference.
- `filteredPurchaseReturnsProvider` (CSV export) updated to the new endpoint; CSV gains
  status + credit note columns.
- Filters (resolved): expose a **date-range filter** (the shared `DateRangeFilter`
  widget already exists and the endpoint supports `start_date`/`end_date`) and a
  **status filter** (All / Posted / Voided) beside the existing search. The return-type
  filter (Purchase Return vs PO Return) is deferred — not needed for the first cut.

### 8.5 Mobile (Compact Card System, < 768px)

- Model the mobile view on `DemandForecastScreen` — the one in-repo converted module with
  a compact-card layout: `LayoutBuilder(maxWidth < 768)` switches the body from the
  Pluto grid to a `ListView.separated` of cards fed by a full-list provider, with the
  toolbar search field and refresh kept above the list.
- Purchase-returns cards show: return no + source doc, return date, item, qty, amount,
  type badge, warehouse, status. Tap opens the existing `PurchaseReturnDetailDialog`
  (detail modal). Per-card popup action menu (⋮) offers View + Void, mirroring the
  `GridRowAction` pattern used on desktop rows.
- A mobile action bar / FAB hosts "New Return" (same source-picker flow as desktop).

### 8.6 Providers

- Add `purchaseReturnsFormProvider` (or local state) for the multi-line form.
- Extend `purchaseReturnsProvider` with date-range + status filters (type filter deferred).
- Add `voidPurchaseReturnProvider` / mutation helper.

---

## 9. Activity log fix

- **Symptom:** grid renders no rows.
- **Root cause (diagnosed + fixed 2026-08-17):** the screen seeds its date range from
  `initialRange` (default: local "This week") and sends `start_date`/`end_date` as
  **local** dates, but `activity_log.created_at` is stored in **UTC** (`CURRENT_TIMESTAMP`).
  `ActivityLogModel.find` compared `al.created_at >= 'local-monday'` against UTC strings —
  in a UTC+ timezone the local week starts on the previous UTC calendar day, so **every
  row failed the filter and the grid came back empty** (verified against
  `server/database/erp.db`: 105 rows, current query 0, fixed query 2 for local Monday). A
  second latent bug: `<= end_date` on a bare date excluded the entire end day.
- **Fix:** `server/src/models/ActivityLog.ts` converts the local date bounds to UTC
  instants (`localDateToUtcBound`: start = local midnight, end = next local midnight,
  exclusive) in `find()` and `getStats()`, keeping `idx_activity_log_created_at` usable
  and matching Dashboard.ts's localtime convention (desktop: server and client share a
  timezone). No Flutter changes were needed — the client already sends local dates.
- **Tests:** new `server/src/__tests__/activityLog.test.ts` pins the conversion invariants;
  full server suite green (209 tests) + `tsc --noEmit` + eslint clean.
- **Acceptance (met):** opening the activity log screen shows records for the default
  week; search/filter/paging work; errors surface via the `ScreenErrorPanel` path.

---

## 10. Permissions (resolved)

- `requirePermission(module, action)` matches the `permissions` table on `module` +
  `action` columns; Admin role bypasses all checks (`middleware/requirePermission.ts`).
- Add a new **`purchase_returns`** module to the seed list in
  `config/database.ts → seedDefaultPermissions()` with actions:
  - `purchase_returns:read` — view the returns grid/detail (module `purchase_returns`, action `read`).
  - `purchase_returns:create` — create returns.
  - `purchase_returns:void` — void returns.
- No new migration file needed: `runRolesPermissionsMigration()` calls
  `seedDefaultPermissions()` on every boot and `INSERT OR IGNORE`s each permission
  (backfills existing databases), then auto-assigns all permissions to Admin and all
  `read` permissions to the User role — so `purchase_returns:read` is granted to User
  automatically and create/void remain Admin/custom-role only.
- Routes: `GET /purchase-returns` → `requirePermission('purchase_returns', 'read')`;
  `POST /purchase-returns` → `requirePermission('purchase_returns', 'create')` + existing
  `sensitiveOperationLimiter`; `POST /purchase-returns/:id/void` →
  `requirePermission('purchase_returns', 'void')` + limiter.
- Flutter: surface/hide the New Return and Void actions based on the current user's
  permissions, following the same helper used for other permission-gated actions.

---

## 11. Error handling / security

- Prepared statements only; no string-concatenated SQL.
- All write paths transactional (return creation, void, credit posting).
- Controllers keep `try/catch` with structured JSON errors and no stack leakage.
- Flutter: `try/catch` around async, toasts on success, error banners on failure, loading
  states everywhere; no silent failures.
- Audit: activity log entries for create/void (who + when + return no).

---

## 12. Testing plan

- **Server:** unit tests for `PurchaseReturnModel` (create caps, multi-line validation,
  void reversal), credit-note creation + supplier ledger posting, permission gating, and
  the legacy backfill migration. Update `server/src/__tests__/api.integration.test.ts`
  (the `GET /purchases/returns` case moves to `GET /purchase-returns`; old POST cases are
  removed).
- **Flutter:** widget tests for the source picker, multi-line form validation (qty caps,
  required fields), void confirmation, and the returns grid rendering; provider tests for
  paging/filter state. Update `test/widget_test.dart` mocks that reference
  `/purchases/1/return` and `/purchases/returns` to the new endpoints.
- **Activity log:** test that a populated activity feed renders rows.
- Run `npm run typecheck` + `npm run lint` (server) and `flutter analyze` (app) as the
  gate; fix all failures before finalizing.

---

## 13. Resolved decisions (previously open questions)

1. **Old-endpoint deprecation — REMOVE in the same change.** `POST /purchases/:id/return`
   and `POST /purchase-orders/:id/return-receipt` have a single in-repo client (the
   Flutter app) and the redesign replaces that flow wholesale; keeping them invites
   drift. Remove them together with `ProcessReturnDialog` and the purchase-detail
   "Process Return" button, and update the affected tests. `GET /purchases/returns` is
   dropped once the grid re-points to `GET /purchase-returns`.
2. **Migrate wholesale, no dual-read.** A backfill migration creates
   `purchase_returns` + `purchase_return_items` rows from existing return stock
   movements (`reference_doctype` IN `PURCHASE_RETURN`/`PO_RETURN`, `quantity < 0`),
   grouped by source doc + date + item; each gets a `return_no` issued through the same
   sequence, `status = 'POSTED'`, no credit note (legacy returns never had one), and its
   stock movements get `stock_movements.purchase_return_id` back-linked. After backfill
   the new endpoint returns all history, so the grid re-points cleanly.
3. **Numbering — `generateDocNo`.** `return_no` = `PR-YYYY-NNNN`, `credit_no` =
   `CN-YYYY-NNNN` via the shared atomic utility; movements keep `STK-YYYY-NNNN`. See §6.
4. **Mobile model — `DemandForecastScreen`.** The only converted module with compact
   cards today (`_CompactForecastCard`, `LayoutBuilder(maxWidth < 768)`, full-list
   provider + `ListView.separated`). See §8.5.
5. **Permissions — new `purchase_returns` module** (`read`/`create`/`void`), seeded via
   the idempotent `seedDefaultPermissions()` — no new migration file needed. See §10.
6. **Grid filters — include date-range + status; defer type.** Server params already
   exist; the shared `DateRangeFilter` widget is ready. See §8.4.

---

## 14b. Phase 1 status (2026-08-17) — server foundation implemented

Phase 1 of the suggested order (§15) is **implemented and tested**:

- **Migration** `server/src/migrations/add-purchase-returns-tables.sql`: creates
  `purchase_returns`, `purchase_return_items`, `credit_notes`, adds the nullable
  `stock_movements.purchase_return_id` FK, plus indexes. Idempotent
  (`CREATE TABLE IF NOT EXISTS` + guarded ALTER in the runner).
- **Backfill** `server/src/utils/purchaseReturnBackfill.ts` (extracted so it's
  unit-testable), called from `config/database.ts` on every boot. Groups legacy
  negative return movements by source doc + date + item; issues `PR-YYYY-NNNN`
  via the shared `generateDocNo` sequence; back-links movements. **Idempotent**
  (only unlinked movements are processed) — verified with a seeded copy of the
  live DB: 3 movements → 2 headers, correct line aggregation, second boot is a
  no-op.
- **Permissions** — `purchase_returns:read/create/void` added to
  `seedDefaultPermissions()` (idempotent, no new migration file). Admin gets
  all; User auto-gets `read` via the existing read-only grant.
- **Model** `server/src/models/PurchaseReturn.ts`: `getAll` (paged, filters
  search/date/type/status/warehouse, whitelisted sort), `getById` (header +
  items + credit ref), `create` (validates per-line returnable caps, deducts
  `returned_quantity`, negative stock movement FIFO-reduces batches, posts GL
  reversal + supplier credit note + ledger entry, activity-log audit), `void`
  (full reversal: positive movement, source `returned_quantity` restored,
  journal lines voided, credit note VOIDED + reversing ledger entry, header
  VOIDED + audit).
- **API** — `GET /purchase-returns`, `GET /purchase-returns/:id`,
  `POST /purchase-returns`, `POST /purchase-returns/:id/void`, all
  permission-gated (`read` / `read` / `create` / `void`) with
  `sensitiveOperationLimiter` on writes; flat paged envelope for the list.
- **Tests** — `server/src/__tests__/purchaseReturn.test.ts` (9 cases: create
  caps for purchase + PO sources, cross-source rejection, void full reversal,
  double-void rejection, backfill grouping + idempotency) and 4 new
  `api.integration.test.ts` cases. Full suite: **218 tests pass**,
  `tsc --noEmit` clean, eslint only pre-existing warnings/errors.

### Deviations from §6/§7 worth knowing

1. **`purchase_returns.source_id` and `purchase_return_items.source_item_id` are
   nullable** (spec DDL said NOT NULL). Rationale: the backfill runs against
   legacy data whose source docs/lines may have been deleted (the old purchase
   delete removes the row). Create still requires them; only the backfill can
   produce NULL.
2. **`credit_notes.supplier_id` nullable** — direct purchases store only
   `supplier_name` (no FK). The credit note resolves the supplier by name
   (NOCASE); when unresolved it is still posted (document exists) but the
   supplier-ledger entry is skipped with a warning.
3. **Old endpoints kept alive during Phase 1.** The spec (§7) planned removing
   `POST /purchases/:id/return`, `POST /purchase-orders/:id/return-receipt` and
   `GET /purchases/returns` in the same change — but the Flutter app still calls
   them until its re-point (Phase 4–5). They remain until the Flutter re-point
   lands in the same change as their removal, exactly as §7's "Remove once the
   grid + CSV re-point" dictates. The backfill means `GET /purchases/returns`
   (movement-based) keeps returning the same rows.
4. GL posting on create keys `reference_id` to the **return header** (so void
   reverses exactly that entry); legacy backfilled returns have no journal lines
   and void only touches new-style entries.

---

## 14. Definition of done

- [x] Returns creatable from: returns-screen action, purchase row menu, PO row menu
  (permission-gated).
- [x] Multi-line return form: fixed source warehouse + date, qty caps, live totals, reason.
- [x] Server: `purchase_returns` + `credit_notes` tables (migration present), unified
  create endpoint, void-with-full-reversal endpoint, supplier ledger + credit note posting.
- [x] Returns grid shows status, supports Void (with audit), and CSV reflects new fields.
- [x] Mobile compact card list for purchase returns.
- [x] Activity log grid renders data.
- [x] `npm run typecheck` + `npm run lint` + `flutter analyze` pass; targeted tests green.
- [x] No suppressed types, no silent failures, api contract consistent between app and
  server.

---

## 15. Suggested implementation order

1. ✅ **DONE (Phase 1)** — Migrations (`purchase_returns`,
   `purchase_return_items`, `credit_notes`, `stock_movements.purchase_return_id`),
   legacy backfill, permission seed, `PurchaseReturnModel` (list/detail/create/void),
   unified endpoints + server tests. Old return endpoints deliberately kept until
   the Flutter re-point (§14b deviation 3).
2. Server: `PurchaseReturnModel` + unified `POST /purchase-returns` / void endpoints,
   credit-note + supplier-ledger posting, `GET /purchase-returns` (paged) + detail —
   ✅ done in Phase 1. Old return endpoints (`POST /purchases/:id/return`,
   `POST /purchase-orders/:id/return-receipt`, `GET /purchases/returns`) — **✅ removed
   in Phase 2** together with the Flutter re-point: routes, controller handlers,
   `Purchase.getReturnHistory` / `Purchase.returnPurchaseItems` /
   `PurchaseOrder.returnReceiptItems`, the `PURCHASE_RETURN_SORT_COLUMNS` whitelist,
   and the `GET /api/purchases/returns` integration test.
3. ✅ Server tests (Phase 1 + full-flow integration): `purchaseReturn.test.ts` unit tests
   (create purchase/PO + caps + cross-source + void reversal + double-void + backfill
   grouping/idempotency) and — added after Phase 5 — a full-flow HTTP integration block in
   `api.integration.test.ts`: seeds item/warehouse/supplier/purchase through the public API,
   creates a return with the picker's exact body shape (201 → `PR-…` + `CN-…`), asserts the
   DB effects (header/line, stock 10→6, back-linked movement, source `returned_quantity`,
   credit note resolved by supplier name + `supplier_ledger` CREDIT_NOTE, 2-line GL journal),
   asserts the over-return cap → 400, voids (stock 6→10, ledger CREDIT_NOTE_VOID debit, GL
   lines voided, reversal movement, header VOIDED), rejects double-void → 400, and asserts
   permission gating (a seeded-User account gets 200 on GET but 403 on create/void).
4. ✅ Flutter re-point (Phase 2): `PurchaseReturn` model rewritten to the header+lines
   contract (`return_no`, `source_no`, `status`, `total_qty`, `total_amount`,
   `credit_no`, `line_count`, `items`), repository re-pointed to `/purchase-returns`
   (`returnsPaged` + new `returnDetail` / `voidReturn`; `returns`/`processReturn`
   dropped), `purchase_return_providers.dart` updated, `PurchaseReturnsScreen` grid +
   CSV + detail dialog adapted to headers (Source column replaces Item; Unit Cost
   dropped), `ProcessReturnDialog` deleted, the purchase-detail Process Return button
   removed, `test/widget_test.dart` + `csv_export_test.dart` updated. Verified:
   `flutter analyze` clean, full Flutter suite 670/670 green, server suite 220/220.
5. ✅ Return entry flow (Phase 5): new `return_source_picker_dialog.dart` (Source Type
   segmented control + searchable document list driven by the new
   `returnSourcePurchasesProvider` / `returnSourceOrdersProvider` family providers) and
   `purchase_return_form_dialog.dart` (multi-line form: source doc read-only header,
   user-selectable return date + restock warehouse, per-line original/returned/available
   columns with editable return qty, live totals, reason, `POST /purchase-returns` via
   the new `createReturn` repo method; success invalidates the returns grid, CSV list,
   purchases + PO grids and the source detail). Entry points wired: returns-tab **New
   Return** primary action (picker → form), purchases row-menu **Return to Supplier**
   (form pre-seeded; hidden when `returnableQty <= 0`), PO row-menu **Process Return**
   (form pre-seeded; hidden for Draft POs — the form lists only received lines). New
   l10n keys (en + ur). 3 new widget tests (picker→form→POST body, purchases row menu,
   PO row menu with received-line filtering); shared row-action menu now ellipsizes
   long labels. Verified: `flutter analyze` clean, full Flutter suite 673/673 green.
6. ✅ Grid status column, Void action, date-range + status filters (Phase 6): new
   `purchase_return_status.dart` (badge colors + localized Posted/Voided labels),
   `purchaseReturnsStatusFilterProvider` / `purchaseReturnsFromDateProvider` /
   `purchaseReturnsToDateProvider` wired into `purchaseReturnsProvider` and
   `filteredPurchaseReturnsProvider` (sent as `status`, `start_date`, `end_date`),
   `purchase_return_void_dialog.dart` (explains the full reversal, collects an optional
   reason, posts `POST /purchase-returns/:id/void` via the `voidReturn` repo method,
   invalidates grid + CSV list, toasts; server rejects non-POSTED), the grid gains a
   Status column (badge), a toolbar status dropdown (All Statuses/Posted/Voided) +
   the shared `DateRangeFilter`, a row-menu **Void** action (hidden once VOIDED), and
   the CSV export adds Status + Credit Note columns. 3 new widget tests (status filter
   → `status` param, date-range → `start_date`/`end_date` + clear reset, row-menu Void
   → POST body + VOIDED badge flip). Verified: `flutter analyze` clean, full Flutter
   suite 676/676 green.
7. ✅ Mobile compact card list (Phase 7, spec §8.5): `LayoutBuilder(maxWidth < 768)` in
   `PurchaseReturnsScreen` switches the body from the Pluto grid + pagination bar to a
   `ListView.separated` of `_CompactReturnCard`s fed by the existing
   `filteredPurchaseReturnsProvider` (so search + status + date filters apply to mobile
   too). Each card shows return no + source doc, return date + type badge, status badge,
   qty / amount / warehouse stats and the reason, plus a per-card ⋮ menu (View + Void,
   Void hidden once voided) mirroring the desktop row actions; tapping the card opens
   the same `PurchaseReturnDetailDialog`. The shared `ScreenToolbar` already wraps on
   narrow panes, so the New Return action stays reachable without a separate FAB. New
   `purchasesReturnloaderror` l10n key (en + ur). 1 new widget test (cards render, tap
   opens the detail modal, ⋮ Void posts the void and flips the badge — pumps the screen
   directly at 600px since the shell's desktop dashboard overflows at narrow widths).
   Verified: `flutter analyze` clean, full Flutter suite 677/677 green.
8. ✅ Activity log fix + test — fixed server-side (see §9); the Flutter screen surfaces
   provider errors with a retry panel. Flutter test optional.
9. ✅ Full self-audit (final): server `tsc --noEmit` clean, eslint 0 errors (baseline
   warnings only), full server suite **228/228** (incl. the purchase-returns unit +
   integration blocks and the invoice-return restock-warehouse integration block);
   `flutter analyze` clean, full Flutter suite **678/678**.

**Post-completion hardening (warehouse model, agreed with the user):** a purchase
return **reduces stock from the source document's warehouse** — the form no longer
asks; it shows the fixed warehouse read-only (the picker is gone). A **customer (invoice)
return asks for a restock warehouse** — `InvoiceReturnDialog` gained a required
`Restock Warehouse` picker, `POST /invoices/:id/return` accepts `warehouse_id` and
`reverseStockForItems` restocks the movement into it (batch-quantity restore stays on
the original sale batches; omitting `warehouse_id` keeps the old sale-origin fallback,
so the endpoint stays backward compatible).
