import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';

let cookie: string;
let warehouseId: number;
const post = (url: string, body: unknown) => request(app).post(url).set('Cookie', cookie).send(body as object);
const put = (url: string, body: unknown) => request(app).put(url).set('Cookie', cookie).send(body as object);
const del = (url: string, body: unknown = {}) => request(app).delete(url).set('Cookie', cookie).send(body as object);
const r2 = (v: number): number => Math.round(v * 100) / 100;
const idOf = (res: request.Response): number => (res.body?.data?.id ?? res.body?.id) as number;

const net = (code: string): number => r2(Number((db.prepare(`
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS v
  FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
  WHERE jl.voided = 0 AND a.code = ?
`).get(code) as { v: number }).v));

const fundBank = (amount: number): void => {
  const bank = AccountingService.getAccountByCode(db, '1010')!;
  const equity = AccountingService.getAccountByCode(db, '3000')!;
  db.transaction(() => AccountingService.postEntry(db, {
    entry_date: '2026-09-01', description: 'regression funding', reference_type: 'OWNER_CAPITAL', reference_id: 0,
    lines: [{ account_id: bank.id, debit: amount }, { account_id: equity.id, credit: amount }],
  }))();
};

let employeeSeq = 0;
const createEmployee = async (salary: number): Promise<number> => {
  employeeSeq += 1;
  const code = `REG3-${employeeSeq}`;
  const res = await post('/api/employees', {
    first_name: 'Reg', last_name: code, employee_code: code, email: `${code}@example.com`,
    department_id: 1, position: 'Clerk', hire_date: '2026-01-01', salary,
  });
  expect([200, 201]).toContain(res.status);
  return idOf(res);
};

