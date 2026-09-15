# Expired Stock Management - Implementation Plan

## Standard ERP GL Account Convention (DECIDED)

The codebase already posts generic inventory adjustments to `7200`
"Inventory Shrinkage" (`add-gl-foundation.sql`, used by ADJUSTMENT
financial posting). To avoid a parallel loss-account family, **7200 is the
single loss parent** and the write-off sub-categories are its children:

- `7200` - Inventory Shrinkage (parent expense category, already exists)
- `7201` - Expired Goods Loss (child of 7200) — default write-off account
- `7202` - Damaged Goods Loss (child of 7200)
- `7203` - Stock Shortage Loss (child of 7200)
- `7204` - Obsolete Stock Loss (child of 7200)

(The original 5400-series numbering is dropped — same taxonomy, grafted
onto the existing 7200 parent instead of inventing a second family.)

## Auto-Created Warehouses
- `EXPIRED` - "Expired Stock" warehouse (is_system = 1, non-deletable)
- `DAMAGED` - "Damaged Stock" warehouse (is_system = 1, non-deletable)

## Movement Types to Add

`stock_movements.movement_type` is a free-form VARCHAR(50) — **no enum
migration needed**. Rows are per-warehouse with signed `quantity`; a
warehouse-to-warehouse move is a paired OUT leg (−qty at source) and IN leg
(+qty at destination), with the IN leg's `reference_docno` set to the OUT
leg's `movement_no` (see `StockMovementModel.recordTransfer`).

- `EXPIRY_TRANSFER` - Sellable → Expired Stock warehouse (paired legs, batch-targeted)
- `DAMAGE_TRANSFER` - Sellable → Damaged Stock warehouse (paired legs, batch-targeted)
- `WRITE_OFF` - single negative leg at the Expired/Damaged warehouse (zeroes the batch)
- `SUPPLIER_RETURN` - no new type; reuse the existing purchase-return flow
  (it already records its own movements via `purchase_return_id`)

## Phase 1: Database & Models

Schema realities this phase must respect:
- `stock_batches` has **no `status` column** — status is derived at read
  time in `server/src/utils/batchStatus.ts` (`EXPIRED` is derived from
  `expiry_date` and cannot be overridden). Do not add a status enum.
- Migrations ship as `.sql` files in `server/src/migrations/` applied via
  the `schema_migrations` ledger in `config/database.ts`. Never seed manually.

1.1 New migration `server/src/migrations/add-expired-stock.sql` — GL seeds:

```sql
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code) VALUES
('7201', 'Expired Goods Loss',  'expense', 'debit', 'expired_goods_loss'),
('7202', 'Damaged Goods Loss',  'expense', 'debit', 'damaged_goods_loss'),
('7203', 'Stock Shortage Loss', 'expense', 'debit', 'stock_shortage_loss'),
('7204', 'Obsolete Stock Loss', 'expense', 'debit', 'obsolete_stock_loss');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE code = '7200')
WHERE code IN ('7201','7202','7203','7204') AND parent_id IS NULL;
```

- Safe: `chart_of_accounts.code` has a UNIQUE constraint, so
  `INSERT OR IGNORE` cannot produce duplicates.
- **Credit side of the write-off entry is the inventory ASSET account
  `1200` ("Inventory Asset"), NOT 7200** — 7200 is an expense account;
  crediting it would net expenses against themselves.
- Manual ADJUSTMENTs continue to post to the 7200 parent as they do today;
  only the structured write-off flow uses 7201–7204.

1.2 Same migration — `is_system` column, system warehouse seeds, delete
trigger, and boot-task indexes:

The migration ledger guarantees each file runs once; the `ALTER TABLE`
therefore needs no `pragma_table_info` guard (SQLite has no
`ADD COLUMN IF NOT EXISTS` — do not pretend otherwise in comments).

