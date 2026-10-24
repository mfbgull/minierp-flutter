import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import ReportsModel from '../models/Reports';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `reportsController.saveCashReconciliation`
 * (CRAP 56). Covers the accounts-array guards, date default, success, and
 * both Error/non-Error failure messages.
 */
describe('reportsController.saveCashReconciliation', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const post = (body: Record<string, unknown>) =>
    request(app)
      .post('/api/reports/cash-reconciliation')
      .set('Cookie', cookie)
      .send(body);

  it('requires a non-empty accounts array', async () => {
    expect((await post({})).status).toBe(400);
    expect((await post({ accounts: [] })).status).toBe(400);
    const notArray = await post({ accounts: 'cash' });
    expect(notArray.status).toBe(400);
    expect(notArray.body.error).toBe('accounts array is required');
  });

  it('saves a dated reconciliation and returns the refreshed data', async () => {
    const save = jest
      .spyOn(ReportsModel, 'saveCashReconciliation')
      .mockReturnValue({ date: '2026-01-31', accounts: [] } as unknown as ReturnType<
        typeof ReportsModel.saveCashReconciliation
      >);

    const accounts = [{ key: 'cash', counted_balance: 10, notes: 'counted' }];
    const res = await post({ date: '2026-01-31', accounts });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      message: 'Cash reconciliation saved',
      data: { date: '2026-01-31', accounts: [] },
    });
    expect(save).toHaveBeenCalledWith(
      expect.anything(),
      '2026-01-31',
      accounts,
      expect.any(Number),
    );
  });

  it('defaults the date to today', async () => {
    const save = jest
      .spyOn(ReportsModel, 'saveCashReconciliation')
      .mockReturnValue({ date: 'today', accounts: [] } as unknown as ReturnType<
        typeof ReportsModel.saveCashReconciliation
      >);

    await post({ accounts: [{ key: 'cash', counted_balance: 1 }] });

    const date = (save.mock.calls[0] as unknown[])[1] as string;
    expect(date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('returns the error message for an Error failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest
      .spyOn(ReportsModel, 'saveCashReconciliation')
      .mockImplementation(() => {
        throw new Error('Unknown account key: bogus');
      });

    const res = await post({ accounts: [{ key: 'bogus', counted_balance: 1 }] });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      success: false,
      error: 'Unknown account key: bogus',
    });
  });

  it('uses a generic message for a non-Error failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest
      .spyOn(ReportsModel, 'saveCashReconciliation')
      .mockImplementation(() => {
        throw 'not an error';
      });

    const res = await post({ accounts: [{ key: 'cash', counted_balance: 1 }] });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      success: false,
      error: 'Failed to save cash reconciliation',
    });
  });
});
