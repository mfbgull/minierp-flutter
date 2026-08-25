/**
 * Fix Script: Duplicate Direct Purchase (PURCH-2026-0004)
 *
 * User confirmed only 15 units were purchased (10 + 5, both @ 500, paid
 * 5,000 + 2,500). The direct purchase PURCH-2026-0004 (5 @ 500 = 2,500)
 * is a duplicate of PO-2026-0002, which was already received via
 * GR-2026-0002 and paid via PAY002. It double-counts 5 units of stock
 * (19 on hand instead of 14) and 2,500 of cash outflow.
 *
 * This reverses the phantom purchase the same way the app already treats
 * deleted purchases (see movements 3/6/7 for PURCH-2026-0001/2/3):
 *   - deletes the purchases row        (removes it from cash-out math)
 *   - posts an ADJUSTMENT -5 movement  (PURCHASE_DELETE, audit trail)
 *   - zeroes the phantom batch         (BATCH-26-PUR-0004 remaining → 0)
 *   - fixes stock_balances / items.current_stock (19 → 14)
 *
 * Idempotent: if PURCH-2026-0004 is already gone it does nothing.
 * Run: npx ts-node src/scripts/fix-duplicate-purchase.ts
 */
import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import StockMovementModel from '../models/StockMovement';

const candidates = [
  process.env.DATABASE_PATH && path.join(process.env.DATABASE_PATH, 'erp.db'),
  path.join(__dirname, '../../../database/erp.db'),
  path.join(__dirname, '../../database/erp.db'),
].filter(Boolean) as string[];

const dbPath = candidates.find((p) => fs.existsSync(p));
if (!dbPath) {
  console.error(`Database not found. Tried:\n  ${candidates.join('\n  ')}`);
  process.exit(1);
}

const db = new Database(dbPath);
db.pragma('foreign_keys = ON');
db.pragma('busy_timeout = 5000');

const PURCHASE_NO = 'PURCH-2026-0004';

const purchase = db.prepare(
  'SELECT * FROM purchases WHERE purchase_no = ?'
).get(PURCHASE_NO) as { id: number; item_id: number; quantity: number; unit_cost: number; total_cost: number } | undefined;

if (!purchase) {
  console.log(`✅ PURCH-2026-0004 not found — nothing to fix (already applied).`);
  db.close();
  process.exit(0);
}

console.log(`Found duplicate purchase: ${PURCHASE_NO} — ` +
  `${purchase.quantity} @ ${purchase.unit_cost} = ${purchase.total_cost}`);

// Back up before touching anything.
const backupPath = dbPath + `.backup-${Date.now()}`;
fs.copyFileSync(dbPath, backupPath);
console.log(`Backup written to: ${backupPath}`);

const fix = db.transaction(() => {
  // 1. Remove the purchases row — cash-out (cashService.collectFlows sums
  //    purchases.total_cost) no longer counts the phantom 2,500.
  const del = db.prepare('DELETE FROM purchases WHERE id = ?').run(purchase.id);
  console.log(`1. Deleted purchases row id=${purchase.id} (${del.changes} row)`);

  // 2. Post the reversal movement, matching the app's PURCHASE_DELETE
  //    convention (same as movements 3/6/7 for earlier deleted purchases).
  const movementNo = StockMovementModel.generateMovementNo(db);
  const wh = db.prepare('SELECT warehouse_id FROM purchases WHERE id = ?').get(purchase.id) as
    { warehouse_id: number } | undefined;
  const warehouseId = wh?.warehouse_id ?? 1;
  db.prepare(`
    INSERT INTO stock_movements (
      movement_no, item_id, warehouse_id, movement_type,
      quantity, unit_cost, reference_doctype, reference_docno,
      remarks, movement_date, created_by
    ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, 'PURCHASE_DELETE', ?, ?, ?, ?)
  `).run(
    movementNo,
    purchase.item_id,
    warehouseId,
    -purchase.quantity,
    purchase.unit_cost,
    PURCHASE_NO,
    `Duplicate purchase reversed - ${PURCHASE_NO}`,
    new Date().toISOString().split('T')[0],
    1
  );
  console.log(`2. Posted ADJUSTMENT -${purchase.quantity} @ ${purchase.unit_cost} (${movementNo}, PURCHASE_DELETE)`);

  // 3. Zero the phantom batch's remaining quantity so batch coverage no
  //    longer includes the duplicate units.
  const batch = db.prepare(`
    SELECT id FROM stock_batches WHERE source_type = 'PURCHASE' AND source_id = ?
  `).get(purchase.id) as { id: number } | undefined;
  if (batch) {
    db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(batch.id);
    console.log(`3. Zeroed batch id=${batch.id} (quantity_remaining → 0)`);
  }

  // 4. Fix on-hand stock: real stock = 15 purchased - 1 sold = 14.
  const bal = db.prepare(
    'SELECT id, quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
  ).get(purchase.item_id, warehouseId) as { id: number; quantity: number } | undefined;
  if (bal) {
    db.prepare('UPDATE stock_balances SET quantity = quantity - ? WHERE id = ?')
      .run(purchase.quantity, bal.id);
    console.log(`4. stock_balances ${bal.quantity} → ${bal.quantity - purchase.quantity}`);
  }

  // 5. Recompute items.current_stock from stock_balances.
  db.prepare(`
    UPDATE items SET current_stock = (
      SELECT COALESCE(SUM(quantity), 0) FROM stock_balances WHERE item_id = items.id
    ) WHERE id = ?
  `).run(purchase.item_id);
  console.log(`5. items.current_stock recomputed`);
});

fix();

// Report the corrected figures.
const stock = db.prepare(
  'SELECT COALESCE(SUM(quantity), 0) as quantity FROM stock_balances WHERE item_id = ?'
).get(purchase.item_id) as { quantity: number };
const supplierPaid = db.prepare(
  'SELECT COALESCE(SUM(amount), 0) t FROM payments WHERE supplier_id IS NOT NULL AND amount > 0'
).get() as { t: number };
const direct = db.prepare('SELECT COALESCE(SUM(total_cost), 0) t FROM purchases').get() as { t: number };

console.log('\n=== Corrected figures ===');
console.log(`On-hand stock      : ${stock.quantity} units`);
console.log(`Supplier payments  : Rs ${supplierPaid.t}`);
console.log(`Direct purchases   : Rs ${direct.t}`);
console.log(`Cash outflow total : Rs ${supplierPaid.t + direct.t}`);
console.log('\nRestart the server — on startup the reconciliation migration folds the');
console.log('14 real units into a batch so valuation shows them at cost (14 × 500 = 7,000).');
db.close();