```sql
ALTER TABLE warehouses ADD COLUMN is_system BOOLEAN NOT NULL DEFAULT 0;

INSERT OR IGNORE INTO warehouses (warehouse_code, warehouse_name, is_system, is_active)
VALUES ('EXPIRED', 'Expired Stock', 1, 1),
       ('DAMAGED', 'Damaged Stock', 1, 1);

-- Defense in depth: the server-side 400 is the user-friendly guard;
-- this trigger stops direct-SQL scripts from deleting system warehouses.
CREATE TRIGGER IF NOT EXISTS trg_warehouses_no_delete_system
BEFORE DELETE ON warehouses
WHEN OLD.is_system = 1
BEGIN
  SELECT RAISE(ABORT, 'Cannot delete system warehouse');
END;

-- Boot-task query support (expiry_date + remaining qty) and the
-- idempotency NOT EXISTS check:
CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry_active
  ON stock_batches(expiry_date, quantity_remaining)
  WHERE quantity_remaining > 0;
CREATE INDEX IF NOT EXISTS idx_stock_movements_batch_type
  ON stock_movements(batch_id, movement_type);
```

Delete guard — server-side, also mandatory:
- `inventoryController.deleteWarehouse` / `WarehouseModel` delete path:
  refuse with a 400 structured error when `is_system = 1`
  (the trigger above is the backstop, not the UX).
- Frontend (Phase 4): hide/disable delete for `isSystem` warehouses.

1.3 Batch "status" — NO schema change:
- `EXPIRED` is already derived from `expiry_date < today` by
  `getEffectiveBatchStatus` — nothing to add.
- `WRITTEN_OFF` is derived, not stored: a batch is written off when
  `quantity_remaining = 0` AND a `WRITE_OFF` movement exists with
  `batch_id = batch.id`. The expiry and valuation reports query this.
- Damage marking uses the existing `status_override` mechanism in
  `batch_stock_by_location` (`DAMAGED` is already a legal override value).

1.4 Movement types — no enum migration (`movement_type` is VARCHAR(50));
documented conventions only — see "Movement Types to Add" above.

1.5 Mirrored batch `source_type` — **DECIDED: reuse `'TRANSFER'`** and
carry the semantics on `movement_type = 'EXPIRY_TRANSFER'` instead.
Extending the `BATCH_SOURCE_TYPES` CHECK requires a SQLite table rebuild
(see the stock_batches rebuild path in `config/database.ts`) — not worth
it for this feature. Do not accumulate a second convention later.

## Phase 2: Server Boot Task (Expiry Detection)

2.1 Rewrite `server/src/boot/expiryDetection.ts` (current version is dead
code with wrong column names and a hardcoded `warehouse_id = 2`):

