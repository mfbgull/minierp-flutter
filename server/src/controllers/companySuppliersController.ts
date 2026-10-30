import type { Request, Response } from 'express';
import db from '../config/database';
import CompanySuppliers from '../models/CompanySuppliers';
import { companyListSchema } from './itemCompanyController';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { listPagination } from '../utils/controllerPagination';

function id(value: unknown): number {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result <= 0) throw new BusinessRuleError(400, 'Invalid ID');
  return result;
}

export function listCompanySuppliers(req: Request, res: Response): void {
  try {
    const { page, limit } = companyListSchema.parse(req.query);
    const result = CompanySuppliers.list(id(req.params.id), page, limit, db);
    res.json({ success: true, data: result.rows, pagination: listPagination(result.total, page, limit) });
  } catch (error) { handleBusinessError(res, error, 'Company suppliers', 'Failed to load company suppliers'); }
}
export function companySupplierProducts(req: Request, res: Response): void {
  try {
    const { page, limit } = companyListSchema.parse(req.query);
    const result = CompanySuppliers.products(id(req.params.id), id(req.params.supplierId), page, limit, db);
    res.json({ success: true, data: result.rows, pagination: listPagination(result.total, page, limit) });
  } catch (error) { handleBusinessError(res, error, 'Company supplier products', 'Failed to load supplier products'); }
}
export function setCompanySupplierLink(req: Request, res: Response): void {
  try {
    CompanySuppliers.setLinked(id(req.params.id), id(req.params.supplierId), req.method === 'POST', db);
    res.json({ success: true });
  } catch (error) { handleBusinessError(res, error, 'Company supplier link', 'Failed to update supplier link'); }
}
