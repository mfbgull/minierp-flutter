import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import ReportsModel from '../models/Reports';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `reportsController.getCustomerStatements`
 * (CRAP 110). The controller owns four query fallbacks plus the success and
 * error response paths; the report model itself is covered elsewhere. Mocking
 * the model isolates and exercises every controller branch through the
 * mounted route.
 */
describe('reportsController.getCustomerStatements', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const get = (query: Record<string, string>) =>
    request(app)
      .get('/api/reports/customer-statements')
      .set('Cookie', cookie)
      .query(query);

  it('passes explicit start/end dates and a numeric customer id', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue({ statements: [] });

    const res = await get({
      customerId: '7',
      startDate: '2026-01-01',
      endDate: '2026-01-31',
    });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, data: { statements: [] } });
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      7,
      '2026-01-01',
      '2026-01-31',
    );
  });

  it('falls back to fromDate/toDate and defaults a missing customer to 0', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue({ statements: [] });

    const res = await get({
      fromDate: '2026-02-01',
      toDate: '2026-02-28',
    });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      0,
      '2026-02-01',
      '2026-02-28',
    );
  });

  it('keeps a lone start date and leaves a missing end date undefined', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue({ statements: [] });

    const res = await get({ startDate: '2026-03-01' });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      0,
      '2026-03-01',
      undefined,
    );
  });

  it('keeps a lone end date and leaves a missing start date undefined', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue({ statements: [] });

    const res = await get({ endDate: '2026-03-31' });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      0,
      undefined,
      '2026-03-31',
    );
  });

  it('passes undefined dates when no range is supplied', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue({ statements: [] });

    const res = await get({});

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(expect.anything(), 0, undefined, undefined);
  });

  it('returns 500 without leaking the model error', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(ReportsModel, 'getCustomerStatements').mockImplementation(() => {
      throw new Error('database detail that must not reach the client');
    });

    const res = await get({ customerId: '7' });

    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      success: false,
      error: 'Failed to fetch customer statements',
    });
  });
});
