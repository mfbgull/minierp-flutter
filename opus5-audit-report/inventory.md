# INVENTORY / STOCK LAYER AUDIT — MiniERP

Read-only. No file was created, modified or deleted. Live DB was copied out (`erp.db` + `-wal` + `-shm`) and read via Python `sqlite3`.

---

## 0. HEADLINE: THE DRIFT IS FULLY EXPLAINED, PER WAREHOUSE

FACT 2 aggregates at item level and hides the real signal. Broken out per `(item_id, warehouse_id)`, the drift matches two code defects **exactly, to the unit**:

| item | wh | `stock_balances` | `SUM(movements)` | `SUM(batches.qty_remaining)` | drift | cause (exact) |
|---|---|---|---|---|---|---|
| 1 Widget A | 1 | 12.0 | 12.0 | 10.0 | **+2.000** | `STK-2026-1787307950666` PhysicalCount **+2** |
| 2 Mustard Oil (Loose) | 1 | 35.0 | 35.0 | 38.722 | **−3.722** | `STK-2026-1787307950667` PhysicalCount **−3.722** |
| 2 Mustard Oil (Loose) | 2 | 10.0 | 10.0 | **0.0** | **+10.000** | `STK-2026-0114` TRANSFER **+10** into WH2, no batch created |
| 15 Test | 1 | 45.0 | 45.0 | 50.0 | **−5.000** | `STK-2026-1787307950665` PhysicalCount **−5** |
| 9,10,11,12,13,14,16,17,18,19 | — | 0 | 0 | 0 | 0 | clean |

Item 2's "short 6.278" in FACT 2 is `−3.722 + 10.0` — two unrelated bugs in opposite directions that partially cancel at item level. **There is no mystery drift.** Two code paths cause 100% of it: `PhysicalCount.completeCount` (INV-01) and the two-leg transfer (INV-02).

---

## 1. TASK 1 — IS THERE A CANONICAL MUTATION FUNCTION?

**No.** `StockMovement.recordMovement` is the *nearest* thing, but five other modules bypass it with hand-rolled SQL. Exhaustive writer census (production code only; `__tests__/` and `audit-trace.ts` excluded):

**`INSERT INTO stock_movements` — 7 sites**
`models/StockMovement.ts:105` · `models/PhysicalCount.ts:279` · `models/Production.ts:213` (inputs) · `:300` (output) · `models/Purchase.ts:181` · `models/PurchaseOrder.ts:793` · `models/SalesOrder.ts:713` · (+ `scripts/fix-duplicate-purchase.ts:74`)

**`stock_balances` upsert — 8 sites, near-identical copy-paste**
`models/StockMovement.ts:134/141` · `models/PhysicalCount.ts:305/312` · `models/Production.ts:244/251` and `:355/362` · `models/Purchase.ts:214/221` · `models/PurchaseOrder.ts:821/827` · `models/SalesOrder.ts:737` (**UPDATE only — no INSERT branch**, INV-06) · `config/database.ts:241/244` (boot self-heal)

**`items.current_stock` recompute — 7 sites**, all the same subquery, incl. `PurchaseOrder.ts:836` (loop) and `PhysicalCount.ts:318`.

**`stock_batches` writers — 10 sites**
INSERT: `Production.ts:274`, `Purchase.ts:155`, `PurchaseOrder.ts:772`, `config/database.ts:1911` (RECON), `scripts/backfill-batches.ts:124/181`
UPDATE: `StockMovement.ts:678` (FIFO consume), `Invoice.ts:633` (return restore), `Production.ts:567/617`, `PurchaseReturn.ts:417/521`, `routes/stockBatches.ts:76/110/143`
DELETE: `migrations/cleanup-orphaned-stock-batches.sql:25`

The structural root cause of everything below:

```ts
// models/StockMovement.ts:100-175  recordMovement()
//   1. INSERT INTO stock_movements
//   2. upsert stock_balances
//   3. UPDATE items SET current_stock = (SELECT SUM(quantity) FROM stock_balances ...)
//   4. if (data.movement_type === 'ADJUSTMENT') postFinancialEntryForAdjustment(...)
//   -- stock_batches is NEVER touched.
```

Every ADJUSTMENT in the system flows through this function. **Every ADJUSTMENT therefore desynchronises `stock_batches` from `stock_balances` by construction.** FACT 5 shows 48 of 105 movements are ADJUSTMENT.

---

## 2. TASK 2 — EVENT → MOVEMENT MATRIX

| Event | Entry point | Movement? | Sign | `stock_balances` | `stock_batches` | GL | Verdict |
|---|---|---|---|---|---|---|---|
| Direct purchase create | `Purchase.recordPurchase:101` | ✔ `PURCHASE` | + ok | ✔ own block | ✔ INSERT | purchase entry | ok (see INV-10) |
| Direct purchase delete | `Purchase.delete:444` | ✔ `ADJUSTMENT`/`PURCHASE_DELETE` | − ok | ✔ | zeroes batch | ✔ | **INV-11: no reversal at all if batch row missing** |
| Direct purchase edit | *none* | — | — | — | — | — | UNVERIFIED — no update path found; edit appears unsupported |
| PO goods receipt | `PurchaseOrder.receiveGoods:~760` | ✔ `PURCHASE`/`GOODS_RECEIPT` | + ok | ✔ own block | ✔ INSERT `source_id=goods_receipt_items.id` | ✔ | **INV-10 id collision** |
| GR reversal / PO cancel after receipt | *none found* | ✘ | — | — | — | — | UNVERIFIED — no un-receive path; received stock is unreversible |
| Invoice create | `invoiceController.ts:134-367` | ✔ one `SALE` per batch | − ok | ✔ | ✔ FIFO/FEFO | invoice + COGS | ok |
| Invoice update | `invoiceController.ts:375-596` | ✔ `ADJUSTMENT`/`INVOICE_UPDATE` **+ new SALEs** | ok | ✔ | partial | invoice reposted, **COGS not** | **INV-12 DOUBLE movements: old SALEs are never deleted** |
| Invoice delete | `invoiceController.ts:603-684` | ✔ `ADJUSTMENT`/`INVOICE_DELETE` | + ok | ✔ | only if `batch_id NOT NULL` | ✔ | **INV-13** |
| Sales return | `invoiceController.ts:773-1227` | ✔ `ADJUSTMENT`/`RETURN` | + ok | ✔ | only if `batch_id NOT NULL`, ratio-scaled | COGS reversal | **INV-13, INV-22** |
| SO → Invoice | `SalesOrder.convertToInvoice:~700` | ✔ own INSERT, `reference_doctype:'Invoice'` | − ok | **UPDATE-only** | ✘ **never** | ✘ | **INV-06 P0 — silent no-op** |
| POS sale | `posController.ts:87-200` | ✔ `SALE`/`POS` | − ok | ✔ | ✔ FIFO | **✘ none** | **INV-17** |
| Mobile invoice submit | `MobileInvoice.submitInvoice:194` | ✔ `SALE`, `reference_docno = String(invoiceId)` | − ok | ✔ | ✘ **never** | ✘ | **INV-03 P0** |
| Purchase return | `PurchaseReturn.create:~330` | ✔ `ADJUSTMENT` | − ok | ✔ | FIFO reduce, shortfall tolerated | ✔ | INV-18 on void |
| Stock adjustment | `inventoryController.createStockMovement:374` | ✔ | ok | ✔ | only if qty<0 | ✔ | INV-08 |
| Transfer | same endpoint, **called twice by the client** | ✔ ×2 | net 0 | ✔ both legs | **source only** | ✘ | **INV-02 P0** |
| Physical count complete | `PhysicalCount.completeCount:264` | ✔ `ADJUSTMENT`/`PhysicalCount` | ok | ✔ own block | ✘ **never** | ✔ own JE | **INV-01 P0** |
| Production | `Production.recordProduction` | ✔ inputs − / output + | ok | ✔ ×2 blocks | ✔ consume + INSERT | ✔ | **correct** |
| Production delete | `Production.delete:539` | ✔ compensating ADJUSTMENTs | ok | ✔ | restores inputs, zeroes output | ✔ | **correct** |