- Resolve the destination warehouse by code — never hardcode ids:
```sql
SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED' AND is_active = 1
-- throw (loud) if missing: the Phase 1 migration guarantees it exists
```
- Candidate query (replaces the invalid `sb.status NOT IN (...)` filter):
```sql
SELECT sb.id, sb.item_id, sb.warehouse_id, sb.batch_no,
       sb.quantity_remaining, sb.unit_cost, sb.expiry_date
FROM stock_batches sb
WHERE sb.expiry_date < ?                    -- today
  AND sb.quantity_remaining > 0
  AND sb.warehouse_id <> ?                  -- not already at EXPIRED
  AND NOT EXISTS (                          -- idempotency: never re-transfer
    SELECT 1 FROM stock_movements sm
    WHERE sm.batch_id = sb.id AND sm.movement_type = 'EXPIRY_TRANSFER')
ORDER BY sb.expiry_date ASC
```
- For each batch, inside its OWN `db.transaction()` (per-batch scope, so
  one bad batch cannot roll back the sweep; batch-targeted, NOT FEFO
  oldest-consumption — we move the specific expired batch):
  1. Zero the source: `UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?`
     — **this is the caller's responsibility**. `recordMovement` touches
     only `stock_movements`, `stock_balances`, `items.current_stock`, and
     `batch_stock_by_location`; it never writes `stock_batches`. Doing
     both would double-decrement — hence exactly one zeroing point.
  2. Mint a mirrored batch at the EXPIRED warehouse (same pattern as
     `recordTransfer`'s TRANSFER mirror): same `unit_cost`,
     `source_type = 'TRANSFER'` (per 1.5), `source_id` = OUT movement id.
  3. Record both legs via `StockMovementModel.recordMovement` — it syncs
     `stock_balances`, `items.current_stock`, and `batch_stock_by_location`
     (when the feature flag is on). **Never UPDATE balances by hand.**
     - OUT leg: source warehouse, quantity = −qty, `batch_id` = source
       batch, `reference_doctype` = 'EXPIRY_TRANSFER', `reference_docno` =
       source `batch_no`.
     - IN leg: EXPIRED warehouse, quantity = +qty, `batch_id` = mirrored
       batch, `reference_docno` = OUT `movement_no`.
  4. Audit trail: the movement rows ARE the audit record — remarks carry
     batch_no + expiry_date + `source=SYSTEM`. No separate audit table write.
- Per-batch failures: catch inside the loop, log `{ batch_id, reason,
  timestamp }` to the error log, continue with the next batch. Failed
  batches stay candidates (idempotency guard not yet triggered) and are
  retried on the next boot automatically — no separate retry queue.
- If `feature_batch_locations` is enabled, verify the move path also
  handles `batch_stock_by_location` (recordMovement already does via
  `syncStockBalancesExtension` / `syncBatchStockByLocationForNewBatch`).

2.2 Integrate into `server/server.ts` (NOT `app.ts` — app.ts is route
wiring only; server.ts owns boot tasks). The sweep is synchronous SQLite
work, so it is cheap — but **`await` it before `listen`** so no request
can observe a half-swept valuation:

```ts
void dbSeedReady.then(async () => {
  try {
    await runExpiryDetection(db); // resolves destination id, sweeps, logs per-batch failures
  } catch (err) {
    logger.error('Expiry detection failed:', err); // log and continue serving
  }
  server = app.listen(PORT, HOST, () => { ... }); // existing
});
```

- Migrations (including Phase 1 seeds) have already run when `dbSeedReady`
  resolves — `import db from './src/config/database'` executes them at
  import time, before this point.
- Failure policy: missing EXPIRED warehouse → throw (migration bug, loud);
  per-batch errors → logged and skipped, retried on next boot. Boot
  continues either way — never block serving on expiry detection.
- Audit actor: **do not borrow an arbitrary admin's user id.** Pass a
  dedicated system identity — `created_by = NULL` plus `source=SYSTEM` in
  the remarks — so the trail distinguishes boot-initiated transfers from
  human actions. If the movements table's FK requires a real user, seed a
  locked `SYSTEM` user row (`is_active = 0`, no login) in the migration.

## Phase 3: Write-off Workflow
3.1 Add write-off endpoint:
```
POST /api/inventory/expired/write-off
Body: { batchIds: [number], reason: string (1–500 chars, trimmed),
        glAccount: string (e.g. "7201") }
```

3.2 Validation:
- batchIds must be expired (derived: `expiry_date < today`, per 1.3 — no
  stored status) and `quantity_remaining > 0`, and not already written off
  (no prior WRITE_OFF movement for the batch)
- **batchIds must already be at the EXPIRED warehouse.** Writing off a
  batch still sitting at MAIN would record a WRITE_OFF at the wrong
  location. To keep UX forgiving, the endpoint performs the expiry
  transfer first (same transaction, same code path as the boot task) when
  a selected batch hasn't been swept yet — boot task and endpoint share
  one transfer implementation.
- glAccount must exist in chart_of_accounts AND be `7200` or a child of
  `7200` (enforce the hierarchy, not mere existence — otherwise
  sub-category reports silently miss postings)
- reason: trim, require non-empty, cap at 500 chars; stored structurally
  in the movement remarks (`[WRITE_OFF] reason=… gl=7201 batch=…`)
- Permission: `requirePermission('inventory', 'update')` for rollout —
  write-off is GL-impacting, so introduce a dedicated
  `inventory.write_off` permission once the roles system supports it.

3.3 GL posting on write-off (via AccountingService journal_lines):
```
Dr. Expired Goods Loss (7201–7204) / Cr. Inventory Asset (1200)
```
- Reduce batch.quantity_remaining to 0 (same ownership rule as 2.1 step 1:
  the write-off code zeroes `stock_batches`, `recordMovement` does not)
- Record a single WRITE_OFF movement (negative qty, batch-linked, at the
  EXPIRED warehouse) via `recordMovement` — this syncs stock_balances and
  doubles as the audit record (see 2.1)
- "WRITTEN_OFF" is derivable from that movement — no status column (1.3)

3.4 Write-off dialog frontend:
- List expired batches per item with qty × cost value
- Multi-select batches
- Reason input field
- GL account selector (or auto-use 7201)
- Confirmation dialog
- Toast on success + refetch data

## Phase 4: Frontend Integration

4.1 System Warehouses (read-only in UI):
- Add `isSystem` flag to warehouse model
- In warehouse dropdown: mark system warehouses with ⚠ icon
- Disable delete button for system warehouses
- System warehouses appear in item location filter but cannot be selected as "new" warehouse

4.2 Inventory Valuation Report (NEW):
```
GET /api/reports/inventory-valuation
Returns:
{
  sellable: { qty: number, value: number },     // qty × sellable cost
  reserved: { qty: number, value: number },
  expired: { qty: number, value: number },      // qty × cost price
  damaged: { qty: number, value: number },      // qty × cost price
  writtenOff: { count: number, qty: number, totalValue: number },
  totalPhysical: { qty: number, value: number }
}
```

Semantics (fixed definitions):
- `reserved` is a **subset of `sellable`** (allocation of on-hand stock to
  pending invoices/orders), reported separately for visibility — it is
  NOT additive with sellable.
- `totalPhysical = (sellable − reserved) + expired + damaged` — everything
  physically on shelves. Written-off stock has qty 0 and is excluded.
- `expired` = stock at the EXPIRED warehouse; `damaged` = batches with
  `status_override = 'DAMAGED'`. A batch that expired but hasn't been
  swept by the boot task yet still shows under `sellable` — the report
  documents this invariant ("accurate as of the last boot sweep"); the
  boot task runs before `listen` (2.2), so the window is one server
  lifetime at most.
- `writtenOff.qty` is included (sum of written-off quantities) alongside
  `count` and `totalValue` for consistency with the other buckets.

4.3 Expiry Report Enhancement:
- Add "Write Off" button per batch
- Show cost value (not selling price)
- Filter: Expired today, this month, in 7 days, in 30 days
- Bulk write-off selection
- Show GL account used

4.4 Supplier Return Integration (reuse existing):
- Use existing purchase return flow: `POST /api/purchases/returns`
- **Verified constraint:** the existing return flow consumes batches at
  their original warehouse via FEFO and records movements with
  `purchase_return_id`. It does not know about the EXPIRED warehouse.
  Two options, in order of preference:
  a. Extend the endpoint to accept an explicit `source_warehouse_id`
     (validated: must hold the batch quantity) — movements then post at
     the EXPIRED warehouse.
  b. If extension is rejected as scope creep, the UI directs expired
     returns through the write-off path instead (supplier credit handled
     outside the system).
- Policy assumption (state in UI): supplier return assumes the supplier
  accepts expired goods back. **Expired stock is often non-returnable —
  the write-off flow is the fallback**, not an edge case.
- When returning expired items via option (a):
  - Reference original PO number
  - System reverses: Dr Accounts Payable (2000) / Cr Inventory Asset (1200)
  - NO GL loss entry (it's a recovery, not a loss)
- Distinguish from write-off in UI:
  - "Write Off" → Creates GL loss entry
  - "Supplier Return" → Uses existing purchase return, no GL loss

## Phase 5: Testing & Rollout

5.1 Unit Tests:
- Expiry detection with various date scenarios
- Write-off validation and GL posting
- System warehouse delete guard (API 400 + trigger)

5.2 Integration Tests:
- Boot task creates correct movements on fresh install
- Write-off endpoint posts correct GL entries
- Valuation report shows separated totals
- Boot wiring regression: an automated test that constructs a DB with an
  expired batch, invokes the boot-task entry point, and asserts the
  mirrored batch + paired movements exist (so CI catches boot-wiring
  regressions without a manual restart — E2E step 2 below is the manual
  confirmation, not the only coverage)

5.3 E2E Tests (manual steps):
1. Fresh install → verify EXPIRED/DAMAGED warehouses auto-created
2. Add item with expiry date in past → on app restart, batch auto-moves to Expired
3. Select expired batches → write off → verify GL entry posted
4. Valuation report shows correct separated values
5. Supplier return flow works without creating loss entry

5.4 Rollout Order:
1. DB migration `add-expired-stock.sql` (accounts, is_system column, warehouse seeds) — applied by the migration runner on every install
2. Boot task implementation (expiryDetection rewrite + server.ts wiring)
3. Write-off endpoint + GL posting (Dr 7201–7204 / Cr 1200)
4. Frontend report updates (valuation + expiry)
5. Supplier return integration test

## Existing Code Preservation

### What NOT to modify:
- `sales_invoice_form_page.dart` sellable_only filter (already correct)
- `invoice_rules.dart` cancellation guards (already correct)
- Existing expiry report screen structure
- Existing purchase return flow

### What TO modify:
- `server/src/models/StockBatch.ts` - No change (status is derived, 1.3)
- `server/src/models/StockMovement.ts` - Add batch-targeted transfer helper
  (paired-leg) for expiryDetection to reuse
- `server/src/migrations/add-expired-stock.sql` - NEW migration (1.1/1.2)
- `server/src/models/Warehouse.ts` - Add system flag + delete guard
- `server/src/boot/expiryDetection.ts` - Rewrite per 2.1
- `server/server.ts` - Register boot task (2.2)
- `server/src/routes/inventory.ts` - Add write-off endpoint
- `lib/features/inventory/warehouse_repository.dart` - Delete guard
- `lib/features/reports/inventory_valuation_report.dart` - NEW or enhance existing
- `lib/features/reports/expiry_report_screen.dart` - Enhance with write-off
- `lib/l10n/app_localizations.dart` + .arb files - Add any new l10n keys

## GL Posting Examples

### Write-off Entry
```
Dr Expired Goods Loss (7201)    5,000
   Cr Inventory Asset (1200)    5,000
```
(Credit the inventory ASSET account 1200 — never 7200, which is itself an
expense account; see Phase 1.1.)

### Supplier Return (no GL loss)
```
Dr Accounts Payable (2000)      5,000
   Cr Inventory Asset (1200)    5,000
```
(no loss entry - it's a recovery)

### Damage Transfer (move to Damaged Stock warehouse, no loss yet)
```
No GL entry — physical reclassification only (paired EXPIRY-style legs
with movement_type = 'DAMAGE_TRANSFER'; inventory stays inventory).

---

## Migration for Existing Installs

Handled automatically by the normal migration runner — no manual script:
- `add-expired-stock.sql` ships in `server/src/migrations/` and is applied
  once via the `schema_migrations` ledger on next server start.
- `INSERT OR IGNORE` makes the warehouse + GL seeds idempotent.
- Existing expired batches are picked up by the Phase 2 boot task on the
  first run after the migration (the `NOT EXISTS` guard makes it a no-op
  on subsequent boots).

## Success Criteria

✅ Fresh install: EXPIRED + DAMAGED warehouses auto-created via migration, non-deletable (API guard + DB trigger)
✅ On startup (before listen): Expired batches auto-transferred to Expired Stock (paired legs, balances synced, SYSTEM actor)
✅ Write-off: Correct GL entry posted (Dr 7201 / Cr 1200)
✅ Valuation report: Sellable/Reserved/Expired/Damaged separated
✅ Supplier return: Uses existing endpoint, NO loss entry
✅ Audit trail: Movement rows carry batch_no, user, timestamp, reason in remarks
✅ Cannot delete: System warehouses protected (server 400 + UI guard)