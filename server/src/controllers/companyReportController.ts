import type { Request, Response } from 'express';
import db from '../config/database';
import { getCompanyStock, getCompanyPeriod } from '../models/CompanyReport';
import logger from '../utils/logger';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isPositiveInt(value: unknown): boolean {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0;
}

function isIsoDate(value: unknown): value is string {
  if (typeof value !== 'string' || !ISO_DATE.test(value)) return false;
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) return false;
  return new Date(parsed).toISOString().slice(0, 10) === value;
}

function isOrderedDateRange(start: unknown, end: unknown): boolean {
  return isIsoDate(start) && isIsoDate(end) && start <= end;
}

function parsePaging(query: Request['query']): { page: number; limit: number } | null {
  const page = Number(query.page ?? 1);
  const limit = Number(query.limit ?? 50);
  if (!isPositiveInt(page) || !isPositiveInt(limit) || limit > 100) return null;
  return { page, limit };
}

function companyExists(companyId: number): boolean {
  return !!db.prepare('SELECT id FROM item_companies WHERE id = ?').get(companyId);
}

export function companyStockReport(req: Request, res: Response): void {
  companyReport(req, res, 'stock');
}

export function companySalesReport(req: Request, res: Response): void {
  companyReport(req, res, 'sales');
}

export function companyPurchasesReport(req: Request, res: Response): void {
  companyReport(req, res, 'purchases');
}

function companyReport(req: Request, res: Response, view: 'stock' | 'sales' | 'purchases'): void {
  const companyId = Number(req.query.company_id);
  const paging = parsePaging(req.query);
  const start = req.query.startDate;
  const end = req.query.endDate;
  if (!isPositiveInt(companyId) || paging === null) {
    res.status(400).json({ error: 'Invalid company or pagination' });
    return;
  }
  if (view !== 'stock' && !isOrderedDateRange(start, end)) {
    res.status(400).json({ error: 'Valid ordered startDate and endDate are required' });
    return;
  }
  try {
    if (!companyExists(companyId)) {
      res.status(404).json({ error: 'Company not found' });
      return;
    }
    const data = view === 'stock' ? getCompanyStock(companyId, paging.page, paging.limit, db)
      : getCompanyPeriod(companyId, view, String(start), String(end), paging.page, paging.limit, db);
    res.json({ success: true, data });
  } catch (error: unknown) {
    logger.error('Company stock report failed:', error);
    res.status(500).json({ error: 'Failed to fetch company stock report' });
  }
}
