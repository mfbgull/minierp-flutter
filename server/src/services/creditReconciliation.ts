import type Database from 'better-sqlite3';
import { roundCurrency, toMinorUnits } from '../utils/currency';

export interface ReconciliationRow {
  readonly customerId: number;
  readonly storedCreditBalance: number;
  readonly ledgerGranted: number;
  readonly ledgerRefunded: number;
  readonly ledgerConsumed: number;
  readonly ledgerDerived: number;
  readonly agrees: boolean;
}

export function reconcileCustomerCredits(db: Database.Database): ReconciliationRow[] {
  const rows = db.prepare<[], Omit<ReconciliationRow, 'ledgerDerived' | 'agrees'>>(`
    SELECT customer.id AS customerId,
           customer.credit_balance AS storedCreditBalance,
           COALESCE(grants.granted, 0) AS ledgerGranted,
           COALESCE(refunds.refunded, 0) AS ledgerRefunded,
           COALESCE(consumptions.consumed, 0) AS ledgerConsumed
    FROM customers customer
    LEFT JOIN (
      SELECT customer_id, SUM(credit) granted FROM customer_ledger
      WHERE transaction_type = 'RETURN' AND credit > 0
        AND COALESCE(voided, 0) = 0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) grants ON grants.customer_id = customer.id
    LEFT JOIN (
      SELECT customer_id, SUM(debit) refunded FROM customer_ledger
      WHERE transaction_type = 'REFUND' AND debit > 0
        AND COALESCE(voided, 0) = 0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) refunds ON refunds.customer_id = customer.id
    LEFT JOIN (
      SELECT customer_id, SUM(credit) consumed FROM customer_ledger
      WHERE transaction_type = 'CREDIT_OFFSET' AND credit > 0
        AND COALESCE(voided, 0) = 0 AND reversed_by IS NULL
      GROUP BY customer_id
    ) consumptions ON consumptions.customer_id = customer.id
    WHERE grants.customer_id IS NOT NULL OR refunds.customer_id IS NOT NULL
       OR consumptions.customer_id IS NOT NULL OR customer.credit_balance <> 0
    ORDER BY customer.id
  `).all();

  return rows.map(row => {
    const ledgerDerived = roundCurrency(row.ledgerGranted - row.ledgerRefunded - row.ledgerConsumed);
    return {
      ...row,
      ledgerDerived,
      agrees: toMinorUnits(row.storedCreditBalance) === toMinorUnits(ledgerDerived),
    };
  });
}
