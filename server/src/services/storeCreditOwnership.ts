import type Database from 'better-sqlite3';
import { toMinorUnits } from '../utils/currency';
import InvoiceReturnModel from '../models/InvoiceReturn';
import { computePosition } from './returnMath';

/** Called inside invoice creation's transaction; old unknown draws stay locked. */
export function recordStoreCreditDraws(db: Database.Database, customerId: number, invoiceId: number, amount: number): void {
  let remaining = toMinorUnits(amount);
  const sources = db.prepare(`
    SELECT s.id, s.amount, COALESCE(SUM(d.amount_minor),0) AS drawn
    FROM return_settlements s JOIN invoice_returns r ON r.id=s.return_id
    LEFT JOIN store_credit_draws d ON d.settlement_id=s.id
    WHERE r.customer_id=? AND r.voided_at IS NULL AND s.voided_at IS NULL AND s.type='credit'
    GROUP BY s.id ORDER BY s.id
  `).all(customerId) as Array<{ id: number; amount: number; drawn: number }>;
  const insert = db.prepare('INSERT INTO store_credit_draws(settlement_id,invoice_id,amount_minor) VALUES(?,?,?)');
  for (const source of sources) {
    const draw = Math.min(remaining, Math.max(0, toMinorUnits(source.amount) - source.drawn));
    if (draw > 0) insert.run(source.id, invoiceId, draw);
    remaining -= draw;
    if (remaining === 0) break;
  }
  // An old manually seeded pool may lack a source. Its consuming ledger row
  // remains the conservative reversal lock below; do not invent provenance.
}

export function hasStoreCreditConsumption(db: Database.Database, customerId: number, settlementId: number): boolean {
  if (db.prepare('SELECT 1 FROM store_credit_draws WHERE settlement_id=? LIMIT 1').get(settlementId)) return true;
  // Pre-migration consumption has no reliable source ownership. Refuse source
  // reversal until separately reconciled, even if a new credit refills the pool.
  return !!db.prepare(`
    SELECT 1 FROM customer_ledger l JOIN invoices i ON l.reference_no='CREDIT-'||i.invoice_no
    WHERE l.customer_id=? AND l.transaction_type='CREDIT' AND l.credit>0
      AND COALESCE(l.voided,0)=0 AND l.reversed_by IS NULL
      AND NOT EXISTS (SELECT 1 FROM store_credit_draws d WHERE d.invoice_id=i.id)
    LIMIT 1
  `).get(customerId);
}

/** Ledger credit already exists. Record its application without another credit or cash leg. */
export function recordLedgerCreditDraws(db: Database.Database, customerId: number, invoiceId: number, invoiceNo: string, amount: number, date: string, userId: number): void {
  let remaining = toMinorUnits(amount);
  const sources = db.prepare(`SELECT r.id,r.invoice_id,r.return_no,r.net_amount,r.settled_amount,
      i.total_amount,i.returned_amount,i.return_fee,i.credit_offset,
      (SELECT COALESCE(SUM(CASE WHEN a.amount>0 THEN a.amount ELSE 0 END),0) FROM payment_allocations a WHERE a.invoice_id=i.id AND a.voided_at IS NULL) AS paid,
      (SELECT COALESCE(SUM(s.amount),0) FROM return_settlements s JOIN invoice_returns t ON t.id=s.return_id
        WHERE t.invoice_id=i.id AND t.voided_at IS NULL AND s.voided_at IS NULL) AS settled
    FROM invoice_returns r JOIN invoices i ON i.id=r.invoice_id
    WHERE r.customer_id=? AND r.voided_at IS NULL AND r.net_amount>r.settled_amount
    ORDER BY r.id`).all(customerId) as Array<{ id: number; invoice_id: number; return_no: string; net_amount: number; settled_amount: number;
      total_amount: number; returned_amount: number; return_fee: number; credit_offset: number; paid: number; settled: number }>;
  const allocated = new Map<number, number>();
  for (const source of sources) {
    const position = computePosition({ originalTotal: source.total_amount, totalReturned: source.returned_amount,
      totalFees: source.return_fee, totalPaid: source.paid + source.credit_offset, totalSettled: source.settled });
    const capacity = Math.max(0, toMinorUnits(position.remainingSettlementCapacity) - (allocated.get(source.invoice_id) ?? 0));
    const draw = Math.min(remaining, capacity, toMinorUnits(source.net_amount - source.settled_amount));
    if (draw <= 0) continue;
    const settlement = InvoiceReturnModel.createSettlement(db, { return_id: source.id,
      settlement_no: `ADJ-${source.return_no}-INV-${invoiceNo}`, type: 'adjust', amount: draw / 100,
      reference: invoiceNo, target_invoice_id: invoiceId, settled_date: date, created_by: userId });
    db.prepare('INSERT INTO store_credit_draws(settlement_id,invoice_id,amount_minor) VALUES(?,?,?)').run(settlement.id, invoiceId, draw);
    allocated.set(source.invoice_id, (allocated.get(source.invoice_id) ?? 0) + draw);
    remaining -= draw;
    if (remaining === 0) break;
  }
  // Pre-table historical ledger credits may have no return source; do not invent one.
}
