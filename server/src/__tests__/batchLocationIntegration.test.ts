// Integration tests (inventory-batch-lot-spec tasks 7.5–7.8): the full
// business flows against per-location batch quantities — purchase-return
// create/void, invoice-return restoration, transfer void restore, and
// physical-count correction — each with the feature flag ON so the new
// batch_stock_by_location path is exercised end to end.

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import PurchaseReturnModel from '../models/PurchaseReturn';
import InvoiceModel from '../models/Invoice';
import PhysicalCountModel from '../models/PhysicalCount';
import StockMovementModel from '../models/StockMovement';
import { setFeatureEnabled } from '../utils/featureFlags';

/**
 * Fixture: replay the real migration chain (incl. the batch-location
 * model) on an in-memory DB, then seed master data.
 */
function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');

  const migrations = [
    'init.sql',
    'add-purchases-table.sql',
    'add-purchase-return-fields.sql',
    'add-batch-costing.sql',
    'add-stock-adjustment-financial.sql',
    'create-supplier-ledger.sql',
    'add-gl-foundation.sql',
    'create-payment-allocations.sql',
    'add-supplier-payment-support.sql',
    'add-purchase-supplier-payment.sql',
    'add-purchase-returns-tables.sql',
    'add-purchase-return-batches.sql',
    'add-disposition-and-supplier-refunds.sql',
    'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
    'add-salary-payments.sql',
    'add-payment-salary-void-columns.sql',
    'add-physical-counts.sql',
    'add-count-correction-columns.sql',
    'add-production-tables.sql',
    'add-item-expiry-tracking.sql',
    'add-batch-location-model.sql',
  ];
  for (const file of migrations) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', file), 'utf8'));
  }

  // purchase_return_batches.location_id — added programmatically at boot
  const prbCols = db.prepare(`SELECT name FROM pragma_table_info('purchase_return_batches')`).all() as { name: string }[];
  if (!prbCols.some((c) => c.name === 'location_id')) {
    db.exec('ALTER TABLE purchase_return_batches ADD COLUMN location_id INTEGER REFERENCES locations(id)');
  }

  const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all() as { name: string }[];
  if (!supCols.some((c) => c.name === 'current_balance')) {
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  }

  const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as { name: string }[];
  const has = (n: string) => cols.some((c) => c.name === n);
  if (!has('batch_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
  if (!has('purchase_return_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN purchase_return_id INTEGER REFERENCES purchase_returns(id)');

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (id,item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES (1,'IT-1','Widget','Nos',10,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (id,warehouse_code,warehouse_name,is_active) VALUES (1,'WH-1','Main',1)`).run();
  db.prepare(`INSERT INTO suppliers (id,supplier_code,supplier_name,is_active) VALUES (1,'SUP-1','Acme',1)`).run();
  db.prepare(`INSERT INTO customers (id,customer_code,customer_name,is_active) VALUES (1,'CUST-1','Cust One',1)`).run();
  // The warehouse is created after add-batch-location-model.sql ran, so
  // seed its DEFAULT location explicitly.
  db.prepare(`INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (1,'DEFAULT','Main default')`).run();

  setFeatureEnabled(db, 'feature_batch_locations', true);
  return db;
}

/** Full stock seed: purchase → batch → location row → balance row. */
function seedStock(db: Database.Database, qty: number, cost = 10): number {
  const pur = db.prepare(`
    INSERT INTO purchases (purchase_no,item_id,warehouse_id,quantity,unit_cost,total_cost,supplier_id,supplier_name,purchase_date,created_by)
    VALUES ('PURCH-1',1,1,?,?,?,1,'Acme','2026-07-01',1)
  `).run(qty, cost, qty * cost);
  const purchaseId = pur.lastInsertRowid as number;
  const b = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
    VALUES ('B1',1,1,'PURCHASE',?,?,?,?,'2026-07-01')
  `).run(purchaseId, qty, qty, cost);
  const batchId = b.lastInsertRowid as number;
  const locId = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id;
  db.prepare(`INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,?,0,?)`)
    .run(batchId, locId, qty, qty);
  db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity,quantity_physical,quantity_reserved,quantity_available) VALUES (1,1,?,?,?,?)`)
    .run(qty, qty, 0, qty);
  db.prepare(`UPDATE items SET current_stock=? WHERE id=1`).run(qty);
  return batchId;
}

describe('7.5 purchase return consumes and voids per-location quantities', () => {
  it('create consumes batch_stock_by_location and records location_id; void restores it', () => {
    const db = createFixture();
    const batchId = seedStock(db, 10);
    const locId = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id;
    const purchaseId = (db.prepare(`SELECT id FROM purchases LIMIT 1`).get() as { id: number }).id;

    const ret = PurchaseReturnModel.create({
      return_date: '2026-07-15',
      source_type: 'PURCHASE',
      source_id: purchaseId,
      warehouse_id: 1,
      disposition: 'credit_on_account',
      items: [{ source_item_id: purchaseId, quantity: 4 }],
    }, 1, db);

    // Location row consumed, master batch synced, balance updated
    let loc = db.prepare(`SELECT quantity_physical, quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, locId) as any;
    expect(loc.quantity_physical).toBe(6);
    let master = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id=?`).get(batchId) as any;
    expect(master.quantity_remaining).toBe(6);
    let bal = db.prepare(`SELECT quantity, quantity_available FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as any;
    expect(bal.quantity).toBe(6);

    // location_id recorded in the consumption ledger
    const prb = db.prepare(`SELECT location_id, quantity FROM purchase_return_batches WHERE batch_id=?`).get(batchId) as any;
    expect(prb.location_id).toBe(locId);
    expect(prb.quantity).toBe(4);

    // Void restores the exact location row
    PurchaseReturnModel.voidReturn(ret.id, 1, 'wrong item', db);
    loc = db.prepare(`SELECT quantity_physical, quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, locId) as any;
    expect(loc.quantity_physical).toBe(10);
    master = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id=?`).get(batchId) as any;
    expect(master.quantity_remaining).toBe(10);
    bal = db.prepare(`SELECT quantity, quantity_available FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as any;
    expect(bal.quantity).toBe(10);
  });
});

describe('7.6 invoice return restores per-location quantities', () => {
  it('reverseStockForItems restores quantity on the warehouse DEFAULT location and records invoice_return_batches', () => {
    const db = createFixture();
    const batchId = seedStock(db, 10);
    const locId = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id;
    const invoiceNo = 'INV-100';
    db.prepare(`INSERT INTO invoices (invoice_no,customer_id,invoice_date,total_amount,status,created_by) VALUES (?,1,'2026-07-02',100,'Paid',1)`).run(invoiceNo);
    db.prepare(`INSERT INTO invoice_items (invoice_id,item_id,quantity,unit_price,amount) VALUES (1,1,4,25,100)`).run();
    // SALE movement consumed the batch at the DEFAULT location
    db.prepare(`INSERT INTO stock_movements (movement_no,item_id,warehouse_id,movement_type,quantity,unit_cost,reference_doctype,reference_docno,movement_date,created_by,batch_id) VALUES ('MV-1',1,1,'SALE',-4,10,'Invoice',?,'2026-07-02',1,?)`).run(invoiceNo, batchId);
    db.prepare(`UPDATE batch_stock_by_location SET quantity_physical=6, quantity_available=6 WHERE batch_id=?`).run(batchId);
    db.prepare(`UPDATE stock_batches SET quantity_remaining=6 WHERE id=?`).run(batchId);
    db.prepare(`UPDATE stock_balances SET quantity=6, quantity_physical=6, quantity_available=6 WHERE item_id=1 AND warehouse_id=1`).run();

    InvoiceModel.reverseStockForItems(
      db,
      [{ item_id: 1, quantity: 4, unit_price: 25 }],
      invoiceNo,
      1,
      'RETURN',
      1 // restock warehouse
    );

    const loc = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, locId) as any;
    expect(loc.quantity_physical).toBe(10);

    const irb = db.prepare(`SELECT location_id, quantity, reference_doctype FROM invoice_return_batches WHERE batch_id=?`).get(batchId) as any;
    expect(irb).toBeTruthy();
    expect(irb.location_id).toBe(locId);
    expect(irb.quantity).toBe(4);
    expect(irb.reference_doctype).toBe('RETURN');
  });
});

describe('7.7 transfer void restores source and destination locations', () => {
  it('transfer void restores batch_stock_by_location on both sides', () => {
    const db = createFixture();
    const batchId = seedStock(db, 10);
    const srcLoc = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id;
    // Second warehouse + DEFAULT location as transfer destination
    db.prepare(`INSERT INTO warehouses (id,warehouse_code,warehouse_name,is_active) VALUES (2,'WH-2','Second',1)`).run();
    db.prepare(`INSERT INTO locations (warehouse_id,location_code,location_name) VALUES (2,'DEFAULT','Second default')`).run();
    const dstLoc = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=2 AND location_code='DEFAULT'`).get() as { id: number }).id;

    // Simulate a completed transfer: 4 out of WH1, 4 into WH2
    db.prepare(`UPDATE batch_stock_by_location SET quantity_physical=6, quantity_available=6 WHERE batch_id=?`).run(batchId);
    db.prepare(`UPDATE stock_batches SET quantity_remaining=6 WHERE id=?`).run(batchId);
    db.prepare(`UPDATE stock_balances SET quantity=6, quantity_physical=6, quantity_available=6 WHERE item_id=1 AND warehouse_id=1`).run();
    db.prepare(`INSERT INTO batch_stock_by_location (batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES (?,?,4,0,4)`).run(batchId, dstLoc);
    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity,quantity_physical,quantity_reserved,quantity_available) VALUES (1,2,4,4,0,4)`).run();

    // Transfer legs as movements; the IN leg pairs with the OUT leg via
    // reference_docno = out movement_no.
    db.prepare(`INSERT INTO stock_movements (movement_no,item_id,warehouse_id,movement_type,quantity,unit_cost,reference_doctype,reference_docno,movement_date,created_by,batch_id) VALUES ('MV-OUT',1,1,'TRANSFER',-4,10,'Transfer','TR-1','2026-07-03',1,?)`).run(batchId);
    db.prepare(`INSERT INTO stock_movements (movement_no,item_id,warehouse_id,movement_type,quantity,unit_cost,reference_doctype,reference_docno,movement_date,created_by,batch_id) VALUES ('MV-IN',1,2,'TRANSFER',4,10,'Transfer','MV-OUT','2026-07-03',1,?)`).run(batchId);

    StockMovementModel.voidTransfer({ outMovementNo: 'MV-OUT' }, 1, db);

    const src = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, srcLoc) as any;
    expect(src.quantity_physical).toBe(10);
    const dst = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, dstLoc) as any;
    expect(dst.quantity_physical).toBe(0);
  });
});

describe('7.8 physical count correction updates location quantities', () => {
  it('correction re-applies variance through batch_stock_by_location', () => {
    const db = createFixture();
    const batchId = seedStock(db, 10);
    const locId = (db.prepare(`SELECT id FROM locations WHERE warehouse_id=1 AND location_code='DEFAULT'`).get() as { id: number }).id;

    const countId = PhysicalCountModel.create({ warehouse_id: 1, count_date: '2026-07-04' } as any, 1, db);
    PhysicalCountModel.recordCount(countId, 1, 8, 1, null, db); // shortage 2
    PhysicalCountModel.completeCount(countId, 1, db);

    let loc = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, locId) as any;
    expect(loc.quantity_physical).toBe(8);
    let bal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as any;
    expect(bal.quantity).toBe(8);

    // Correct the count upward: 10 counted → surplus 2 restored
    PhysicalCountModel.correctCount({ countId, corrections: [{ item_id: 1, counted_quantity: 10 }] }, 1, db);

    loc = db.prepare(`SELECT quantity_physical FROM batch_stock_by_location WHERE batch_id=? AND location_id=?`).get(batchId, locId) as any;
    expect(loc.quantity_physical).toBe(10);
    bal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as any;
    expect(bal.quantity).toBe(10);
  });
});
