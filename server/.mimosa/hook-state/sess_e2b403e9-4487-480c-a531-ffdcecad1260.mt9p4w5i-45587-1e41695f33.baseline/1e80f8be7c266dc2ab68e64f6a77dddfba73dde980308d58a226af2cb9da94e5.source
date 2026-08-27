import Database from 'better-sqlite3';
import DashboardModel from '../models/Dashboard';

/**
 * Unit tests for `DashboardModel.getKPI` — the per-card metric endpoint
 * behind the dashboard customizer (spec §10). Covers the 7 core cards
 * added in Phase 1 (stock_value, sales_revenue, gross_profit,
 * purchase_orders, warehouse_stock, total_items) with value correctness
 * and date-range filtering. The in-memory schema is minimal — only the
 * columns each metric reads.
 */

let db: Database.Database;

beforeEach(() => {
  db = new Database(':memory:');
  db.exec(`
    CREATE TABLE items (
      id            INTEGER PRIMARY KEY,
      is_active     INTEGER DEFAULT 1,
      current_stock INTEGER DEFAULT 0,
      standard_cost REAL DEFAULT 0,
      reorder_level INTEGER DEFAULT 0
    );
    CREATE TABLE stock_batches (
      id                 INTEGER PRIMARY KEY,
      item_id            INTEGER,
      quantity_remaining REAL DEFAULT 0,
      unit_cost          REAL DEFAULT 0
    );
    CREATE TABLE stock_balances (
      id       INTEGER PRIMARY KEY,
      item_id  INTEGER,
      quantity REAL DEFAULT 0
    );
    CREATE TABLE invoices (
      id             INTEGER PRIMARY KEY,
      invoice_no     TEXT,
      customer_id    INTEGER,
      invoice_date   TEXT,
      status         TEXT,
      total_amount   REAL DEFAULT 0,
      returned_amount REAL DEFAULT 0,
      balance_amount REAL DEFAULT 0
    );
    CREATE TABLE stock_movements (
      id              INTEGER PRIMARY KEY,
      movement_date   TEXT,
      movement_type   TEXT,
      quantity        REAL DEFAULT 0,
      unit_cost       REAL DEFAULT 0,
      reference_doctype TEXT
    );
    CREATE TABLE purchase_orders (
      id           INTEGER PRIMARY KEY,
      po_no        TEXT,
      po_date      TEXT,
      status       TEXT,
      total_amount REAL DEFAULT 0
    );
    CREATE TABLE expenses (
      id            INTEGER PRIMARY KEY,
      expense_no    TEXT,
      expense_date  TEXT,
      amount        REAL DEFAULT 0,
      status        TEXT
    );
    CREATE TABLE supplier_ledger (
      id               INTEGER PRIMARY KEY,
      supplier_id      INTEGER,
      transaction_date TEXT,
      transaction_type TEXT,
      balance          REAL DEFAULT 0
    );
    CREATE TABLE customers (
      id            INTEGER PRIMARY KEY,
      customer_code TEXT,
      customer_name TEXT,
      is_active     INTEGER DEFAULT 1
    );
  `);
});

afterEach(() => {
  db.close();
});

function seedItem(
  id: number,
  opts: { isActive?: number; currentStock?: number; cost?: number } = {},
): void {
  db.prepare(
    `INSERT INTO items (id, is_active, current_stock, standard_cost, reorder_level)
     VALUES (?, ?, ?, ?, 0)`,
  ).run(id, opts.isActive ?? 1, opts.currentStock ?? 0, opts.cost ?? 0);
}

function seedBatch(itemId: number, qty: number, unitCost: number): void {
  db.prepare(
    `INSERT INTO stock_batches (item_id, quantity_remaining, unit_cost)
     VALUES (?, ?, ?)`,
  ).run(itemId, qty, unitCost);
}

function seedBalance(itemId: number, qty: number): void {
  db.prepare(
    `INSERT INTO stock_balances (item_id, quantity) VALUES (?, ?)`,
  ).run(itemId, qty);
}

function seedInvoice(
  date: string,
  amount: number,
  status = 'Paid',
  returned = 0,
): void {
  db.prepare(
    `INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount, returned_amount, balance_amount)
     VALUES (?, 1, ?, ?, ?, ?, 0)`,
  ).run(`INV-${Date.now()}-${Math.random()}`, date, status, amount, returned);
}

