import { beforeAll, beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import DashboardModel from '../models/Dashboard';
import PurchaseOrderModel from '../models/PurchaseOrder';
import { createSeasonalEvent } from '../services/forecastService';
import { getCashAccountTransactions } from '../services/cashService';

/**
 * Fallow health remediation — `Dashboard.getKPI` (CRAP 39),
 * `PurchaseOrder.update` transaction (CRAP 42), `createSeasonalEvent`
 * (CRAP 30) and `getCashAccountTransactions` (CRAP 31).
 */

let adminId = 0;
beforeAll(() => {
  adminId = (
    db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
  ).id;
});

describe('Dashboard.getKPI', () => {
  it('serves every dashboard metric', () => {
    const metrics = [
      'sales_revenue',
      'gross_profit',
      'purchase_orders',
      'expenses',
      'net_profit',
      'stock_value',
      'warehouse_stock',
      'total_items',
      'inventory_turnover',
      'avg_days_to_pay',
      'total_active_items',
      'stock_health',
      'outstanding_receivables',
      'monthly_revenue',
      'outstanding_payables',
      'total_customers',
      'low_stock_count',
      'outstanding_loans',
    ];
    for (const metric of metrics) {
      const result = DashboardModel.getKPI(db, metric, '2000-01-01', '2099-12-31');
      expect(result.metric).toBe(metric);
      expect(Number.isFinite(result.value)).toBe(true);
    }
  });

  it('falls back to all-time defaults and reports unknown metrics', () => {
    expect(DashboardModel.getKPI(db, 'sales_revenue').value).toBe(0);
    expect(DashboardModel.getKPI(db, 'nope')).toEqual({
      metric: 'nope',
      value: 0,
      unit: '',
      label: 'Unknown Metric',
    });
  });

  it('computes inventory turnover and stock health from live items', () => {
    const item = db
      .prepare(
        `INSERT INTO items (item_code, item_name, is_active, current_stock, standard_cost, reorder_level)
         VALUES ('KPI-IT', 'KPI Item', 1, 10, 5, 20)`
      )
      .run();

    const turnover = DashboardModel.getKPI(db, 'inventory_turnover');
    const health = DashboardModel.getKPI(db, 'stock_health');
    const lowStock = DashboardModel.getKPI(db, 'low_stock_count');

    expect(turnover.unit).toBe('ratio');
    expect(health.value).toBe(0);
    expect(lowStock.value).toBeGreaterThanOrEqual(1);
    db.prepare('DELETE FROM items WHERE id = ?').run(item.lastInsertRowid);
  });
});

describe('PurchaseOrder.update transaction', () => {
  let supplierId = 0;
  let itemId = 0;

  beforeAll(() => {
    supplierId = Number(
      db
        .prepare(
          `INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('PO-COV-S', 'PO Supplier')`
        )
        .run().lastInsertRowid
    );
    itemId = Number(
      db
        .prepare(`INSERT INTO items (item_code, item_name) VALUES ('PO-COV-I', 'PO Item')`)
        .run().lastInsertRowid
    );
  });

  function seedPO(status = 'Draft'): number {
    const po = db
      .prepare(
        `INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, created_by)
         VALUES (?, ?, '2026-01-05', ?, ?)`
      )
      .run(`PO-COV-${Date.now()}-${Math.random()}`, supplierId, status, adminId);
    return Number(po.lastInsertRowid);
  }

  it('recalculates the header total from its lines', () => {
    const id = seedPO();
    db.prepare(
      `INSERT INTO purchase_order_items (po_id, item_id, quantity, unit_price, amount, input_tax_amount)
       VALUES (?, ?, 2, 15, 30, 5)`
    ).run(id, itemId);

    const updated = PurchaseOrderModel.update(
      id,
      { notes: 'recalculated' },
      adminId,
      db
    );

    expect(updated.id).toBe(id);
    expect(Number(updated.total_amount)).toBe(35);
  });

  it('rejects unknown and non-draft orders', () => {
    expect(() => PurchaseOrderModel.update(999999, {}, adminId, db)).toThrow(
      'Purchase Order not found'
    );
    const completed = seedPO('Completed');
    expect(() => PurchaseOrderModel.update(completed, {}, adminId, db)).toThrow(
      'Only Draft Purchase Orders can be edited'
    );
  });
});

describe('createSeasonalEvent', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM forecast_seasonal_events').run();
  });

  it('stores a full event', () => {
    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('SEASON-IT', 'Season Item')`)
      .run();
    createSeasonalEvent({
      event_name: 'Eid Sale',
      start_date: '2026-03-01',
      end_date: '2026-03-10',
      multiplier: 1.5,
      applies_to_category: 'Widgets',
      applies_to_item_id: Number(item.lastInsertRowid),
      is_recurring: 1,
    } as never);

    const row = db
      .prepare('SELECT * FROM forecast_seasonal_events')
      .get() as Record<string, unknown>;
    expect(row).toMatchObject({
      event_name: 'Eid Sale',
      multiplier: 1.5,
      applies_to_category: 'Widgets',
      applies_to_item_id: Number(item.lastInsertRowid),
      is_recurring: 1,
    });
  });

  it('defaults the multiplier and optional targets', () => {
    createSeasonalEvent({
      event_name: 'Minimal',
      start_date: '2026-04-01',
      end_date: '2026-04-02',
    } as never);

    const row = db
      .prepare('SELECT multiplier, applies_to_category, applies_to_item_id, is_recurring FROM forecast_seasonal_events')
      .get() as Record<string, unknown>;
    expect(row).toEqual({
      multiplier: 1,
      applies_to_category: null,
      applies_to_item_id: null,
      is_recurring: 0,
    });
  });
});

describe('getCashAccountTransactions', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM employee_loan_repayments').run();
    db.prepare('DELETE FROM employee_loans').run();
    db.prepare('DELETE FROM salary_payments').run();
    db.prepare('DELETE FROM expense_payments').run();
    db.prepare('DELETE FROM expenses').run();
    db.prepare('DELETE FROM payments').run();
    db.prepare('DELETE FROM owner_withdrawals').run();
    db.prepare('DELETE FROM owner_capital').run();

    const suffix = `${Date.now()}-${Math.random()}`;
    const customer = db
      .prepare(`INSERT INTO customers (customer_code, customer_name) VALUES (?, 'Cash Co')`)
      .run(`CASH-C-${suffix}`);
    const supplier = db
      .prepare(`INSERT INTO suppliers (supplier_code, supplier_name) VALUES (?, 'Cash Sup')`)
      .run(`CASH-S-${suffix}`);
    const employee = db
      .prepare(
        `INSERT INTO employees (employee_code, first_name, last_name, salary)
         VALUES (?, 'Cash', 'Employee', 100)`
      )
      .run(`CASH-EMP-${suffix}`);

    const payment = db.prepare(
      `INSERT INTO payments (payment_no, customer_id, supplier_id, payment_date, amount, payment_method, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );
    payment.run(`CASH-P-1-${suffix}`, customer.lastInsertRowid, null, '2026-01-10', 100, 'Cash', 'cust in');
    payment.run(`CASH-P-2-${suffix}`, customer.lastInsertRowid, null, '2026-01-11', -20, 'Cash', 'refund out');
    payment.run(`CASH-P-3-${suffix}`, customer.lastInsertRowid, null, '2026-01-12', 40, 'Bank', 'bank in');
    payment.run(`CASH-P-4-${suffix}`, null, supplier.lastInsertRowid, '2026-01-13', 30, 'Cash', 'supplier out');

    const expense = db
      .prepare(
        `INSERT INTO expenses (expense_no, expense_category, amount, expense_date, payment_method, description, status)
         VALUES (?, 'Supplies', 15, '2026-01-14', 'Cash', 'expense out', 'Recorded')`
      )
      .run(`CASH-E-1-${suffix}`);
    db.prepare(
      `INSERT INTO expense_payments (expense_id, payment_date, payment_method, amount)
       VALUES (?, '2026-01-15', 'Cash', 3)`
    ).run(expense.lastInsertRowid);

    db.prepare(
      `INSERT INTO salary_payments (employee_id, amount, payment_date, payment_method, reference_no, notes)
       VALUES (?, 20, '2026-01-16', 'Cash', 'SAL-1', 'salary out')`
    ).run(employee.lastInsertRowid);

    db.prepare(
      `INSERT INTO owner_capital (capital_no, capital_date, amount, payment_method, note, status)
       VALUES (?, '2026-01-17', 200, 'Cash', 'capital in', 'posted')`
    ).run(`CASH-CAP-${suffix}`);
    db.prepare(
      `INSERT INTO owner_withdrawals (withdrawal_no, withdrawal_date, kind, amount, payment_method, note, status)
       VALUES (?, '2026-01-18', 'cash', 50, 'Cash', 'withdrawal out', 'posted')`
    ).run(`CASH-WD-${suffix}`);

    const loan = db
      .prepare(
        `INSERT INTO employee_loans (employee_id, amount, balance, payment_method, disbursement_date, status)
         VALUES (?, 30, 20, 'Cash', '2026-01-19', 'active')`
      )
      .run(employee.lastInsertRowid);
    db.prepare(
      `INSERT INTO employee_loan_repayments
         (loan_id, employee_id, amount, payment_date, payment_method, repayment_type)
       VALUES (?, ?, 10, '2026-01-20', 'Cash', 'direct')`
    ).run(loan.lastInsertRowid, employee.lastInsertRowid);
  });

  it('collects every cash movement in date order and skips other methods', () => {
    const rows = getCashAccountTransactions(db, 'cash', '2099-12-31');

    expect(rows.map(r => r.type)).toEqual([
      'payment_received',
      'refund',
      'supplier_payment',
      'expense',
      'expense_payment',
      'salary',
      'owner_capital',
      'owner_withdrawal',
      'loan_disbursement',
      'loan_repayment',
    ]);
    expect(rows.map(r => r.amount)).toEqual([100, -20, -30, -15, -3, -20, 200, -50, -30, 10]);
    expect(rows.some(r => r.amount === 40)).toBe(false);
  });

  it('filters by the account key and date', () => {
    const bank = getCashAccountTransactions(db, 'bank', '2099-12-31');
    expect(bank).toHaveLength(1);
    expect(bank[0]).toMatchObject({ type: 'payment_received', amount: 40 });
    const early = getCashAccountTransactions(db, 'cash', '2026-01-13');
    expect(early.map(r => r.type)).toEqual([
      'payment_received',
      'refund',
      'supplier_payment',
    ]);
  });
});
