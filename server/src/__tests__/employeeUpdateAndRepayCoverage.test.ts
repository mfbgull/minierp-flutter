import { afterEach, beforeAll, beforeEach, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import EmployeeModel from '../models/Employee';
import EmployeeLoanModel from '../models/EmployeeLoan';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `employeeController.updateEmployee` (CRAP 110)
 * and the repayment guard branches of `repayLoan` (CRAP 32.2).
 */
describe('employee update and loan repayment guards', () => {
  let cookie = '';
  let employeeId = 0;
  let loanId = 0;
  let seq = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  beforeEach(() => {
    seq += 1;
    employeeId = Number(
      db
        .prepare(
          `INSERT INTO employees (employee_code, first_name, last_name, salary)
           VALUES (?, 'Cover', 'Age', 1000)`
        )
        .run(`EMP-COV-${Date.now()}-${seq}`).lastInsertRowid
    );
    loanId = Number(
      db
        .prepare(
          `INSERT INTO employee_loans
             (employee_id, amount, balance, payment_method, disbursement_date, status)
           VALUES (?, 1000, 1000, 'cash', '2026-09-01', 'active')`
        )
        .run(employeeId).lastInsertRowid
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('updateEmployee', () => {
    const update = (id: number | string, body: Record<string, unknown>) =>
      request(app).put(`/api/employees/${id}`).set('Cookie', cookie).send(body);

    it('returns 404 for an unknown employee', async () => {
      expect((await update(999999, { first_name: 'X' })).status).toBe(404);
    });

    it('rejects an invalid email', async () => {
      const res = await update(employeeId, { email: 'not-an-email' });
      expect(res.status).toBe(422);
      expect(res.body).toEqual({ success: false, error: 'Invalid email format' });
    });

    it('returns 404 when the update affects no row', async () => {
      jest
        .spyOn(EmployeeModel, 'update')
        .mockReturnValue({ changes: 0, lastInsertRowid: 0 });

      const res = await update(employeeId, { first_name: 'Ghost' });
      expect(res.status).toBe(404);
      expect(res.body).toEqual({ success: false, error: 'Employee not found' });
    });

    it('applies the update and returns the fresh row', async () => {
      const res = await update(employeeId, { first_name: 'Renamed', email: 'ok@example.com' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.first_name).toBe('Renamed');
      expect(res.body.data.email).toBe('ok@example.com');
    });

    it('returns a sanitized 500 when the update fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(EmployeeModel, 'update').mockImplementation(() => {
        throw new Error('forced update failure');
      });

      const res = await update(employeeId, { first_name: 'Boom' });
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ success: false, error: 'Failed to update employee' });
    });
  });

  describe('repayLoan guards', () => {
    const repay = (pathEmployee: number, pathLoan: number, body: Record<string, unknown>) =>
      request(app)
        .post(`/api/employees/${pathEmployee}/loans/${pathLoan}/repay`)
        .set('Cookie', cookie)
        .send(body);

    it('returns 404 for a missing, foreign or voided loan', async () => {
      expect((await repay(employeeId, 999999, { amount: 100 })).status).toBe(404);

      const other = Number(
        db
          .prepare(
            `INSERT INTO employees (employee_code, first_name, last_name, salary)
             VALUES (?, 'Other', 'Person', 1000)`
          )
          .run(`EMP-OTHER-${Date.now()}`).lastInsertRowid
      );
      expect((await repay(other, loanId, { amount: 100 })).status).toBe(404);

      db.prepare(`UPDATE employee_loans SET voided_at = '2026-09-02' WHERE id = ?`).run(loanId);
      expect((await repay(employeeId, loanId, { amount: 100 })).status).toBe(404);
    });

    it('rejects a completed loan', async () => {
      db.prepare(`UPDATE employee_loans SET status = 'completed' WHERE id = ?`).run(loanId);

      const res = await repay(employeeId, loanId, { amount: 100 });
      expect(res.status).toBe(409);
      expect(res.body).toEqual({ success: false, error: 'Loan is not active' });
    });

    it('validates amount, method, balance and date', async () => {
      const badAmount = await repay(employeeId, loanId, { amount: 0 });
      expect(badAmount.status).toBe(422);
      expect(badAmount.body).toEqual({ success: false, error: 'Valid amount is required' });

      const badMethod = await repay(employeeId, loanId, {
        amount: 100,
        payment_method: 'Barter',
      });
      expect(badMethod.status).toBe(422);
      expect(badMethod.body.error).toContain('Invalid payment_method');

      const tooMuch = await repay(employeeId, loanId, { amount: 5000 });
      expect(tooMuch.status).toBe(422);
      expect(tooMuch.body).toEqual({ success: false, error: 'Repayment exceeds loan balance' });

      const noDate = await repay(employeeId, loanId, { amount: 100 });
      expect(noDate.status).toBe(422);
      expect(noDate.body).toEqual({ success: false, error: 'Payment date is required' });
    });
  });
});
