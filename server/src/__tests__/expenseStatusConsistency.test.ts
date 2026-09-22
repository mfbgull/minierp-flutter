import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import AccountingService from '../services/accountingService';
import ExpenseModel from '../models/Expense';
import ReportsModel from '../models/Reports';
import DashboardModel from '../models/Dashboard';
import { syncOpeningBalancesToGl } from '../services/cashService';

/**
 * TASK 14 — H5: P&L must exclude cancelled expenses.
 * Authoritative accounting state = GL-worthiness (see glWorthy in
 * models/Expense.ts): Draft carries no GL lines, Cancelled has them
 * voided. Every expense aggregate must agree with the GL.
 */

const MIGRATIONS = [
  'init.sql', 'add-purchases-table.sql', 'create-payment-allocations.sql',
  'add-expenses-table.sql', 'add-supplier-payment-support.sql',
  'create-customer-ledger.sql', 'create-supplier-ledger.sql',
  'add-gl-foundation.sql', 'add-gl-void-attribution.sql',
  'add-salary-payments.sql', 'add-cash-accounts.sql', 'add-opening-balances.sql',
  'add-owner-equity.sql', 'add-employees-table.sql', 'add-employee-loans.sql',
  'add-purchase-returns-tables.sql', 'add-disposition-and-supplier-refunds.sql',
  'add-purchase-supplier-payment.sql', 'add-payment-salary-void-columns.sql',
  'add-employee-loan-void-columns.sql', 'add-returned-amount.sql',
  'add-user-preferences.sql', 'add-batch-costing.sql',
];

const RANGE = { from: '2026-09-01', to: '2026-09-30' };

function makeDb(): Database.Database {
  const db = new Database(':memory:');
  for (const f of MIGRATIONS) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
  }
  db.exec(`
    CREATE TABLE IF NOT EXISTS journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reference_type TEXT NOT NULL,
      reference_id INTEGER NOT NULL,
      entry_date DATE NOT NULL,
      description TEXT,
      debit_account TEXT NOT NULL,
      credit_account TEXT NOT NULL,
      amount DECIMAL(15,4) NOT NULL,
      created_by INTEGER REFERENCES users(id),
      voided BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
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
  finalStatus: 'Draft' | 'Submitted' | 'Cancelled',
): number {
  const id = ExpenseModel.create(db, {
    expense_no: no, expense_category: 'Utilities', description: no,
    amount, expense_date: '2026-09-01', payment_method: 'Cash', status: 'Draft', created_by: 1,
  });
  if (finalStatus === 'Submitted') {
    ExpenseModel.update(db, id, { status: 'Submitted' }, { userId: 1 });
  } else if (finalStatus === 'Cancelled') {
    ExpenseModel.update(db, id, { status: 'Submitted' }, { userId: 1 });
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
    addExpense(db, 'EXP-A', 300, 'Submitted');
    addExpense(db, 'EXP-B', 120, 'Cancelled');

    const pl = ReportsModel.getProfitLossReport(RANGE.from, RANGE.to, db);
    expect(pl.totalExpenses).toBe(300);
    expect(pl.expenses).toEqual([{ expense_category: 'Utilities', total: 300 }]);
    db.close();
  });

  it('income statement and expense summary exclude cancelled and draft', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Submitted');
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
    addExpense(db, 'EXP-A', 300, 'Submitted');
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
    addExpense(db, 'EXP-A', 300, 'Submitted');
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

  it('all expense surfaces agree via the shared predicate', () => {
    const db = makeDb();
    addExpense(db, 'EXP-A', 300, 'Submitted');
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
