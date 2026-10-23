import { Request, Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import suppliersController from '../controllers/suppliersController';
import DashboardModel from '../models/Dashboard';
import EmployeeModel from '../models/Employee';
import SupplierModel from '../models/Supplier';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `dashboardController.getSummary` (CRAP 72),
 * `employeeController.getEmployees` (CRAP 72) and
 * `suppliersController.getSupplierLedger` (CRAP 72). Covers date/filter
 * fallbacks, sort/page defaults, pagination envelopes, not-found, and the
 * sanitized error paths.
 */
describe('CRAP 72 controller queries', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('dashboard.getSummary', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app).get('/api/dashboard/summary').set('Cookie', cookie).query(query);

    it('passes camelCase dates and omits the range when empty', async () => {
      const spy = jest
        .spyOn(DashboardModel, 'getSummary')
        .mockReturnValue({ totalItems: 1 } as unknown as ReturnType<
          typeof DashboardModel.getSummary
        >);

      const dated = await get({
        fromDate: '2026-01-01',
        toDate: '2026-01-31',
      });
      expect(dated.status).toBe(200);
      expect(dated.body).toEqual({ success: true, data: { totalItems: 1 } });
      expect(spy).toHaveBeenLastCalledWith(
        expect.anything(),
        '2026-01-01',
        '2026-01-31',
      );

      await get();
      expect(spy).toHaveBeenLastCalledWith(
        expect.anything(),
        undefined,
        undefined,
      );
    });

    it('uses snake_case dates as a fallback', async () => {
      const spy = jest
        .spyOn(DashboardModel, 'getSummary')
        .mockReturnValue({} as ReturnType<typeof DashboardModel.getSummary>);

      const res = await get({
        from_date: '2026-02-01',
        to_date: '2026-02-28',
      });

      expect(res.status).toBe(200);
      expect(spy).toHaveBeenLastCalledWith(
        expect.anything(),
        '2026-02-01',
        '2026-02-28',
      );
    });

    it('returns a sanitized 500 when the summary read fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(DashboardModel, 'getSummary').mockImplementation(() => {
        throw new Error('database detail that must not reach the client');
      });

      const res = await get();

      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to fetch dashboard summary' });
    });
  });

  describe('employees.getEmployees', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app).get('/api/employees').set('Cookie', cookie).query(query);

    it('passes filters, sort and pagination and returns the envelope', async () => {
      const spy = jest.spyOn(EmployeeModel, 'getAll').mockReturnValue({
        data: [{ id: 1 }],
        total: 25,
      } as unknown as ReturnType<typeof EmployeeModel.getAll>);

      const res = await get({
        search: 'ali',
        department: 'Ops',
        status: 'inactive',
        sortBy: 'first_name',
        sortOrder: 'DESC',
        page: '2',
        limit: '10',
      });

      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        data: [{ id: 1 }],
        pagination: { page: 2, limit: 10, total: 25, totalPages: 3 },
      });
      expect(spy).toHaveBeenCalledWith(
        expect.anything(),
        { search: 'ali', department: 'Ops', status: 'inactive' },
        'first_name',
        'DESC',
        2,
        10,
      );
    });

    it('defaults sort and pagination for missing or invalid values', async () => {
      const spy = jest.spyOn(EmployeeModel, 'getAll').mockReturnValue({
        data: [],
        total: 0,
      } as unknown as ReturnType<typeof EmployeeModel.getAll>);

      const res = await get({ page: 'abc', limit: '0' });

      expect(res.status).toBe(200);
      expect(res.body.pagination).toEqual({
        page: 1,
        limit: 20,
        total: 0,
        totalPages: 0,
      });
      expect(spy).toHaveBeenCalledWith(
        expect.anything(),
        { search: undefined, department: undefined, status: undefined },
        'employee_code',
        'ASC',
        1,
        20,
      );
    });

    it('returns a sanitized 500 when the employee read fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(EmployeeModel, 'getAll').mockImplementation(() => {
        throw new Error('database detail that must not reach the client');
      });

      const res = await get();

      expect(res.status).toBe(500);
      expect(res.body).toEqual({
        success: false,
        error: 'Failed to fetch employees',
      });
    });
  });

  describe('suppliers.getSupplierLedger', () => {
    const get = (id: string, query: Record<string, string> = {}) =>
      request(app)
        .get(`/api/suppliers/${id}/ledger`)
        .set('Cookie', cookie)
        .query(query);

    it('returns 404 for an unknown supplier', async () => {
      jest.spyOn(SupplierModel, 'getById').mockReturnValue(undefined);

      const res = await get('999999');

      expect(res.status).toBe(404);
      expect(res.body).toEqual({
        success: false,
        error: 'Supplier not found',
      });
    });

    it('returns a dated, sorted, paginated ledger', async () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      const ledger = jest.spyOn(SupplierModel, 'getLedger').mockReturnValue({
        rows: [{ id: 10 }],
        total: 2,
      } as unknown as ReturnType<typeof SupplierModel.getLedger>);

      const res = await get('1', {
        sortBy: 'transaction_date',
        sortOrder: 'ASC',
        fromDate: '2026-01-01',
        toDate: '2026-01-31',
        page: '2',
        limit: '1',
      });

      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        data: [{ id: 10 }],
        pagination: { page: 2, limit: 1, total: 2, total_pages: 2 },
      });
      expect(ledger).toHaveBeenCalledWith(
        1,
        'transaction_date',
        'ASC',
        expect.anything(),
        2,
        1,
        '2026-01-01',
        '2026-01-31',
      );
    });

    it('uses ledger sort and page defaults and drops absent dates', async () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      const ledger = jest
        .spyOn(SupplierModel, 'getLedger')
        .mockReturnValue({ rows: [], total: 0 } as unknown as ReturnType<
          typeof SupplierModel.getLedger
        >);

      const res = await get('1');

      expect(res.status).toBe(200);
      expect(ledger).toHaveBeenCalledWith(
        1,
        'transaction_date',
        'DESC',
        expect.anything(),
        1,
        100,
        undefined,
        undefined,
      );
    });

    it('falls back to the safe ledger sort for invalid parameters', async () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      const ledger = jest
        .spyOn(SupplierModel, 'getLedger')
        .mockReturnValue({ rows: [], total: 0 } as unknown as ReturnType<
          typeof SupplierModel.getLedger
        >);

      await get('1', {
        sortBy: 'transaction_date; DROP TABLE x',
        sortOrder: 'sideways',
      });

      expect(ledger).toHaveBeenCalledWith(
        1,
        'transaction_date',
        'DESC',
        expect.anything(),
        1,
        100,
        undefined,
        undefined,
      );
    });

    it('accepts an array route param through the controller helper', () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      jest
        .spyOn(SupplierModel, 'getLedger')
        .mockReturnValue({ rows: [], total: 0 } as unknown as ReturnType<
          typeof SupplierModel.getLedger
        >);
      const status = jest.fn();
      const json = jest.fn();
      const res = { status, json } as unknown as Response;
      status.mockReturnValue(res);

      suppliersController.getSupplierLedger(
        { params: { id: ['1'] }, query: {} } as unknown as Request,
        res,
      );

      expect(json).toHaveBeenCalledWith(
        expect.objectContaining({ success: true }),
      );
    });

    it('returns a sanitized 500 when the ledger read fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      jest.spyOn(SupplierModel, 'getLedger').mockImplementation(() => {
        throw new Error('database detail that must not reach the client');
      });

      const res = await get('1');

      expect(res.status).toBe(500);
      expect(res.body).toEqual({
        success: false,
        error: 'Failed to fetch supplier ledger',
      });
    });
  });
});