**MISSING movements:** SO→Invoice when no `stock_balances` row exists (INV-06); GR reversal (no path exists); destination batch on transfer (INV-02).
**DOUBLE movements:** invoice update leaves the superseded `SALE` rows in place under the same `reference_docno` — live proof, item 1 / `INV-2026-958984`: `STK-2026-0108 SALE −1`, `STK-2026-0110 ADJ +1`, `STK-2026-0112 SALE −1`. Quantity nets correctly, but every later consumer that queries `WHERE reference_docno = ? AND movement_type='SALE'` now sees `totalSold = 2` for a 1-unit invoice (INV-12).

---

## 3. FINDINGS

### INV-01 — `PhysicalCount.completeCount` writes balances and GL but never `stock_batches` — **P0**
`server/src/models/PhysicalCount.ts:264-379`
```ts
const transaction = db.transaction(() => {          // :271  DEFERRED, not .immediate()
  for (const item of adjustmentItems) {
    const movementResult = db.prepare(`INSERT INTO stock_movements (...) VALUES (?,?,?,'ADJUSTMENT',?,?, 'PhysicalCount', ?,?,?,?)`).run(
      `STK-${new Date().getFullYear()}-${Date.now()}`,   // :285
      item.item_id, count.warehouse_id, item.variance, item.unit_cost, ...);
    // :299-315  own stock_balances upsert
    // :318-326  own items.current_stock recompute
    // :336-364  own journal_entries INSERT
  }                                                  // <- no stock_batches statement anywhere
});
```
**Why it matters:** the physical count is the one operation whose entire purpose is to make the system agree with reality, and it updates two of the three caches. `stock_batches` is what the balance sheet, the dashboard inventory tile and the stock-valuation report read.
**Live damage:** 3 of the 4 drifting rows. Item 15: counted 45, batches still say 50 → balance sheet carries 5 phantom units. Item 1: counted 12, batches say 10 → balance sheet is missing 2 units × Rs 500 = **Rs 1,000**.
**Fix:** inside the same loop, for `variance < 0` call `StockMovement.consumeFromOldestBatches` (or reduce FIFO directly); for `variance > 0` insert a `source_type='ADJUSTMENT'` batch at `item.unit_cost`. Requires relaxing the FACT-4 CHECK (INV-22).
**Migration needed:** yes — one-off batch reconciliation for the 3 affected rows.
**Historical data affected:** yes, all 3 completed count adjustments.

