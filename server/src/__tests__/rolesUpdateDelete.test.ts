import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import RoleModel from '../models/Role';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `rolesController.updateRole` and
 * `deleteRole` (CRAP 42 each). Covers success, not-found, system-role,
 * in-use, generic and non-Error failures.
 */
describe('role update/delete controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const put = (body: Record<string, unknown>) =>
    request(app).put('/api/roles/5').set('Cookie', cookie).send(body);
  const del = () =>
    request(app).delete('/api/roles/5').set('Cookie', cookie);

  describe('updateRole', () => {
    it('updates a role', async () => {
      jest
        .spyOn(RoleModel, 'update')
        .mockReturnValue({ id: 5, role_name: 'Ops' } as ReturnType<
          typeof RoleModel.update
        >);
      const res = await put({ role_name: 'Ops' });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        data: { id: 5, role_name: 'Ops' },
      });
    });

    it('maps not-found, system-role and duplicate errors', async () => {
      jest.spyOn(RoleModel, 'update').mockImplementation(() => {
        throw new Error('Role not found');
      });
      expect((await put({ role_name: 'Ops' })).status).toBe(404);

      jest.spyOn(RoleModel, 'update').mockImplementation(() => {
        throw new Error('Cannot modify system roles');
      });
      expect((await put({ role_name: 'Ops' })).status).toBe(400);

      jest.spyOn(RoleModel, 'update').mockImplementation(() => {
        throw new Error('Role name already exists');
      });
      expect((await put({ role_name: 'Ops' })).status).toBe(400);
    });

    it('returns 500 for generic and non-Error failures', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(RoleModel, 'update').mockImplementation(() => {
        throw new Error('forced');
      });
      expect((await put({ role_name: 'Ops' })).status).toBe(500);

      jest.spyOn(RoleModel, 'update').mockImplementation(() => {
        throw 'not an error';
      });
      expect((await put({ role_name: 'Ops' })).status).toBe(500);
    });
  });

  describe('deleteRole', () => {
    it('deletes a role', async () => {
      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {});
      const res = await del();
      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        success: true,
        message: 'Role deleted successfully',
      });
    });

    it('maps not-found, system-role and in-use errors', async () => {
      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {
        throw new Error('Role not found');
      });
      expect((await del()).status).toBe(404);

      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {
        throw new Error('Cannot delete system roles');
      });
      expect((await del()).status).toBe(400);

      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {
        throw new Error('Cannot delete role: 2 user(s) have this role.');
      });
      expect((await del()).status).toBe(400);
    });

    it('returns 500 for generic and non-Error failures', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {
        throw new Error('forced');
      });
      expect((await del()).status).toBe(500);

      jest.spyOn(RoleModel, 'delete').mockImplementation(() => {
        throw 'not an error';
      });
      expect((await del()).status).toBe(500);
    });
  });
});
