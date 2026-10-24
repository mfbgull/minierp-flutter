import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import DashboardLayoutModel from '../models/DashboardLayout';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `dashboardLayoutController.createLayout`
 * (CRAP 30) and `duplicateLayout` (CRAP 30).
 */
describe('dashboard layout create/duplicate', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const layout = { id: 11, layout_name: 'Default', blocks: [], is_active: 1 };

  describe('POST /api/dashboard/layout', () => {
    const create = (body: Record<string, unknown> = {}) =>
      request(app).post('/api/dashboard/layout').set('Cookie', cookie).send(body);

    it('creates a layout with defaults', async () => {
      const spy = jest
        .spyOn(DashboardLayoutModel, 'createLayout')
        .mockReturnValue(layout as unknown as ReturnType<typeof DashboardLayoutModel.createLayout>);

      const res = await create();

      expect(res.status).toBe(201);
      expect(res.body).toEqual({ success: true, data: layout });
      expect(spy).toHaveBeenCalledWith(
        expect.objectContaining({ layout_name: 'Default', blocks: [] }),
        true
      );
    });

    it('honours is_active false', async () => {
      const spy = jest
        .spyOn(DashboardLayoutModel, 'createLayout')
        .mockReturnValue({ ...layout, is_active: 0 } as unknown as ReturnType<
          typeof DashboardLayoutModel.createLayout
        >);

      await create({ layout_name: 'Ops', blocks: [{ id: 'kpi' }], is_active: false });

      expect(spy).toHaveBeenCalledWith(
        expect.objectContaining({ layout_name: 'Ops', blocks: [{ id: 'kpi' }] }),
        false
      );
    });

    it('maps a duplicate name to 409', async () => {
      jest.spyOn(DashboardLayoutModel, 'createLayout').mockImplementation(() => {
        throw Object.assign(new Error('UNIQUE constraint failed'), {
          code: 'SQLITE_CONSTRAINT_UNIQUE',
        });
      });

      const res = await create({ layout_name: 'Default' });

      expect(res.status).toBe(409);
      expect(res.body).toEqual({ error: 'A layout with this name already exists' });
    });

    it('returns a sanitized 500 for other failures', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(DashboardLayoutModel, 'createLayout').mockImplementation(() => {
        throw new Error('forced create failure');
      });

      const res = await create();
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to create layout' });
    });
  });

  describe('POST /api/dashboard/layout/duplicate', () => {
    const duplicate = (body: Record<string, unknown>) =>
      request(app).post('/api/dashboard/layout/duplicate').set('Cookie', cookie).send(body);

    it('requires a numeric id', async () => {
      expect((await duplicate({})).status).toBe(400);
      expect((await duplicate({ id: '7' })).status).toBe(400);
    });

    it('returns 404 when the source layout is missing', async () => {
      jest.spyOn(DashboardLayoutModel, 'duplicateLayout').mockReturnValue(null);
      expect((await duplicate({ id: 7 })).status).toBe(404);
    });

    it('returns the duplicated layout', async () => {
      const copy = { ...layout, id: 12, layout_name: 'Default (Copy)' };
      const spy = jest
        .spyOn(DashboardLayoutModel, 'duplicateLayout')
        .mockReturnValue(copy as unknown as ReturnType<typeof DashboardLayoutModel.duplicateLayout>);

      const res = await duplicate({ id: 11 });

      expect(res.status).toBe(201);
      expect(res.body).toEqual({ success: true, data: copy });
      expect(spy).toHaveBeenCalledWith(11, expect.any(Number));
    });

    it('returns a sanitized 500 when duplication fails', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(DashboardLayoutModel, 'duplicateLayout').mockImplementation(() => {
        throw new Error('forced duplicate failure');
      });

      const res = await duplicate({ id: 11 });
      expect(res.status).toBe(500);
      expect(res.body).toEqual({ error: 'Failed to duplicate layout' });
    });
  });
});