beforeAll(async () => {
  cookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

describe('ACCT-013: reversing a cash inflow must not overdraw cash', () => {
  const spendable = async (amount: number, date: string) => {
    const c = await post('/api/owner-equity/capital', { capital_date: date, amount, payment_method: 'Cash' });
    expect(c.status).toBe(201);
    return idOf(c);
  };

  it('rejects voiding owner capital whose cash has already been withdrawn', async () => {
    const capitalId = await spendable(1000, '2026-09-02');
    const w = await post('/api/owner-equity/withdrawals', { withdrawal_date: '2026-09-03', kind: 'cash', amount: 900, payment_method: 'Cash' });
    expect(w.status).toBe(201);
    const before = net('1000');
    const res = await del(`/api/owner-equity/capital/${capitalId}`, { reason: 'regression' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(net('1000')).toBe(before);
    expect(net('1000')).toBeGreaterThanOrEqual(0);
  });

  it('rejects editing owner capital down below what was already withdrawn', async () => {
    // Uses the bank account, which no earlier test has touched.
    const c = await post('/api/owner-equity/capital', { capital_date: '2026-09-04', amount: 1000, payment_method: 'Bank' });
    expect(c.status).toBe(201);
    const capitalId = idOf(c);
    const w = await post('/api/owner-equity/withdrawals', { withdrawal_date: '2026-09-05', kind: 'cash', amount: 900, payment_method: 'Bank' });
    expect(w.status).toBe(201);
    const before = net('1010');
    const res = await put(`/api/owner-equity/capital/${capitalId}`, { capital_date: '2026-09-04', amount: 100, payment_method: 'Bank' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(net('1010')).toBe(before);
    expect(net('1010')).toBeGreaterThanOrEqual(0);
  });

  it('rejects deleting a customer receipt whose cash has already been spent', async () => {
    const itemId = await createItem('ACCT-013 item', cookie);
    await purchaseStock(itemId, warehouseId, 5, 5, cookie);
    const customerId = await createCustomer('ACCT-013 customer', cookie);
    const invoice = await createInvoice({ customerId, itemId, lines: [{ quantity: 1, unitPrice: 5000 }], invoiceDate: '2026-09-10' }, cookie);
    const pay = await post('/api/payments', {
      customer_id: customerId, payment_date: '2026-09-11', amount: 5000, payment_method: 'cash',
      invoice_allocations: [{ invoice_id: invoice.invoiceId, amount: 5000 }],
    });
    expect(pay.status).toBe(201);
    const paymentId = idOf(pay);
    // Spend everything available, so the receipt's cash is certainly gone
    // (robust to whatever the account held before; the receipt guarantees > 0).
    const available = net('1000');
    expect(available).toBeGreaterThan(0);
    const w = await post('/api/owner-equity/withdrawals', { withdrawal_date: '2026-09-12', kind: 'cash', amount: available, payment_method: 'Cash' });
    expect(w.status).toBe(201);
    const before = net('1000');
    const res = await del(`/api/payments/${paymentId}`);
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(net('1000')).toBe(before);
  });
});

describe('PAY-003: salary and loan payouts respect the funds guard', () => {
  it('rejects a cash salary payment larger than the cash on hand', async () => {
    const employeeId = await createEmployee(1000);
    const before = net('1000');
    const res = await post(`/api/employees/${employeeId}/salary/pay`, {
      amount: 50_000_000, payment_date: '2026-09-05', payment_method: 'cash', payment_type: 'partial',
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(net('1000')).toBe(before);
  });

  it('rejects an employee loan larger than the cash on hand', async () => {
    const employeeId = await createEmployee(1000);
    const before = net('1000');
    const res = await post(`/api/employees/${employeeId}/loans`, {
      amount: 50_000_000, disbursement_date: '2026-09-18', payment_method: 'cash', monthly_installment: 100,
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(net('1000')).toBe(before);
  });
});

describe('PAY-001 / PAY-002: salary overpayment and its auto-advance', () => {
  beforeAll(() => fundBank(500_000));

  it('posts 1,500 once as 1,000 salary and a linked 500 advance receivable', async () => {
    const employeeId = await createEmployee(1000);
    const bankBefore = net('1010');
    const wagesBefore = net('6100');
    const advanceBefore = net('1310');
    const res = await post(`/api/employees/${employeeId}/salary/pay`, {
      amount: 1500, payment_date: '2026-09-10', payment_method: 'bank', payment_type: 'full',
    });
    expect(res.status).toBe(201);
    expect(r2(bankBefore - net('1010'))).toBe(1500);
    expect(r2(net('6100') - wagesBefore)).toBe(1000);
    expect(r2(net('1310') - advanceBefore)).toBe(500);
    const payments = db.prepare('SELECT id, amount, payment_date, parent_payment_id FROM salary_payments WHERE employee_id = ? ORDER BY id')
      .all(employeeId);
    expect(payments).toEqual([
      { id: idOf(res), amount: 1000, payment_date: '2026-09-10', parent_payment_id: null },
      { id: res.body.data.advance_created, amount: 500, payment_date: '2026-09-10', parent_payment_id: idOf(res) },
    ]);
  });

  it('voiding the payment also removes the auto-created advance (nothing left posted)', async () => {
    const employeeId = await createEmployee(1000);
    const bankBefore = net('1010');
    const wagesBefore = net('6100');
    const advanceBefore = net('1310');
    const res = await post(`/api/employees/${employeeId}/salary/pay`, {
      amount: 1500, payment_date: '2026-09-11', payment_method: 'bank', payment_type: 'full',
    });
    expect(res.status).toBe(201);
    const primaryId = idOf(res);
    const voided = await del(`/api/employees/${employeeId}/salary/${primaryId}`);
    expect([200, 204]).toContain(voided.status);
    expect(net('1010')).toBe(bankBefore);
    expect(net('6100')).toBe(wagesBefore);
    expect(net('1310')).toBe(advanceBefore);
    const live = (db.prepare('SELECT COUNT(*) AS n FROM salary_payments WHERE employee_id = ? AND voided_at IS NULL').get(employeeId) as { n: number }).n;
    expect(live).toBe(0);
  });
});

describe('PAY-004: salary-deduction loan repayment keeps the GL in step', () => {
  beforeAll(() => fundBank(500_000));

  it('GL 1300 equals the loan balance after a salary-deduction repayment and after write-off', async () => {
    const employeeId = await createEmployee(1000);
    const glBefore = net('1300');
    const loan = await post(`/api/employees/${employeeId}/loans`, {
      amount: 1000, disbursement_date: '2026-09-12', payment_method: 'bank', purpose: 'regression', monthly_installment: 100,
    });
    expect(loan.status).toBe(201);
    const loanId = idOf(loan);
    const salary = await post(`/api/employees/${employeeId}/salary/pay`, {
      amount: 500, payment_date: '2026-09-15', payment_method: 'bank', payment_type: 'partial',
    });
    expect(salary.status).toBe(201);
    const deduction = await post(`/api/employees/${employeeId}/loans/${loanId}/repay`, {
      amount: 200, payment_date: '2026-09-16', payment_method: 'bank', salary_payment_id: idOf(salary),
    });
    expect(deduction.status).toBe(201);
    const direct = await post(`/api/employees/${employeeId}/loans/${loanId}/repay`, {
      amount: 100, payment_date: '2026-09-17', payment_method: 'bank',
    });
    expect(direct.status).toBe(201);

    const balance = (db.prepare('SELECT balance FROM employee_loans WHERE id = ?').get(loanId) as { balance: number }).balance;
    expect(balance).toBe(700);
    expect(r2(net('1300') - glBefore)).toBe(balance);

    const writeOff = await post(`/api/employees/${employeeId}/loans/${loanId}/write-off`, {});
    expect(writeOff.status).toBe(200);
    expect(r2(net('1300') - glBefore)).toBe(0);
  });
});
