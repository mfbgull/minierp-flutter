import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import request from 'supertest';
import app from '../app';
import purchaseOrderController from '../controllers/purchaseOrderController';
import PurchaseOrderModel from '../models/PurchaseOrder';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `purchaseOrderController.getSummaryBySupplier`
 * (CRAP 42).
 */
describe('GET /api/purchase-orders/summary/supplier/:supplierId', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const get = (supplierId: number, query: Record<string, string> = {}) =>
    request(app)
      .get(`/api/purchase-orders/summary/supplier/${supplierId}`)
      .set('Cookie', cookie)
      .query(query);

  const summary = {
    total_pos: 3,
    draft_pos: 1,
    submitted_pos: 1,
    partially_received_pos: 0,
    completed_pos: 1,
    total_value: 450,
  };

  it('returns the supplier summary with no date bounds', async () => {
    const spy = jest
      .spyOn(PurchaseOrderModel, 'getSummaryBySupplier')
      .mockReturnValue(summary);

    const res = await get(4);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(summary);
    expect(spy).toHaveBeenCalledWith(4, expect.anything(), {
      startDate: undefined,
      endDate: undefined,
    });
  });

  it('passes inclusive start and end date bounds', async () => {
    const spy = jest
      .spyOn(PurchaseOrderModel, 'getSummaryBySupplier')
      .mockReturnValue(summary);

    const res = await get(4, { start_date: '2026-01-01', end_date: '2026-02-01' });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(4, expect.anything(), {
      startDate: '2026-01-01',
      endDate: '2026-02-01',
    });
  });

  it('falls back to a zeroed summary when the model returns nothing', async () => {
    jest.spyOn(PurchaseOrderModel, 'getSummaryBySupplier').mockReturnValue(
      null as unknown as ReturnType<typeof PurchaseOrderModel.getSummaryBySupplier>
    );

    const res = await get(4);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      total_pos: 0,
      draft_pos: 0,
      submitted_pos: 0,
      partially_received_pos: 0,
      completed_pos: 0,
      total_value: 0,
    });
  });

  it('rejects a request with no supplier id', () => {
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    purchaseOrderController.getSummaryBySupplier(
      { params: {}, query: {} } as unknown as Request,
      res
    );

    expect(status).toHaveBeenCalledWith(400);
    expect(json).toHaveBeenCalledWith({ error: 'Supplier ID is required' });
  });

  it('returns a sanitized 500 when the summary read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(PurchaseOrderModel, 'getSummaryBySupplier').mockImplementation(() => {
      throw new Error('forced summary failure');
    });

    const res = await get(4);

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to get purchase order summary' });
  });
});
