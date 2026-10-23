import { Request, Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import suppliersController from '../controllers/suppliersController';
import CustomerModel from '../models/Customer';
import SupplierModel from '../models/Supplier';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — the single-party statement controllers
 * (`suppliersController.getSupplierStatement` CRAP 90 and
 * `customersController.getCustomerStatement` CRAP 72). Covers not-found,
 * dated/undated periods, running balances over debit/credit rows, and the
 * sanitized error path.
 */
describe('statement controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('supplier statement', () => {
    const get = (id: string, query: Record<string, string> = {}) =>
      request(app)
        .get(`/api/suppliers/${id}/statement`)
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

    it('computes opening and closing balances for a dated period', async () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      const statement = jest
        .spyOn(SupplierModel, 'getStatement')
        .mockReturnValue({
          openingBalance: 100,
          transactions: [
            { debit: 50, credit: 20 },
            { debit: null, credit: 10 },
            { debit: 5, credit: 0 },
          ],
        } as unknown as ReturnType<typeof SupplierModel.getStatement>);

      const res = await get('1', {
        fromDate: '2026-01-01',
        toDate: '2026-01-31',
      });

      expect(res.status).toBe(200);
      expect(res.body.data).toMatchObject({
        supplier: { id: 1, supplier_name: 'Acme' },
        period: { fromDate: '2026-01-01', toDate: '2026-01-31' },
        openingBalance: 100,
        closingBalance: 125,
      });
      expect(res.body.data.transactions).toHaveLength(3);
      expect(statement).toHaveBeenCalledWith(
        1,
        '2026-01-01',
        '2026-01-31',
        expect.anything(),
      );
    });

    it('uses a null period when no dates are supplied', async () => {
      jest
        .spyOn(SupplierModel, 'getById')
        .mockReturnValue({
          id: 1,
          supplier_name: 'Acme',
        } as ReturnType<typeof SupplierModel.getById>);
      const statement = jest
        .spyOn(SupplierModel, 'getStatement')
        .mockReturnValue({
          openingBalance: 10,
          transactions: [],
        } as unknown as ReturnType<typeof SupplierModel.getStatement>);

      const res = await get('1');

      expect(res.status).toBe(200);
      expect(res.body.data.period).toEqual({ fromDate: null, toDate: null });
      expect(statement).toHaveBeenCalledWith(
        1,
        undefined,
        undefined,
        expect.anything(),
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
        .spyOn(SupplierModel, 'getStatement')
        .mockReturnValue({
          openingBalance: 0,
          transactions: [],
        } as unknown as ReturnType<typeof SupplierModel.getStatement>);
      const status = jest.fn();
      const json = jest.fn();
      const res = { status, json } as unknown as Response;
      status.mockReturnValue(res);

      suppliersController.getSupplierStatement(
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
      jest.spyOn(SupplierModel, 'getStatement').mockImplementation(() => {
        throw new Error('database detail that must not reach the client');
      });

      const res = await get('1');

      expect(res.status).toBe(500);
      expect(res.body).toEqual({
        success: false,
        error: 'Failed to fetch supplier statement',
      });
    });
  });

  describe('customer statement', () => {
    const get = (id: string, query: Record<string, string> = {}) =>
      request(app)
        .get(`/api/customers/${id}/statement`)
        .set('Cookie', cookie)
        .query(query);

    it('returns 404 for an unknown customer', async () => {
      jest.spyOn(CustomerModel, 'getById').mockReturnValue(undefined);

      const res = await get('999999');

      expect(res.status).toBe(404);
      expect(res.body).toEqual({
        success: false,
        error: 'Customer not found',
      });
    });

    it('computes the closing balance from string debit/credit rows', async () => {
      jest
        .spyOn(CustomerModel, 'getById')
        .mockReturnValue({
          id: 42,
          customer_name: 'Beta',
        } as ReturnType<typeof CustomerModel.getById>);
      const statement = jest
        .spyOn(CustomerModel, 'getStatement')
        .mockReturnValue({
          openingBalance: 25.5,
          transactions: [
            { debit: '10.5', credit: '0' },
            { debit: '0', credit: '5' },
            { debit: 0, credit: 0 },
          ],
        } as unknown as ReturnType<typeof CustomerModel.getStatement>);

      const res = await get('42');

      expect(res.status).toBe(200);
      expect(res.body.data).toMatchObject({
        customer: { id: 42, customer_name: 'Beta' },
        openingBalance: 25.5,
        closingBalance: 31,
      });
      expect(statement).toHaveBeenCalledWith(
        '42',
        undefined,
        undefined,
        expect.anything(),
      );
    });

    it('returns a sanitized 500 when the ledger read fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest
        .spyOn(CustomerModel, 'getById')
        .mockReturnValue({
          id: 42,
          customer_name: 'Beta',
        } as ReturnType<typeof CustomerModel.getById>);
      jest.spyOn(CustomerModel, 'getStatement').mockImplementation(() => {
        throw new Error('database detail that must not reach the client');
      });

      const res = await get('42');

      expect(res.status).toBe(500);
      expect(res.body).toEqual({
        success: false,
        error: 'Failed to fetch customer statement',
      });
    });
  });
});
