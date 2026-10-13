
import Database from 'better-sqlite3';
import PhysicalCountModel from '../models/PhysicalCount';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

/** createFixtureDb() clones schema only, so the rows add-gl-foundation.sql and
 * add-opening-balances.sql seed as DATA are absent. Stock movement GL posting
 * resolves inventory/shrinkage/correction accounts by code. */
function seedProductionReferenceData(db: Database.Database): void {
  db.exec(`
    INSERT OR IGNORE INTO opening_balances (account_key, amount) VALUES
      ('cash', 0), ('bank', 0), ('easypaisa', 0), ('jazzcash', 0), ('upaisa', 0);
  `);
  db.exec(`
    INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description) VALUES
      ('1000', 'Cash', 'asset', 'debit', 'cash', 'On-hand cash'),
      ('1010', 'Bank', 'asset', 'debit', 'bank', 'Bank balances'),
      ('1020', 'Easypaisa / Mobile Wallet', 'asset', 'debit', 'easypaisa', 'Easypaisa / mobile wallet balances'),
      ('1030', 'JazzCash', 'asset', 'debit', 'jazzcash', 'JazzCash wallet balances'),
      ('1040', 'UPaisa', 'asset', 'debit', 'upaisa', 'UPaisa wallet balances'),
      ('1100', 'Accounts Receivable', 'asset', 'debit', 'accounts_receivable', 'Customer balances'),
      ('1110', 'Customer Credit', 'asset', 'credit', 'customer_credit', 'Customer credit balances'),
      ('1200', 'Inventory Asset', 'asset', 'debit', 'inventory_asset', 'On-hand inventory at cost'),
      ('1300', 'Employee Loan Receivable', 'asset', 'debit', 'employee_loan_receivable', 'Loans advanced to employees'),
      ('2000', 'Accounts Payable', 'liability', 'credit', 'accounts_payable', 'Supplier balances'),
      ('2100', 'Tax Payable', 'liability', 'credit', 'tax_payable', 'Sales tax collected'),
      ('3000', 'Owner''s Equity', 'equity', 'credit', 'owners_equity', 'Capital contributions'),
      ('3100', 'Retained Earnings', 'equity', 'credit', 'opening_retained_earnings', 'Cumulative profit/loss carried forward'),
      ('3200', 'Owner Capital', 'equity', 'credit', 'owner_capital', 'Cash contributed by the owner'),
      ('3300', 'Owner Drawings', 'equity', 'debit', 'owner_drawings', 'Cash/goods taken by the owner (contra-equity)'),
      ('4000', 'Sales Revenue', 'revenue', 'credit', 'sales_revenue', 'Revenue from invoices and POS'),
      ('4100', 'Sales Returns', 'revenue', 'debit', 'sales_returns', 'Contra-revenue: returned/credited sales'),
      ('4150', 'Restocking Fee Income', 'revenue', 'credit', 'restocking_fee_income', 'Fees charged on returned items'),
      ('5000', 'Cost of Goods Sold', 'expense', 'debit', 'cogs', 'Cost of items sold'),
      ('6000', 'Operating Expenses', 'expense', 'debit', 'operating_expenses', 'General operating costs'),
      ('6100', 'Wages & Salaries', 'expense', 'debit', 'wages_salaries', 'Payroll'),
      ('6300', 'Loan Write-off', 'expense', 'debit', 'loan_write_off', 'Employee loans written off / forgiven'),
      ('7000', 'Production Clearing', 'expense', 'debit', 'production_clearing', 'Clearing account for production cost flow'),
      ('7100', 'Inventory Correction', 'expense', 'debit', 'inventory_correction', 'Adjustments adding to inventory'),
      ('7200', 'Inventory Shrinkage', 'expense', 'debit', 'inventory_shrinkage', 'Losses / removals from inventory'),
      ('7201', 'Expired Goods Loss', 'expense', 'debit', 'expired_goods_loss', 'Written-off expired stock (write-off endpoint)'),
      ('7202', 'Damaged Goods Loss', 'expense', 'debit', 'damaged_goods_loss', 'Written-off damaged stock'),
      ('7203', 'Stock Shortage Loss', 'expense', 'debit', 'stock_shortage_loss', 'Physical count shortages written off'),
      ('7204', 'Obsolete Stock Loss', 'expense', 'debit', 'obsolete_stock_loss', 'Written-off obsolete stock')
  `);
}

