import type Database from 'better-sqlite3';
import { UnappliedCashError } from '../services/unappliedCashTypes';
import CustomerModel from './Customer';

interface ReceiptReplay {
  request_hash: string;
  payment_id: number;
  amount: number;
}

export function getReceiptReplay(db: Database.Database, customerId: number, key: string, hash: string): ReceiptReplay | undefined {
  const replay = db.prepare<[number, string], ReceiptReplay>(
    'SELECT request_hash,payment_id,amount FROM unapplied_receipt_replays WHERE customer_id=? AND idempotency_key=?',
  ).get(customerId, key);
  if (replay && replay.request_hash !== hash) throw new UnappliedCashError('IDEMPOTENCY_CONFLICT', 'Idempotency-Key was used for a different request');
  return replay;
}

export function saveReceiptReplay(db: Database.Database, customerId: number, key: string, hash: string, paymentId: number, amount: number): void {
  db.prepare(`INSERT INTO unapplied_receipt_replays (customer_id,idempotency_key,request_hash,payment_id,amount)
    VALUES (?,?,?,?,?)`).run(customerId, key, hash, paymentId, amount);
}

export interface CashReceipt {
  source_id: number;
  payment_id: number;
  payment_no: string;
  payment_date: string;
  payment_method: string;
  original_amount: number;
  applied_amount: number;
  refunded_amount: number;
  remaining_amount: number;
  voided_at: string | null;
  can_reverse: boolean;
}

export interface CashPagination {
  currentPage: number;
  totalPages: number;
  totalItems: number;
  limit: number;
}

export interface CashSummaryResponse {
  success: true;
  data: {
    customer_id: number;
    operation_date: string;
    remaining_amount: number;
    available_amount: number;
    refundable_amount: number;
    receipts: CashReceipt[];
  };
  pagination: CashPagination;
}

interface CapacityTotals { remaining_amount: number; available_amount: number; }

function pagination(page: number, limit: number, total: number): CashPagination {
  return { currentPage: page, totalPages: Math.ceil(total / limit), totalItems: total, limit };
}

function requireCustomer(db: Database.Database, customerId: number): void {
  if (!CustomerModel.getById(customerId, db)) throw new UnappliedCashError('CUSTOMER_NOT_FOUND', 'Customer not found', 404);
}

export function getCashSummary(db: Database.Database, customerId: number, date: string, page: number, limit: number): CashSummaryResponse {
  return db.transaction((): CashSummaryResponse => {
    requireCustomer(db, customerId);
    const totals = db.prepare<[string, number], CapacityTotals>(`SELECT
      ROUND(COALESCE(SUM(source.remaining_amount),0),2) remaining_amount,
      ROUND(COALESCE(SUM(CASE WHEN receipt.payment_date<=? AND receipt.amount>0 THEN
        MAX(0,MIN(source.remaining_amount,source.refundable_cash_amount,
          ROUND(receipt.amount-source.refunded_amount-COALESCE((SELECT SUM(amount) FROM payment_allocations
            WHERE payment_id=receipt.id AND voided_at IS NULL),0),2))) ELSE 0 END),0),2) available_amount
      FROM customer_credit_sources source JOIN payments receipt ON receipt.id=source.origin_payment_id
      WHERE source.customer_id=? AND source.kind='UNAPPLIED_CASH' AND source.voided_at IS NULL
        AND receipt.customer_id=source.customer_id AND receipt.payment_kind='UNAPPLIED_RECEIPT' AND receipt.voided_at IS NULL`).get(date, customerId);
    const count = db.prepare<[number], { total: number }>(`SELECT COUNT(*) total
      FROM customer_credit_sources source JOIN payments receipt ON receipt.id=source.origin_payment_id
      WHERE source.customer_id=? AND source.kind='UNAPPLIED_CASH'
        AND receipt.customer_id=source.customer_id AND receipt.payment_kind='UNAPPLIED_RECEIPT'`).get(customerId)?.total ?? 0;
    const rows = db.prepare<[number, number, number], Omit<CashReceipt, 'can_reverse'> & { can_reverse: number }>(`SELECT
      source.id source_id,receipt.id payment_id,receipt.payment_no,receipt.payment_date,receipt.payment_method,
      receipt.amount original_amount,source.consumed_amount applied_amount,source.refunded_amount,
      source.remaining_amount,COALESCE(receipt.voided_at,source.voided_at) voided_at,
      CASE WHEN receipt.voided_at IS NULL AND source.voided_at IS NULL
        AND source.consumed_amount=0 AND source.refunded_amount=0
        AND NOT EXISTS (SELECT 1 FROM credit_source_consumptions WHERE source_id=source.id AND voided_at IS NULL)
        AND NOT EXISTS (SELECT 1 FROM payment_allocations WHERE payment_id=receipt.id AND voided_at IS NULL)
        THEN 1 ELSE 0 END can_reverse
      FROM customer_credit_sources source JOIN payments receipt ON receipt.id=source.origin_payment_id
      WHERE source.customer_id=? AND source.kind='UNAPPLIED_CASH'
        AND receipt.customer_id=source.customer_id AND receipt.payment_kind='UNAPPLIED_RECEIPT'
      ORDER BY receipt.payment_date DESC,receipt.id DESC LIMIT ? OFFSET ?`).all(customerId, limit, (page - 1) * limit);
    return {
      success: true,
      data: { customer_id: customerId, operation_date: date, remaining_amount: totals?.remaining_amount ?? 0,
        available_amount: totals?.available_amount ?? 0, refundable_amount: totals?.available_amount ?? 0,
        receipts: rows.map(row => ({ ...row, can_reverse: row.can_reverse === 1 })) },
      pagination: pagination(page, limit, count),
    };
  })();
}

