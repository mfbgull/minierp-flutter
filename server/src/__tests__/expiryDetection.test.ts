/**
 * Expired-stock plan Phase 2 — boot task unit tests.
 *
 * Covers the rewritten expiryDetection.ts:
 *   1. Sweeps expired batches into the EXPIRED warehouse via the shared
 *      paired-leg helper (movements + mirror batch + balances)
 *   2. Is idempotent — a second run moves nothing
 *   3. Skips batches already at EXPIRED, not-yet-expired, and zero-qty
 *   4. Per-batch isolation: one bad batch doesn't roll back the sweep
 *   5. Throws loud when the EXPIRED warehouse is missing (migration bug)
 */
import Database from 'better-sqlite3';
import { runExpiryDetection } from '../boot/expiryDetection';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/** createFixtureDb() clones schema only, so the rows add-gl-foundation.sql and
 * add-expired-stock.sql seed as DATA are absent. The expiry sweep posts loss to
 * the 7201-7204 accounts add-expired-stock.sql seeds. */
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

function createFixture(): Database.Database {
  const db = createFixtureDb();
  seedProductionReferenceData(db);

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-1','Widget','Nos',10,1,1)`).run();
  // WH-001 is created by runtime code in database.ts, not init.sql — seed it.
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-001','Main',1)`).run();

  // The EXPIRED/DAMAGED system warehouses add-expired-stock.sql seeds. Seeded
  // AFTER WH-001 so the id order matches production (WH-001=1, EXPIRED=2,
  // DAMAGED=3) — the sweep resolves them by code, but the fixtures' id
  // assumptions must not drift from it.
  db.prepare(`INSERT OR IGNORE INTO warehouses (warehouse_code, warehouse_name, is_system, is_active)
              VALUES ('EXPIRED','Expired Stock',1,1), ('DAMAGED','Damaged Stock',1,1)`).run();
  return db;
}

function seedBatch(
  db: Database.Database,
  batchNo: string,
  opts: { qty: number; expiry: string; warehouseId?: number }
): number {
  const wh = opts.warehouseId ?? (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'WH-001'`).get() as { id: number }).id;
  const r = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
    VALUES (?,1,?,'PURCHASE',1,?,?,5,'2026-01-01',?)
  `).run(batchNo, wh, opts.qty, opts.qty, opts.expiry);
  const batchId = r.lastInsertRowid as number;
  // Item-level balance is UNIQUE(item_id, warehouse_id) — accumulate.
  db.prepare(`
    INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,?,?)
    ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = quantity + excluded.quantity
  `).run(wh, opts.qty);
  return batchId;
}

