import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import OwnerCapitalModel from '../models/OwnerCapital';
import OwnerWithdrawalModel from '../models/OwnerWithdrawal';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `ownerEquityController.getCapitalList` and
 * `getWithdrawalList` (CRAP 42 each). Covers defaults, filters, sorting,
 * pagination, and the failure path.
 */
describe('owner equity list controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('getCapitalList', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app)
        .get('/api/owner-equity/capital')
        .set('Cookie', cookie)
        .query(query);

    it('uses list defaults and returns the pagination envelope', async () => {
      jest.spyOn(OwnerCapitalModel, 'getAll').mockReturnValue([
        { id: 1 },
      ] as ReturnType<typeof OwnerCapitalModel.getAll>);
      const count = jest
        .spyOn(OwnerCapitalModel, 'getCount')
        .mockReturnValue(3);

      const res = await get();

      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        data: [{ id: 1 }],
        pagination: {
          currentPage: 1,
          totalPages: 1,
          totalItems: 3,
          hasNext: false,
          hasPrev: false,
        },
      });
      expect(count).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          page: 1,
          limit: 10,
          sortBy: 'oc.capital_date',
          sortOrder: 'DESC',
        }),
      );
    });

    it('passes filters and pagination through', async () => {
      const list = jest
        .spyOn(OwnerCapitalModel, 'getAll')
        .mockReturnValue([] as ReturnType<typeof OwnerCapitalModel.getAll>);
      jest.spyOn(OwnerCapitalModel, 'getCount').mockReturnValue(12);

      const res = await get({
        page: '2',
        limit: '5',
        status: 'posted',
        from_date: '2026-01-01',
        to_date: '2026-01-31',
        search: 'capital',
        sortBy: 'oc.amount',
        sortOrder: 'ASC',
      });

      expect(res.status).toBe(200);
      expect(res.body.pagination).toMatchObject({
        currentPage: 2,
        totalPages: 3,
        totalItems: 12,
        hasNext: true,
        hasPrev: true,
      });
      expect(list).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          page: 2,
          limit: 5,
          status: 'posted',
          from_date: '2026-01-01',
          to_date: '2026-01-31',
          search: 'capital',
          sortBy: 'oc.amount',
          sortOrder: 'ASC',
        }),
      );
    });

    it('returns a sanitized 500 when the list fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(OwnerCapitalModel, 'getAll').mockImplementation(() => {
        throw new Error('forced capital failure');
      });

      const res = await get();
      expect(res.status).toBe(500);
    });
  });

  describe('getWithdrawalList', () => {
    const get = (query: Record<string, string> = {}) =>
      request(app)
        .get('/api/owner-equity/withdrawals')
        .set('Cookie', cookie)
        .query(query);

    it('uses list defaults and passes the kind filter', async () => {
      const list = jest
        .spyOn(OwnerWithdrawalModel, 'getAll')
        .mockReturnValue([] as ReturnType<typeof OwnerWithdrawalModel.getAll>);
      jest.spyOn(OwnerWithdrawalModel, 'getCount').mockReturnValue(1);

      const res = await get({ kind: 'goods' });

      expect(res.status).toBe(200);
      expect(res.body.pagination).toEqual({
        currentPage: 1,
        totalPages: 1,
        totalItems: 1,
        hasNext: false,
        hasPrev: false,
      });
      expect(list).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          page: 1,
          limit: 10,
          kind: 'goods',
          sortBy: 'ow.withdrawal_date',
          sortOrder: 'DESC',
        }),
      );
    });

    it('returns a sanitized 500 when the list fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(OwnerWithdrawalModel, 'getAll').mockImplementation(() => {
        throw new Error('forced withdrawal failure');
      });

      const res = await get();
      expect(res.status).toBe(500);
    });
  });
});
