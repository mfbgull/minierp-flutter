import type Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { SupplierPaymentService } from '../services/SupplierPaymentService';
import type { SupplierPaymentAllocation } from '../services/paymentRecordingTypes';
import { isValidPaymentMethod } from '../services/cashService';
import { BusinessRuleError } from '../utils/businessRuleError';
import { addCurrency, roundCurrency } from '../utils/currency';
import { claimIdempotencyKey, hashRequestPayload, startIdempotentRequest } from '../utils/idempotency';

interface PrepaymentInput {
  supplier_id: number;
  prepay_date: string;
  amount: number;
  payment_method: string;
  reference_no?: string;
  notes?: string;
}
export interface SupplierPrepayment extends PrepaymentInput {
  id: number;
  applied_amount: number;
  available_amount: number;
  voided_at: string | null;
}
export interface SupplierPaymentTarget {
  kind: SupplierPaymentAllocation['kind'];
  id: number;
  reference: string;
  balance_amount: number;
}
type Headers = Record<string, string | string[] | undefined>;
const PREPAYMENT_SELECT = `
  SELECT a.*, COALESCE(used.amount, 0) AS applied_amount,
    CASE WHEN a.voided_at IS NULL THEN ROUND(a.amount - COALESCE(used.amount, 0), 2) ELSE 0 END AS available_amount
  FROM supplier_prepayments a LEFT JOIN (
    SELECT x.prepayment_id, SUM(x.amount) AS amount FROM supplier_prepayment_applications x
    JOIN payments p ON p.id = x.payment_id WHERE p.voided_at IS NULL GROUP BY x.prepayment_id
  ) used ON used.prepayment_id = a.id
`;

export class SupplierPrepaymentModel {
  constructor(private readonly db: Database.Database) {}

  get(id: number): SupplierPrepayment {
    const source = this.db.prepare(`${PREPAYMENT_SELECT} WHERE a.id = ?`).get(id) as SupplierPrepayment | undefined;
    if (!source) throw new BusinessRuleError(404, 'Supplier advance not found');
    return source;
  }

  list(supplierId: number, page: number, limit: number): SupplierPrepayment[] {
    return this.db.prepare(`${PREPAYMENT_SELECT} WHERE a.supplier_id = ? ORDER BY a.prepay_date DESC, a.id DESC LIMIT ? OFFSET ?`).all(supplierId, limit, (page - 1) * limit) as SupplierPrepayment[];
  }

  count(supplierId: number): number {
    return (this.db.prepare('SELECT COUNT(*) AS count FROM supplier_prepayments WHERE supplier_id = ?').get(supplierId) as { count: number }).count;
  }

  targets(id: number, search: string): SupplierPaymentTarget[] {
    const source = this.get(id);
    if (source.voided_at) throw new BusinessRuleError(409, 'Supplier advance is voided');
    return this.db.prepare(`
      SELECT * FROM (
        SELECT 'purchase' AS kind, p.id, p.purchase_no AS reference,
          ROUND(v.total_payable - v.returned_amount - v.paid_amount, 2) AS balance_amount
        FROM purchases p JOIN direct_purchase_payables v ON v.id = p.id
        WHERE p.supplier_id = ? AND p.voided_at IS NULL
        UNION ALL
        SELECT 'purchase_order', po.id, po.po_no,
          ROUND(v.total_payable - v.returned_amount - v.paid_amount, 2)
        FROM purchase_orders po JOIN purchase_order_payables v ON v.id = po.id
        WHERE po.supplier_id = ? AND LOWER(po.status) <> 'cancelled'
        UNION ALL
        SELECT 'supplier_bill', b.id, b.bill_no,
          ROUND(b.total_amount - COALESCE((SELECT SUM(a.amount) FROM supplier_bill_allocations a JOIN payments p ON p.id = a.payment_id WHERE a.bill_id = b.id AND a.voided_at IS NULL AND p.voided_at IS NULL), 0), 2)
        FROM supplier_bills b WHERE b.supplier_id = ? AND b.voided_at IS NULL
      ) WHERE balance_amount > 0 AND reference LIKE ? COLLATE NOCASE
      ORDER BY reference LIMIT 50
    `).all(source.supplier_id, source.supplier_id, source.supplier_id, `%${search}%`) as SupplierPaymentTarget[];
  }