describe('expiryDetection boot task', () => {
  it('sweeps expired batches to EXPIRED with paired legs and mirror batch', () => {
    const db = createFixture();
    const expiredWhId = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    const b1 = seedBatch(db, 'BOOT-B1', { qty: 5, expiry: '2026-08-01' });
    const b2 = seedBatch(db, 'BOOT-B2', { qty: 3, expiry: '2026-07-15' });

    const result = runExpiryDetection(db);
    expect(result.candidates).toBe(2);
    expect(result.moved).toBe(2);
    expect(result.failed).toBe(0);

    // Both batches zeroed at source; mirrored at EXPIRED with same cost
    for (const id of [b1, b2]) {
      const src = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(id) as { quantity_remaining: number };
      expect(src.quantity_remaining).toBe(0);
    }
    const mirrors = db.prepare(
      `SELECT COUNT(*) AS n FROM stock_batches WHERE warehouse_id = ? AND source_type = 'TRANSFER'`
    ).get(expiredWhId) as { n: number };
    expect(mirrors.n).toBe(2);

    // Paired movement legs exist for each source batch (OUT −qty on the
    // source batch id; the IN leg rides the mirror batch, verified via the
    // mirror count above).
    for (const id of [b1, b2]) {
      const legs = db.prepare(
        `SELECT quantity FROM stock_movements WHERE batch_id = ? AND movement_type = 'EXPIRY_TRANSFER'`
      ).all(id) as Array<{ quantity: number }>;
      expect(legs).toHaveLength(1);
      expect(legs[0].quantity).toBeLessThan(0); // OUT leg
    }
    const inLegs = (db.prepare(
      `SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = 'EXPIRY_TRANSFER' AND quantity > 0`
    ).get() as { n: number }).n;
    expect(inLegs).toBe(2); // IN leg per moved batch, on the mirror batches

    // Balance conservation: item total unchanged (5 + 3)
    const total = db.prepare(`SELECT COALESCE(SUM(quantity),0) AS q FROM stock_balances WHERE item_id = 1`).get() as { q: number };
    expect(total.q).toBe(8);

    db.close();
  });

  it('is idempotent — a second run moves nothing', () => {
    const db = createFixture();
    seedBatch(db, 'BOOT-B3', { qty: 4, expiry: '2026-08-01' });

    const first = runExpiryDetection(db);
    expect(first.moved).toBe(1);

    const second = runExpiryDetection(db);
    expect(second.candidates).toBe(0);
    expect(second.moved).toBe(0);

    // No duplicated movement legs
    const legs = (db.prepare(
      `SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = 'EXPIRY_TRANSFER'`
    ).get() as { n: number }).n;
    expect(legs).toBe(2); // one OUT + one IN total
    db.close();
  });

  it('skips not-yet-expired, zero-quantity, and already-EXPIRED batches', () => {
    const db = createFixture();
    const expiredWhId = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
    seedBatch(db, 'BOOT-FUTURE', { qty: 5, expiry: '2099-01-01' }); // not expired
    seedBatch(db, 'BOOT-ZERO', { qty: 0, expiry: '2026-08-01' }); // no qty
    seedBatch(db, 'BOOT-ATDEST', { qty: 2, expiry: '2026-08-01', warehouseId: expiredWhId }); // already there
    seedBatch(db, 'BOOT-GOOD', { qty: 6, expiry: '2026-08-01' }); // should move

    const result = runExpiryDetection(db);
    expect(result.candidates).toBe(1);
    expect(result.moved).toBe(1);
    db.close();
  });

  it('isolates a bad batch — the rest of the sweep still completes', () => {
    const db = createFixture();
    seedBatch(db, 'BOOT-OK', { qty: 2, expiry: '2026-08-01' });

    // Orphan the item reference of another expired batch to break its legs
    // (FK enforcement inside recordExpiryTransfer will fail for it).
    db.pragma('foreign_keys = OFF');
    const bad = db.prepare(`
      INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
      VALUES ('BOOT-BAD', 99999, 1, 'PURCHASE', 1, 3, 3, 5, '2026-01-01', '2026-08-01')
    `).run();
    db.pragma('foreign_keys = ON');

    const result = runExpiryDetection(db);
    expect(result.moved).toBe(1); // the good batch moved
    expect(result.failed).toBe(1); // the bad one failed
    expect(result.failures[0].batchNo).toBe('BOOT-BAD');
    expect(result.failures[0].batchId).toBe(bad.lastInsertRowid as number);

    // The good batch is fully processed despite the bad one
    const ok = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no = 'BOOT-OK'`).get() as { quantity_remaining: number };
    expect(ok.quantity_remaining).toBe(0);
    db.close();
  });

  it('throws loud when the EXPIRED warehouse is missing (migration bug)', () => {
    const db = createFixture();
    // Drop the delete-guard trigger — this test simulates a DB where the
    // migration never ran (so neither the trigger nor the warehouse exists).
    db.exec(`DROP TRIGGER IF EXISTS trg_warehouses_no_delete_system`);
    db.prepare(`DELETE FROM warehouses WHERE warehouse_code = 'EXPIRED'`).run();
    seedBatch(db, 'BOOT-NOWH', { qty: 1, expiry: '2026-08-01' });

    expect(() => runExpiryDetection(db)).toThrow(/add-expired-stock\.sql migration did not run/);
    db.close();
  });
});