### INV-02 — Warehouse transfer is two independent HTTP requests and creates no destination batch — **P0**
`lib/features/inventory/stock_transfer_dialog.dart:92-158`, server side `server/src/controllers/inventoryController.ts:374-435`, routes `server/src/routes/inventory.ts:28`
```dart
// Leg 1 — OUT of the source warehouse.
if (_outMovementNo == null) { final out = await repo.createStockMovement({... 'quantity': -qty ...});
  switch (out) { case ApiFailure(:final error): setState(...); return; } }
// Leg 2 — IN to the destination, linked to the outgoing movement.
final incoming = await repo.createStockMovement({... 'quantity': qty, 'reference_docno': _outMovementNo! ...});
case ApiFailure(:final error):
  // The OUT leg is already on the server; flag it so a retry doesn't silently re-post.
  setState(() { _error = '${l10n.stockmovementsTransferpartialfail} ${error.message}'; });
```
There is **no transfer endpoint**. `POST /api/stock-movements` is the only mutation route (confirmed by grep over `server/src/routes/`). So a transfer is not one transaction, not one request, and not recoverable server-side: the compensating knowledge (`_outMovementNo`) lives only in Flutter widget state. Close the dialog, lose the network, or kill the app between legs and the stock is **permanently destroyed** with no pending record anywhere.
Second defect: the IN leg goes to `recordMovement` (positive quantity ⇒ `recordBatchMovement` delegates), which never creates a batch. Live: `STK-2026-0113` decremented batch 18 in WH1 by 10; `STK-2026-0114` added 10 to WH2's balance; **WH2 now holds 10 units with zero cost layers** — Rs 4,000 invisible to the balance sheet.
**Fix:** server-side `POST /api/stock-transfers` taking source+dest, doing both legs inside one `db.transaction(...).immediate()`, consuming source batches FIFO and inserting mirror batches in the destination carrying the same `unit_cost`, `received_date` and `expiry_date`.
**Migration:** yes (INV-01's reconciliation covers it). **Historical:** yes, 1 transfer.

### INV-03 — `MobileInvoice.submitInvoice` is an unguarded, unbatched, unposted sale path — **P0**
`server/src/models/MobileInvoice.ts:194-255`, live at `POST /api/mobile-invoices/submit` (`app.ts:229`, `routes/mobileInvoices.ts:25`)
```ts
const warehouseId = item.warehouse_id || findWarehouseForItem(db, item.item_id, item.quantity);
StockMovementModel.recordMovement({
  item_id: item.item_id, warehouse_id: warehouseId, movement_type: 'SALE',
  quantity: -item.quantity,
  unit_cost: item.unit_price,               // <- SELLING price written into the cost column
  reference_doctype: 'INVOICE',
  reference_docno: String(invoiceId),       // <- bare rowid, not invoice_no
  ...}, data.userId, db);
```
Five defects in one function: (a) **no stock check at all** — `findWarehouseForItem:172-192` falls back to `WH-001`/id 1 even at zero stock, so this path can drive stock negative; (b) **no batch consumption** → drift; (c) `unit_cost = unit_price` poisons `stock_movements.unit_cost`, which is the input to `runUnbatchedStockReconciliation`'s cost average (INV-04), `reverseStockForItems`' `avgUnitCost` (`Invoice.ts:648`) and the return-COGS reversal (`invoiceController.ts:958`); (d) `reference_docno` is the rowid, so `reverseStockForItems` (which matches on `invoiceNo`) can **never** find these movements — deleting or returning a mobile invoice logs `[BatchReversal] No SALE movements found` and silently restores nothing; (e) no `postInvoiceEntry`, no `postCOGSEntry` — mobile revenue and COGS never reach the GL.
**Fix:** route through the same code as `invoiceController.createInvoice`. **Migration:** only if mobile invoices exist in production (live DB shows none — this is a live landmine, not yet damage).

### INV-04 — `runUnbatchedStockReconciliation` mints inventory value on every boot, at a wrong cost — **P0**
`server/src/config/database.ts:1879-1962`, called unconditionally at `:1085`
```ts
const uncovered = row.on_hand - row.covered;
if (uncovered <= 0.0005) continue;
const avg = db.prepare(`SELECT COALESCE(SUM(quantity*unit_cost)*1.0/NULLIF(SUM(quantity),0),0) as cost
  FROM stock_movements WHERE item_id = ? AND quantity > 0 AND batch_id IS NULL`).get(row.item_id);
const unitCost = avg.cost > 0 ? avg.cost : (row.standard_cost || 0);
insertBatch.run(batchNo, row.item_id, row.warehouse_id, uncovered, uncovered, unitCost, today);
//   INSERT ... source_type='PURCHASE', source_id=0
```
No guard, no version flag, no idempotency key — it re-evaluates the gap on **every single server start** and mints a new `BATCH-yy-RECON-nnnn` row for any positive gap, with **no journal entry**. Inventory asset value appears out of nothing.
The cost is wrong three ways: (1) not warehouse-scoped (`WHERE item_id = ?` only) while the batch it creates is; (2) it includes inbound movements from **deleted** purchases, because `cleanup-orphaned-stock-batches.sql` NULLs their `batch_id`, which is exactly this query's filter; (3) it includes inbound `ADJUSTMENT` rows.
**Live, right now:** item 1 has gap +2 and item 2/WH2 has gap +10. On the next restart this will fire. Item 1's unbatched inbound set is `+10@500, +500@10 (deleted purchase), +5@500, +5@500, +1@500, +1@500, +2@500` → weighted average **Rs 32.44**. Two units of Widget A, whose real cost is Rs 500, will be capitalised at Rs 32.44 — a 94% understatement — because a purchase that was deleted three steps earlier still drags the average down. Item 2/WH2's 10 units will likewise be minted at the item-level average, not WH2's actual cost.
The gap only ever closes upward: the negative-direction rows (item 2/WH1 −3.722, item 15 −5) are skipped by `if (uncovered <= 0.0005) continue`, so batches that **exceed** balances are never trimmed. This is a one-way ratchet toward overstated inventory.
Interaction with INV-05: RECON rows use `source_id = 0`, which survives the cleanup's `source_id > 0` predicate — but a RECON row created with `unitCost = 0` (possible when `avg.cost = 0` and `standard_cost` is 0/NULL) is matched by the cleanup's `unit_cost <= 0` clause. Since `runUnbatchedStockReconciliation()` runs at `:1085` and `runOrphanedBatchCleanup()` at `:1086`, such a row is **created and destroyed within the same boot, forever**, and the cleanup NULLs `batch_id` on any movement it touched on the way out.
**Fix:** gate behind a one-time migration flag; scope the cost average to `(item_id, warehouse_id)` and to `movement_type IN ('PURCHASE','PRODUCTION')`; post a balancing journal entry; handle the negative direction explicitly instead of ignoring it.

### INV-05 — Boot-time cleanup destroys live batch quantity and severs historical batch links — **P0**
`server/src/migrations/cleanup-orphaned-stock-batches.sql`, driven by `config/database.ts:1990-2019` on every start when the orphan count > 0
```sql
UPDATE stock_movements SET batch_id = NULL WHERE batch_id IN (
  SELECT sb.id FROM stock_batches sb
  WHERE (sb.source_type = 'PURCHASE' AND sb.source_id > 0
         AND NOT EXISTS (SELECT 1 FROM purchases WHERE id = sb.source_id)
         AND NOT EXISTS (SELECT 1 FROM goods_receipt_items WHERE id = sb.source_id))
     OR sb.unit_cost <= 0 OR sb.quantity_original <= 0);
DELETE FROM stock_batches WHERE (... same predicate ...) OR unit_cost <= 0 OR quantity_original <= 0;
```
`DELETE` has **no `quantity_remaining = 0` guard** — it removes cost layers that still hold stock, with no compensating `stock_balances` change and no journal entry, so batch coverage silently drops below on-hand (which INV-04 then re-mints at a wrong cost on the following boot).
Worse, NULLing `batch_id` on historical **SALE** movements is irreversible destruction of the audit link. `Invoice.reverseStockForItems:630` restores batch quantity only `if (movement.batch_id !== null)`, so any invoice whose SALE rows were scrubbed can never be returned correctly again — the balance goes back up, the batch does not.
**Live evidence:** `STK-2026-0010` (`SALE −1`, item 1, `INV-2026-120373`) has `batch_id = NULL` and its remark still reads `(batch 4)`. Batch 4 is gone. Returning that invoice today restores balance and not batches.
**Fix:** add `AND quantity_remaining <= 0.0005` to the DELETE; never rewrite `stock_movements.batch_id` — mark batches `voided` instead; convert this from a boot task into an explicit, logged, reviewable script.
**Historical data affected:** yes — `stock_batches` ids 3, 4, 6, 7, 8 (and others) are gone; movements 1, 5, 8, 9, 10 lost their links.

### INV-06 — `SalesOrder.convertToInvoice` deducts stock with an `UPDATE`-only balance write — **P0**
`server/src/models/SalesOrder.ts:~700-745`
```ts
const effectiveWarehouseId = salesOrder.warehouse_id || 1;
// ... :713 own INSERT INTO stock_movements (reference_doctype 'Invoice')
db.prepare(`UPDATE stock_balances SET quantity = quantity + ?, last_updated = CURRENT_TIMESTAMP
            WHERE item_id = ? AND warehouse_id = ?`).run(-qty, itemId, effectiveWarehouseId);   // :737
```
It is the only balance writer in the codebase with no `INSERT` fallback. When no `(item_id, warehouse_id)` row exists — a brand-new item, a warehouse that has never stocked the item, or the `|| 1` fallback pointing at a warehouse the item was never received into — `changes = 0` and **nothing is deducted**, silently. No batch consumption either, and no availability check. `salesController.convertSalesOrderToInvoice:360` wraps it in a DEFERRED transaction, so it commits happily.
Note this is masked in the data by `config/database.ts:224-265`, which INSERTs any missing balance row from `SUM(stock_movements)` on the next boot — so the ledger and the balance eventually agree while the *live* system sold goods it never deducted (INV-09).
**Fix:** delete this block and call `StockMovement.recordBatchMovement`.

### INV-07 — No canonical stock-mutation API; logic duplicated 8× — **P1**
See §1 for the full census. Every one of the P0/P1 findings above is an instance of one copy of the block being fixed and the others not: `SalesOrder.ts:737` lacks the INSERT branch that `StockMovement.ts:141` has; `PhysicalCount.ts:305` and `SalesOrder.ts:713` lack the batch logic that `recordBatchMovement:708` has; `PurchaseOrder.ts:836` recomputes `current_stock` in a second loop instead of inline. There is no `StockService`.
**Fix:** one `StockService.apply(movement[])` used by all callers, taking an open transaction, updating all three tables and posting GL; make direct SQL against `stock_balances`/`stock_batches` a lint error.

### INV-08 — Negative-stock guard is check-then-act, outside the transaction — **P1**
`server/src/controllers/inventoryController.ts:383-410`
```ts
if (['OUT','TRANSFER','ADJUSTMENT'].includes(movement_type) && quantity < 0) {
  const currentStock = StockMovementModel.getBalance(item_id, warehouse_id, db) as {quantity:number}|undefined;
  const availableQty = currentStock?.quantity || 0;
  if (availableQty < Math.abs(quantity)) { res.status(400).json({error:'Insufficient stock', ...}); return; }
}
const useBatchConsumption = ['SALE','TRANSFER','ADJUSTMENT'].includes(movement_type) && quantity < 0;
```
The read and the write are in different transactions (the write's transaction is opened later, inside the model). `'SALE'` is absent from the guard list but present in the consumption list; `'OUT'` is the reverse.
`posController.ts:87-97` has the same shape — validation loop, then `db.transaction(...)` opened at `:100` in **DEFERRED** mode, so SQLite takes no write lock until the first mutation and two concurrent tills both pass validation.
`Invoice.findWarehouseForItem:507-567` does not guard at all: on insufficient stock it `logger.warn(... 'Proceeding anyway.')` and picks another warehouse, then `WH-001`, then id 1.
The **only** real enforcement is inside `StockMovement.consumeFromOldestBatches:586-592` (`throw new Error('Insufficient stock for ...')`), which reads `stock_balances` inside the transaction — but that transaction is DEFERRED everywhere except production, so the read is not serialised against a concurrent writer.
`models/Production.ts:397` is the single correct instance: `return transaction.immediate();`
FACT 7 (no negative stock today) is a single-user artifact, not evidence the guard works.
**Fix:** `.immediate()` on every transaction that decrements stock, and re-check availability inside it. Add `CHECK(quantity >= 0)` on `stock_balances` as a backstop (INV-21).

### INV-09 — Boot-time self-heal rewrites live stock data and masks every balance-side bug — **P1**
`server/src/config/database.ts:224-273`
```ts
const movementSums = db.prepare(`SELECT item_id, warehouse_id, SUM(quantity) as total_qty
  FROM stock_movements GROUP BY item_id, warehouse_id`).all();
for (const sum of movementSums) { /* :241 */ db.prepare('UPDATE stock_balances SET quantity = ?, last_updated = CURRENT_TIMESTAMP WHERE id = ?').run(sum.total_qty, existing.id);
  /* :244 */ else db.prepare('INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?,?,?)').run(...); }
// :266-273  UPDATE items SET current_stock = (SELECT COALESCE(SUM(quantity),0) FROM stock_balances WHERE item_id = items.id)
```
This is why FACT 1 holds. `stock_balances` and `items.current_stock` reconciling with `SUM(stock_movements)` is **not evidence that the write paths are correct** — it is evidence that they are overwritten from the ledger on every restart. INV-06's silent no-deduction, `PurchaseOrder.ts:836`'s split loop and any partially-applied write are all invisible for exactly this reason. It also means a bug that writes a *wrong movement* is faithfully preserved, while a bug that writes a *wrong balance* is erased — so the observable symptom is always batch drift, never balance drift. `stock_batches` is never rebuilt.
**Fix:** keep the query, drop the writes — log a discrepancy and expose it on an admin health endpoint. A silent boot-time rewrite of financial data is not a repair mechanism.

### INV-10 — `stock_batches.source_id` is a shared namespace across two tables — **P1**
`Purchase.recordPurchase` writes `('PURCHASE', purchases.id)`; `PurchaseOrder.receiveGoods:772-788` writes `('PURCHASE', goods_receipt_items.id)`; `runUnbatchedStockReconciliation` writes `('PURCHASE', 0)`. Three disjoint id spaces under one discriminator.
```ts
// Purchase.ts:172-175 — re-read after INSERT, non-unique key, no ORDER BY, .get()
const created = db.prepare(`SELECT id FROM stock_batches WHERE source_type = 'PURCHASE' AND source_id = ?`).get(purchaseId);
// Purchase.ts:~470 — delete path, same lookup, then posts ADJUSTMENT for -batch.quantity_remaining and zeroes it
```
**Live proof the namespace is shared:** batch 18 (`BATCH-26-PUR-0017`, item 2, `quantity_remaining = 38.722`) has `source_id = 3`, which is `goods_receipt_items.id = 3`; the only row in `purchases` is `id = 29`. And batches 1 & 2 — created by direct purchases `PURCH-2026-0001/0002`, both since deleted, hence genuinely orphaned — **survived the cleanup only because `goods_receipt_items` happens to contain ids 1 and 2**, satisfying the second `NOT EXISTS`. The cleanup predicate is unsound for the same reason.
Not yet exploitable (`purchases` is at id 29, `goods_receipt_items` at id 3) but structurally guaranteed as the tables grow: once `goods_receipt_items` reaches the 20s, `Purchase.delete(id)` can find a *goods-receipt* batch, post an ADJUSTMENT for someone else's `quantity_remaining` and zero it.
**Fix:** split into `source_table` + `source_id`, or use disjoint `source_type` values (`'PURCHASE'` vs `'GOODS_RECEIPT'` vs `'RECON'`). **Migration:** yes, re-stamp existing rows.

### INV-11 — `Purchase.delete` reverses no stock when the batch row is missing — **P1**
`server/src/models/Purchase.ts:444-521`
```ts
const batch = db.prepare(`SELECT id, batch_no, quantity_remaining, unit_cost FROM stock_batches
                          WHERE source_type='PURCHASE' AND source_id = ?`).get(id);
if (batch && batch.quantity_remaining > 0) {
  // record ADJUSTMENT -batch.quantity_remaining ; UPDATE stock_batches SET quantity_remaining = 0
}
// the purchases row is deleted regardless
```
Two failure modes: (a) the batch was already removed by INV-05's cleanup → the purchase row disappears and the stock stays on the books forever with no offsetting movement; (b) the purchase was fully sold (`quantity_remaining = 0`) → nothing is reversed, which is arguably right for stock but leaves the COGS already posted against a purchase that no longer exists. Also, reversing only `quantity_remaining` rather than the purchased quantity means a partially-sold purchase can be deleted while its sold units keep their cost basis pointing at a deleted document.
**Fix:** block deletion outright once any of the batch has been consumed; otherwise reverse the full purchased quantity inside the same transaction.

### INV-12 — Invoice update leaves stale SALE movements and never re-posts COGS — **P1**
`server/src/controllers/invoiceController.ts:375-596` (esp. `:517`)
```ts
InvoiceModel.reverseStockForItems(db, oldItems, originalInvoice.invoice_no, userId, 'INVOICE_UPDATE');
// ... then new SALE movements are inserted with the SAME reference_docno
// ... postInvoiceEntry is re-run.  postCOGSEntry is NOT.
```
The superseded `SALE` rows are never deleted. Quantity nets out (a compensating `ADJUSTMENT` is written), but `reference_docno` is the only join key in the system (FACT 3), so every downstream reader over-counts. Two concrete victims:
- `Invoice.reverseStockForItems:615` → `const totalSold = saleMovements.reduce(...)` → `:626 const ratio = Math.min(remainingToReturn / totalSold, 1)` → `:631 restoreQty = |movement.quantity| * ratio`. With a stale row inflating `totalSold`, each batch restore is scaled down, so a later return restores the full quantity to `stock_balances` (`:656 quantity: remainingToReturn`) but only a fraction to `stock_batches` → **new drift, every time**.
- `invoiceController.ts:943-959` → the return's COGS reversal computes `returnCogsTotal += |movement.quantity| * movement.unit_cost * ratio` over the same inflated set. It happens to be exact when every layer shares one unit cost, and is wrong whenever the sale spanned batches at different costs.
Separately, COGS is never recomputed on update: change an invoice from 1 unit to 50 and revenue is re-posted while `cogs`/`inventory_asset` still reflect 1 unit.
**Fix:** hard-delete (or tombstone) the superseded SALE movements inside the update transaction, and reverse+repost COGS the way revenue is.
**Historical:** yes — `INV-2026-958984` currently carries doubled SALE rows for items 1 and 2.

### INV-13 — `reverseStockForItems` restores balances in full but skips batches when `batch_id IS NULL` — **P1**
`server/src/models/Invoice.ts:628-665`
```ts
for (const movement of saleMovements) {
  if (movement.batch_id !== null) {                       // :630
    const restoreQty = Math.abs(movement.quantity) * ratio;
    db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?`).run(restoreQty, movement.batch_id);
  }
}
...
StockMovementModel.recordMovement({ ..., quantity: remainingToReturn, ... });   // :651-665  ALWAYS full quantity
```
`batch_id IS NULL` arises from three sources, all live: `consumeFromOldestBatches`' legacy fallback (`StockMovement.ts:649-667`), INV-05's cleanup, and INV-03/INV-06's unbatched sale paths. In all three cases the return credits balance and not batches — an unbounded, silent divergence with no error and no log at the point of loss.
A second, quieter defect: the comment at `:601-605` concedes the restock warehouse may differ from the batch's warehouse, so a return into WH2 can add `quantity_remaining` back to a WH1 batch — inventing stock in one warehouse and cost basis in another.
**Fix:** if any matched movement has `batch_id IS NULL`, create a compensating batch for that portion (needs INV-22) rather than silently skipping; restore into a batch in the restock warehouse.

### INV-14 — Three concurrent valuation bases; the live discrepancy is Rs 3,461.20 (14%) — **P1**
| basis | formula | reader | live total |
|---|---|---|---|
| batch | `SUM(quantity_remaining * unit_cost)` | `Reports.ts:596` (balance sheet), `Dashboard.ts:103` & `:455` (inventory tile), `Reports.ts:318-343` (valuation report) | **Rs 20,988.80** |
| standard cost | `SUM(current_stock * standard_cost)` | `StockMovement.ts:330` (`getStockSummary` → `/api/inventory/stock-summary`), `config/database.ts:1752` (custom-report `stock_value` field), `Dashboard.ts:534` | **Rs 24,450.00** |
| FIFO layer cost | `entry.consumed * entry.unitCost` | COGS on sale (`invoiceController.ts:271`) | per-transaction |

Per item: Widget A 10×500 = 5,000 (batch) vs 12×500 = 6,000 (std); Mustard Oil 38.722×400 = 15,488.80 vs 45×400 = 18,000; Test 50×10 = 500 vs 45×10 = 450. **Two screens of the same running app disagree by Rs 3,461.20 today**, and it is the drift of INV-01/INV-02 that makes them disagree.
There is also a fourth basis for adjustments: `StockMovement.postFinancialEntryForAdjustment:349-393` values every ADJUSTMENT at `items.standard_cost`, while the sale that created the shortfall was relieved at the *batch* cost. Buy at 400, sell at 400, then write off at `standard_cost` 500 and inventory is credited more than it was ever debited. **No weighted-average recalculation of `standard_cost` exists anywhere** — it is a manually maintained field that silently governs adjustment GL value, `getStockSummary`, and the legacy valuation fallback.
The valuation report also reports `total_stock` from `stock_batches` (`Reports.ts:321`), so it shows 38.722 units of Mustard Oil while the stock-balances screen shows 45.
**Fix:** one function, batch-based, with an explicit and *loud* fallback; drive the balance sheet from the GL `inventory_asset` account instead of recomputing from a cache; retire `standard_cost` as a valuation input or recompute it as a weighted average on every receipt.

### INV-15 — Expired stock is sellable; the halt is a FEFO filter, not a block — **P1**
`server/src/models/StockMovement.ts:569-701`
```ts
const availableQty = /* SELECT quantity FROM stock_balances ... */;
if (availableQty < quantity) throw new Error(`Insufficient stock for ...`);      // :586-592
const useFEFO = itemRow?.has_expiry === 1;                                        // :596
// FEFO :604-619  WHERE quantity_remaining > 0 AND (halted = 0 OR halted IS NULL)
//                  AND (expiry_date IS NULL OR expiry_date >= date('now'))
//                ORDER BY (expiry_date IS NULL), expiry_date ASC, received_date ASC, id ASC
// FIFO :634-643  ORDER BY received_date ASC, id ASC        <- no expiry filter, no halt filter
```
- The expiry/halt filter applies **only when `items.has_expiry = 1`**. For every other item, expired and halted batches are consumed normally — the FIFO branch does not look at either column.
- The authoritative availability check at `:586` reads `stock_balances`, which counts halted and expired units. So a sale is authorised against stock that FEFO then refuses to supply: you get `throw` at `:652-658` ("all batches halted/expired") or the shortfall throw at `:687-698` ("Batch coverage shortfall … Run a batch reconciliation") — a 500-level failure mid-transaction rather than a clean domain rejection.
- **The legacy fallback is the real hole:** `:649-667` returns `[{ batchId: null, consumed: quantity, unitCost: standard_cost }]`. When it triggers, the sale proceeds with no batch consumed, the cost basis silently switches from FIFO to `standard_cost`, and the movement is written with `batch_id NULL` — which INV-13 then cannot reverse. Any item whose stock is uncovered by batches (item 2/WH2 today, 10 units) sells through this path.
- `invoices.override_sale` / `invoice_items.is_expired_at_sale` are **descriptive only**. `invoiceController.ts:151/221/281` accepts `expired_batch_overrides`, sets `override_sale = 1` and rebuilds display notes via `InvoiceModel.denormalizeExpiryInfo:182-249`. It does not authorise anything, because nothing was blocking.
- The actual bypass is `PATCH /api/stock-batches/:id` (`routes/stockBatches.ts:64-87`): any `inventory:write` user may set `expiry_date` to any value **including NULL**, with no audit row, no activity log and no permission distinct from ordinary stock entry. `expiry_date = NULL` makes the batch permanently FEFO-eligible. `/halt` and `/unhalt` (`:93-154`) are equally unlogged.
**Fix:** move the expiry/halt filter into the FIFO branch too; compute availability from *eligible* batches, not from `stock_balances`, so the rejection is a clean 400; require an explicit override flag to reach expired batches instead of letting the operator edit the expiry date; log every mutation in `routes/stockBatches.ts`.

### INV-16 — `financial_posted` is meaningless — **P1**
`recordMovement` posts a journal entry (and, per FACT 6, sets `financial_posted = 1`) only for `movement_type === 'ADJUSTMENT'`. All 55 PURCHASE/SALE movements carry `financial_posted = 0` even though their GL entries were posted by `AccountingService.postCOGSEntry` / the purchase path. The flag therefore cannot be used to detect unposted or double-posted movements — the one thing a posting flag is for. Any future "post unposted movements" job would double-post every purchase and sale in the ledger.
**Fix:** set it from whichever layer actually posts, or drop the column.

### INV-17 — POS sales post no GL at all — **P1**
`server/src/controllers/posController.ts:87-200`. Consumes FIFO correctly via `InvoiceModel.consumeFromOldestBatches:161` and writes `SALE`/`POS` movements, but there is no `postInvoiceEntry`, no `postCOGSEntry`, and no `denormalizeExpiryInfo`. Stock leaves; revenue, COGS and the inventory relief never reach the ledger. (Flagged here because it is the same code path; the accounting audit owns the remedy.)

### INV-18 — `PurchaseReturn.voidReturn` un-consumes LIFO against a FIFO consumption — **P1**
`server/src/models/PurchaseReturn.ts:~500-525`
```ts
// create(): reduce batches oldest-first
db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?`)...   // :417
// voidReturn(): add the FULL quantity back to ONE batch — the newest
//   SELECT id FROM stock_batches WHERE ... ORDER BY received_date DESC, id DESC LIMIT 1
db.prepare(`UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?`)...   // :521
```
Void is not the inverse of create: a return that spanned three old cheap layers is voided entirely into the newest expensive layer. Total quantity is preserved; the cost distribution is scrambled, permanently and unrecoverably. `create()` also explicitly tolerates drift — *"If batches didn't fully cover the return (legacy unbatchable stock), the remainder is fine — the reconciliation migration folds it later"* — deferring to the boot-time job that INV-04 shows folds it at the wrong cost.
**Fix:** persist which batches a return consumed (a `purchase_return_batches` link table) and reverse against exactly those.

