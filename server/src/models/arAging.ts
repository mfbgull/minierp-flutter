import type Database from 'better-sqlite3';
import { addCurrency } from '../utils/currency';

interface AgingBucket {
  readonly customer_name: string;
  readonly customer_code: string;
  readonly total_outstanding: number;
  readonly current_amount: number;
  readonly days_1_30: number;
  readonly days_31_60: number;
  readonly days_61_90: number;
  readonly days_over_90: number;
}

export function computeARAging(asOfDate: string, db: Database.Database) {
  const agingBuckets = db.prepare<{ asOf: string }, AgingBucket>(`
    WITH allocations AS (
      SELECT a.invoice_id, SUM(a.amount) AS all_paid,
        SUM(CASE WHEN p.payment_kind <> 'UNAPPLIED_RECEIPT' AND p.payment_date <= @asOf
          THEN a.amount ELSE 0 END) AS dated_paid
      FROM payment_allocations a JOIN payments p ON p.id = a.payment_id
      WHERE a.amount > 0 AND a.voided_at IS NULL AND p.voided_at IS NULL
      GROUP BY a.invoice_id
    ), applications AS (
      SELECT draw.invoice_id, SUM(draw.amount) AS dated_paid
      FROM credit_source_consumptions draw
      JOIN credit_applications application ON application.id = draw.application_id
      JOIN customer_credit_sources source ON source.id = draw.source_id
      WHERE draw.kind = 'APPLY' AND draw.voided_at IS NULL
        AND source.kind = 'UNAPPLIED_CASH' AND source.voided_at IS NULL
        AND application.operation_date <= @asOf
      GROUP BY draw.invoice_id
    ), returns AS (
      SELECT invoice_id, SUM(returned_amount) AS all_returned, SUM(fee_amount) AS all_fees,
        SUM(CASE WHEN return_date <= @asOf THEN returned_amount - fee_amount ELSE 0 END) AS dated_net
      FROM invoice_returns WHERE voided_at IS NULL AND status <> 'Voided'
      GROUP BY invoice_id
    ), historical AS (
      SELECT i.customer_id, i.due_date,
        MAX(0, ROUND(i.total_amount - COALESCE(i.credit_offset, 0)
          - MAX(0, COALESCE(i.paid_amount, 0) - COALESCE(i.credit_offset, 0) - COALESCE(a.all_paid, 0))
          - COALESCE(a.dated_paid, 0) - COALESCE(application.dated_paid, 0)
          - MAX(0, COALESCE(i.returned_amount, 0) - COALESCE(r.all_returned, 0))
          + MAX(0, COALESCE(i.return_fee, 0) - COALESCE(r.all_fees, 0))
          - COALESCE(r.dated_net, 0), 2)) AS balance_amount
      FROM invoices i
      LEFT JOIN allocations a ON a.invoice_id = i.id
      LEFT JOIN applications application ON application.invoice_id = i.id
      LEFT JOIN returns r ON r.invoice_id = i.id
      WHERE i.invoice_date <= @asOf AND i.deleted_at IS NULL
        AND i.status NOT IN ('Cancelled', 'Draft', 'Deleted')
    )
    SELECT c.customer_name, c.customer_code, ROUND(SUM(i.balance_amount), 2) AS total_outstanding,
      ROUND(SUM(CASE WHEN i.due_date IS NULL OR julianday(@asOf) <= julianday(i.due_date)
        THEN i.balance_amount ELSE 0 END), 2) AS current_amount,
      ROUND(SUM(CASE WHEN julianday(@asOf) - julianday(i.due_date) > 0
        AND julianday(@asOf) - julianday(i.due_date) <= 30 THEN i.balance_amount ELSE 0 END), 2) AS days_1_30,
      ROUND(SUM(CASE WHEN julianday(@asOf) - julianday(i.due_date) > 30
        AND julianday(@asOf) - julianday(i.due_date) <= 60 THEN i.balance_amount ELSE 0 END), 2) AS days_31_60,
      ROUND(SUM(CASE WHEN julianday(@asOf) - julianday(i.due_date) > 60
        AND julianday(@asOf) - julianday(i.due_date) <= 90 THEN i.balance_amount ELSE 0 END), 2) AS days_61_90,
      ROUND(SUM(CASE WHEN julianday(@asOf) - julianday(i.due_date) > 90
        THEN i.balance_amount ELSE 0 END), 2) AS days_over_90
    FROM historical i JOIN customers c ON c.id = i.customer_id
    WHERE i.balance_amount > 0
    GROUP BY i.customer_id, c.customer_name, c.customer_code
    ORDER BY total_outstanding DESC
  `).all({ asOf: asOfDate });

  const summary = agingBuckets.reduce((sum, row) => ({
    totalReceivables: addCurrency(sum.totalReceivables, row.total_outstanding),
    current_amount: addCurrency(sum.current_amount, row.current_amount),
    total_1_30: addCurrency(sum.total_1_30, row.days_1_30),
    total_31_60: addCurrency(sum.total_31_60, row.days_31_60),
    total_61_90: addCurrency(sum.total_61_90, row.days_61_90),
    total_over_90: addCurrency(sum.total_over_90, row.days_over_90),
  }), { totalReceivables: 0, current_amount: 0, total_1_30: 0, total_31_60: 0, total_61_90: 0, total_over_90: 0 });
  return { asOfDate, agingBuckets, summary };
}