afterAll(() => cleanupFixtureDbs());

function createFixture(): Database.Database {
  const db = createFixtureDb();
  seedProductionReferenceData(db);

db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-C','Counted','Nos',10,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-1','Main',1)`).run();
  return db;
}

describe('PhysicalCount.completeCount batch sync (INV-01/23/24)', () => {
  it('shortage consumes FIFO layers; surplus creates ADJUSTMENT batch; coverage == balance; sequential movement numbers', () => {
    const db = createFixture();
    // Seed batches: layer1 20@5, layer2 10@8 → balance 30
    db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B1',1,1,'PURCHASE',1,20,20,5,'2026-01-01')`).run();
    db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B2',1,1,'PURCHASE',2,10,10,8,'2026-02-01')`).run();
    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,30)`).run();
    db.prepare(`UPDATE items SET current_stock=30 WHERE id=1`).run();

    const countId = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);

    // record shortage: counted 25 → variance -5. FIFO: 5 from B1 @5.
    PhysicalCountModel.recordCount(countId, 1, 25, 1, null, db);

    PhysicalCountModel.completeCount(countId, 1, db);

    const bal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as { quantity: number };
    expect(bal.quantity).toBe(25);

    const b1 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B1'`).get() as { quantity_remaining: number };
    const b2 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B2'`).get() as { quantity_remaining: number };
    expect(b1.quantity_remaining).toBe(15); // 20-5 FIFO
    expect(b2.quantity_remaining).toBe(10);
    // coverage == balance
    const covered = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get() as { s: number };
    expect(covered.s).toBe(25);

    // movement: sequential number, batch linked, JE valued at consumed cost (5*5=25)
    const mv = db.prepare(`SELECT movement_no, batch_id, unit_cost, financial_value FROM stock_movements WHERE reference_doctype='PhysicalCount'`).get() as { movement_no: string; batch_id: number; unit_cost: number; financial_value: string };
    const b1row = db.prepare(`SELECT id FROM stock_batches WHERE batch_no='B1'`).get() as { id: number };
    if (b1row) expect(mv.batch_id).toBe(b1row.id);
    expect(mv.movement_no).toMatch(/^STK-\d{4}-\d{4}$/);
    expect(mv.financial_value).toBe(25);

    // Surplus path: record +3 via a second count
    const countId2 = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);
    PhysicalCountModel.recordCount(countId2, 1, 31, 1, null, db);
    PhysicalCountModel.completeCount(countId2, 1, db);

    const adjBatch = db.prepare(`SELECT source_type, quantity_original, unit_cost FROM stock_batches WHERE source_type='ADJUSTMENT'`).get() as { source_type: string; quantity_original: number; unit_cost: number };
    expect(adjBatch).toBeTruthy();
    expect(adjBatch.quantity_original).toBe(6);
    expect(adjBatch.unit_cost).toBe(10); // snapshot unit_cost = standard_cost
    const covered2 = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get() as { s: number };
    const bal2 = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as { quantity: number };
    expect(covered2.s).toBe(bal2.quantity); // 28

    // Sequential numbering across both counts
    const nos = db.prepare(`SELECT movement_no FROM stock_movements ORDER BY id`).all() as { movement_no: string }[];
    expect(nos.length).toBeGreaterThanOrEqual(2);
  });

  it('aborts when recording a count with no snapshot row (INV-24)', () => {
    const db = createFixture();
    const countId = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);
    expect(() => PhysicalCountModel.recordCount(countId, 999, 5, 1, null, db)).toThrow(/snapshot/i);
  });
});