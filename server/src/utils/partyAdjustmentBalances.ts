import type Database from 'better-sqlite3';
import { BusinessRuleError } from './businessRuleError';
import { parseCurrency } from './currency';

export function invoiceAdjustmentAmount(db: Database.Database, invoiceId: number): number {
  const row = db.prepare<[number], { amount: number }>(`
    SELECT COALESCE(SUM(a.amount), 0) AS amount
    FROM party_adjustment_receivables a JOIN party_adjustments p ON p.id = a.adjustment_id
    WHERE a.invoice_id = ? AND p.status = 'posted'
  `).get(invoiceId);
  return parseCurrency(row?.amount);
}

export function assertNoPartyAdjustment(
  db: Database.Database,
  kind: 'invoice' | 'purchase' | 'purchase_order' | 'supplier_bill',
  id: number,
): void {
  const row = kind === 'invoice'
    ? db.prepare<[number], { id: number }>(`SELECT p.id
        FROM party_adjustment_receivables a JOIN party_adjustments p ON p.id = a.adjustment_id
        WHERE a.invoice_id = ? AND p.status = 'posted' LIMIT 1`).get(id)
    : db.prepare<{ kind: string; id: number }, { id: number }>(`SELECT p.id
        FROM party_adjustment_payables a JOIN party_adjustments p ON p.id = a.adjustment_id
        WHERE p.status = 'posted' AND ((@kind = 'purchase' AND a.purchase_id = @id)
          OR (@kind = 'purchase_order' AND a.purchase_order_id = @id)
          OR (@kind = 'supplier_bill' AND a.bill_id = @id)) LIMIT 1`).get({ kind, id });
  if (row) throw new BusinessRuleError(409, 'Reverse the active customer-supplier adjustment before changing this document');
}
