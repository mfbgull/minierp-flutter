import type Database from 'better-sqlite3';

export interface AdjustmentSettlementRow {
  id: number;
  payment_no: string;
  payment_date: string;
  payment_method: string;
  reference_no: string;
  notes: string;
  amount: number;
}

interface AdjustmentRow {
  amount: number;
  adjustment_no: string;
  adjustment_date: string;
  notes: string | null;
}

function adjustmentRows(
  db: Database.Database,
  target: { kind: 'invoice' | 'purchase' | 'purchase_order'; id: number },
): AdjustmentRow[] {
  switch (target.kind) {
    case 'invoice':
      return db.prepare<[number], AdjustmentRow>(`
        SELECT a.amount, p.adjustment_no, p.adjustment_date, p.notes
        FROM party_adjustment_receivables a JOIN party_adjustments p ON p.id = a.adjustment_id
        WHERE a.invoice_id = ? AND p.status = 'posted'
      `).all(target.id);
    case 'purchase':
      return db.prepare<[number], AdjustmentRow>(`
        SELECT a.amount, p.adjustment_no, p.adjustment_date, p.notes
        FROM party_adjustment_payables a JOIN party_adjustments p ON p.id = a.adjustment_id
        WHERE a.purchase_id = ? AND p.status = 'posted'
      `).all(target.id);
    case 'purchase_order':
      return db.prepare<[number], AdjustmentRow>(`
        SELECT a.amount, p.adjustment_no, p.adjustment_date, p.notes
        FROM party_adjustment_payables a JOIN party_adjustments p ON p.id = a.adjustment_id
        WHERE a.purchase_order_id = ? AND p.status = 'posted'
      `).all(target.id);
  }
}

export function appendAdjustmentSettlements(
  db: Database.Database,
  rows: AdjustmentSettlementRow[],
  target: { kind: 'invoice' | 'purchase' | 'purchase_order'; id: number },
): void {
  for (const adjustment of adjustmentRows(db, target)) {
    rows.push({
      id: 0,
      payment_no: adjustment.adjustment_no,
      payment_date: adjustment.adjustment_date,
      payment_method: 'ADJUSTMENT',
      reference_no: `Noncash adjustment ${adjustment.adjustment_no}`,
      notes: adjustment.notes ?? 'Customer and supplier balance adjustment',
      amount: adjustment.amount,
    });
  }
  rows.sort((left, right) => (right.payment_date || '').localeCompare(left.payment_date || ''));
}
