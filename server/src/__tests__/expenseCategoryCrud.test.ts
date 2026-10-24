import { Response } from 'express';
import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import expenseController from '../controllers/expenseController';
import ExpenseModel from '../models/Expense';
import { AuthRequest } from '../types';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — expense category create/update/delete
 * controllers (CRAP 42 each). Covers required-name, duplicate, not-found,
 * in-use, generic and non-Error failures.
 */
describe('expense category controllers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const post = (body: Record<string, unknown>) =>
    request(app)
      .post('/api/expenses/categories')
      .set('Cookie', cookie)
      .send(body);
  const put = (id: number, body: Record<string, unknown>) =>
    request(app)
      .put(`/api/expenses/categories/${id}`)
      .set('Cookie', cookie)
      .send(body);
  const del = (id: number) =>
    request(app)
      .delete(`/api/expenses/categories/${id}`)
      .set('Cookie', cookie);

  describe('createExpenseCategory', () => {
    it('rejects a missing name at the controller guard', () => {
      const status = jest.fn();
      const json = jest.fn();
      const res = { status, json } as unknown as Response;
      status.mockReturnValue(res);
      expenseController.createExpenseCategory(
        { body: {}, user: { id: 1 } } as unknown as AuthRequest,
        res,
      );
      expect(status).toHaveBeenCalledWith(400);
    });

    it('creates a category', async () => {
      jest.spyOn(ExpenseModel, 'createCategory').mockReturnValue(5);
      const res = await post({
        category_name: 'Travel',
        description: 'Travel costs',
      });
      expect(res.status).toBe(201);
      expect(res.body.data).toEqual({
        id: 5,
        category_name: 'Travel',
        description: 'Travel costs',
        is_active: 1,
      });
    });

    it('creates a category without a description', async () => {
      jest.spyOn(ExpenseModel, 'createCategory').mockReturnValue(6);
      const res = await post({ category_name: 'Misc' });
      expect(res.status).toBe(201);
      expect(res.body.data.description).toBe('');
    });

    it('maps a duplicate name to 400', async () => {
      jest.spyOn(ExpenseModel, 'createCategory').mockImplementation(() => {
        throw new Error('Category already exists');
      });
      const res = await post({ category_name: 'Travel' });
      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Category already exists');
    });

    it('returns a generic 500 for other and non-Error failures', async () => {
      jest.spyOn(logger, 'error').mockImplementation(() => logger);
      jest.spyOn(ExpenseModel, 'createCategory').mockImplementation(() => {
        throw new Error('forced');
      });
      expect((await post({ category_name: 'Travel' })).status).toBe(500);

      jest.spyOn(ExpenseModel, 'createCategory').mockImplementation(() => {
        throw 'not an error';
      });
      expect((await post({ category_name: 'Travel' })).status).toBe(500);
    });
  });

  describe('updateExpenseCategory', () => {
    it('returns 404 for an unknown category', async () => {
      jest.spyOn(ExpenseModel, 'getCategoryById').mockReturnValue(undefined);
      const res = await put(5, { category_name: 'Travel' });
      expect(res.status).toBe(404);
    });

    it('updates an existing category', async () => {
      jest
        .spyOn(ExpenseModel, 'getCategoryById')
        .mockReturnValueOnce({ id: 5, category_name: 'Old' })
        .mockReturnValueOnce({ id: 5, category_name: 'New' });
      jest.spyOn(ExpenseModel, 'updateCategory').mockImplementation(() => {});
      const res = await put(5, { category_name: 'New' });
      expect(res.status).toBe(200);
      expect(res.body.data).toEqual({ id: 5, category_name: 'New' });
    });

    it('maps model not-found/duplicate errors and generic failure', async () => {
      jest
        .spyOn(ExpenseModel, 'getCategoryById')
        .mockReturnValue({ id: 5, category_name: 'Old' });
      jest.spyOn(logger, 'error').mockImplementation(() => logger);

      jest.spyOn(ExpenseModel, 'updateCategory').mockImplementation(() => {
        throw new Error('Category not found');
      });
      expect((await put(5, { category_name: 'New' })).status).toBe(404);

      jest.spyOn(ExpenseModel, 'updateCategory').mockImplementation(() => {
        throw new Error('Category already exists');
      });
      expect((await put(5, { category_name: 'New' })).status).toBe(400);

      jest.spyOn(ExpenseModel, 'updateCategory').mockImplementation(() => {
        throw 'not an error';
      });
      expect((await put(5, { category_name: 'New' })).status).toBe(500);
    });
  });

  describe('deleteExpenseCategory', () => {
    it('returns 404 for an unknown category', async () => {
      jest.spyOn(ExpenseModel, 'getCategoryById').mockReturnValue(undefined);
      const res = await del(5);
      expect(res.status).toBe(404);
    });

    it('deletes an existing category', async () => {
      jest
        .spyOn(ExpenseModel, 'getCategoryById')
        .mockReturnValue({ id: 5, category_name: 'Travel' });
      jest.spyOn(ExpenseModel, 'deleteCategory').mockImplementation(() => {});
      const res = await del(5);
      expect(res.status).toBe(200);
    });

    it('maps in-use and generic failures', async () => {
      jest
        .spyOn(ExpenseModel, 'getCategoryById')
        .mockReturnValue({ id: 5, category_name: 'Travel' });
      jest.spyOn(logger, 'error').mockImplementation(() => logger);

      jest.spyOn(ExpenseModel, 'deleteCategory').mockImplementation(() => {
        throw new Error('Category is being used');
      });
      expect((await del(5)).status).toBe(400);

      jest.spyOn(ExpenseModel, 'deleteCategory').mockImplementation(() => {
        throw 'not an error';
      });
      expect((await del(5)).status).toBe(500);
    });
  });
});
