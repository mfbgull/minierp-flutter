import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import PurchaseOrderModel from '../models/PurchaseOrder';
import { BusinessRuleError } from '../utils/businessRuleError';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `purchaseOrderController.updateLineItem`
 * (CRAP 72). Covers both required-field guards, both positivity guards,
 * the success path, a typed business error, and a generic failure.
 */
describe('purchaseOrderController.updateLineItem', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const put = (body: Record<string, unknown>) =>
    request(app)
      .put('/api/purchase-orders/1/items/2')
      .set('Cookie', cookie)
      .send(body);

  it('requires both quantity and unit price', async () => {
    expect((await put({})).status).toBe(400);
    const onlyQuantity = await put({ quantity: 5 });
    expect(onlyQuantity.status).toBe(400);
    expect(onlyQuantity.body.error).toMatch(/required/i);
  });

  it('rejects non-positive values after the required check', async () => {
    const quantity = await put({ quantity: -1, unit_price: 10 });
    expect(quantity.status).toBe(400);
    expect(quantity.body.error).toBe('Quantity must be positive');

    const price = await put({ quantity: 1, unit_price: -1 });
    expect(price.status).toBe(400);
    expect(price.body.error).toBe('Unit price must be positive');
  });

  it('updates a line and returns the model result', async () => {
    const item = { id: 2, quantity: 5, unit_price: 10 };
    const update = jest
      .spyOn(PurchaseOrderModel, 'updateItem')
      .mockReturnValue(
        item as unknown as ReturnType<typeof PurchaseOrderModel.updateItem>,
      );

    const res = await put({ quantity: 5, unit_price: 10, input_tax_amount: 1 });

    expect(res.status).toBe(200);
    expect(res.body).toEqual(item);
    expect(update).toHaveBeenCalledWith(
      2,
      { quantity: 5, unit_price: 10, input_tax_amount: 1 },
      expect.anything(),
    );
  });

  it('maps a business rule error to its status', async () => {
    jest.spyOn(PurchaseOrderModel, 'updateItem').mockImplementation(() => {
      throw new BusinessRuleError(409, 'Cannot edit items in non-Draft Purchase Orders');
    });

    const res = await put({ quantity: 5, unit_price: 10 });

    expect(res.status).toBe(409);
    expect(res.body.error).toBe(
      'Cannot edit items in non-Draft Purchase Orders',
    );
  });

  it('returns the sanitized message for an unexpected failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(PurchaseOrderModel, 'updateItem').mockImplementation(() => {
      throw new Error('forced update failure');
    });

    const res = await put({ quantity: 5, unit_price: 10 });

    expect(res.status).toBe(500);
    expect(res.body.error).toBe('forced update failure');
  });

  it('returns the generic message when the failure has no text', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(PurchaseOrderModel, 'updateItem').mockImplementation(() => {
      throw new Error('');
    });

    const res = await put({ quantity: 5, unit_price: 10 });

    expect(res.status).toBe(500);
    expect(res.body.error).toBe('Failed to update line item');
  });
});
