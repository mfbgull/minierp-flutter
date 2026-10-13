import { afterEach, beforeAll, beforeEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { collectFlows } from '../services/cashService';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

let cookie: string;
let employeeId: number;

interface CreatedPayment {
  readonly id: number;
  readonly advance_created: number | null;
}

const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);

function net(code: string): number {
  return db.prepare<[string], { amount: number }>(`
    SELECT ROUND(COALESCE(SUM(j.debit - j.credit), 0), 2) AS amount
    FROM journal_lines j JOIN chart_of_accounts a ON a.id = j.account_id
    WHERE a.code = ? AND j.voided = 0
  `).get(code)?.amount ?? 0;
}

function records() {
  return {
    salary: db.prepare('SELECT * FROM salary_payments ORDER BY id').all(),
    loans: db.prepare('SELECT * FROM employee_loans ORDER BY id').all(),
    repayments: db.prepare('SELECT * FROM employee_loan_repayments ORDER BY id').all(),
    lines: db.prepare('SELECT * FROM journal_lines ORDER BY id').all(),
  };
}

async function salary(amount: number): Promise<CreatedPayment> {
  const response = await post(`/api/employees/${employeeId}/salary/pay`, {
    amount, payment_date: '2026-09-10', payment_method: 'bank', payment_type: 'partial',
  });
  expect(response.status).toBe(201);
  const body: { data: CreatedPayment } = response.body;
  return body.data;
}

async function loan(): Promise<number> {
  const response = await post(`/api/employees/${employeeId}/loans`, {
    amount: 1000, disbursement_date: '2026-09-05', payment_method: 'bank',
  });
  expect(response.status).toBe(201);
  const body: { data: { id: number } } = response.body;
  return body.data.id;
}

beforeAll(async () => { cookie = await getAuthCookie(); });
beforeEach(async () => {
  db.exec('SAVEPOINT payroll_case');
  const funding = await post('/api/owner-equity/capital', {
    amount: 10000, capital_date: '2026-09-01', payment_method: 'Bank',
  });
  expect(funding.status).toBe(201);
  const employee = await post('/api/employees', {
    employee_code: 'PAY-LIFECYCLE', first_name: 'Pay', last_name: 'Lifecycle', salary: 1000,
  });
  expect(employee.status).toBe(201);
  const body: { data: { id: number } } = employee.body;
  employeeId = body.data.id;
});
afterEach(() => { db.exec('ROLLBACK TO payroll_case; RELEASE payroll_case'); });

describe('payroll recovery lifecycle', () => {
  it('only advances the new excess across repeated partial payments', async () => {
    await salary(800);
    await salary(700);
    await salary(200);

    expect(net('1010')).toBe(8300);
    expect(net('6100')).toBe(1000);
    expect(net('1310')).toBe(700);
    expect(db.prepare('SELECT SUM(amount) AS total FROM salary_payments').get()).toEqual({ total: 1700 });
    expect(collectFlows(db, '2026-09-30').get('bank')?.outflow).toBe(1700);
  });

  it('rejects voiding an advance independently of its parent', async () => {
    const paid = await salary(1500);
    const before = records();

    const response = await request(app).delete(`/api/employees/${employeeId}/salary/${paid.advance_created}`)
      .set('Cookie', cookie);

    expect(response.status).toBe(409);
    expect(records()).toEqual(before);
  });

  it('replays an overpayment without duplicating either linked row', async () => {
    const payload = { amount: 1500, payment_date: '2026-09-10', payment_method: 'bank', payment_type: 'partial' };
    const first = await request(app).post(`/api/employees/${employeeId}/salary/pay`)
      .set('Cookie', cookie).set('Idempotency-Key', 'payroll-linked-retry').send(payload);
    expect(first.status).toBe(201);
    const before = records();

    const repeated = await request(app).post(`/api/employees/${employeeId}/salary/pay`)
      .set('Cookie', cookie).set('Idempotency-Key', 'payroll-linked-retry').send(payload);

    expect(repeated.status).toBe(201);
    expect(repeated.headers['x-idempotent-replay']).toBe('true');
    expect(records()).toEqual(before);
  });

  it('rolls back the primary salary when its advance cannot be funded', async () => {
    const before = records();

    const response = await post(`/api/employees/${employeeId}/salary/pay`, {
      amount: 10000.01, payment_date: '2026-09-10', payment_method: 'bank', payment_type: 'partial',
    });

    expect(response.status).toBe(400);
    expect(records()).toEqual(before);
  });

  it('rejects a loan that exceeds funds by one cent without writing records', async () => {
    const before = records();

    const response = await post(`/api/employees/${employeeId}/loans`, {
      amount: 10000.01, disbursement_date: '2026-09-10', payment_method: 'bank',
    });

    expect(response.status).toBe(400);
    expect(records()).toEqual(before);
  });

  it('posts a deduction to cash reports and reverses it with the salary', async () => {
    const loanId = await loan();
    const paid = await salary(500);
    const deducted = await post(`/api/employees/${employeeId}/loans/${loanId}/repay`, {
      amount: 200, payment_date: '2026-09-10', salary_payment_id: paid.id,
    });
    expect(deducted.status).toBe(201);
    expect(net('1010')).toBe(8700);
    expect(net('1300')).toBe(800);
    expect(collectFlows(db, '2026-09-30').get('bank')).toEqual({ inflow: 10200, outflow: 1500 });

    const response = await request(app).delete(`/api/employees/${employeeId}/salary/${paid.id}`)
      .set('Cookie', cookie);

    expect(response.status).toBe(204);
    expect(net('1010')).toBe(9000);
    expect(net('1300')).toBe(1000);
    expect(db.prepare('SELECT balance FROM employee_loans WHERE id = ?').get(loanId)).toEqual({ balance: 1000 });
    expect(db.prepare('SELECT COUNT(*) AS n FROM employee_loan_repayments WHERE voided_at IS NULL').get()).toEqual({ n: 0 });
  });

  it('reverses the GL when a salary deduction is voided independently', async () => {
    const loanId = await loan();
    const paid = await salary(500);
    const deducted = await post(`/api/employees/${employeeId}/loans/${loanId}/repay`, {
      amount: 200, payment_date: '2026-09-10', salary_payment_id: paid.id,
    });
    expect(deducted.status).toBe(201);
    const body: { data: { id: number } } = deducted.body;

    const response = await post(`/api/employees/${employeeId}/loans/${loanId}/repayments/${body.data.id}/void`, {});

    expect(response.status).toBe(200);
    expect(net('1010')).toBe(8500);
    expect(net('1300')).toBe(1000);
  });

  it('rejects deductions exceeding the linked salary across multiple loans', async () => {
    const loanId = await loan();
    const secondLoan = await loan();
    const paid = await salary(500);
    const first = await post(`/api/employees/${employeeId}/loans/${loanId}/repay`, {
      amount: 400, payment_date: '2026-09-10', salary_payment_id: paid.id,
    });
    expect(first.status).toBe(201);
    const before = records();

    const response = await post(`/api/employees/${employeeId}/loans/${secondLoan}/repay`, {
      amount: 200, payment_date: '2026-09-10', salary_payment_id: paid.id,
    });

    expect(response.status).toBe(400);
    expect(records()).toEqual(before);
  });
});
