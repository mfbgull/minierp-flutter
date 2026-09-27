import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import ReportsModel from '../models/Reports';
import {
  netRevenueSum,
  NET_REVENUE_STATUS,
  ACTIVE_EXPENSE_STATUS,
  cogsForPeriod,
} from '../utils/reportSql';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import {
  getAuthCookie,
  createCustomer,
  createItem,
  purchaseStock,
  createInvoice,
} from './helpers/invoiceReturnSpec';

type AccountRow = { id: number; code: string; normal_balance: 'debit' | 'credit' };
type AccountTotal = { total_debit: number; total_credit: number };

const TOLERANCE = 0.01;

describe('GL authority (audit task 34)', () => {
  let authCookie = '';
  let customerId = 0;
  let itemId = 0;
  let warehouseId = 0;
  let taxInvoiced: { invoiceId: number; invoiceNo: string; invoiceItemIds: number[] };
  const periodStart = '2026-01-01';
  const periodEnd = '2026-12-31';

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = await createCustomer('GL Authority Customer', authCookie);
    itemId = await createItem('GL Authority Item', authCookie);
    await purchaseStock(itemId, warehouseId, 20, 20, authCookie);

    OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-01-01'),
      capital_date: '2026-01-01',
      amount: 100_000,
      payment_method: 'Cash',
      created_by: 1,
    });

    await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );

    const expense = await request(app).post('/api/expenses')
      .set('Cookie', authCookie)
      .send({ expense_category: 'Utilities', amount: 30, expense_date: '2026-03-15' });
    expect([200, 201]).toContain(expense.status);

    taxInvoiced = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100, taxRate: 10 }], payment: 'full' },
      authCookie,
    );

    const returned = await request(app).post(`/api/invoices/${taxInvoiced.invoiceId}/return`)
      .set('Cookie', authCookie)
      .send({
        items: [{ invoice_item_id: taxInvoiced.invoiceItemIds[0], return_quantity: 1 }],
        fee_type: 'none',
        fee_value: 0,
        reason: 'GL authority return',
      });
    expect([200, 201]).toContain(returned.status);
  });

  /**
   * Deliberately not getAccountBalance: an independent GROUP BY so this is a
   * real cross-check of the single balance model, not a tautology.
   */
  function aggregateFromJournalLines(accountId: number): AccountTotal {
    const row = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS total_debit,
             COALESCE(SUM(credit), 0) AS total_credit
      FROM journal_lines
      WHERE account_id = ? AND voided = 0
    `).get(accountId) as AccountTotal;
    return { total_debit: Number(row.total_debit), total_credit: Number(row.total_credit) };
  }

  function accounts(): AccountRow[] {
    return db.prepare('SELECT id, code, normal_balance FROM chart_of_accounts').all() as AccountRow[];
  }

  it('keeps the trial balance balanced', () => {
    const trialBalance = ReportsModel.getTrialBalance(periodEnd, db);

    expect(trialBalance.balanced).toBe(true);
    expect(Math.abs(trialBalance.total_debit - trialBalance.total_credit)).toBeLessThan(TOLERANCE);
  });

  it('has exactly one balance model: getAccountBalance equals a direct journal_lines aggregation', () => {
    for (const account of accounts()) {
      const fromService = AccountingService.getAccountBalance(db, account.id, periodEnd);
      const direct = aggregateFromJournalLines(account.id);

      expect(Number(fromService.total_debit)).toBeCloseTo(direct.total_debit, 2);
      expect(Number(fromService.total_credit)).toBeCloseTo(direct.total_credit, 2);

      const expectedBalance = account.normal_balance === 'debit'
        ? direct.total_debit - direct.total_credit
        : direct.total_credit - direct.total_debit;
      expect(Number(fromService.balance)).toBeCloseTo(expectedBalance, 2);
    }
  });

  it('derives revenue, COGS and operating expenses from the GL, with no operational drift', () => {
    const glBalance = (code: string): number => {
      const row = db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code) as { id: number } | undefined;
      if (!row) throw new Error(`Chart of accounts is missing ${code}`);
      return Number(AccountingService.getAccountBalance(db, row.id, periodEnd).balance);
    };

    const glRevenue = glBalance('4000') - glBalance('4100');
    const glCogs = glBalance('5000');
    const glOpex = glBalance('6000');

    // Computed here, not via the report: the report is GL-derived now, so
    // comparing it to the GL would only prove it equals itself.
    const operational = db.prepare(`
      SELECT ${netRevenueSum()} AS total FROM invoices
      WHERE invoice_date BETWEEN ? AND ? AND ${NET_REVENUE_STATUS()}
    `).get(periodStart, periodEnd) as { total: number };

    const operationalOpex = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) AS total FROM expenses
      WHERE ${ACTIVE_EXPENSE_STATUS()} AND expense_date BETWEEN ? AND ?
    `).get(periodStart, periodEnd) as { total: number };

    const operationalCogs = cogsForPeriod(db, periodStart, periodEnd);

    const profitLoss = ReportsModel.getProfitLossReport(periodStart, periodEnd, db);
    expect(Number(profitLoss.totalRevenue)).toBeCloseTo(glRevenue, 2);
    expect(Number(profitLoss.totalCogs)).toBeCloseTo(glCogs, 2);
    expect(Number(profitLoss.totalExpenses)).toBeCloseTo(glOpex, 2);

    // A non-zero delta means a flow posts to one truth and not the other.
    expect(glRevenue).toBeCloseTo(Number(operational.total), 2);
    expect(glCogs).toBeCloseTo(Number(operationalCogs), 2);
    expect(glOpex).toBeCloseTo(Number(operationalOpex.total), 2);
  });
});
