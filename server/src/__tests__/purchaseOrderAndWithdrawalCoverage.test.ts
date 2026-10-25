import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import PurchaseOrderModel from '../models/PurchaseOrder';
import OwnerWithdrawalModel from '../models/OwnerWithdrawal';
import { BusinessRuleError } from '../utils/businessRuleError';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `purchaseOrderController.addLineItem` (CRAP 90)
 * and `ownerEquityController.voidWithdrawal` (CRAP 42).
 */
describe('purchase order line add', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const add = (body: Record<string, unknown>) =>
    request(app).post('/api/purchase-orders/3/items').set('Cookie', cookie).send(body);

  it('requires item, quantity and unit price', async () => {
    expect((await add({})).status).toBe(400);
    expect((await add({ item_id: 1, unit_price: 5 })).status).toBe(400);
  });

  it('rejects non-positive quantity and price', async () => {
    const qty = await add({ item_id: 1, quantity: -2, unit_price: 5 });
    expect(qty.status).toBe(400);
    expect(qty.body).toEqual({ error: 'Quantity must be positive' });

    const price = await add({ item_id: 1, quantity: 2, unit_price: -5 });
    expect(price.status).toBe(400);
    expect(price.body).toEqual({ error: 'Unit price must be positive' });
  });

  it('adds the line item', async () => {
    const line = { id: 9, po_id: 3, item_id: 1, quantity: 2, unit_price: 5 };
    const spy = jest
      .spyOn(PurchaseOrderModel, 'addItem')
      .mockReturnValue(line as unknown as ReturnType<typeof PurchaseOrderModel.addItem>);

    const res = await add({ item_id: 1, quantity: 2, unit_price: 5, input_tax_amount: 1 });

    expect(res.status).toBe(201);
    expect(res.body).toEqual(line);
    expect(spy).toHaveBeenCalledWith(
      3,
      { item_id: 1, quantity: 2, unit_price: 5, input_tax_amount: 1 },
      expect.anything()
    );
  });

  it('maps a BusinessRuleError to its own status', async () => {
    jest.spyOn(PurchaseOrderModel, 'addItem').mockImplementation(() => {
      throw new BusinessRuleError(409, 'Purchase order is not editable');
    });

    const res = await add({ item_id: 1, quantity: 2, unit_price: 5 });
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: 'Purchase order is not editable' });
  });

  it('falls back to a generic message for an empty failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(PurchaseOrderModel, 'addItem').mockImplementation(() => {
      throw '';
    });

    const res = await add({ item_id: 1, quantity: 2, unit_price: 5 });
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to add line item' });
  });
});

describe('owner withdrawal void', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const voidWithdrawal = (body: Record<string, unknown> = {}) =>
    request(app).delete('/api/owner-equity/withdrawals/7').set('Cookie', cookie).send(body);

  it('returns 404 for an unknown withdrawal', async () => {
    jest.spyOn(OwnerWithdrawalModel, 'getById').mockReturnValue(undefined);

    const res = await voidWithdrawal();
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ success: false, error: 'Owner withdrawal not found' });
  });

  it('voids the withdrawal with a reason', async () => {
    jest
      .spyOn(OwnerWithdrawalModel, 'getById')
      .mockReturnValue({ id: 7, withdrawal_no: 'OW-7' } as unknown as ReturnType<
        typeof OwnerWithdrawalModel.getById
      >);
    const softVoid = jest.spyOn(OwnerWithdrawalModel, 'softVoid').mockImplementation(() => {});

    const res = await voidWithdrawal({ reason: 'entered twice' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      message: 'Owner withdrawal voided',
      data: { id: 7, status: 'voided' },
    });
    expect(softVoid).toHaveBeenCalledWith(expect.anything(), 7, {
      userId: expect.any(Number),
      reason: 'entered twice',
    });
  });

  it('treats a non-string reason as absent', async () => {
    jest
      .spyOn(OwnerWithdrawalModel, 'getById')
      .mockReturnValue({ id: 7, withdrawal_no: 'OW-7' } as unknown as ReturnType<
        typeof OwnerWithdrawalModel.getById
      >);
    const softVoid = jest.spyOn(OwnerWithdrawalModel, 'softVoid').mockImplementation(() => {});

    expect((await voidWithdrawal({ reason: 42 })).status).toBe(200);
    expect(softVoid).toHaveBeenCalledWith(expect.anything(), 7, {
      userId: expect.any(Number),
      reason: undefined,
    });
  });

  it('maps a client-side rule violation to 400', async () => {
    jest
      .spyOn(OwnerWithdrawalModel, 'getById')
      .mockReturnValue({ id: 7, withdrawal_no: 'OW-7' } as unknown as ReturnType<
        typeof OwnerWithdrawalModel.getById
      >);
    jest.spyOn(OwnerWithdrawalModel, 'softVoid').mockImplementation(() => {
      throw new Error('Owner withdrawal already voided');
    });

    const res = await voidWithdrawal();
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ success: false, error: 'Owner withdrawal already voided' });
  });

  it('returns a sanitized 500 for an unexpected failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest
      .spyOn(OwnerWithdrawalModel, 'getById')
      .mockReturnValue({ id: 7, withdrawal_no: 'OW-7' } as unknown as ReturnType<
        typeof OwnerWithdrawalModel.getById
      >);
    jest.spyOn(OwnerWithdrawalModel, 'softVoid').mockImplementation(() => {
      throw new Error('db exploded');
    });

    const res = await voidWithdrawal();
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to void owner withdrawal' });
  });
});
