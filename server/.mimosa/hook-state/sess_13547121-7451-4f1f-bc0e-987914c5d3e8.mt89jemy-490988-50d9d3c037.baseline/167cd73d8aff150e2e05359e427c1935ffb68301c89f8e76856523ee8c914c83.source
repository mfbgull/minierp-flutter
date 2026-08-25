/**
 * Reconciliation Script: Stock ↔ Batches & Duplicate Purchases
 *
 * READ-ONLY — never writes to the database. Flags two known problem
 * classes so they can be confirmed before any fix is applied:
 *
 *   1. UNBATCHABLE STOCK — on-hand stock with no covering stock_batches
 *      row. Goods receipts (GOODS_RECEIPT movements) used to add stock to
 *      stock_balances without creating a cost layer, so batch-based
 *      valuation (dashboard stock value, stock valuation report, balance
 *      sheet) silently undercounts it.
 *
 *   2. POSSIBLE DUPLICATE PURCHASES — direct purchases (purchases table)
 *      that match a purchase-order line that was already received and
 *      paid, i.e. the same item, quantity, unit price and date recorded
 *      twice. Direct purchases are counted as cash out separately from
 *      supplier payments, so a duplicate inflates both stock and cash
 *      outflow.
 *
 * Run: npx ts-node src/scripts/reconcile-stock-cash.ts
 * Or after build: node dist/scripts/reconcile-stock-cash.js
 *
 * Exits 0 when nothing is flagged, 1 when issues are found.
 */
import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

// Resolve the DB path. The compiled script lives at dist/src/scripts
// (where ../../../database is correct, like database.ts), while running
// via ts-node from src/scripts needs ../../database — try both plus the
// DATABASE_PATH override (Electron).
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

// Read-only: this script exists to confirm, never to change.
const db = new Database(dbPath, { readonly: true });

let issues = 0;

// ────────────────────────────────────────────────────────────────────
// 1. Unbatchable stock — on hand but no cost layer
// ────────────────────────────────────────────────────────────────────
function flagUnbatchableStock(): void {
  console.log('\n[1] UNBATCHABLE STOCK (on hand, no stock_batches cost layer)');
  console.log('    ' + '-'.repeat(70));

  const rows = db.prepare(`
    SELECT
      sb.item_id,
      sb.warehouse_id,
      i.item_code,
      i.item_name,
      w.warehouse_name,
      sb.quantity as on_hand,
      COALESCE((
        SELECT SUM(quantity_remaining)
        FROM stock_batches
        WHERE item_id = sb.item_id AND warehouse_id = sb.warehouse_id
      ), 0) as covered
    FROM stock_balances sb
    JOIN items i ON i.id = sb.item_id
    JOIN warehouses w ON w.id = sb.warehouse_id
    WHERE sb.quantity > 0
    ORDER BY sb.item_id, sb.warehouse_id
  `).all() as Array<{
    item_id: number;
    warehouse_id: number;
    item_code: string;
    item_name: string;
    warehouse_name: string;
    on_hand: number;
    covered: number;
  }>;

  let found = 0;
  for (const r of rows) {
    const uncovered = r.on_hand - r.covered;
    if (uncovered <= 0.0005) continue;
    found++;
    issues++;

    // Weighted-average cost of the inbound movements that are NOT
    // batch-linked — those are precisely the units this gap represents.
    const avg = db.prepare(`
      SELECT COALESCE(
        SUM(quantity * unit_cost) * 1.0 / NULLIF(SUM(quantity), 0),
        0
      ) as cost
      FROM stock_movements
      WHERE item_id = ? AND quantity > 0 AND batch_id IS NULL
    `).get(r.item_id) as { cost: number };

    console.log(`  ⚠ ${r.item_code} (${r.item_name}) @ ${r.warehouse_name}:`);
    console.log(`      on-hand ${r.on_hand} units, batch-covered ${r.covered}` +
      ` → ${uncovered.toFixed(3)} UNCOVERED (~Rs ${(uncovered * avg.cost).toFixed(2)} @ ${avg.cost.toFixed(2)})`);

    const sources = db.prepare(`
      SELECT movement_no, movement_type, quantity, unit_cost,
             reference_doctype, reference_docno, movement_date
      FROM stock_movements
      WHERE item_id = ? AND quantity > 0 AND batch_id IS NULL
      ORDER BY movement_date, id
    `).all(r.item_id) as Array<{
      movement_no: string;
      movement_type: string;
      quantity: number;
      unit_cost: number;
      reference_doctype: string;
      reference_docno: string;
      movement_date: string;
    }>;

    if (sources.length > 0) {
      console.log(`      inbound movements without a batch link:`);
      for (const s of sources) {
        console.log(`        ${s.movement_date}  ${s.reference_docno}  ` +
          `${s.reference_doctype}  +${s.quantity} @ ${s.unit_cost}`);
      }
    }
    console.log(`      → fix: runUnbatchedStockReconciliation (runs on server start) folds`);
    console.log(`        these into a synthetic RECON batch.`);
    console.log();
  }

  if (found === 0) {
    console.log('  ✅ All on-hand stock is covered by batch rows.');
  }
}