### INV-19 — Physical count posts a snapshot variance with no re-read at commit time — **P1**
`PhysicalCount.create:97-136` snapshots `system_quantity` from `stock_balances` when the session opens. `completeCount:288` posts `item.variance`, computed at `recordCount` time from that snapshot. Between opening the count and completing it, sales, purchases and transfers continue — and `completeCount` never re-reads the live balance, never compares it against the snapshot, and never aborts. A count opened Monday and completed Friday silently overwrites the week's movements: any sale in that window is added straight back. There is no locking, no "recount required" state, and no warning.
**Fix:** at completion, re-read the live balance and abort (or re-derive the variance) when it differs from `system_quantity`; better, freeze the item/warehouse for the duration or compute the adjustment as `counted − live_at_commit`.

### INV-20 — Document linkage is free text, and the vocabulary is inconsistent — **P1**
FACT 3 confirmed: `reference_doctype`/`reference_docno` are plain `VARCHAR` with no FK, no index pairing and no constraint. 15 SALE movements point at invoice numbers that no longer exist. Beyond the missing FK, the writers do not even agree on spelling: `'INVOICE'` (invoiceController), `'Invoice'` (`SalesOrder.ts:713`), `'POS'` (posController), `'Purchase'` / `'GOODS_RECEIPT'` / `'PURCHASE_DELETE'` / `'INVOICE_DELETE'` / `'INVOICE_UPDATE'` / `'RETURN'` / `'PhysicalCount'` / `'TRANSFER'`. `MobileInvoice` writes a bare rowid into `reference_docno` where every other path writes a document number (INV-03). Every reversal, COGS and drift-detection query in the system matches on these strings, so a case mismatch is a silent no-op — `reverseStockForItems:596` `continue`s with a `logger.warn` when it matches nothing.
**Fix:** enum-constrain `reference_doctype`, add nullable typed FK columns (`invoice_id`, `purchase_id`, `production_id`, `goods_receipt_item_id`) alongside the text for display, and index them.

