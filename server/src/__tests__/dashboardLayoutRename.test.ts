import { Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import dashboardLayoutController from '../controllers/dashboardLayoutController';
import DashboardLayoutModel from '../models/DashboardLayout';
import { AuthRequest } from '../types';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `dashboardLayoutController.renameLayout`
 * (CRAP 56). Covers all validation branches, success, not-found, duplicate
 * name, and the generic failure path.
 */
describe('dashboardLayoutController.renameLayout', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const patch = (body: Record<string, unknown>) =>
    request(app)
      .patch('/api/dashboard/layout/5/rename')
      .set('Cookie', cookie)
      .send(body);

  it('rejects missing, non-string and blank names at the controller guard', () => {
    const statuses: number[] = [];
    for (const name of [undefined, 7, '   ']) {
      const status = jest.fn();
      const json = jest.fn();
      const res = { status, json } as unknown as Response;
      status.mockReturnValue(res);
      dashboardLayoutController.renameLayout(
        {
          params: { id: '5' },
          body: { layout_name: name },
          user: { id: 1 },
        } as unknown as AuthRequest,
        res,
      );
      statuses.push(status.mock.calls[0][0] as number);
    }
    expect(statuses).toEqual([400, 400, 400]);
  });

  it('renames a layout and trims the supplied name', async () => {
    const rename = jest
      .spyOn(DashboardLayoutModel, 'renameLayout')
      .mockReturnValue(true);

    const res = await patch({ layout_name: '  Operations  ' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, message: 'Layout renamed' });
    expect(rename).toHaveBeenCalledWith(5, expect.any(Number), 'Operations');
  });

  it('returns 404 when the layout is not owned by the user', async () => {
    jest
      .spyOn(DashboardLayoutModel, 'renameLayout')
      .mockReturnValue(false);

    const res = await patch({ layout_name: 'Operations' });

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Layout not found' });
  });

  it('returns 409 for a duplicate layout name', async () => {
    jest
      .spyOn(DashboardLayoutModel, 'renameLayout')
      .mockImplementation(() => {
        const error = new Error('duplicate') as Error & { code: string };
        error.code = 'SQLITE_CONSTRAINT_UNIQUE';
        throw error;
      });

    const res = await patch({ layout_name: 'Operations' });

    expect(res.status).toBe(409);
    expect(res.body).toEqual({
      error: 'A layout with this name already exists',
    });
  });

  it('returns a sanitized 500 for an unexpected failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest
      .spyOn(DashboardLayoutModel, 'renameLayout')
      .mockImplementation(() => {
        throw new Error('forced failure');
      });

    const res = await patch({ layout_name: 'Operations' });

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to rename layout' });
  });
});