  create(input: PrepaymentInput, userId: number, headers: Headers): SupplierPrepayment {
    return this.db.transaction(() => {
      const hash = hashRequestPayload(input);
      const start = startIdempotentRequest(this.db, headers, 'supplier-prepayments.create', hash);
      if (start.kind === 'error') throw new BusinessRuleError(start.status, start.message);
      if (start.kind === 'replay') return this.get(start.resourceId);
      const amount = roundCurrency(input.amount);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 1e9 || !isValidPaymentMethod(input.payment_method)) throw new BusinessRuleError(400, 'Invalid supplier advance amount or payment method');
      if (!this.db.prepare('SELECT id FROM suppliers WHERE id = ? AND is_active = 1').get(input.supplier_id)) throw new BusinessRuleError(404, 'Active supplier not found');
      AccountingService.assertPeriodNotClosed(this.db, input.prepay_date, 'Supplier advance');
      const cash = AccountingService.getAccountByCode(this.db, AccountingService._cashOrBankAccountCode(input.payment_method));
      const advance = AccountingService.getAccountByCode(this.db, '1330');
      if (!cash || !advance) throw new Error('Supplier advance accounts are missing');
      AccountingService.assertSufficientFunds(this.db, { accountId: cash.id, amount, asOfDate: input.prepay_date, label: 'Supplier advance' });
      const result = this.db.prepare(`INSERT INTO supplier_prepayments
        (supplier_id, prepay_date, amount, payment_method, reference_no, notes, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)`).run(input.supplier_id, input.prepay_date, amount, input.payment_method, input.reference_no ?? null, input.notes ?? null, userId);
      const id = Number(result.lastInsertRowid);
      AccountingService.postEntry(this.db, {
        entry_date: input.prepay_date, reference_type: 'SUPPLIER_PREPAYMENT', reference_id: id,
        description: `Supplier advance ${id}`, created_by: userId,
        lines: [{ account_id: advance.id, debit: amount }, { account_id: cash.id, credit: amount }],
      });
      if (start.key) claimIdempotencyKey(this.db, 'supplier-prepayments.create', start.key, hash, id);
      return this.get(id);
    })();
  }

  apply(id: number, input: { applied_at: string; allocations: SupplierPaymentAllocation[] }, userId: number, headers: Headers): { id: number } {
    return this.db.transaction(() => {
      const hash = hashRequestPayload({ prepaymentId: id, ...input });
      const start = startIdempotentRequest(this.db, headers, 'supplier-prepayments.apply', hash);
      if (start.kind === 'error') throw new BusinessRuleError(start.status, start.message);
      if (start.kind === 'replay') return { id: start.resourceId };
      const source = this.get(id);
      if (source.voided_at) throw new BusinessRuleError(409, 'Supplier advance is voided');
      const amount = input.allocations.reduce((sum, allocation) => addCurrency(sum, allocation.amount), 0);
      if (!Number.isFinite(amount) || amount <= 0 || amount > source.available_amount) throw new BusinessRuleError(400, 'Application exceeds the available supplier advance');
      const payment = new SupplierPaymentService(this.db).recordSupplierPayment({
        supplierId: source.supplier_id, paymentDate: input.applied_at, amount, paymentMethod: 'credit',
        allocations: input.allocations, supplierPrepaymentId: id, userId,
        notes: `Supplier advance ${id} applied`,
      });
      if (start.key) claimIdempotencyKey(this.db, 'supplier-prepayments.apply', start.key, hash, payment.paymentId);
      return { id: payment.paymentId };
    })();
  }

  void(id: number, userId: number, reason: string): SupplierPrepayment {
    return this.db.transaction(() => {
      const source = this.get(id);
      if (source.voided_at) return source;
      if (source.applied_amount > 0) throw new BusinessRuleError(409, 'Reverse supplier advance applications before voiding');
      AccountingService.assertPeriodNotClosed(this.db, source.prepay_date, 'Supplier advance');
      AccountingService.voidJournalLinesByReference(this.db, 'SUPPLIER_PREPAYMENT', id, { voidedBy: userId, voidReason: reason });
      this.db.prepare('UPDATE supplier_prepayments SET voided_at = CURRENT_TIMESTAMP, voided_by = ?, void_reason = ? WHERE id = ?').run(userId, reason, id);
      return this.get(id);
    })();
  }
}
