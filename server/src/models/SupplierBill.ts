import type Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { SupplierPaymentService } from '../services/SupplierPaymentService';
import { BusinessRuleError } from '../utils/businessRuleError';
import { roundCurrency } from '../utils/currency';
import { claimIdempotencyKey, hashRequestPayload, startIdempotentRequest } from '../utils/idempotency';
import ledgerUtils from '../utils/ledgerUtils';
import SupplierLedgerModel from './SupplierLedger';

export interface SupplierBillInput {
  supplier_id: number;
  bill_no: string;
  bill_date: string;
  due_date?: string;
  description: string;
  net_amount: number;
  input_tax_amount: number;
}
export interface SupplierBill extends SupplierBillInput {
  id: number;
  supplier_name: string;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  voided_at: string | null;
}
type Headers = Record<string, string | string[] | undefined>;
interface BillPaymentInput { amount: number; payment_date: string; payment_method: string; reference_no?: string }

const BILL_SELECT = `
  SELECT b.*, s.supplier_name,
    COALESCE(paid.amount, 0) AS paid_amount,
    CASE WHEN b.voided_at IS NULL THEN ROUND(b.total_amount - COALESCE(paid.amount, 0), 2) ELSE 0 END AS balance_amount
  FROM supplier_bills b JOIN suppliers s ON s.id = b.supplier_id
  LEFT JOIN (
    SELECT a.bill_id, SUM(a.amount) AS amount FROM supplier_bill_allocations a
    JOIN payments p ON p.id = a.payment_id
    WHERE a.voided_at IS NULL AND p.voided_at IS NULL GROUP BY a.bill_id
  ) paid ON paid.bill_id = b.id
`;

export class SupplierBillModel {
  constructor(private readonly db: Database.Database) {}

  list(supplierId: number, page: number, limit: number): SupplierBill[] {
    return this.db.prepare(`${BILL_SELECT} WHERE b.supplier_id = ? ORDER BY b.bill_date DESC, b.id DESC LIMIT ? OFFSET ?`).all(supplierId, limit, (page - 1) * limit) as SupplierBill[];
  }

  count(supplierId: number): number {
    return (this.db.prepare('SELECT COUNT(*) AS count FROM supplier_bills WHERE supplier_id = ?').get(supplierId) as { count: number }).count;
  }

  get(id: number): SupplierBill {
    const bill = this.db.prepare(`${BILL_SELECT} WHERE b.id = ?`).get(id) as SupplierBill | undefined;
    if (!bill) throw new BusinessRuleError(404, 'Supplier bill not found');
    return bill;
  }

