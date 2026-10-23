import { Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import dashboardController from '../controllers/dashboardController';
import DashboardModel from '../models/Dashboard';
import { AuthRequest } from '../types';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `dashboardController.getKPIBatch` (CRAP 90).
 * Covers metric parsing/trimming/capping, date fallbacks, per-metric
 * degradation, the empty batch, and both error layers.
 */
describe('dashboardController.getKPIBatch', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const get = (query: Record<string, string | string[]>) =>
    request(app)
      .get('/api/dashboard/kpi-batch')
      .set('Cookie', cookie)
      .query(query);

  const kpi = (value: number) =>
    value as unknown as ReturnType<typeof DashboardModel.getKPI>;

  it('trims metrics, passes the date range, and returns each value', async () => {
    const spy = jest
      .spyOn(DashboardModel, 'getKPI')
      .mockImplementation((_db, metric) => kpi(metric.length));

    const res = await get({
      metrics: ' sales , expenses ,, ',
      fromDate: '2026-01-01',
      toDate: '2026-01-31',
    });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: { sales: 5, expenses: 8 },
    });
    expect(spy).toHaveBeenCalledTimes(2);
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      'sales',
      '2026-01-01',
      '2026-01-31',
    );
  });

  it('omits the date range when no bounds are supplied', async () => {
    const spy = jest.spyOn(DashboardModel, 'getKPI').mockReturnValue(kpi(1));

    const res = await get({ metrics: 'sales' });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(
      expect.anything(),
      'sales',
      undefined,
      undefined,
    );
  });

  it('returns an empty map when no metrics are requested', async () => {
    const spy = jest.spyOn(DashboardModel, 'getKPI').mockReturnValue(kpi(1));

    const res = await get({});

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, data: {} });
    expect(spy).not.toHaveBeenCalled();
  });

  it('caps a batch at twelve metrics', async () => {
    const spy = jest.spyOn(DashboardModel, 'getKPI').mockReturnValue(kpi(1));
    const metrics = Array.from({ length: 14 }, (_, index) => `m${index}`);

    const res = await get({ metrics: metrics.join(',') });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledTimes(12);
    expect(Object.keys(res.body.data)).toHaveLength(12);
    expect(res.body.data).not.toHaveProperty('m12');
    expect(res.body.data).not.toHaveProperty('m13');
  });

  it('returns null for a metric that throws without failing the batch', async () => {
    jest
      .spyOn(DashboardModel, 'getKPI')
      .mockImplementation((_db, metric) => {
        if (metric === 'broken') throw new Error('metric failure');
        return kpi(1);
      });

    const res = await get({ metrics: 'sales,broken' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: { sales: 1, broken: null },
    });
  });

  it('returns a sanitized 500 when request parsing itself fails', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);
    const req = Object.defineProperty({}, 'query', {
      get() {
        throw new Error('malformed query');
      },
    }) as unknown as AuthRequest;

    dashboardController.getKPIBatch(req, res);

    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({ error: 'Failed to calculate KPIs' });
  });
});