function seedMovement(
  date: string,
  type: string,
  qty: number,
  unitCost: number,
  referenceDoctype: string | null = null,
): void {
  db.prepare(
    `INSERT INTO stock_movements (movement_date, movement_type, quantity, unit_cost, reference_doctype)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(date, type, qty, unitCost, referenceDoctype);
}

function seedPurchaseOrder(
  date: string,
  amount: number,
  status = 'Received',
): void {
  db.prepare(
    `INSERT INTO purchase_orders (po_no, po_date, status, total_amount)
     VALUES (?, ?, ?, ?)`,
  ).run(`PO-${Date.now()}-${Math.random()}`, date, status, amount);
}

describe('dashboard /kpi core metrics (Phase 1)', () => {
  test('stock_value = batch value + legacy fallback for unbatchable stock', () => {
    // 10 units @ 500 in a batch, plus 5 legacy units @ 300 with no batch.
    seedItem(1);
    seedBatch(1, 10, 500);
    seedItem(2, { currentStock: 5, cost: 300 });

    const result = DashboardModel.getKPI(db, 'stock_value');
    expect(result.value).toBe(10 * 500 + 5 * 300); // 6500
  });

  test('sales_revenue sums non-cancelled invoices within the range', () => {
    seedInvoice('2026-01-10', 1000);
    seedInvoice('2026-01-20', 2000);
    seedInvoice('2026-02-01', 400, 'Cancelled');
    seedInvoice('2026-02-15', 300, 'Paid', 50); // returned 50

    const all = DashboardModel.getKPI(db, 'sales_revenue');
    expect(all.value).toBe(1000 + 2000 + 300 - 50); // 3250

    // January only — filters by invoice_date.
    const jan = DashboardModel.getKPI(db, 'sales_revenue', '2026-01-01', '2026-01-31');
    expect(jan.value).toBe(1000 + 2000); // 3000
  });

  test('gross_profit = revenue − sale COGS (returns adjust COGS)', () => {
    seedInvoice('2026-01-10', 1000);
    seedInvoice('2026-01-12', 500);
    // Sales movements reduce stock, so quantity is negative.
    seedMovement('2026-01-10', 'SALE', -2, 100); // COGS 200
    seedMovement('2026-01-12', 'SALE', -1, 100); // COGS 100
    // A return adds stock back — positive quantity offsets the COGS.
    seedMovement('2026-01-15', 'ADJUSTMENT', 1, 100, 'RETURN'); // −100

    const result = DashboardModel.getKPI(db, 'gross_profit', '2026-01-01', '2026-01-31');
    // Revenue 1500 − (200 + 100 − 100) = 1300.
    expect(result.value).toBe(1300);
  });

  test('purchase_orders sums non-draft/cancelled POs within the range', () => {
    seedPurchaseOrder('2026-01-05', 5000);
    seedPurchaseOrder('2026-01-15', 2500);
    seedPurchaseOrder('2026-01-20', 900, 'Draft');
    seedPurchaseOrder('2026-02-10', 700);

    const jan = DashboardModel.getKPI(db, 'purchase_orders', '2026-01-01', '2026-01-31');
    expect(jan.value).toBe(5000 + 2500); // 7500
  });

  test('warehouse_stock counts positive stock_balances rows', () => {
    seedBalance(1, 10);
    seedBalance(2, 0); // zero — excluded
    seedBalance(3, 5);
    const result = DashboardModel.getKPI(db, 'warehouse_stock');
    expect(result.value).toBe(2);
  });

  test('total_items counts active items (alias of total_active_items)', () => {
    seedItem(1);
    seedItem(2, { isActive: 0 });
    seedItem(3);
    expect(DashboardModel.getKPI(db, 'total_items').value).toBe(2);
    expect(DashboardModel.getKPI(db, 'total_active_items').value).toBe(2);
  });

  test('stock_value / warehouse_stock / total_items ignore the date range', () => {
    seedItem(1);
    seedBatch(1, 10, 500);
    seedBalance(1, 10);

    const ranged = DashboardModel.getKPI(db, 'stock_value', '2026-01-01', '2026-01-31');
    const allTime = DashboardModel.getKPI(db, 'stock_value');
    expect(ranged.value).toBe(allTime.value);

    const wh = DashboardModel.getKPI(db, 'warehouse_stock', '2020-01-01', '2020-01-01');
    expect(wh.value).toBe(1);
  });

  test('unknown metric falls back to a zero result (never throws)', () => {
    const result = DashboardModel.getKPI(db, 'not_a_metric');
    expect(result.value).toBe(0);
    expect(result.label).toBe('Unknown Metric');
  });
});

describe('dashboard /kpi additional cards (net profit, expenses, etc.)', () => {
  function seedExpense(date: string, amount: number, status = 'Approved'): void {
    db.prepare(
      `INSERT INTO expenses (expense_no, expense_date, amount, status)
       VALUES (?, ?, ?, ?)`,
    ).run(`EXP-${Date.now()}-${Math.random()}`, date, amount, status);
  }

  function seedSupplierLedger(
    supplierId: number,
    date: string,
    balance: number,
  ): void {
    db.prepare(
      `INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, balance)
       VALUES (?, ?, 'PURCHASE_ORDER', ?)`,
    ).run(supplierId, date, balance);
  }

  function seedCustomer(id: number, isActive = 1): void {
    db.prepare(
      `INSERT INTO customers (id, customer_code, customer_name, is_active)
       VALUES (?, ?, ?, ?)`,
    ).run(id, `C${id}`, `Customer ${id}`, isActive);
  }

  test('expenses sums non-cancelled expenses within the range', () => {
    seedExpense('2026-01-05', 300);
    seedExpense('2026-01-20', 150);
    seedExpense('2026-01-25', 400, 'Cancelled');
    seedExpense('2026-02-10', 500);

    const jan = DashboardModel.getKPI(db, 'expenses', '2026-01-01', '2026-01-31');
    expect(jan.value).toBe(300 + 150); // 450
    const all = DashboardModel.getKPI(db, 'expenses');
    expect(all.value).toBe(300 + 150 + 500); // 950
  });

  test('net_profit = revenue − COGS − expenses (matches P&L)', () => {
    seedInvoice('2026-01-10', 1000);
    seedInvoice('2026-01-12', 500);
    seedMovement('2026-01-10', 'SALE', -2, 100); // COGS 200
    seedMovement('2026-01-12', 'SALE', -1, 100); // COGS 100
    seedExpense('2026-01-15', 300);
    seedExpense('2026-01-20', 100);

    const result = DashboardModel.getKPI(db, 'net_profit', '2026-01-01', '2026-01-31');
    // Revenue 1500 − COGS 300 − expenses 400 = 800.
    expect(result.value).toBe(800);
  });

  test('net_profit is range-filtered like the P&L report', () => {
    seedInvoice('2026-01-10', 1000);
    seedExpense('2026-01-15', 200);
    // February sales + expenses fall outside January.
    seedInvoice('2026-02-10', 900);
    seedExpense('2026-02-10', 500);

    const jan = DashboardModel.getKPI(db, 'net_profit', '2026-01-01', '2026-01-31');
    expect(jan.value).toBe(1000 - 200); // 800
  });

  test('outstanding_payables = latest supplier ledger balance per supplier', () => {
    // Supplier 1: PO 1000, then payment brings it to 400.
    seedSupplierLedger(1, '2026-01-01', 1000);
    seedSupplierLedger(1, '2026-01-10', 400);
    // Supplier 2: unpaid PO 2500.
    seedSupplierLedger(2, '2026-01-05', 2500);
    // Supplier 3: fully paid (zero balance) — excluded.
    seedSupplierLedger(3, '2026-01-05', 0);

    const result = DashboardModel.getKPI(db, 'outstanding_payables');
    expect(result.value).toBe(400 + 2500); // 2900
  });

  test('total_customers counts active customers', () => {
    seedCustomer(1);
    seedCustomer(2, 0);
    seedCustomer(3);
    const result = DashboardModel.getKPI(db, 'total_customers');
    expect(result.value).toBe(2);
  });

  test('low_stock_count counts active items at or below reorder level', () => {
    // Item 1: 5 stock, reorder 10 → low.
    db.prepare(
      `INSERT INTO items (id, is_active, current_stock, standard_cost, reorder_level)
       VALUES (1, 1, 5, 0, 10)`,
    ).run();
    // Item 2: 20 stock, reorder 10 → healthy.
    db.prepare(
      `INSERT INTO items (id, is_active, current_stock, standard_cost, reorder_level)
       VALUES (2, 1, 20, 0, 10)`,
    ).run();
    // Item 3: inactive — excluded.
    db.prepare(
      `INSERT INTO items (id, is_active, current_stock, standard_cost, reorder_level)
       VALUES (3, 0, 3, 0, 10)`,
    ).run();
    // Item 4: no reorder level set — excluded.
    db.prepare(
      `INSERT INTO items (id, is_active, current_stock, standard_cost, reorder_level)
       VALUES (4, 1, 2, 0, 0)`,
    ).run();

    const result = DashboardModel.getKPI(db, 'low_stock_count');
    expect(result.value).toBe(1);
  });
});
