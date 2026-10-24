import { Request, Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import suppliersController from '../controllers/suppliersController';
import SupplierModel from '../models/Supplier';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `suppliersController.updateSupplier` (CRAP 56).
 * Covers not-found, success, the is_active mapping, array params, and the
 * sanitized failure path.
 */
describe('suppliersController.updateSupplier', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const put = (body: Record<string, unknown>) =>
    request(app).put('/api/suppliers/1').set('Cookie', cookie).send(body);

  it('updates a supplier and maps is_active=true', async () => {
    const update = jest
      .spyOn(SupplierModel, 'update')
      .mockReturnValue({ changes: 1 } as ReturnType<typeof SupplierModel.update>);

    const res = await put({
      supplier_name: 'Acme Updated',
      contact_person: 'Alicia',
      email: 'a@x.test',
      phone: '999',
      address: 'Street',
      payment_terms: 'Net 60',
      is_active: true,
    });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: {
        id: 1,
        supplier_name: 'Acme Updated',
        contact_person: 'Alicia',
        email: 'a@x.test',
        phone: '999',
        address: 'Street',
        payment_terms: 'Net 60',
        is_active: 1,
      },
    });
    expect(update).toHaveBeenCalledWith(
      1,
      {
        supplier_name: 'Acme Updated',
        contact_person: 'Alicia',
        email: 'a@x.test',
        phone: '999',
        address: 'Street',
        payment_terms: 'Net 60',
        is_active: true,
      },
      expect.anything(),
    );
  });

  it('maps is_active=false and defaults a missing flag to 1', async () => {
    jest
      .spyOn(SupplierModel, 'update')
      .mockReturnValue({ changes: 1 } as ReturnType<typeof SupplierModel.update>);

    const inactive = await put({ supplier_name: 'Acme', is_active: false });
    expect(inactive.body.data.is_active).toBe(0);

    const omitted = await put({ supplier_name: 'Acme' });
    expect(omitted.body.data.is_active).toBe(1);
  });

  it('returns 404 when no row changed', async () => {
    jest
      .spyOn(SupplierModel, 'update')
      .mockReturnValue({ changes: 0 } as ReturnType<typeof SupplierModel.update>);

    const res = await put({ supplier_name: 'Acme' });

    expect(res.status).toBe(404);
    expect(res.body).toEqual({
      success: false,
      error: 'Supplier not found',
    });
  });

  it('accepts an array route param through the controller helper', () => {
    jest
      .spyOn(SupplierModel, 'update')
      .mockReturnValue({ changes: 1 } as ReturnType<typeof SupplierModel.update>);
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    suppliersController.updateSupplier(
      {
        params: { id: ['1'] },
        body: { supplier_name: 'Acme' },
        user: { id: 1 },
      } as unknown as Request,
      res,
    );

    expect(json).toHaveBeenCalledWith(
      expect.objectContaining({ success: true }),
    );
  });

  it('returns a sanitized 500 when the update fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(SupplierModel, 'update').mockImplementation(() => {
      throw new Error('database detail that must not reach the client');
    });

    const res = await put({ supplier_name: 'Acme' });

    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      success: false,
      error: 'Failed to update supplier',
    });
  });
});
