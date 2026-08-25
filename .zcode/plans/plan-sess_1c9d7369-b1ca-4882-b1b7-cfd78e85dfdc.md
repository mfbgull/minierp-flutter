# Plan: Hide voided purchases + toggle, and multi-item Record Purchase form

## Current state / root causes
- **Voided rows shown:** `GET /purchases` (`Purchase.getAll`, `server/src/models/Purchase.ts:289`) has no `voided_at` filter — voided rows are returned like any other. Void state = nullable `voided_at` timestamp column (no migration needed).
- **Single-item form:** `purchase_form_dialog.dart` captures one item; `PurchaseRepository.create()` posts a flat single-item body; server `Purchase.recordPurchase` creates exactly one `purchases` row per call (batch, stock movement, balances, supplier ledger, GL entry, activity log — all inside one better-sqlite3 transaction).

## Key design decisions
1. Voided hiding happens **server-side** (pagination is server-side; client-side hiding would break page counts). Toggle sends `include_voided=1`.
2. Multi-item purchase = **N `purchases` rows created atomically in ONE transaction**, each with its own auto-generated `PURCH-…` number. No schema change — a header/lines restructure would ripple through returns, payment allocations, void logic, GL posting, and reports. Each row stays fully compatible with all existing downstream flows.
3. Extend `POST /purchases` with an optional `items[]` array (backward compatible with today's single-item payload). House precedent: PO create and `PurchaseReturn.create` already accept `items[]`.
4. The form **closes after every successful save** (the stay-open `PaymentSuccessScreen` path is removed per your instruction; failures keep the form open with an error banner).

## Backend (`server/src`)
1. **`models/Purchase.ts`**
   - `Purchase` interface: add optional `voided_at?`, `void_reason?`.
   - `PurchaseFilters`: add `include_voided?: boolean`.
   - `getAll()`: unless `include_voided`, push `p.voided_at IS NULL` into conditions — the shared `where` applies it to both the data query and the COUNT query, keeping pagination consistent.
   - Extract `recordPurchase`'s transaction body into an internal per-line helper; add `recordPurchaseMulti(header, items[], userId, db)` running **one** `db.transaction` around the loop (doc number generated per line, supplier resolved once, full side-effect chain per line: batch, stock movement, stock balance/current_stock, supplier ledger + rebuildBalances, GL postPurchaseEntry, activity log).
2. **`controllers/purchaseController.ts`**
   - `getPurchases`: parse `include_voided` (`'1'`/`'true'`) into filters.
   - `recordPurchase`: if `body.items` is a non-empty array → validate header (`warehouse_id`, `purchase_date`) and each line (`item_id`, `quantity > 0`, `unit_cost >= 0`) → multi path, respond 201 with the created rows array; otherwise legacy single-item path unchanged.
3. **Tests:** extend `__tests__/purchaseVoid.test.ts` — voided purchase absent from default list (rows *and* total count), present with `include_voided=1`. Add a batch-creation test — N rows + side effects created, atomic rollback on bad line, legacy single payload still works.

## Flutter (`lib/`)
4. **`data/models/purchase.dart`:** parse `voidedAt` + `isVoided` getter (mirror `purchase_return.dart` pattern).
5. **`features/purchases/purchase_providers.dart`:**
   - New `purchasesIncludeVoidedProvider` (`StateProvider<bool>`, default false).
   - `purchasesProvider` watches it → `extra: {'include_voided': '1'}` when on (same mechanism as inventory `low_stock`).
   - `filteredPurchasesProvider` honors it too so detail lookups match the visible grid.
6. **`features/purchases/purchases_screen.dart`:**
   - Toolbar: `FilterChip` "Show Voided" in `ScreenToolbar(filters:)` between search and New Purchase, bound to the provider, resets page to 1 on change (exact pattern from `items_screen.dart:204-223`).
   - When voided rows are visible they're **marked**: hidden `isVoided` cell + `purchaseNo` renderer shows red strikethrough.
7. **`features/purchases/purchase_form_dialog.dart`** — restructure the item section following the proven `purchase_order_form_dialog.dart` multi-line pattern:
   - `List<_PurchaseLine>` (item `SearchableSelect` + qty + unit cost + per-line expiry picker), "Add Item" button, per-line remove button (disabled at 1 line), totals footer summing qty×cost and driving the payment section's grand total.
   - Supplier / date / warehouse / invoice no become true header fields applied to all lines; remarks moves to the document section.
   - Submit → `repo.createMulti(...)`; on failure show `ErrorBanner` and stay open; on success invalidate providers, allocate any recorded payment greedily across the created purchase ids, success toast, then **always `Navigator.pop()`**.
8. **`data/repositories/purchase_repository.dart`:** add `createMulti({warehouseId, purchaseDate, supplierId, invoiceNo, remarks, items})` posting `{warehouse_id, purchase_date, supplier_id?, invoice_no?, remarks?, items:[{item_id, quantity, unit_cost, expiry_date?}]}` to `POST /purchases`; leave existing `create()` untouched.
9. **l10n:** add `purchasesShowvoided` ("Show Voided") + Urdu translation to `lib/l10n/en.arb`/`ur.arb`; reuse existing keys for Add Item / Remove / "Add at least one item" (cross-feature key reuse is already house style — this screen uses `salesTotalpaid`/`salesBalance`). Run `flutter gen-l10n`.

## Verification (self-audit per AGENTS.md)
- `server`: `npm run typecheck`, `npm run lint`, targeted jest runs for the touched tests.
- `flutter analyze`.
- `graphify update .` (AGENTS.md §18).
- Note: `locales/*.arb` looks like a manual mirror of `lib/l10n` — I'll check for any build consumer during implementation and sync only if one exists.

## Impact summary
Affected: server purchases controller/model/tests · Flutter purchase model/providers/screen/form/repository · l10n files. No DB migration, no breaking API contract (additive `items[]` + `include_voided` params only).