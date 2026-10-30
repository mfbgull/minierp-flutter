import type { Request, Response } from 'express';
import { z } from 'zod';
import db from '../config/database';
import ItemCompanyModel from '../models/ItemCompany';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { listPagination } from '../utils/controllerPagination';
import type { AuthRequest } from '../types';
import { logCRUD } from '../services/activityLogger';

export const companyNameSchema = z.object({ company_name: z.string().trim().min(1).max(200) });
export const companyListSchema = z.object({
  search: z.string().trim().max(200).default(''),
  status: z.enum(['active', 'archived', 'all']).default('active'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

function companyId(req: Request): number {
  const id = Number(req.params.id);
  if (!Number.isSafeInteger(id) || id <= 0) throw new BusinessRuleError(400, 'Invalid company ID');
  return id;
}

function handle(action: (req: Request, res: Response) => void) {
  return (req: AuthRequest, res: Response): void => {
    try {
      action(req, res);
      if (req.method !== 'GET') {
        logCRUD(req.method === 'DELETE' ? 'DELETE' : req.method === 'PUT' ? 'UPDATE' : 'CREATE',
          'ItemCompany', req.params.id ? companyId(req) : undefined,
          `Company operation: ${req.method} ${req.path}`, req.user?.id);
        req.activityLogged = true;
      }
    } catch (error) {
      handleBusinessError(res, error, 'Company operation', 'Failed to complete company operation');
    }
  };
}

export const listCompanies = handle((req, res) => {
  const query = companyListSchema.parse(req.query);
  const result = ItemCompanyModel.list(query.search, query.status, query.page, query.limit, db);
  res.json({ success: true, data: result.rows, pagination: listPagination(result.total, query.page, query.limit) });
});
export const getCompany = handle((req, res) => { res.json(ItemCompanyModel.get(companyId(req), db)); });
export const createCompany = handle((req, res) => {
  const body = companyNameSchema.parse(req.body);
  res.status(201).json(ItemCompanyModel.create(body.company_name, db));
});
export const renameCompany = handle((req, res) => {
  const body = companyNameSchema.parse(req.body);
  res.json(ItemCompanyModel.rename(companyId(req), body.company_name, db));
});
export const archiveCompany = handle((req, res) => { res.json(ItemCompanyModel.setActive(companyId(req), false, db)); });
export const restoreCompany = handle((req, res) => { res.json(ItemCompanyModel.setActive(companyId(req), true, db)); });
export const deleteCompany = handle((req, res) => {
  ItemCompanyModel.delete(companyId(req), db);
  res.json({ success: true });
});
export const companyProducts = handle((req, res) => {
  const query = companyListSchema.parse(req.query);
  const result = ItemCompanyModel.products(companyId(req), query.page, query.limit, db);
  res.json({ success: true, data: result.rows, pagination: listPagination(result.total, query.page, query.limit) });
});
