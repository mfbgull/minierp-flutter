"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Backfill Script: Batch Costing
 *
 * Creates stock_batch records for existing productions and purchases
 * that were created before the batch costing system was implemented.
 *
 * Run: npx ts-node src/scripts/backfill-batches.ts
 * Or after build: node dist/scripts/backfill-batches.js
 */
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const dbDir = process.env.DATABASE_PATH || path_1.default.join(__dirname, '../../../database');
const dbPath = path_1.default.join(dbDir, 'erp.db');
if (!fs_1.default.existsSync(dbPath)) {
    console.error(`Database not found at ${dbPath}`);
    process.exit(1);
}
const db = new better_sqlite3_1.default(dbPath);
db.pragma('foreign_keys = OFF');
let batchCounter = 0;
function generateBatchNo(sourceType, sourceId, year) {
    const yearShort = year % 100;
    const prefix = sourceType === 'PRODUCTION' ? 'PRD' : 'PUR';
    return `BATCH-${yearShort}-${prefix}-${String(sourceId).padStart(4, '0')}`;
}
function backfillProductions() {
    console.log('\n=== Backfilling Productions ===');
    const productions = db.prepare(`
    SELECT p.*, sm.unit_cost
    FROM productions p
    LEFT JOIN (
      SELECT reference_docno, unit_cost
      FROM stock_movements
      WHERE movement_type = 'PRODUCTION' AND quantity > 0
    ) sm ON sm.reference_docno = p.production_no
  `).all();
    const batches = [];
    for (const prod of productions) {
        const year = new Date(prod.production_date).getFullYear();
        // Calculate material cost
        const inputs = db.prepare(`
      SELECT pi.quantity, COALESCE(i.standard_cost, 0) as standard_cost
      FROM production_inputs pi
      JOIN items i ON pi.item_id = i.id
      WHERE pi.production_id = ?
    `).all(prod.id);
        const materialCost = inputs.reduce((sum, inp) => sum + inp.quantity * inp.standard_cost, 0);
        const overhead = prod.overhead_cost ?? 0;
        const totalCost = materialCost + overhead;
        const costPerUnit = prod.output_quantity > 0 ? totalCost / prod.output_quantity : (prod.unit_cost ?? 0);
        // Check if this production already has a batch
        const existingBatch = db.prepare(`SELECT id FROM stock_batches WHERE source_type = 'PRODUCTION' AND source_id = ?`).get(prod.id);
        if (existingBatch) {
            console.log(`  ⏭️  Production ${prod.production_no} already has batch #${existingBatch.id}`);
            continue;
        }
        batches.push({
            batch_no: generateBatchNo('PRODUCTION', prod.id, year),
            item_id: prod.output_item_id,
            warehouse_id: prod.warehouse_id,
            source_type: 'PRODUCTION',
            source_id: prod.id,
            quantity_original: prod.output_quantity,
            quantity_remaining: prod.output_quantity, // We won't know actual remaining after sales
            unit_cost: costPerUnit,
            received_date: prod.production_date
        });
        // Update the productions record with batch cost info
        db.prepare(`
      UPDATE productions
      SET batch_no = ?, unit_cost = ?, total_material_cost = ?, total_batch_cost = ?
      WHERE id = ?
    `).run(generateBatchNo('PRODUCTION', prod.id, year), costPerUnit, materialCost, totalCost, prod.id);
        batchCounter++;
        console.log(`  ✅ Production ${prod.production_no}: batch created, cost = ${costPerUnit.toFixed(2)}/unit`);
    }
    // Insert all production batches
    for (const batch of batches) {
        db.prepare(`
      INSERT INTO stock_batches
        (batch_no, item_id, warehouse_id, source_type, source_id,
         quantity_original, quantity_remaining, unit_cost, received_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(batch.batch_no, batch.item_id, batch.warehouse_id, batch.source_type, batch.source_id, batch.quantity_original, batch.quantity_remaining, batch.unit_cost, batch.received_date);
        // Link to stock_movements for this production output
        const movement = db.prepare(`
      SELECT id FROM stock_movements
      WHERE reference_docno = (SELECT production_no FROM productions WHERE id = ?)
        AND movement_type = 'PRODUCTION' AND quantity > 0
      LIMIT 1
    `).get(batch.source_id);
        if (movement) {
            const batchRecord = db.prepare('SELECT id FROM stock_batches WHERE source_type = ? AND source_id = ?').get('PRODUCTION', batch.source_id);
            if (batchRecord) {
                db.prepare('UPDATE stock_movements SET batch_id = ? WHERE id = ?').run(batchRecord.id, movement.id);
            }
        }
    }
}
function backfillPurchases() {
    console.log('\n=== Backfilling Purchases ===');
    const purchases = db.prepare(`
    SELECT p.*
    FROM purchases p
  `).all();
    for (const purch of purchases) {
        const year = new Date(purch.purchase_date).getFullYear();
        // Check if this purchase already has a batch
        const existingBatch = db.prepare(`SELECT id FROM stock_batches WHERE source_type = 'PURCHASE' AND source_id = ?`).get(purch.id);
        if (existingBatch) {
            console.log(`  ⏭️  Purchase ${purch.purchase_no} already has batch #${existingBatch.id}`);
            continue;
        }
        const batchNo = generateBatchNo('PURCHASE', purch.id, year);
        db.prepare(`
      INSERT INTO stock_batches
        (batch_no, item_id, warehouse_id, source_type, source_id,
         quantity_original, quantity_remaining, unit_cost, received_date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(batchNo, purch.item_id, purch.warehouse_id, 'PURCHASE', purch.id, purch.quantity, purch.quantity, purch.unit_cost, purch.purchase_date);
        // Update purchase record
        db.prepare('UPDATE purchases SET batch_no = ? WHERE id = ?').run(batchNo, purch.id);
        // Link to stock_movements
        const movement = db.prepare(`
      SELECT id FROM stock_movements
      WHERE reference_docno = ? AND movement_type = 'PURCHASE'
      LIMIT 1
    `).get(purch.purchase_no);
        if (movement) {
            const batchId = db.prepare('SELECT id FROM stock_batches WHERE source_type = ? AND source_id = ?').get('PURCHASE', purch.id).id;
            db.prepare('UPDATE stock_movements SET batch_id = ? WHERE id = ?').run(batchId, movement.id);
        }
        batchCounter++;
        console.log(`  ✅ Purchase ${purch.purchase_no}: batch created, cost = ${purch.unit_cost.toFixed(2)}/unit`);
    }
}
function main() {
    console.log('=== Batch Costing Backfill ===');
    console.log(`Database: ${dbPath}`);
    // Verify stock_batches table exists
    const tableCheck = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='stock_batches'`).get();
    if (!tableCheck) {
        console.error('❌ stock_batches table not found. Run the server first to apply the migration.');
        process.exit(1);
    }
    backfillProductions();
    backfillPurchases();
    console.log(`\n=== Complete: ${batchCounter} batches created ===`);
    db.pragma('foreign_keys = ON');
    db.close();
}
main();
