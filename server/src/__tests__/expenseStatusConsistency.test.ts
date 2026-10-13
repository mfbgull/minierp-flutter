import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import ExpenseModel from '../models/Expense';
import ReportsModel from '../models/Reports';
import DashboardModel from '../models/Dashboard';
import { syncOpeningBalancesToGl } from '../services/cashService';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * TASK 14 — H5: P&L must exclude cancelled expenses.
 * Authoritative accounting state = GL-worthiness (see glWorthy in
 * models/Expense.ts): Draft carries no GL lines, Cancelled has them
 * voided. Every expense aggregate must agree with the GL.
 */

const RANGE = { from: '2026-09-01', to: '2026-09-30' };

/** createFixtureDb() clones schema only, so the rows add-gl-foundation.sql and
 * add-opening-balances.sql seed as DATA are absent. Every assertion here reads
 * account codes off journal_lines and the opening 'cash' row. */
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

function makeDb(): Database.Database {
  const db = createFixtureDb();
  seedProductionReferenceData(db);
  db.prepare(`INSERT INTO users (username, email, password_hash, full_name, role, is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`UPDATE opening_balances SET amount = 10000 WHERE account_key = 'cash'`).run();
  // Seed the GL opening dated before the test range (cashTruth fixture
  // pattern): the anchor Draft row makes 2026-09-01 the earliest
  // transaction, so the opening line lands on 2026-08-31 and the funds
  // guard sees the cash when expenses submit. The anchor is Draft (never
  // posts, never counted) and removed right after the sync.
  const anchorId = ExpenseModel.create(db, {
    expense_no: 'EXP-ANCHOR', expense_category: 'Utilities', description: 'anchor',
    amount: 1, expense_date: '2026-09-01', payment_method: 'Cash', status: 'Draft', created_by: 1,
  });
  db.transaction(() => syncOpeningBalancesToGl(db, 1))();
  db.prepare('DELETE FROM expenses WHERE id = ?').run(anchorId);
  return db;
}

function addExpense(
  db: Database.Database,
  no: string,
  amount: number,
finalStatus: 'Draft' | 'Recorded' | 'Cancelled',
  ): number {
    const id = ExpenseModel.create(db, {
      expense_no: no, expense_category: 'Utilities', description: no,
      amount, expense_date: '2026-09-01', payment_method: 'Cash', status: 'Draft', created_by: 1,
    });
    if (finalStatus === 'Recorded') {
      ExpenseModel.update(db, id, { status: 'Recorded' }, { userId: 1 });
    } else if (finalStatus === 'Cancelled') {
      ExpenseModel.update(db, id, { status: 'Recorded' }, { userId: 1 });
      ExpenseModel.update(db, id, { status: 'Cancelled' }, { userId: 1 });
    }
    return id;
  }

/** Active (non-voided) GL debit on account 6000 Operating Expenses. */
function glExpenseTotal(db: Database.Database): number {
  return (db.prepare(`
    SELECT COALESCE(SUM(l.debit - l.credit), 0) as total
    FROM journal_lines l JOIN chart_of_accounts a ON l.account_id = a.id
    WHERE a.code = '6000' AND l.voided = 0 AND l.line_date BETWEEN ? AND ?
  `).get(RANGE.from, RANGE.to) as { total: number }).total;
}

describe('H5: expense aggregates follow GL-worthiness', () => {
  // Audit scenario: active 300 + cancelled 120 must report 300 everywhere.
  it('P&L excludes a cancelled expense (audit case: 420 → 300)', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Recorded');
    addExpense(db, 'EXP-B', 120, 'Cancelled');

    const pl = ReportsModel.getProfitLossReport(RANGE.from, RANGE.to, db);
    expect(pl.totalExpenses).toBe(300);
    expect(pl.expenses).toEqual([{ expense_category: 'Utilities', total: 300 }]);
    db.close();
  });

  it('income statement and expense summary exclude cancelled and draft', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Recorded');
    addExpense(db, 'EXP-B', 120, 'Cancelled');
    addExpense(db, 'EXP-C', 50, 'Draft');

    const income = ReportsModel.getIncomeStatement(RANGE.from, RANGE.to, db);
    expect(income.expenses).toBe(300);

    const summary = ExpenseModel.getSummary(db, RANGE.from, RANGE.to);
    expect(summary.overall_summary).toEqual({ total_expenses: 1, total_amount: 300 });
    expect(summary.category_summary).toEqual([
      { expense_category: 'Utilities', count: 1, total_amount: 300 },
    ]);

    const byRange = ExpenseModel.getByDateRange(db, RANGE.from, RANGE.to);
    expect(byRange.total_amount).toBe(300);

    const byCat = ExpenseModel.getByCategory(db, 'Utilities', RANGE.from, RANGE.to);
    expect(byCat.total_amount).toBe(300);
    db.close();
  });

  it('dashboard expense summary and expense/net-profit KPIs exclude cancelled and draft', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Recorded');
    addExpense(db, 'EXP-B', 120, 'Cancelled');
    addExpense(db, 'EXP-C', 50, 'Draft');

    const expensesKpi = DashboardModel.getKPI(db, 'expenses', RANGE.from, RANGE.to);
    expect(expensesKpi.value).toBe(300);

    // No invoices/COGS in this fixture → net profit = −expenses.
    const netProfitKpi = DashboardModel.getKPI(db, 'net_profit', RANGE.from, RANGE.to);
    expect(netProfitKpi.value).toBe(-300);
    db.close();
  });

  it('cash flow and GL exclude cancelled; active expense stays in both', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Recorded');
    addExpense(db, 'EXP-B', 120, 'Cancelled');
    addExpense(db, 'EXP-C', 50, 'Draft');

    // GL: only EXP-A has a live expense line (300).
    expect(glExpenseTotal(db)).toBe(300);

    // Report cash flow: outflow is the active expense only, and the
    // movement drill-down never shows cancelled/draft rows.
    const cf = ReportsModel.getCashFlow(RANGE.from, RANGE.to, db);
    expect(cf.totalOutflow).toBe(300);
    expect(cf.movements.filter(m => m.type === 'expense').map(m => m.reference)).toEqual(['EXP-A']);

    // Cash reconciliation flows agree.
    const flows = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total FROM expenses
      WHERE status NOT IN ('Cancelled', 'Draft') AND expense_date BETWEEN ? AND ?
    `).get(RANGE.from, RANGE.to) as { total: number };
    expect(flows.total).toBe(300);
    db.close();
  });

  it('closed period blocks expense update', () => {
    const db = makeDb();
    const id = addExpense(db, 'EXP-CP', 200, 'Recorded');
    db.prepare(`INSERT INTO accounting_periods (period_name, start_date, end_date, status)
                VALUES ('2026-09-cp', '2026-09-01', '2026-09-30', 'closed')`).run();
    expect(() => ExpenseModel.update(db, id, { amount: 999 }, { userId: 1 }))
      .toThrow(/closed accounting period/i);
    expect((db.prepare('SELECT amount FROM expenses WHERE id = ?').get(id) as { amount: number }).amount).toBe(200);
    db.close();
  });

  it('all expense surfaces agree via the shared predicate', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Recorded');
    addExpense(db, 'EXP-B', 120, 'Cancelled');
    addExpense(db, 'EXP-C', 50, 'Draft');

    const pl = ReportsModel.getProfitLossReport(RANGE.from, RANGE.to, db);
    const summary = ExpenseModel.getSummary(db, RANGE.from, RANGE.to);
    const kpi = DashboardModel.getKPI(db, 'expenses', RANGE.from, RANGE.to);

    expect(pl.totalExpenses).toBe(300);
    expect(summary.overall_summary.total_amount).toBe(300);
    expect(kpi.value).toBe(300);
    expect(glExpenseTotal(db)).toBe(300);

    // AccountingService balance path (trial-balance source) agrees too.
    const balances = AccountingService.getAllAccountBalances(db, RANGE.to);
    const opex = balances.find(b => b.account_code === '6000');
    expect(opex?.balance).toBe(300);
    db.close();
  });
});