  create(input: SupplierBillInput, userId: number, headers: Headers): SupplierBill {
    return this.db.transaction(() => {
      const hash = hashRequestPayload(input);
      const start = startIdempotentRequest(this.db, headers, 'supplier-bills.create', hash);
      if (start.kind === 'error') throw new BusinessRuleError(start.status, start.message);
      if (start.kind === 'replay') return this.get(start.resourceId);
      const net = roundCurrency(input.net_amount);
      const tax = roundCurrency(input.input_tax_amount);
      const total = roundCurrency(net + tax);
      if (!Number.isFinite(total) || net <= 0 || tax < 0 || total > 1e9) throw new BusinessRuleError(400, 'Invalid supplier bill amounts');
      if (!this.db.prepare('SELECT id FROM suppliers WHERE id = ? AND is_active = 1').get(input.supplier_id)) throw new BusinessRuleError(404, 'Active supplier not found');
      const billNo = input.bill_no.trim();
      if (!billNo) throw new BusinessRuleError(400, 'Supplier invoice number is required');
      if (input.due_date && input.due_date < input.bill_date) throw new BusinessRuleError(400, 'Due date cannot precede the bill');
      if (this.db.prepare('SELECT id FROM supplier_bills WHERE supplier_id = ? AND bill_no = ? AND voided_at IS NULL').get(input.supplier_id, billNo)) throw new BusinessRuleError(409, 'Supplier invoice number already recorded');
      AccountingService.assertPeriodNotClosed(this.db, input.bill_date, 'Supplier bill');
      const result = this.db.prepare(`INSERT INTO supplier_bills
        (supplier_id, bill_no, bill_date, due_date, description, net_amount, input_tax_amount, total_amount, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(input.supplier_id, billNo, input.bill_date, input.due_date ?? null, input.description, net, tax, total, userId);
      const id = Number(result.lastInsertRowid);
      const expense = AccountingService.getAccountByCode(this.db, '6000');
      const inputTax = AccountingService.getAccountByCode(this.db, '1320');
      const payable = AccountingService.getAccountByCode(this.db, '2000');
      if (!expense || !inputTax || !payable) throw new Error('Supplier bill accounts are missing');
      AccountingService.postEntry(this.db, {
        entry_date: input.bill_date, description: `Supplier bill ${billNo}`,
        reference_type: 'SUPPLIER_BILL', reference_id: id, created_by: userId,
        lines: [
          { account_id: expense.id, debit: net },
          ...(tax > 0 ? [{ account_id: inputTax.id, debit: tax }] : []),
          { account_id: payable.id, credit: total },
        ],
      });
      SupplierLedgerModel.createEntry({ supplier_id: input.supplier_id, transaction_date: input.bill_date,
        transaction_type: 'SUPPLIER_BILL', reference_no: `BILL-${id}`, debit: total, description: billNo }, this.db);
      SupplierLedgerModel.rebuildBalances(input.supplier_id, this.db);
      if (start.key) claimIdempotencyKey(this.db, 'supplier-bills.create', start.key, hash, id);
      return this.get(id);
    })();
  }

  pay(id: number, input: BillPaymentInput, userId: number, headers: Headers): { id: number } {
    return this.db.transaction(() => {
      const hash = hashRequestPayload({ billId: id, ...input });
      const start = startIdempotentRequest(this.db, headers, 'supplier-bills.pay', hash);
      if (start.kind === 'error') throw new BusinessRuleError(start.status, start.message);
      if (start.kind === 'replay') return { id: start.resourceId };
      const bill = this.get(id);
      if (bill.voided_at) throw new BusinessRuleError(409, 'Supplier bill is voided');
      const amount = roundCurrency(input.amount);
      if (!Number.isFinite(amount) || amount <= 0 || amount > bill.balance_amount) throw new BusinessRuleError(400, 'Payment exceeds the outstanding bill');
      if (input.payment_date < bill.bill_date) throw new BusinessRuleError(400, 'Payment cannot precede the supplier bill');
      const payment = new SupplierPaymentService(this.db).recordSupplierPayment({
        supplierId: bill.supplier_id, paymentDate: input.payment_date, amount,
        paymentMethod: input.payment_method, referenceNo: input.reference_no, userId,
        allocations: [{ kind: 'supplier_bill', id, amount }],
      });
      if (start.key) claimIdempotencyKey(this.db, 'supplier-bills.pay', start.key, hash, payment.paymentId);
      return { id: payment.paymentId };
    })();
  }

  void(id: number, userId: number, reason: string): SupplierBill {
    return this.db.transaction(() => {
      const bill = this.get(id);
      if (bill.voided_at) return bill;
      if (bill.paid_amount > 0) throw new BusinessRuleError(409, 'Reverse supplier bill payments before voiding');
      AccountingService.assertPeriodNotClosed(this.db, bill.bill_date, 'Supplier bill');
      AccountingService.voidJournalLinesByReference(this.db, 'SUPPLIER_BILL', id, { voidedBy: userId, voidReason: reason });
      const rows = this.db.prepare("SELECT id FROM supplier_ledger WHERE supplier_id = ? AND reference_no = ? AND transaction_type = 'SUPPLIER_BILL' AND voided = 0").all(bill.supplier_id, `BILL-${id}`) as Array<{ id: number }>;
      for (const row of rows) ledgerUtils.reverseLedgerEntry('supplier_ledger', row.id, reason);
      SupplierLedgerModel.rebuildBalances(bill.supplier_id, this.db);
      this.db.prepare('UPDATE supplier_bills SET voided_at = CURRENT_TIMESTAMP, voided_by = ?, void_reason = ? WHERE id = ?').run(userId, reason, id);
      return this.get(id);
    })();
  }
}
