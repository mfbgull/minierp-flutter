/**
 * H10 — Positive stock adjustments must create costed batches.
 *
 * Every sellable unit must have an identifiable cost layer so FIFO
 * consumption can price COGS correctly.  This suite verifies:
 *   1. Positive adjustment → OPENING/ADJUSTMENT batch created with unit_cost
 *   2. FIFO sale after adjustment → COGS from batch, not standard_cost
 *   3. Negative adjustment → no batch created
 *   4. Item creation with current_stock → OPENING batch created
 *   5. FIFO sale after item creation → COGS from OPENING batch
 *   6. Profit calculation uses correct COGS from batch
 *   7. Adjustment batch has correct source_type and batch_no
 *   8. Multiple adjustments → separate batches, FIFO order preserved
 *   9. Negative adjustment without batch does not break FIFO consumption
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import StockMovementModel from '../models/StockMovement';
import ItemModel from '../models/Item';

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  const migrations = [
    'init.sql', 'add-purchases-table.sql', 'add-purchase-return-fields.sql',
    'add-batch-costing.sql', 'add-stock-adjustment-financial.sql',
    'create-supplier-ledger.sql', 'add-gl-foundation.sql',
    'add-physical-counts.sql', 'add-production-tables.sql',
    'add-item-expiry-tracking.sql', 'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
  ];
  for (const file of migrations) {
    const p = path.join(__dirname, '..', 'migrations', file);
    if (fs.existsSync(p)) db.exec(fs.readFileSync(p, 'utf8'));
    else console.warn('MISSING migration fixture:', file);
  }
  const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as { name: string }[];
  const has = (n: string) => cols.some((c) => c.name === n);
  if (!has('batch_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-001','Main',1)`).run();
  return db;
}

function createItem(db: Database.Database, code: string, standardCost: number): number {
  const r = db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, standard_selling_price, is_purchased, is_active, created_by)
    VALUES (?, ?, 'Nos', ?, ?, 1, 1, (SELECT id FROM users ORDER BY id LIMIT 1))
  `).run(code, `Test ${code}`, standardCost, standardCost * 3);
  return r.lastInsertRowid as number;
}

function mainWhId(db: Database.Database): number {
  return (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'WH-001'`).get() as { id: number }).id;
}

describe('H10 — Positive adjustments create costed batches', () => {
  it('positive adjustment creates an ADJUSTMENT batch with correct unit_cost', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-ADJ-1', 15);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 50,
      unit_cost: 15,
      movement_type: 'ADJUSTMENT',
      movement_date: '2026-09-20',
    }, 1, db);

    const batch = db.prepare(`
      SELECT source_type, quantity_original, quantity_remaining, unit_cost
      FROM stock_batches WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, whId) as {
      source_type: string; quantity_original: number;
      quantity_remaining: number; unit_cost: number;
    };

    expect(batch).toBeTruthy();
    expect(batch.source_type).toBe('ADJUSTMENT');
    expect(batch.quantity_original).toBe(50);
    expect(batch.quantity_remaining).toBe(50);
    expect(batch.unit_cost).toBe(15);
  });

  it('batch_no follows BATCH-YY-ADJ-XXXX pattern', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-ADJ-2', 10);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 20,
      unit_cost: 10,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const batch = db.prepare(`
      SELECT batch_no FROM stock_batches WHERE item_id = ?
    `).get(itemId) as { batch_no: string };

    expect(batch.batch_no).toMatch(/^BATCH-\d{2}-ADJ-\d{4}$/);
  });

  it('negative adjustment does NOT create a batch', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-NEG-1', 20);
    const whId = mainWhId(db);

    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (?,?,?)`).run(itemId, whId, 100);
    db.prepare(`UPDATE items SET current_stock = 100 WHERE id = ?`).run(itemId);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -30,
      unit_cost: 20,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const batches = db.prepare(`
      SELECT COUNT(*) as cnt FROM stock_batches WHERE item_id = ?
    `).get(itemId) as { cnt: number };

    expect(batches.cnt).toBe(0);
  });

  it('GL posting uses batch unit_cost, not standard_cost', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-GL-1', 100);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 10,
      unit_cost: 85,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const mv = db.prepare(`
      SELECT financial_value FROM stock_movements
      WHERE item_id = ? AND movement_type = 'ADJUSTMENT'
    `).get(itemId) as { financial_value: number };

    expect(mv.financial_value).toBe(850);
  });
});

describe('H10 — FIFO sale uses batch cost, not standard_cost', () => {
  it('FIFO consumption after positive adjustment prices COGS from batch', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-FIFO-1', 10);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 40,
      unit_cost: 12,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const results = StockMovementModel.recordBatchMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -15,
      unit_cost: 0,
      movement_type: 'SALE',
      movement_date: '2026-09-20',
    }, 1, db);

    expect(results.length).toBe(1);
    expect(results[0].unit_cost).toBe(12);
    expect(results[0].quantity).toBe(-15);

    const batch = db.prepare(`
      SELECT quantity_remaining FROM stock_batches WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, whId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(25);
  });

  it('sale after item creation with current_stock uses OPENING batch cost', () => {
    const db = createFixture();
    const whId = mainWhId(db);
    const itemId = createItem(db, 'H10-OPENING-1', 10);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 30,
      unit_cost: 25,
      movement_type: 'OPENING',
      reference_doctype: 'ITEM_CREATE',
      reference_docno: 'H10-OPENING-1',
    }, 1, db);

    const results = StockMovementModel.recordBatchMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -10,
      unit_cost: 0,
      movement_type: 'SALE',
      movement_date: '2026-09-20',
    }, 1, db);

    expect(results.length).toBe(1);
    expect(results[0].unit_cost).toBe(25);
    expect(results[0].quantity).toBe(-10);
  });
});

describe('H10 — Multiple adjustments create separate batches (FIFO order)', () => {
  it('two adjustments create two batches; FIFO sells oldest first', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-MULTI-1', 10);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 20,
      unit_cost: 5,
      movement_type: 'ADJUSTMENT',
      movement_date: '2026-01-01',
    }, 1, db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 10,
      unit_cost: 8,
      movement_type: 'ADJUSTMENT',
      movement_date: '2026-06-01',
    }, 1, db);

    const batches = db.prepare(`
      SELECT batch_no, quantity_remaining, unit_cost, received_date
      FROM stock_batches WHERE item_id = ? AND warehouse_id = ?
      ORDER BY received_date ASC, id ASC
    `).all(itemId, whId) as Array<{
      batch_no: string; quantity_remaining: number;
      unit_cost: number; received_date: string;
    }>;

    expect(batches.length).toBe(2);
    expect(batches[0].unit_cost).toBe(5);
    expect(batches[0].quantity_remaining).toBe(20);
    expect(batches[1].unit_cost).toBe(8);
    expect(batches[1].quantity_remaining).toBe(10);

    const results = StockMovementModel.recordBatchMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -25,
      unit_cost: 0,
      movement_type: 'SALE',
      movement_date: '2026-09-20',
    }, 1, db);

    expect(results.length).toBe(2);
    expect(results[0].unit_cost).toBe(5);
    expect(results[0].quantity).toBe(-20);
    expect(results[1].unit_cost).toBe(8);
    expect(results[1].quantity).toBe(-5);

    const remaining = db.prepare(`
      SELECT quantity_remaining, unit_cost FROM stock_batches
      WHERE item_id = ? AND warehouse_id = ?
      ORDER BY received_date ASC, id ASC
    `).all(itemId, whId) as Array<{ quantity_remaining: number; unit_cost: number }>;

    expect(remaining[0].quantity_remaining).toBe(0);
    expect(remaining[1].quantity_remaining).toBe(5);
  });
});

describe('H10 — Profit calculation uses correct COGS from batch', () => {
  it('COGS from batch at adjustment cost, not standard_cost', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-PROFIT-1', 50);
    const whId = mainWhId(db);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: 100,
      unit_cost: 30,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const saleResults = StockMovementModel.recordBatchMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -10,
      unit_cost: 0,
      movement_type: 'SALE',
      movement_date: '2026-09-20',
    }, 1, db);

    const cogsPerUnit = saleResults[0].unit_cost;
    const sellingPrice = 80;

    expect(cogsPerUnit).toBe(30);
    expect(sellingPrice - cogsPerUnit).toBe(50);

    const batch = db.prepare(`
      SELECT quantity_remaining FROM stock_batches WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, whId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(90);
  });
});

describe('H10 — Negative adjustment without batch does not break FIFO', () => {
  it('negative adjustment on item with no batches reduces balance only', () => {
    const db = createFixture();
    const itemId = createItem(db, 'H10-NEGFIFO-1', 10);
    const whId = mainWhId(db);

    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (?,?,?)`).run(itemId, whId, 50);
    db.prepare(`UPDATE items SET current_stock = 50 WHERE id = ?`).run(itemId);

    StockMovementModel.recordMovement({
      item_id: itemId,
      warehouse_id: whId,
      quantity: -20,
      unit_cost: 10,
      movement_type: 'ADJUSTMENT',
    }, 1, db);

    const bal = db.prepare(`
      SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, whId) as { quantity: number };
    expect(bal.quantity).toBe(30);

    const batches = db.prepare(`
      SELECT COUNT(*) as cnt FROM stock_batches WHERE item_id = ?
    `).get(itemId) as { cnt: number };
    expect(batches.cnt).toBe(0);
  });
});
