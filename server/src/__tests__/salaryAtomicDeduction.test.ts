import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

describe('Salary deduction is one idempotent transaction', () => {
  let cookie: string;
  let employeeId: number;
  let loanId: number;
  const post = (url: string, body: object) => request(app).post(url).set('Cookie', cookie).send(body);
  beforeAll(async () => {
    cookie = await getAuthCookie();
    const capital = await post('/api/owner-equity/capital', { capital_date: '2026-09-01', amount: 10000, payment_method: 'Cash' });
    expect(capital.status).toBe(201);
    const employee = await post('/api/employees', {
      first_name: 'Atomic', last_name: 'Deduction', employee_code: 'ATOMIC-DEDUCT',
      department_id: 1, position: 'Clerk', hire_date: '2026-01-01', salary: 1000,
    });
    expect(employee.status).toBe(201);
    employeeId = employee.body.data.id;
    const loan = await post(`/api/employees/${employeeId}/loans`, {
      amount: 500, disbursement_date: '2026-09-02', payment_method: 'cash', monthly_installment: 100,
    });
    expect(loan.status).toBe(201);
    loanId = loan.body.data.id;
  });

  it('records a linked deduction once and salary void restores the loan', async () => {
    const body = { amount: 1000, loan_deduction: 100, loan_id: loanId, payment_date: '2026-09-05', payment_method: 'cash', payment_type: 'partial' };
    const url = `/api/employees/${employeeId}/salary/pay`;
    const paid = await request(app).post(url).set('Cookie', cookie).set('Idempotency-Key', 'atomic-salary-deduction').send(body);
    expect(paid.status).toBe(201);
    const paymentId = paid.body.data.id;
    const retry = await request(app).post(url).set('Cookie', cookie).set('Idempotency-Key', 'atomic-salary-deduction').send(body);
    expect(retry.status).toBe(201);
    expect(db.prepare('SELECT balance FROM employee_loans WHERE id = ?').get(loanId)).toEqual({ balance: 400 });
    expect(db.prepare('SELECT amount, salary_payment_id FROM employee_loan_repayments WHERE loan_id = ?').all(loanId))
      .toEqual([{ amount: 100, salary_payment_id: paymentId }]);
    const voided = await request(app).delete(`/api/employees/${employeeId}/salary/${paymentId}`).set('Cookie', cookie).send({ reason: 'Regression correction' });
    expect(voided.status).toBe(204);
    expect(db.prepare('SELECT balance FROM employee_loans WHERE id = ?').get(loanId)).toEqual({ balance: 500 });
  });

  it('invalid deduction rolls back salary, GL and retry-key claim', async () => {
    const before = db.prepare('SELECT COUNT(*) AS count FROM salary_payments').get();
    const journalBefore = db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get();
    const result = await request(app).post(`/api/employees/${employeeId}/salary/pay`).set('Cookie', cookie)
      .set('Idempotency-Key', 'invalid-atomic-deduction').send({ amount: 1000, loan_deduction: 600, loan_id: loanId, payment_date: '2026-09-06', payment_method: 'cash', payment_type: 'partial' });
    expect(result.status).toBe(400);
    expect(db.prepare('SELECT COUNT(*) AS count FROM salary_payments').get()).toEqual(before);
    expect(db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get()).toEqual(journalBefore);
    expect(db.prepare('SELECT COUNT(*) AS count FROM idempotency_keys WHERE key LIKE ?').get('%invalid-atomic-deduction')).toEqual({ count: 0 });
  });
});
