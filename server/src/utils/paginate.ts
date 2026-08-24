/**
 * Shared pagination helper (audit-remediation task 8.7).
 *
 * Parses `page` (1-based) and `limit` query parameters with sane caps, and
 * renders a standard `{ page, limit, total, total_pages }` envelope. Used by
 * the unbounded list endpoints: customer/supplier ledgers + statements and
 * the stock-batches listing.
 */
import { Request } from 'express';
import { getQueryInteger } from './queryUtils';

export const DEFAULT_PAGE_SIZE = 100;
export const MAX_PAGE_SIZE = 500;

export interface PageParams {
  page: number;
  limit: number;
  offset: number;
}

export function parsePageParams(req: Request): PageParams {
  const page = Math.max(1, getQueryInteger(req.query.page, 1) || 1);
  const rawLimit = getQueryInteger(req.query.limit, DEFAULT_PAGE_SIZE) || DEFAULT_PAGE_SIZE;
  const limit = Math.min(Math.max(1, rawLimit), MAX_PAGE_SIZE);
  return { page, limit, offset: (page - 1) * limit };
}

export interface PageEnvelope {
  page: number;
  limit: number;
  total: number;
  total_pages: number;
}

export function envelope(total: number, p: PageParams): PageEnvelope {
  return {
    page: p.page,
    limit: p.limit,
    total,
    total_pages: Math.max(1, Math.ceil(total / p.limit)),
  };
}