### INV-21 — No database-level invariants on any of the three caches — **P2**
`stock_batches` (`migrations/add-batch-costing.sql`) has no `CHECK(quantity_remaining >= 0)` and no `CHECK(quantity_remaining <= quantity_original)`. `stock_balances` (`migrations/init.sql:69-98`) has no `CHECK(quantity >= 0)`. `items.current_stock` has none. Every bug above therefore fails silently and accumulates instead of aborting the transaction. Item 15 currently holds `quantity_remaining = 50` against `quantity_original = 50` while only 45 units exist — a state the schema should have made unrepresentable.
**Fix:** add the CHECKs (SQLite requires a table rebuild). Do it *after* the reconciliation migration, or existing rows will block it.

### INV-22 — `source_type` CHECK makes returned goods unbatchable — **P2**
`migrations/add-batch-costing.sql`: `source_type VARCHAR(20) NOT NULL CHECK(source_type IN ('PRODUCTION','PURCHASE'))`. Confirms FACT 4. A sales return, a positive stock adjustment and a positive physical-count variance are all real stock inflows that cannot legally create a cost layer, which is *why* INV-01 and INV-13 take the shortcut of updating balances only. `runUnbatchedStockReconciliation` works around it by lying (`source_type='PURCHASE', source_id=0`), which is also why RECON rows are indistinguishable from purchase rows in reports.
**Fix:** extend to `('PRODUCTION','PURCHASE','GOODS_RECEIPT','RETURN','ADJUSTMENT','OPENING','TRANSFER','RECON')`. Prerequisite for fixing INV-01, INV-02 and INV-13. **Migration:** yes (table rebuild).

