import { z } from 'zod';
import { documentDate } from './validation';
import { roundCurrency, toMinorUnits } from '../utils/currency';

const positiveId = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const amount = z.number().finite().positive()
  .refine(value => Number.isSafeInteger(toMinorUnits(value)), 'Amount exceeds currency precision')
  .transform(roundCurrency).refine(value => value >= 0.01, 'Amount must be at least 0.01');
const method = z.enum(['Cash', 'Bank', 'Easypaisa', 'JazzCash', 'Upaisa']).default('Cash');

export const cashIdParams = z.object({
  id: z.string().regex(/^[1-9]\d*$/).refine(value => Number.isSafeInteger(Number(value)), 'Invalid ID'),
});

export const receiveCashBody = z.object({
  amount,
  operation_date: documentDate('operation_date'),
  payment_method: method,
}).strict();

export const applyCashBody = z.object({
  customer_id: positiveId,
  operation_date: documentDate('operation_date'),
  allocations: z.array(z.object({ invoice_id: positiveId, amount }).strict()).min(1).max(1000),
}).strict();

export const refundCashBody = receiveCashBody.extend({ customer_id: positiveId });

export const reverseCashBody = z.object({
  reason: z.string().trim().min(1).max(500).optional(),
}).strict().default({});

const pageNumber = (maximum: number, fallback: string) => z.string().regex(/^[1-9]\d*$/).default(fallback)
  .transform(Number).refine(value => Number.isSafeInteger(value) && value <= maximum, 'Invalid pagination');

const cashPagination = {
  page: pageNumber(Math.floor(Number.MAX_SAFE_INTEGER / 100), '1'),
  limit: pageNumber(100, '20'),
};

export const cashSummaryQuery = z.object({
  ...cashPagination,
  operation_date: documentDate('operation_date').optional(),
}).strict();

export const cashActivityQuery = z.object({
  ...cashPagination,
  fromDate: documentDate('fromDate').optional(),
  toDate: documentDate('toDate').optional(),
}).strict().refine(value => !value.fromDate || !value.toDate || value.fromDate <= value.toDate, 'Invalid date range');