export interface CashActivityLine {
  id: number;
  application_id: number;
  source_id: number;
  invoice_id: number | null;
  invoice_no: string | null;
  payment_id: number | null;
  amount: number;
  kind: 'APPLY' | 'REFUND';
  voided_at: string | null;
}

interface CashActivity {
  application_id: number;
  operation: 'APPLY' | 'REFUND';
  operation_date: string;
  total_amount: number;
  payment_id: number | null;
}

export interface CashActivityResponse {
  success: true;
  data: (CashActivity & { lines: CashActivityLine[] })[];
  pagination: CashPagination;
}

export function getCashActivity(db: Database.Database, customerId: number, page: number, limit: number, fromDate?: string, toDate?: string): CashActivityResponse {
  return db.transaction((): CashActivityResponse => {
    requireCustomer(db, customerId);
    const from = fromDate ?? null;
    const to = toDate ?? null;
    const count = db.prepare<[number, string | null, string | null, string | null, string | null], { total: number }>(`SELECT COUNT(*) total
      FROM credit_applications WHERE customer_id=? AND (? IS NULL OR operation_date>=?) AND (? IS NULL OR operation_date<=?)`)
      .get(customerId, from, from, to, to)?.total ?? 0;
    const rows = db.prepare<[number, string | null, string | null, string | null, string | null, number, number], CashActivity>(`SELECT
      id application_id,operation,operation_date,total_amount,payment_id FROM credit_applications
      WHERE customer_id=? AND (? IS NULL OR operation_date>=?) AND (? IS NULL OR operation_date<=?)
      ORDER BY operation_date DESC,id DESC LIMIT ? OFFSET ?`).all(customerId, from, from, to, to, limit, (page - 1) * limit);
    const lines = db.prepare<[number, string | null, string | null, string | null, string | null, number, number], CashActivityLine>(`SELECT
      consumption.id,consumption.application_id,consumption.source_id,consumption.invoice_id,invoice.invoice_no,
      consumption.payment_id,consumption.amount,consumption.kind,consumption.voided_at
      FROM credit_source_consumptions consumption LEFT JOIN invoices invoice ON invoice.id=consumption.invoice_id
      WHERE consumption.application_id IN (SELECT id FROM credit_applications
        WHERE customer_id=? AND (? IS NULL OR operation_date>=?) AND (? IS NULL OR operation_date<=?)
        ORDER BY operation_date DESC,id DESC LIMIT ? OFFSET ?)
      ORDER BY consumption.application_id,consumption.id`).all(customerId, from, from, to, to, limit, (page - 1) * limit);
    const grouped = new Map<number, CashActivityLine[]>();
    for (const line of lines) {
      const group = grouped.get(line.application_id) ?? [];
      group.push(line);
      grouped.set(line.application_id, group);
    }
    return { success: true, data: rows.map(row => ({ ...row, lines: grouped.get(row.application_id) ?? [] })), pagination: pagination(page, limit, count) };
  })();
}
