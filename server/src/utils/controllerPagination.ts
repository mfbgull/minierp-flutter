import type { Request } from 'express';
import { getQueryInteger, getQueryParam } from './queryUtils';

export function listPagination(total: number, page: number, limit: number) {
  const totalPages = Math.ceil(total / limit);
  return { currentPage: page, totalPages, totalItems: total, hasNext: page < totalPages, hasPrev: page > 1 };
}

export function listPageQuery(query: Request['query']) {
  return { page: getQueryInteger(query.page, 1), limit: getQueryInteger(query.limit, 10) };
}

export interface ListRequestQuery {
  search?: string;
  sortBy?: string;
  sortOrder?: string;
  page: number;
  limit: number;
}

/**
 * Parse the list request shared by every paged GET: free-text search, sort
 * column and direction, and pagination. Entity-specific filters stay in the
 * caller, which spreads these next to its own fields.
 */
export function listRequestQuery(query: Request['query']): ListRequestQuery {
  return {
    search: getQueryParam(query.search) || undefined,
    sortBy: getQueryParam(query.sortBy) || undefined,
    sortOrder: getQueryParam(query.sortOrder) || undefined,
    ...listPageQuery(query),
  };
}

export function rawListPageQuery(query: Request['query']) {
  return { pageParam: getQueryParam(query.page), limitParam: getQueryParam(query.limit), searchParam: getQueryParam(query.search) };
}