// ────────────────────────────────────────────────────────────────────
// 2. Possibly duplicate purchases — direct purchase vs received PO
// ────────────────────────────────────────────────────────────────────
function flagDuplicatePurchases(): void {
  console.log('\n[2] POSSIBLE DUPLICATE PURCHASES (direct purchase vs received+paid PO)');
  console.log('    ' + '-'.repeat(70));

  // A "receipt chain" for each PO item: the received quantity and the
  // price recorded for it (from the GR movement).
  const receipts = db.prepare(`
    SELECT
      po.id as po_id,
      po.po_no,
      po.po_date,
      po.supplier_id,
      s.supplier_name,
      poi.item_id,
      poi.quantity as po_quantity,
      poi.unit_price,
      COALESCE(SUM(gri.received_quantity), 0) as received_quantity,
      COALESCE(SUM(gri.received_quantity * poi.unit_price), 0) as received_value
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.po_id = po.id
    JOIN suppliers s ON s.id = po.supplier_id
    LEFT JOIN goods_receipt_items gri ON gri.po_item_id = poi.id
    WHERE po.status NOT IN ('Draft', 'Cancelled')
    GROUP BY poi.id
  `).all() as Array<{
    po_id: number;
    po_no: string;
    po_date: string;
    supplier_id: number;
    supplier_name: string;
    item_id: number;
    po_quantity: number;
    unit_price: number;
    received_quantity: number;
    received_value: number;
  }>;

  const purchases = db.prepare(`
    SELECT id, purchase_no, purchase_date, item_id, warehouse_id,
           quantity, unit_cost, total_cost, supplier_name
    FROM purchases
    ORDER BY purchase_date, id
  `).all() as Array<{
    id: number;
    purchase_no: string;
    purchase_date: string;
    item_id: number;
    warehouse_id: number | null;
    quantity: number;
    unit_cost: number;
    total_cost: number;
    supplier_name: string | null;
  }>;

  let found = 0;
  for (const rec of receipts) {
    if (rec.received_quantity <= 0) continue;

    for (const p of purchases) {
      // Same item, same quantity, same unit price, same day — a direct
      // purchase that merely re-enters goods the PO already brought in.
      if (p.item_id !== rec.item_id) continue;
      if (Math.abs(p.quantity - rec.received_quantity) > 0.0005) continue;
      if (Math.abs(p.unit_cost - rec.unit_price) > 0.0005) continue;
      if (p.purchase_date !== rec.po_date) continue;

      // Was this PO actually paid? If a supplier payment covers it, the
      // direct purchase is a second record of the same money going out.
      const paid = db.prepare(`
        SELECT COALESCE(SUM(amount), 0) as total
        FROM po_allocations WHERE po_id = ?
      `).get(rec.po_id) as { total: number };

      found++;
      issues++;
      console.log(`  ⚠ Direct purchase ${p.purchase_no} matches received PO line ${rec.po_no}:`);
      console.log(`      item      : ${rec.item_id}`);
      console.log(`      quantity  : ${p.quantity} (PO received ${rec.received_quantity})`);
      console.log(`      unit price: ${p.unit_cost} (PO ${rec.unit_price})`);
      console.log(`      date      : ${p.purchase_date} (PO ${rec.po_date})`);
      console.log(`      PO supplier: ${rec.supplier_name}${p.supplier_name ? ' | purchase supplier: ' + p.supplier_name : ''}`);
      console.log(`      PO payment: ${paid.total > 0 ? `paid Rs ${paid.total} (PO ${rec.po_no})` : 'not paid'}`);
      console.log(`      total     : Rs ${p.total_cost}`);
      console.log(`      → if duplicate: stock overstated by ${p.quantity} units and cash`);
      console.log(`        outflow overstated by Rs ${p.total_cost} (direct purchases are counted`);
      console.log(`        as cash out on top of the supplier payment).`);
      console.log();
    }
  }

  if (found === 0) {
    console.log('  ✅ No direct purchase matches a received PO line.');
  }
}

// ────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────
function cashSummary(): void {
  // For context: what the cash position currently counts as money out.
  const supplierPaid = db.prepare(
    `SELECT COALESCE(SUM(amount), 0) t FROM payments WHERE supplier_id IS NOT NULL AND amount > 0`
  ).get() as { t: number };
  const directPurchases = db.prepare(
    `SELECT COALESCE(SUM(total_cost), 0) t FROM purchases`
  ).get() as { t: number };
  console.log('\n[CONTEXT] Current cash-out accounting:');
  console.log(`    supplier payments  : Rs ${supplierPaid.t}`);
  console.log(`    direct purchases   : Rs ${directPurchases.t}`);
}

console.log('═══════════════════════════════════════════════════════════════');
console.log('  RECONCILIATION CHECK  (read-only, nothing was modified)');
console.log(`  db: ${dbPath}`);
console.log('═══════════════════════════════════════════════════════════════');

flagUnbatchableStock();
flagDuplicatePurchases();
cashSummary();

db.close();

console.log('\n' + '='.repeat(63));
if (issues > 0) {
  console.log(`  RESULT: ${issues} issue(s) flagged — review and confirm before fixing.`);
  process.exit(1);
} else {
  console.log('  RESULT: no issues found.');
  process.exit(0);
}
