import { Request, Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import employeeController from '../controllers/employeeController';
import { AccountingService } from '../services/accountingService';
import { EmployeeLoanModel } from '../models/EmployeeLoan';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `employeeController.deleteLoan` (CRAP 42).
 * Covers not-found, already-voided, repayment-history, success, array params
 * and the sanitized failure path.
 */
describe('employeeController.deleteLoan', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const del = () =>
    request(app)
      .delete('/api/employees/1/loans/2')
      .set('Cookie', cookie);

  const activeLoan = { id: 2, voided_at: null } as ReturnType<
    typeof EmployeeLoanModel.getById
  >;

  it('returns 404 for an unknown loan', async () => {
    jest.spyOn(EmployeeLoanModel, 'getById').mockReturnValue(undefined);

    const res = await del();

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ success: false, error: 'Loan not found' });
  });

  it('returns 409 for an already-voided loan', async () => {
    jest
      .spyOn(EmployeeLoanModel, 'getById')
      .mockReturnValue({ ...activeLoan!, voided_at: '2026-01-01' });

    const res = await del();

    expect(res.status).toBe(409);
    expect(res.body).toEqual({
      success: false,
      error: 'Loan is already voided',
    });
  });

  it('returns 409 when repayments exist', async () => {
    jest.spyOn(EmployeeLoanModel, 'getById').mockReturnValue(activeLoan);
    jest.spyOn(EmployeeLoanModel, 'hasRepayments').mockReturnValue(true);

    const res = await del();

    expect(res.status).toBe(409);
    expect(res.body).toEqual({
      success: false,
      error: 'Cannot delete loan with repayment history',
    });
  });

  it('voids the loan and its disbursement journal', async () => {
    jest.spyOn(EmployeeLoanModel, 'getById').mockReturnValue(activeLoan);
    jest.spyOn(EmployeeLoanModel, 'hasRepayments').mockReturnValue(false);
    const voidLines = jest
      .spyOn(AccountingService, 'voidJournalLinesByReference')
      .mockReturnValue(0);
    const remove = jest
      .spyOn(EmployeeLoanModel, 'delete')
      .mockImplementation(() => {});

    const res = await del();

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true });
    expect(voidLines).toHaveBeenCalledWith(
      expect.anything(),
      'LOAN_DISBURSEMENT',
      2,
      expect.objectContaining({ voidReason: 'Loan deleted' }),
    );
    expect(remove).toHaveBeenCalledWith(
      2,
      expect.anything(),
      expect.anything(),
      'Loan deleted',
    );
  });

  it('accepts an array route param through the controller helper', () => {
    jest.spyOn(EmployeeLoanModel, 'getById').mockReturnValue(undefined);
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    employeeController.deleteLoan(
      {
        params: { id: '1', loanId: ['2'] },
        user: { id: 1 },
      } as unknown as Request,
      res,
    );

    expect(status).toHaveBeenCalledWith(404);
  });

  it('deletes an anonymous loan without a user id', () => {
    jest.spyOn(EmployeeLoanModel, 'getById').mockReturnValue(activeLoan);
    jest.spyOn(EmployeeLoanModel, 'hasRepayments').mockReturnValue(false);
    jest
      .spyOn(AccountingService, 'voidJournalLinesByReference')
      .mockReturnValue(0);
    const remove = jest
      .spyOn(EmployeeLoanModel, 'delete')
      .mockImplementation(() => {});
    const json = jest.fn();
    const status = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    employeeController.deleteLoan(
      { params: { id: '1', loanId: '2' } } as unknown as Request,
      res,
    );

    expect(json).toHaveBeenCalledWith({ success: true });
    expect(remove).toHaveBeenCalledWith(
      2,
      expect.anything(),
      null,
      'Loan deleted',
    );
  });

  it('returns a sanitized 500 when the loan read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(EmployeeLoanModel, 'getById').mockImplementation(() => {
      throw new Error('forced loan failure');
    });

    const res = await del();

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to delete loan' });
  });
});