### INV-23 — Physical count breaks the movement-number sequence — **P2**
`PhysicalCount.ts:285` — `` `STK-${new Date().getFullYear()}-${Date.now()}` `` instead of `StockMovement.generateMovementNo(db)`. Live rows: `STK-2026-1787307950665/666/667` against the sequence's `STK-2026-0001…0114`. Any ordering, gap detection or numeric parsing over `movement_no` is broken, and the epoch-ms suffix will collide with a legitimate 13-digit sequence value in the far future. **Fix:** call the shared generator.

### INV-24 — Operator-precedence bug silently zeroes a variance — **P3**
`PhysicalCount.ts:248-250`
```ts
const variance = countedQuantity - (db.prepare('SELECT system_quantity FROM physical_count_items WHERE count_id = ? AND item_id = ?')
  .get(countId, itemId) as { system_quantity: number } | undefined)?.system_quantity || 0;
```
Parses as `(countedQuantity - x?.system_quantity) || 0`. When the row is missing, `countedQuantity - undefined` is `NaN` and `NaN || 0` yields `0` — the count is accepted and recorded as "no variance". **Fix:** `const sys = ...?.system_quantity ?? 0; const variance = countedQuantity - sys;` and throw when the row is absent.

### INV-25 — `getInvoiceItemsForStockReverse` returns gross quantity — **P3**
`Invoice.ts:877-879` — `SELECT item_id, quantity, unit_price FROM invoice_items WHERE invoice_id = ?`, ignoring `returned_qty`. `reverseStockForItems` compensates by subtracting `alreadyReturned` (`:609-618`) — but that subquery counts only `reference_doctype = 'RETURN'`, so an `INVOICE_UPDATE` reversal is not counted as already-returned. Update-then-delete an invoice and the delete reverses the gross original quantity again. **UNVERIFIED** whether the delete path is reachable after an update that had a return (delete is blocked at `invoiceController.ts:615-624` when returns exist).

