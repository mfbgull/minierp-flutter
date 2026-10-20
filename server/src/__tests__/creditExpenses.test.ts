import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import Reports from '../models/Reports';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { collectFlows } from '../services/cashService';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

describe('Accrual expenses and settlements', () => {
  let cookie: string;
  let category: string;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  const balance = (code: string) => db.prepare(`
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS amount
    FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0
  `).get(code) as { amount: number };
  beforeAll(async () => {
    cookie = await getAuthCookie();
    category = (db.prepare('SELECT category_name FROM expense_categories LIMIT 1').get() as { category_name: string }).category_name;
    expect((await post('/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 500, payment_method: 'Cash' })).status).toBe(201);
  });

  it('records a liability without cash, pays once, and requires reversing payments before cancellation', async () => {
    const cashBefore = balance('1000');
    const created = await post('/api/expenses', {
      expense_category: category, amount: 200, expense_date: '2026-09-03',
      payment_method: 'Credit', description: 'Accrued services', vendor_name: 'Service vendor',
    });
    expect(created.status).toBe(201);
    const expenseId = created.body.data.id;
    const recorded = await request(app).put(`/api/expenses/${expenseId}`).set('Cookie', cookie).send({ status: 'Recorded' });
    expect(recorded.status).toBe(200);
    expect(balance('1000')).toEqual(cashBefore);
    expect(balance('2115')).toEqual({ amount: -200 });
    const beforePaymentFeed = await request(app).get('/api/payments/unified').query({ fromDate: '2026-09-03', toDate: '2026-09-03', type: 'expense' }).set('Cookie', cookie);
    expect(beforePaymentFeed.status).toBe(200);
    expect(beforePaymentFeed.body.data).toEqual([]);
    expectAllInvariantsHold('after recording credit expense', db);
    expect(Reports.getCashFlow('2026-09-03', '2026-09-03', db).movements.filter(m => m.reference === created.body.data.expense_no)).toEqual([]);
    const paymentBody = { amount: 50, payment_date: '2026-09-04', payment_method: 'Cash' };
    const payment = await request(app).post(`/api/expenses/${expenseId}/payments`).set('Cookie', cookie).set('Idempotency-Key', 'credit-expense-partial').send(paymentBody);
    expect(payment.status).toBe(201);
    const retry = await request(app).post(`/api/expenses/${expenseId}/payments`).set('Cookie', cookie).set('Idempotency-Key', 'credit-expense-partial').send(paymentBody);
    expect(retry.status).toBe(201);
    expect(balance('2115')).toEqual({ amount: -150 });
    expect(balance('1000').amount).toBe(cashBefore.amount - 50);
    const paymentFeed = await request(app).get('/api/payments/unified').query({ fromDate: '2026-09-04', toDate: '2026-09-04', type: 'expense' }).set('Cookie', cookie);
    expect(paymentFeed.status).toBe(200);
    expect(paymentFeed.body.data).toEqual([expect.objectContaining({ source: 'expense_payment', amount: 50, direction: 'out' })]);
    const laterCash = collectFlows(db, '2027-09-04').get('cash');
    expect((laterCash?.inflow ?? 0) - (laterCash?.outflow ?? 0)).toBe(cashBefore.amount - 50);
    expectAllInvariantsHold('after partial expense payment', db);
    expect(Reports.getCashFlow('2026-09-04', '2026-09-04', db).movements.filter(m => m.reference === created.body.data.expense_no))
      .toEqual([expect.objectContaining({ type: 'expense_payment', amount: -50 })]);
    const cancelled = await request(app).put(`/api/expenses/${expenseId}`).set('Cookie', cookie).send({ status: 'Cancelled' });
    expect(cancelled.status).toBe(409);
    const overpaid = await post(`/api/expenses/${expenseId}/payments`, { ...paymentBody, amount: 151 });
    expect(overpaid.status).toBe(400);
    const paymentId = payment.body.data.id;
    expect((await post(`/api/expenses/${expenseId}/payments/${paymentId}/void`, { reason: 'Correction' })).status).toBe(200);
    expect((await request(app).put(`/api/expenses/${expenseId}`).set('Cookie', cookie).send({ status: 'Cancelled' })).status).toBe(200);
    expect(balance('2115')).toEqual({ amount: 0 });
    expect(balance('1000')).toEqual(cashBefore);
    expectAllInvariantsHold('after reversing and cancelling credit expense', db);
  });

  it('keeps older cash expenses and salary outflows in cumulative balances', async () => {
    const cashBefore = balance('1000').amount;
    const expense = await post('/api/expenses', { expense_category: category, amount: 100, expense_date: '2026-09-05', payment_method: 'Cash', description: 'Historical cash expense regression' });
    expect(expense.status).toBe(201);
    expect((await request(app).put(`/api/expenses/${expense.body.data.id}`).set('Cookie', cookie).send({ status: 'Recorded' })).status).toBe(200);
    const employee = await post('/api/employees', { employee_code: 'CASH-HISTORY', first_name: 'Cash', last_name: 'History', department_id: 1, position: 'Clerk', hire_date: '2026-01-01', salary: 50 });
    expect(employee.status).toBe(201);
    expect((await post(`/api/employees/${employee.body.data.id}/salary/pay`, { amount: 50, payment_date: '2026-09-06', payment_method: 'cash', payment_type: 'partial' })).status).toBe(201);
    const laterCash = collectFlows(db, '2027-09-04').get('cash');
    expect((laterCash?.inflow ?? 0) - (laterCash?.outflow ?? 0)).toBe(cashBefore - 150);
    expectAllInvariantsHold('older cash transactions', db);
  });
});
