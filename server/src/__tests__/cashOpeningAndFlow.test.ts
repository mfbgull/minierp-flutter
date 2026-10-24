import { Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import dashboardController from '../controllers/dashboardController';
import ReportsModel from '../models/Reports';
import { AuthRequest } from '../types';
import * as cashService from '../services/cashService';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `dashboardController.saveCashOpeningBalances`
 * and `reportsController.getCashFlowReport` (CRAP 42 each). Covers guards,
 * success, date requirements, and sanitized failures.
 */
describe('cash-opening and cash-flow controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('saveCashOpeningBalances', () => {
    const put = (body: Record<string, unknown>) =>
      request(app)
        .put('/api/dashboard/cash-opening-balances')
        .set('Cookie', cookie)
        .send(body);

    it('rejects missing or non-array accounts at the controller guard', () => {
      for (const accounts of [undefined, 'cash']) {
        const status = jest.fn();
        const json = jest.fn();
        const res = { status, json } as unknown as Response;
        status.mockReturnValue(res);
        dashboardController.saveCashOpeningBalances(
          { body: { accounts }, user: { id: 1 } } as unknown as AuthRequest,
          res,
        );
        expect(status).toHaveBeenCalledWith(400);
      }
    });

    it('rejects an unknown account key through the route', async () => {
      const res = await put({ accounts: [{ key: 'bogus', amount: 1 }] });
      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Unknown account key: bogus');
    });

    it('saves known keys and returns every tracked account', async () => {
      const save = jest
        .spyOn(cashService, 'saveOpeningBalance')
        .mockReturnValue(new Map());
      const sync = jest
        .spyOn(cashService, 'syncOpeningBalancesToGl')
        .mockImplementation(() => {});
      jest.spyOn(cashService, 'getOpeningBalances').mockReturnValue(
        new Map([
          ['cash', 100],
          ['bank', 200],
        ]),
      );

      const res = await put({
        accounts: [
          { key: 'cash', amount: 0 },
          { key: 'bank', amount: 200 },
        ],
      });

      expect(res.status).toBe(200);
      expect(res.body.data.accounts).toHaveLength(5);
      expect(res.body.data.accounts[0]).toEqual({
        key: 'cash',
        name: 'Cash',
        amount: 100,
      });
      expect(save).toHaveBeenCalledWith(expect.anything(), 'cash', 0);
      expect(save).toHaveBeenCalledTimes(2);
      expect(sync).toHaveBeenCalledWith(expect.anything(), expect.any(Number));
    });

    it('returns a sanitized 500 when the transaction fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest
        .spyOn(cashService, 'saveOpeningBalance')
        .mockImplementation(() => {
          throw new Error('forced save failure');
        });

      const res = await put({ accounts: [{ key: 'cash', amount: 1 }] });

      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to save cash opening balances' });
    });
  });

  describe('getCashFlowReport', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app).get('/api/reports/cash-flow').set('Cookie', cookie).query(query);

    it('requires both report dates', async () => {
      expect((await get()).status).toBe(400);
      const fromOnly = await get({ fromDate: '2026-01-01' });
      expect(fromOnly.status).toBe(400);
      expect(fromOnly.body.error).toBe('fromDate and toDate are required');
    });

    it('returns the cash-flow report for a complete range', async () => {
      const flow = { net: 10 };
      const spy = jest
        .spyOn(ReportsModel, 'getCashFlow')
        .mockReturnValue(flow as unknown as ReturnType<
          typeof ReportsModel.getCashFlow
        >);

      const res = await get({
        fromDate: '2026-01-01',
        toDate: '2026-01-31',
      });

      expect(res.status).toBe(200);
      expect(res.body).toEqual({ success: true, data: flow });
      expect(spy).toHaveBeenCalledWith(
        '2026-01-01',
        '2026-01-31',
        expect.anything(),
      );
    });

    it('returns a sanitized 500 when the report fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(ReportsModel, 'getCashFlow').mockImplementation(() => {
        throw new Error('forced report failure');
      });

      const res = await get({
        fromDate: '2026-01-01',
        toDate: '2026-01-31',
      });

      expect(res.status).toBe(500);
      expect(res.body).toEqual({
        success: false,
        error: 'Failed to fetch cash flow report',
      });
    });
  });
});