### INV-26 — `fix-duplicate-purchase.ts` reads `warehouse_id` after deleting the row — **P3**
`scripts/fix-duplicate-purchase.ts:64` deletes the purchase, then `:70` does `SELECT warehouse_id FROM purchases WHERE id = ?` on the deleted row → `undefined` → `:72 const warehouseId = wh?.warehouse_id ?? 1`. The reversal movement and the balance correction always land in warehouse 1 regardless of where the stock actually was. Harmless for the single case it was written for; wrong if reused. `:94-96` also uses the colliding `source_id` lookup (INV-10).

### INV-27 — `purchaseController` rejects a zero unit cost as falsy — **P3**
`controllers/purchaseController.ts:~60` — `if (!item_id || !warehouse_id || !quantity || !unit_cost || !purchase_date)`. Free samples and promotional stock cannot be recorded through this route (which, incidentally, is the only thing preventing `unit_cost = 0` batches that INV-05's cleanup would then delete). PO receipts have no equivalent guard, so the inconsistency is reachable from the other direction.

---

## 4. TASK 10 — RECONCILIATION / REPAIR TOOLING

| tool | what it does | verdict |
|---|---|---|
| `server/src/scripts/reconcile-stock-cash.ts` (272 ln) | read-only (`new Database(dbPath, {readonly:true})`); flags `on_hand − batch_covered > 0.0005` and duplicate direct-purchase-vs-received-PO | **the only sound tool in the repo.** But it detects **one direction only** — the `if (uncovered <= 0.0005) continue` at `:88` skips exactly the case affecting 2 of the 4 live rows (item 2/WH1 −3.722, item 15 −5). Its suggested remedy (`:130`) points at INV-04. |
| `config/database.ts:224-273` | boot-time rebuild of `stock_balances` + `items.current_stock` from `SUM(stock_movements)` | INV-09 — masks bugs, rewrites live data silently, never touches batches |
| `config/database.ts:1879-1962` `runUnbatchedStockReconciliation` | boot-time synthetic RECON batch for any positive gap | INV-04 — unguarded, wrong cost, one-way ratchet, no GL entry |
| `config/database.ts:1990-2019` + `migrations/cleanup-orphaned-stock-batches.sql` | boot-time DELETE of orphaned/zero-cost batches, NULLs `batch_id` on movements | INV-05 — destructive, no quantity guard, severs audit links |
| `scripts/backfill-batches.ts` (232 ln) | one-off: creates batches for pre-batch-costing purchases/productions | `quantity_remaining = quantity_original` with the comment *"We won't know actual remaining after sales"* (`:99`) — knowingly over-states coverage for anything already sold. Retro-writes `stock_movements.batch_id` (`:144`, `:202`). Uses the colliding lookup (`:170`, `:201`). Values production batches at `standard_cost` (`:77`), a different basis from `Production.recordProduction`'s actual layer costs. |
| `scripts/fix-duplicate-purchase.ts` (139 ln) | one-off, hard-codes `PURCH-2026-0004` | INV-26; does take a file backup first (`:57-59`), which is good practice |
| `utils/purchaseReturnBackfill.ts` (168 ln) | boot-time purchase-return backfill | not stock-batch related; UNVERIFIED in detail |
| `src/audit-trace.ts` | standalone harness; builds a throwaway DB under `../../audit-db` and `process.env.DATABASE_PATH` override; never imported by `app.ts` | diagnostic only, not production code. Its scenario at `:1132-1163` compares batch vs standard-cost valuation — the authors already knew about INV-14. |

**Gap:** nothing in the repo detects or repairs `SUM(stock_batches.quantity_remaining) > stock_balances.quantity`, which is the majority of the live drift. There is no per-warehouse check anywhere (both `reconcile-stock-cash.ts:65-69` and `runUnbatchedStockReconciliation:1892-1896` group by item+warehouse for coverage but average cost by item only). No admin-facing health endpoint. No CI check.

---

## 5. TASK 9 — CACHE REDUNDANCY AND WHO READS WHICH

`stock_movements` is the only true ledger; the other three are caches, and **each has a different reader population**, so modules routinely disagree:

- **`items.current_stock`** — dashboard low-stock alerts (`Dashboard.ts:155-158`, `:659`), item-list low-stock filter (`Item.ts:134`), mobile item catalogue (`MobileInvoice.ts:121`), `getStockSummary` (`StockMovement.ts:327-332`), legacy valuation fallback (`Reports.ts:326`, `:604`), BOM availability (`BOM.ts:240`), custom-report `stock_value` (`config/database.ts:1752`).
- **`stock_balances`** — every write path's availability guard, POS validation, `inventoryController.deleteItem:136-169` (with the explicit comment *"Check stock_balances (authoritative stock count) instead of item.current_stock"*), the low-stock **report** (`Reports.ts:875`, `COALESCE(SUM(sb.quantity),0) as current_stock`), `MobileInvoice.findWarehouseForItem`.
- **`stock_batches`** — balance sheet (`Reports.ts:596`), dashboard inventory value (`Dashboard.ts:103`, `:455`), valuation report incl. its **quantity** column (`Reports.ts:321`), FIFO/FEFO consumption.

So "low stock" is computed from `items.current_stock` on the dashboard and from `SUM(stock_balances.quantity)` in the report — two caches, two screens, same label. And inventory quantity is 45 on the stock-balances screen and 38.722 on the valuation report for the same item, today.

**Is a cache redundant?** `items.current_stock` is strictly derivable (`SUM(stock_balances)`) and is the one that could be dropped — but it is also the one 7 read sites depend on, and it exists only to avoid a GROUP BY. `stock_balances` is *not* redundant: it is the per-warehouse dimension. `stock_batches` is not redundant either: it is the cost dimension. The correct target is three tables, one writer, one transaction — not fewer tables.
**Can modules disagree? They do, right now, in the live database, by Rs 3,461.20 and by 6.278 units.**

---

## 6. WHAT IS CORRECT — DO NOT CHANGE

1. **`stock_movements` as an append-only signed ledger** with `quantity` positive-in / negative-out. The design is right; every reconstruction in this audit was possible because of it.
2. **`Production.recordProduction` is the reference implementation.** `models/Production.ts:397` — `return transaction.immediate();` — is the only correctly serialised stock mutation in the codebase. It pre-checks availability (`:192-202`) *inside* the transaction, consumes via `consumeFromOldestBatches` (`:207`), creates the output batch at true layer cost (`:270`, `costPerUnit = (totalMaterialCost + overhead) / output_quantity`), and posts GL. Copy this pattern everywhere else.
3. **`Production.delete` (`:539-639`)** is the only reversal in the system that is a genuine inverse: it restores each raw-material batch's `quantity_remaining`, posts matching compensating ADJUSTMENTs, and zeroes the output batch. It is internally consistent across all three caches.
4. **The FEFO ordering clause itself** (`StockMovement.ts:604-619`): `ORDER BY (expiry_date IS NULL), expiry_date ASC, received_date ASC, id ASC` correctly sorts NULL-expiry last and is fully deterministic via the `id` tiebreak. The bug is where it is applied, not the clause.
5. **`consumeFromOldestBatches` returning explicit `(batchId, consumed, unitCost)` layers**, and callers emitting one movement per layer with `batch_id` set. This is the right shape for FIFO costing and makes COGS auditable per layer. Keep it; remove only the silent `batchId: null` fallback.
6. **`inventoryController.deleteItem:136-169`** deliberately reads `stock_balances` rather than `items.current_stock`, with a comment explaining why. Correct choice.
7. **`UNIQUE(item_id, warehouse_id)` on `stock_balances`** (`migrations/init.sql`) — the one real invariant in the stock schema.
8. **`scripts/reconcile-stock-cash.ts` opening the DB `readonly: true`** and refusing to write. Extend its coverage; do not change its posture.
9. **`sensitiveOperationLimiter` + `requirePermission('inventory', …)` on every mutating inventory route** (`routes/inventory.ts:28`, `:34-40`). Authorisation coverage on this layer is complete.
10. **`PurchaseReturn.create`'s tolerance check `available < line.quantity - 0.001`** — using an epsilon against float quantities is right for an app with fractional units (loose oil at 3 decimal places).
11. **FACT 7 remains true** — there is no negative stock today, and no negative `quantity_remaining`. Whatever fixes go in must preserve that.

---

## 7. RECOMMENDED ORDER OF WORK

1. **Freeze the boot-time mutators** — gate `runUnbatchedStockReconciliation` (INV-04) and the orphan cleanup (INV-05) behind a one-time flag, and demote `config/database.ts:224-273` (INV-09) to detect-and-log. Nothing else can be measured while these three rewrite the data on every start. Note: the next restart will mint two wrong-cost RECON batches for item 1 and item 2/WH2 unless this is done first.
2. **INV-22** (widen the `source_type` CHECK) — prerequisite for 3 and 4.
3. **INV-01** and **INV-02** — the two causes of 100% of the live drift.
4. **INV-03** and **INV-06** — unguarded/unbatched write paths that will create fresh drift tomorrow.
5. **One-off reconciliation migration** for the 4 known rows, then **INV-21** (add the CHECK constraints so the class of bug can never recur silently).
6. **INV-07** — extract `StockService`, delete the 8 duplicated blocks; **INV-08** — `.immediate()` on every decrementing transaction.
7. **INV-12**, **INV-13**, **INV-14**, **INV-15** — correctness of reversal, cost and expiry enforcement.

---

## 8. UNVERIFIED

- Whether any purchase **edit** path exists (none found; only create and delete).
- Whether any goods-receipt **reversal / un-receive** path exists (none found — received stock appears irreversible except by manual adjustment).
- Whether INV-25's gross-quantity reversal is reachable in practice given the delete guard at `invoiceController.ts:615-624`.
- The exact historical sequence that produced batch 5 (`BATCH-26-RECON-0001`, `quantity_original = 15`): reconstruction from the ledger leaves a residual of one unit, so one of the two invoice reversals against that batch (`STK-2026-0016` RETURN, `STK-2026-0110` INVOICE_UPDATE) did not restore `quantity_remaining` — most likely because its SALE movement's `batch_id` was NULL at that moment (INV-05). This does not affect the §0 conclusion, which holds exactly at the current state.
- `utils/purchaseReturnBackfill.ts` internals (168 lines, not read in detail; runs at boot via `runPurchaseReturnsBackfill()` at `config/database.ts:1048`).
- Flutter-side stock guards beyond `stock_transfer_dialog.dart`: not systematically reviewed. Any client-side check is advisory regardless, given INV-08.

agentId: a481d347c6a897825 (use SendMessage with to: 'a481d347c6a897825', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 139170
tool_uses: 61
duration_ms: 2559050</usage>