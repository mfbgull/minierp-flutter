import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import SupplierModel from '../models/Supplier';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `suppliersController.getSuppliers` (CRAP 56).
 * Covers list defaults, filters/sort/pagination, safe fallbacks, the
 * pagination envelope, and the sanitized error path.
 */
describe('suppliersController.getSuppliers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const get = (query: Record<string, string> = {}) =>
    request(app).get('/api/suppliers').set('Cookie', cookie).query(query);

  it('uses list defaults and returns the pagination envelope', async () => {
    const spy = jest.spyOn(SupplierModel, 'getAll').mockReturnValue({
      data: [{ id: 1 }],
      total: 12,
    } as unknown as ReturnType<typeof SupplierModel.getAll>);

    const res = await get({ page: '2', limit: '5' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: [{ id: 1 }],
      pagination: {
        currentPage: 2,
        totalPages: 3,
        totalItems: 12,
        hasNext: true,
        hasPrev: true,
      },
    });
    expect(spy).toHaveBeenCalledWith(
      { search: '', status: undefined },
      'supplier_name',
      'ASC',
      2,
      5,
      expect.anything(),
    );
  });

  it('passes search, status and explicit sort through', async () => {
    const spy = jest
      .spyOn(SupplierModel, 'getAll')
      .mockReturnValue({ data: [], total: 0 } as unknown as ReturnType<
        typeof SupplierModel.getAll
      >);

    await get({
      search: 'acme',
      status: 'inactive',
      sortBy: 'supplier_code',
      sortOrder: 'DESC',
    });

    expect(spy).toHaveBeenCalledWith(
      { search: 'acme', status: 'inactive' },
      'supplier_code',
      'DESC',
      1,
      10,
      expect.anything(),
    );
  });

  it('falls back for invalid page, limit and sort parameters', async () => {
    const spy = jest
      .spyOn(SupplierModel, 'getAll')
      .mockReturnValue({ data: [], total: 0 } as unknown as ReturnType<
        typeof SupplierModel.getAll
      >);

    await get({
      page: 'abc',
      limit: '0',
      sortBy: 'supplier_name; DROP TABLE x',
      sortOrder: 'sideways',
    });

    expect(spy).toHaveBeenCalledWith(
      { search: '', status: undefined },
      'supplier_name',
      'ASC',
      1,
      10,
      expect.anything(),
    );
  });

  it('returns a sanitized 500 when the list read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(SupplierModel, 'getAll').mockImplementation(() => {
      throw new Error('database detail that must not reach the client');
    });

    const res = await get();

    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      success: false,
      error: 'Failed to fetch suppliers',
    });
  });
});
