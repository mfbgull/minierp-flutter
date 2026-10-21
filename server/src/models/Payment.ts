import Database from 'better-sqlite3';
import { getNextSequenceNumber } from '../utils/sequence';
import ledgerUtils from '../utils/ledgerUtils';
import AccountingService from '../services/accountingService';
import { assertCashTimeline } from '../services/cashBalanceGuard';
import { parseCurrency } from '../utils/currency';
import SupplierLedgerModel from './SupplierLedger';
import { isValidPaymentMethod } from '../services/cashService';
import { PaymentRecordingService } from '../services/PaymentRecordingService';
import { SupplierPaymentService } from '../services/SupplierPaymentService';
import type { SupplierPaymentAllocation } from '../services/paymentRecordingTypes';
import { assertLegacyPaymentAllowed, assertLegacyInvoiceAllocationsAllowed } from '../services/unappliedPaymentGuard';
import { BusinessRuleError } from '../utils/businessRuleError';

interface PaymentFilters {
  search?: string;
  customerId?: string;
  supplierId?: string;
  fromDate?: string;
  toDate?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface UnifiedPaymentFilters {
  search?: string;
  type?: string;
  fromDate?: string;
  toDate?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface InvoiceAllocation {
  invoice_id: string;
  amount: number;
}

interface CreatePaymentDTO {
  customer_id: number;
  payment_date: string;
  amount: number;
  payment_method?: string;
  reference_no?: string;
  notes?: string;
  invoice_allocations: InvoiceAllocation[];
  userId: number;
}

interface CreateSupplierPaymentDTO {
  supplier_id: number;
  payment_date: string;
  amount: number;
  payment_method?: string;
  reference_no?: string;
  notes?: string;
  po_allocations?: Array<{ po_id: string; amount: number }>;
  purchase_allocations?: Array<{ purchase_id: string; amount: number }>;
  userId: number;
}

// Static class for Payment model operations
export type UnifiedPaymentRow = {
  source: string;
  source_id: number;
  ref_no: string;
  date: string;
  amount: number;
  method: string | null;
  type: string;
  party: string | null;
  party_id: number | null;
  party_type: string | null;
  status: string;
  description: string | null;
  sort_created_at: string;
  direction: 'in' | 'out' | 'unknown';
  payment_kind: string | null;
};

/** A persisted allocation row (see services/paymentRecordingTypes.ts for the command shape). */
export type PaymentAllocationRow = {
  id: number;
  payment_id: number;
  invoice_id: number;
  invoice_no: string;
  amount: number;
};

export type PaymentDetailRow = {
  id: number;
  payment_no: string;
  customer_id: number;
  customer_name: string;
  supplier_id: number | null;
  voided_at: string | null;
  payment_kind: string;
  invoice_id: number | null;
  invoice_no: string | null;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference_no: string;
  notes: string;
  created_at: string;
  allocated_invoices: string | null;
  allocation_amounts: string | null;
  allocation_ids: string | null;
  allocations?: PaymentAllocationRow[];
};

/**
 * H8: void-and-reissue the GL so the journal carries the payment's FINAL date
 * and cash/bank account. `voidJournalLinesByReference` returns how many
 * lines it retired — repost only when the payment actually had a posting, so
 * an edit never invents a movement.
 */
function repostEditedPaymentGl(
  db: Database.Database,
  paymentId: number,
  finalPayment: PaymentDetailRow,
  finalAmount: number,
  isRefund: boolean,
  voidedLines: number,
  userId: number | undefined
): void {
  if (voidedLines <= 0) return;

  if (isRefund && finalPayment.customer_id) {
    AccountingService.postRefundEntry(db, {
      refundPaymentId: paymentId,
      refundPaymentNo: finalPayment.payment_no,
      amount: Math.abs(finalAmount),
      refundDate: finalPayment.payment_date,
      paymentMethod: finalPayment.payment_method,
      customerId: finalPayment.customer_id,
      userId,
    });
    return;
  }

  if (finalPayment.customer_id) {
    AccountingService.postPaymentEntry(db, {
      paymentId,
      paymentNo: finalPayment.payment_no,
      amount: finalAmount,
      paymentDate: finalPayment.payment_date,
      paymentMethod: finalPayment.payment_method,
      customerId: finalPayment.customer_id,
      userId,
    });
    return;
  }

  if (finalPayment.supplier_id) {
    AccountingService.postSupplierPaymentEntry(db, {
      paymentId,
      paymentNo: finalPayment.payment_no,
      amount: finalAmount,
      paymentDate: finalPayment.payment_date,
      paymentMethod: finalPayment.payment_method,
      userId,
    });
  }
}

/**
 * H8: a date edit must also move the subledger row — otherwise the ledger
 * keeps posting on the old date while the payment row carries the new one.
 * Reverse the active PAYMENT row append-only and reissue one fresh row at
 * the new date (ACC-14 / ACC-20 reversal rules — the same primitives
 * payment deletion uses).
 *
 * NB: ledgerUtils writes through the config/database singleton, so these nest
 * as savepoints only when `db` IS that singleton (as all controllers pass it).
 */
function moveEditedPaymentLedgerDate(
  db: Database.Database,
  finalPayment: PaymentDetailRow,
  finalAmount: number,
  isRefund: boolean,
  newDate: string
): void {
  if (finalPayment.customer_id) {
    // Refund payments sit in the ledger as REFUND debits (applyRefund);
    // ordinary customer payments as PAYMENT credits.
    const ledgerType = isRefund ? 'REFUND' : 'PAYMENT';
    const custRows = db.prepare(
      `SELECT id, description FROM customer_ledger
       WHERE reference_no = ? AND voided = 0 AND transaction_type = ? AND customer_id = ?`
    ).all(finalPayment.payment_no, ledgerType, finalPayment.customer_id) as Array<{ id: number; description: string | null }>;
    if (custRows.length > 0) {
      for (const row of custRows) {
        ledgerUtils.reverseLedgerEntry('customer_ledger', row.id, `payment ${finalPayment.payment_no} date edited to ${newDate}`);
      }
      ledgerUtils.createLedgerEntry(
        finalPayment.customer_id,
        newDate,
        ledgerType,
        finalPayment.payment_no,
        isRefund ? Math.abs(finalAmount) : 0,
        isRefund ? 0 : finalAmount,
        custRows[0].description || `Payment ${finalPayment.payment_no}`,
      );
      ledgerUtils.recalcCustomerBalanceFromLedger(finalPayment.customer_id);
    }
    return;
  }

  if (finalPayment.supplier_id) {
    const supRows = db.prepare(
      `SELECT id, description FROM supplier_ledger
       WHERE reference_no = ? AND voided = 0 AND transaction_type = 'PAYMENT' AND supplier_id = ?`
    ).all(finalPayment.payment_no, finalPayment.supplier_id) as Array<{ id: number; description: string | null }>;
    if (supRows.length > 0) {
      for (const row of supRows) {
        ledgerUtils.reverseLedgerEntry('supplier_ledger', row.id, `payment ${finalPayment.payment_no} date edited to ${newDate}`);
      }
      SupplierLedgerModel.createEntry({
        supplier_id: finalPayment.supplier_id,
        transaction_date: newDate,
        transaction_type: 'PAYMENT',
        reference_no: finalPayment.payment_no,
        credit: parseCurrency(finalPayment.amount),
        description: supRows[0].description || `Payment ${finalPayment.payment_no}`,
      }, db);
      SupplierLedgerModel.rebuildBalances(finalPayment.supplier_id, db);
    }
  }
}

export class PaymentModel {
  /**
   * Generate payment number using sequence utility.
   * Re-syncs from the actual max in the table on every call to prevent
   * duplicate payment_no errors when data is manually inserted or restored.
   */

  /**
   * Get payment by ID
   */
  static getById(db: Database.Database, id: number): PaymentDetailRow | undefined {
    const payment = db.prepare(`
      SELECT p.id, p.payment_no, p.customer_id, c.customer_name, p.supplier_id, p.invoice_id, i.invoice_no,
             p.payment_date, p.amount, p.payment_method, p.reference_no, p.notes, p.created_at,
             p.voided_at, p.payment_kind,
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts,
             GROUP_CONCAT(pa.id, ',') as allocation_ids
      FROM payments p LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE p.id = ? GROUP BY p.id
    `).get(id) as PaymentDetailRow | undefined;

    if (payment && payment.allocated_invoices) {
      payment.allocations = db.prepare(`
        SELECT pa.id, pa.payment_id, pa.invoice_id, i.invoice_no, pa.amount
        FROM payment_allocations pa LEFT JOIN invoices i ON pa.invoice_id = i.id
        WHERE pa.payment_id = ? AND pa.voided_at IS NULL ORDER BY pa.id
      `).all(id) as PaymentAllocationRow[];
    } else if (payment) {
      payment.allocations = [];
    }

    return payment;
  }

  /**
   * Get all payments with filtering
   */
  static getAll(db: Database.Database, filters: PaymentFilters = {}, sortColumns: string[], defaultSort: string, defaultOrder: string) {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    let query = `
      SELECT p.id, p.payment_no, p.customer_id, c.customer_name, p.supplier_id, s.supplier_name as supplier_name,
             p.invoice_id, i.invoice_no,
             p.payment_date, p.amount, p.payment_method, p.reference_no, p.notes, p.created_at,
             p.voided_at, p.payment_kind,
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts
      FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE p.voided_at IS NULL
    `;
    const params: (string | number)[] = [];

    if (filters.search) {
      const term = `%${filters.search}%`;
      query += ` AND (p.payment_no LIKE ? OR COALESCE(c.customer_name, s.supplier_name) LIKE ? OR p.reference_no LIKE ?)`;
      params.push(term, term, term);
    }
    if (filters.customerId) { query += ' AND p.customer_id = ?'; params.push(parseInt(filters.customerId, 10)); }
    if (filters.supplierId) { query += ' AND p.supplier_id = ?'; params.push(parseInt(filters.supplierId, 10)); }
    if (filters.fromDate) { query += ' AND p.payment_date >= ?'; params.push(filters.fromDate); }
    if (filters.toDate) { query += ' AND p.payment_date <= ?'; params.push(filters.toDate); }

    const sortBy = filters.sortBy && sortColumns.includes(filters.sortBy) ? filters.sortBy : defaultSort;
    const sortOrder = filters.sortOrder === 'ASC' ? 'ASC' : defaultOrder;

    query += ` GROUP BY p.id ORDER BY ${sortBy} ${sortOrder} LIMIT ? OFFSET ?`;
    params.push(limitNum, (pageNum - 1) * limitNum);

    const payments = db.prepare(query).all(...params);
    
    let countQuery = `
      SELECT COUNT(DISTINCT p.id) as total FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE p.voided_at IS NULL
    `;
    const countParams: (string | number)[] = [];
    if (filters.search) {
      const term = `%${filters.search}%`;
      countQuery += ` AND (p.payment_no LIKE ? OR COALESCE(c.customer_name, s.supplier_name) LIKE ? OR p.reference_no LIKE ?)`;
      countParams.push(term, term, term);
    }
    if (filters.customerId) { countQuery += ' AND p.customer_id = ?'; countParams.push(parseInt(filters.customerId, 10)); }
    if (filters.supplierId) { countQuery += ' AND p.supplier_id = ?'; countParams.push(parseInt(filters.supplierId, 10)); }
    if (filters.fromDate) { countQuery += ' AND p.payment_date >= ?'; countParams.push(filters.fromDate); }
    if (filters.toDate) { countQuery += ' AND p.payment_date <= ?'; countParams.push(filters.toDate); }

    const total = db.prepare(countQuery).get(...countParams) as { total: number };

    return { payments, total: total.total, pageNum, limitNum };
  }

  /**
   * Emits a SQL CASE fragment that normalizes a raw payment-method string
   * into the unified allowed set (cash | bank | card | mobile_wallet |
   * credit | other | unknown). This is SQL text, NOT a TS function call —
   * better-sqlite3 cannot invoke a JS helper inside a query.
   */
  static unifiedMethodSql(column: string): string {
    return `CASE LOWER(TRIM(COALESCE(${column}, '')))
      WHEN '' THEN 'unknown'
      WHEN 'cash' THEN 'cash'
      WHEN 'bank' THEN 'bank'
      WHEN 'bank transfer' THEN 'bank'
      WHEN 'check' THEN 'bank'
      WHEN 'online transfer' THEN 'bank'
      WHEN 'online payment' THEN 'bank'
      WHEN 'raast' THEN 'bank'
      WHEN 'easypaisa' THEN 'mobile_wallet'
      WHEN 'jazzcash' THEN 'mobile_wallet'
      WHEN 'upaisa' THEN 'mobile_wallet'
      WHEN 'mobile wallet' THEN 'mobile_wallet'
      WHEN 'credit card' THEN 'card'
      WHEN 'debit card' THEN 'card'
      WHEN 'credit' THEN 'credit'
      ELSE 'other' END`;
  }

  /**
   * Unified cash-movement projection across the five payment-related
   * sources (payments, expenses, salary_payments, owner_capital,
   * owner_withdrawals). Read-only aggregation — creation stays in each
   * source's own flow, so GL posting is never duplicated.
   *
   * Invariants enforced server-side:
   *  - `amount` is ALWAYS a positive absolute value (ABS).
   *  - `direction` (in | out | unknown) is derived from `type`, never from
   *    the raw amount sign. Legacy invalid payment rows (both or neither
   *    counterparty id) surface as type='unknown' / direction='unknown'
   *    rather than being silently classified as customer payments.
   *  - `owner_withdrawals` is filtered to kind='cash' (goods withdrawals are
   *    inventory movements, not payments).
   *  - Data and count queries share the exact same predicate builder, so
   *    `totalItems` always matches the filtered result.
   *  - Sorting appends a deterministic tie-breaker (sort_created_at, source,
   *    source_id) for stable server-side pagination.
   */
  static getUnifiedPayments(db: Database.Database, filters: UnifiedPaymentFilters = {}): { payments: UnifiedPaymentRow[]; total: number; pageNum: number; limitNum: number } {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const rawCte = `
      SELECT 'payment' source, p.id source_id, p.payment_no ref_no, p.payment_date date, ABS(p.amount) amount,
             ${PaymentModel.unifiedMethodSql('p.payment_method')} method,
             CASE WHEN p.supplier_id IS NOT NULL AND p.customer_id IS NOT NULL THEN 'unknown'
                  WHEN p.supplier_id IS NOT NULL THEN 'supplier'
                  WHEN p.customer_id IS NOT NULL THEN 'customer' ELSE 'unknown' END type,
             COALESCE(c.customer_name, s.supplier_name) party,
             CASE WHEN p.supplier_id IS NOT NULL THEN p.supplier_id
                  WHEN p.customer_id IS NOT NULL THEN p.customer_id ELSE NULL END party_id,
             CASE WHEN p.supplier_id IS NOT NULL THEN 'supplier'
                  WHEN p.customer_id IS NOT NULL THEN 'customer' ELSE 'unknown' END party_type,
             'posted' status, p.notes description,
             COALESCE(p.created_at, p.payment_date) sort_created_at, p.payment_kind
      FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE p.voided_at IS NULL
      UNION ALL
      SELECT 'expense', e.id, e.expense_no, e.expense_date, ABS(e.amount),
             ${PaymentModel.unifiedMethodSql('e.payment_method')}, 'expense',
             COALESCE(e.vendor_name, e.expense_category) party, NULL party_id, NULL party_type,
             e.status, e.description,
             COALESCE(e.created_at, e.expense_date), NULL
      FROM expenses e WHERE e.status NOT IN ('Draft', 'Cancelled') AND LOWER(COALESCE(e.payment_method, '')) <> 'credit'
      UNION ALL
      SELECT 'expense_payment', ep.id, e.expense_no || '/PAY-' || ep.id, ep.payment_date, ep.amount,
             ${PaymentModel.unifiedMethodSql('ep.payment_method')}, 'expense',
             COALESCE(NULLIF(e.vendor_name, ''), e.expense_category), NULL, NULL,
             'posted', e.description, ep.created_at, NULL
      FROM expense_payments ep JOIN expenses e ON e.id = ep.expense_id WHERE ep.voided_at IS NULL
      UNION ALL
      SELECT 'supplier_advance', a.id, 'ADV-' || a.id, a.prepay_date, a.amount,
             ${PaymentModel.unifiedMethodSql('a.payment_method')}, 'supplier_advance',
             s.supplier_name, a.supplier_id, 'supplier', 'posted', a.notes, a.created_at, NULL
      FROM supplier_prepayments a JOIN suppliers s ON s.id = a.supplier_id WHERE a.voided_at IS NULL
      UNION ALL
      SELECT 'salary', sp.id, 'SAL-' || sp.id, sp.payment_date, ABS(sp.amount),
             ${PaymentModel.unifiedMethodSql('sp.payment_method')}, 'salary',
             TRIM(sp_emp.first_name || ' ' || sp_emp.last_name) party, sp.employee_id party_id, 'employee' party_type,
             sp.status, sp.notes,
             COALESCE(sp.created_at, sp.payment_date), NULL
      FROM salary_payments sp LEFT JOIN employees sp_emp ON sp_emp.id = sp.employee_id
      WHERE sp.voided_at IS NULL
      UNION ALL
      SELECT 'owner_capital', oc.id, oc.capital_no, oc.capital_date, ABS(oc.amount),
             ${PaymentModel.unifiedMethodSql('oc.payment_method')}, 'owner_capital',
             'Owner' party, NULL party_id, NULL party_type,
             oc.status, oc.note,
             COALESCE(oc.created_at, oc.capital_date), NULL
      FROM owner_capital oc WHERE oc.status = 'posted'
      UNION ALL
      SELECT 'owner_withdrawal', ow.id, ow.withdrawal_no, ow.withdrawal_date, ABS(ow.amount),
             ${PaymentModel.unifiedMethodSql('ow.payment_method')}, 'owner_withdrawal',
             'Owner' party, NULL party_id, NULL party_type,
             ow.status, ow.note,
             COALESCE(ow.created_at, ow.withdrawal_date), NULL
      FROM owner_withdrawals ow WHERE ow.status = 'posted' AND ow.kind = 'cash'
    `;

    const directionSql = `CASE WHEN type = 'customer' AND payment_kind = 'REFUND' THEN 'out' ELSE CASE type
        WHEN 'customer' THEN 'in' WHEN 'owner_capital' THEN 'in'
        WHEN 'supplier' THEN 'out' WHEN 'supplier_advance' THEN 'out' WHEN 'expense' THEN 'out'
        WHEN 'salary' THEN 'out' WHEN 'owner_withdrawal' THEN 'out'
        ELSE 'unknown' END END`;

    const whereParts: string[] = [];
    const params: (string | number)[] = [];
    if (filters.type && filters.type !== 'all') { whereParts.push('type = ?'); params.push(filters.type); }
    if (filters.fromDate) { whereParts.push('date >= ?'); params.push(filters.fromDate); }
    if (filters.toDate) { whereParts.push('date <= ?'); params.push(filters.toDate); }
    if (filters.search) {
      const term = `%${filters.search}%`;
      whereParts.push('(ref_no LIKE ? OR party LIKE ? OR description LIKE ?)');
      params.push(term, term, term);
    }
    const whereSql = whereParts.length ? `WHERE ${whereParts.join(' AND ')}` : '';

    const sortColumns: Record<string, string> = { date: 'date', amount: 'amount', type: 'type', party: 'party', ref_no: 'ref_no' };
    const sortBy = sortColumns[filters.sortBy ?? ''] ? sortColumns[filters.sortBy as string] : 'date';
    const order = filters.sortOrder === 'ASC' ? 'ASC' : 'DESC';
    const orderSql = `ORDER BY ${sortBy} ${order}, sort_created_at DESC, source ASC, source_id DESC`;

    const ctes = `WITH unified_raw AS (${rawCte}), unified AS (SELECT *, ${directionSql} direction FROM unified_raw)`;

    const rows = db.prepare(`${ctes} SELECT * FROM unified ${whereSql} ${orderSql} LIMIT ? OFFSET ?`)
      .all(...params, limitNum, (pageNum - 1) * limitNum) as UnifiedPaymentRow[];

    const totalRow = db.prepare(`${ctes} SELECT COUNT(*) AS total FROM unified ${whereSql}`)
      .get(...params) as { total: number };

    return { payments: rows, total: totalRow.total, pageNum, limitNum };
  }

  /**
   * Customer payment against one or more invoices.
   *
   * TASK 33: the writes live in PaymentRecordingService — this stays as the
   * model-level entry point the payments controller already calls.
   */
  static create(db: Database.Database, data: CreatePaymentDTO): number {
    return new PaymentRecordingService(db).recordCustomerPayment({
      mode: 'RECEIPT',
      customerId: data.customer_id,
      paymentDate: data.payment_date,
      amount: data.amount,
      paymentMethod: data.payment_method || 'Cash',
      referenceNo: data.reference_no,
      notes: data.notes,
      userId: data.userId,
      allocations: data.invoice_allocations.map((alloc) => ({
        invoiceId: parseInt(String(alloc.invoice_id), 10),
        amount: alloc.amount,
      })),
    }).paymentId;
  }

  /**
   * Supplier payout against POs and/or purchases.
   *
   * TASK 33: routed through PaymentRecordingService so the H7 full-allocation
   * rule, the cash funds guard, the AP journal entry and the closed-period
   * guard are decided in one place.
   */
  static createSupplierPayment(db: Database.Database, data: CreateSupplierPaymentDTO): number {
    const allocations: SupplierPaymentAllocation[] = [
      ...(data.po_allocations || []).map((alloc) => ({
        kind: 'purchase_order' as const,
        id: parseInt(String(alloc.po_id), 10),
        amount: alloc.amount,
      })),
      ...(data.purchase_allocations || []).map((alloc) => ({
        kind: 'purchase' as const,
        id: parseInt(String(alloc.purchase_id), 10),
        amount: alloc.amount,
      })),
    ];

    return new SupplierPaymentService(db).recordSupplierPayment({
      supplierId: data.supplier_id,
      paymentDate: data.payment_date,
      amount: data.amount,
      paymentMethod: data.payment_method || 'Cash',
      referenceNo: data.reference_no,
      notes: data.notes,
      userId: data.userId,
      allocations,
    }).paymentId;
  }

  /**
   * Update payment
   *
   * H8 (payment-edit-gl-integrity): an operational edit must never leave
   * the books behind. `reference_no` / `notes` are pure metadata, but
   * `payment_date` and `payment_method` move accounting, so they follow
   * the same void-and-reissue model as payment deletion:
   *
   *   amount         — never editable; void and re-record (PAY-04).
   *   payment_date   — the journal entry date AND the subledger row date
   *                    move with the payment: the old journal lines are
   *                    voided and a fresh entry posts at the new date, and
   *                    the ledger row is reversed and reissued at it.
   *   payment_method — selects a different cash/bank GL account, so the
   *                    journal is voided and reposted against the new
   *                    account — for supplier payments too (the old path
   *                    only reposted customer payments, leaving a supplier
   *                    method change crediting the old cash account).
   *
   * Accounting is re-posted only where it already existed (the void count
   * tells us), so an edit never invents a money movement. The OLD period
   * and, when the date moves, the NEW one must both be open.
   *
   * Refund payments (negative amount, posted by postRefundEntry) are
   * reposted through the SAME refund primitive — postPaymentEntry ignores
   * amounts ≤ 0, so a refund edit routed through it would void the GL and
   * silently lose the cash exit.
   */
  static update(
    db: Database.Database,
    id: number,
    data: { payment_date?: string; amount?: number; payment_method?: string; reference_no?: string; notes?: string },
    attribution?: { userId?: number | null },
  ): void {
    const existing = this.getById(db, id);
    if (!existing) throw new Error('Payment not found');
    assertLegacyPaymentAllowed(db, id);

    // PAY-04 (financial-audit-p0-remediation 2.1): amount edits on an
    // allocated payment silently rescaled allocations past invoice balances
    // and desynced allocations/ledger/GL. Policy: void-and-reissue.
    const amountChanged = data.amount !== undefined && parseCurrency(data.amount) !== parseCurrency(existing.amount);
    if (amountChanged) {
      throw new Error(
        `Cannot change the amount of payment ${existing.payment_no} — it has recorded allocations. ` +
        `Void this payment and record a new one with the correct amount.`
      );
    }

    // CASH-02 (task 1.4): method edits must pass the same whitelist.
    if (data.payment_method !== undefined && !isValidPaymentMethod(data.payment_method)) {
      throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
    }

    const dateChanged = !!data.payment_date && data.payment_date !== existing.payment_date;
    const methodChanged = data.payment_method !== undefined &&
      data.payment_method.toLowerCase() !== String(existing.payment_method).toLowerCase();

    if ((dateChanged || methodChanged) && db.prepare('SELECT id FROM supplier_prepayment_applications WHERE payment_id = ?').get(id)) {
      throw new BusinessRuleError(409, 'Reverse and reapply supplier advances to change their application date or funding');
    }
    if (dateChanged || methodChanged) {
      const bills = db.prepare(`SELECT b.bill_date FROM supplier_bill_allocations a
        JOIN supplier_bills b ON b.id = a.bill_id
        WHERE a.payment_id = ? AND a.voided_at IS NULL`).all(id) as Array<{ bill_date: string }>;
      for (const bill of bills) {
        if ((data.payment_date ?? existing.payment_date) < bill.bill_date) {
          throw new BusinessRuleError(400, 'Payment cannot precede the supplier bill');
        }
        AccountingService.assertPeriodNotClosed(db, bill.bill_date, 'Supplier bill');
      }
    }

    // The payment already posted in its CURRENT period and, when the date
    // moves, will post in the TARGET period — both must be open before any
    // accounting is rewritten (H6 closed-period immutability).
    AccountingService.assertPeriodNotClosed(db, existing.payment_date, `Payment ${existing.payment_no}`);
    if (dateChanged) {
      AccountingService.assertPeriodNotClosed(db, data.payment_date as string, `Payment ${existing.payment_no}`);
    }

    // Pure metadata: nothing accounting-affecting changed, so a plain
    // in-place UPDATE is enough — no GL / ledger work needed.
    if (!dateChanged && !methodChanged) {
      db.transaction(() => {
        db.prepare(`
          UPDATE payments SET
            payment_date = COALESCE(?, payment_date),
            payment_method = COALESCE(?, payment_method), reference_no = COALESCE(?, reference_no),
            notes = COALESCE(?, notes) WHERE id = ?
        `).run(data.payment_date, data.payment_method, data.reference_no, data.notes, id);
      })();
      return;
    }

    db.transaction(() => {
      db.prepare(`
        UPDATE payments SET
          payment_date = COALESCE(?, payment_date),
          payment_method = COALESCE(?, payment_method), reference_no = COALESCE(?, reference_no),
          notes = COALESCE(?, notes) WHERE id = ?
      `).run(data.payment_date, data.payment_method, data.reference_no, data.notes, id);

      const finalPayment = this.getById(db, id);
      if (!finalPayment) throw new Error('Payment not found');

      // H8: void-and-reissue the GL so the journal carries the payment's
      // FINAL date and cash/bank account. voidJournalLinesByReference
      // returns how many lines it retired — repost only when the payment
      // actually had a posting, so an edit never invents a movement.
      const changes = [dateChanged && 'date', methodChanged && 'method'].filter(Boolean).join(' + ');
      const voidedLines = AccountingService.voidJournalLinesByReference(db, 'PAYMENT', id, {
        voidedBy: attribution?.userId ?? undefined,
        voidReason: `Payment ${existing.payment_no} edited (${changes})`,
      });
      const finalAmount = parseCurrency(finalPayment.amount);
      const isRefund = finalAmount < 0;
      repostEditedPaymentGl(db, id, finalPayment, finalAmount, isRefund, voidedLines, attribution?.userId ?? undefined);

      if (voidedLines > 0 && existing.customer_id && Number(existing.amount) > 0) {
        assertCashTimeline(db, { paymentMethod: existing.payment_method, fromDate: existing.payment_date });
        assertCashTimeline(db, { paymentMethod: finalPayment.payment_method, fromDate: finalPayment.payment_date });
      }

      // H8: a date edit must also move the subledger row — otherwise the
      // ledger keeps posting on the old date while the payment row carries
      // the new one. Reverse the active PAYMENT row append-only and reissue
      // one fresh row at the new date (ACC-14 / ACC-20 reversal rules —
      // the same primitives payment deletion uses).
      // NB: ledgerUtils writes through the config/database singleton, so
      // these nest as savepoints only when `db` IS that singleton (as all
      // controllers pass it).
      if (dateChanged) {
        moveEditedPaymentLedgerDate(
          db, finalPayment, finalAmount, isRefund, data.payment_date as string
        );
      }

    })();
  }

  /**
   * Delete payment
   */
  static delete(db: Database.Database, id: number, attribution?: { voidedBy?: number | null; voidReason?: string }): void {
    const existing = this.getById(db, id);
    if (!existing) throw new Error('Payment not found');
    if (existing.voided_at) throw new Error('Payment is already voided');

    AccountingService.assertPeriodNotClosed(db, existing.payment_date, `Payment ${existing.payment_no}`);

    db.transaction(() => {
      assertLegacyPaymentAllowed(db, id);
      // GL consistency (ACC-09): the payment's journal lines (Dr Cash /
      // Cr AR, or supplier-side) must not survive as active orphans once
      // the payment is voided.
      AccountingService.voidJournalLinesByReference(db, 'PAYMENT', id);
      if (existing.customer_id && Number(existing.amount) > 0) {
        assertCashTimeline(db, { paymentMethod: existing.payment_method, fromDate: existing.payment_date });
      }

      // C6 (reversal-rules): a payment moved money, so it is never
      // hard-deleted. Void the row and its allocations with attribution;
      // the audit history stays queryable and no ON DELETE CASCADE fires.
      const allocations = db.prepare(
        'SELECT * FROM payment_allocations WHERE payment_id = ? AND voided_at IS NULL'
      ).all(id) as Array<{ invoice_id: number }>;
      db.prepare(
        'UPDATE payment_allocations SET voided_at = CURRENT_TIMESTAMP WHERE payment_id = ? AND voided_at IS NULL'
      ).run(id);
      db.prepare(
        'UPDATE purchase_allocations SET voided_at = CURRENT_TIMESTAMP WHERE payment_id = ? AND voided_at IS NULL'
      ).run(id);
      db.prepare(
         'UPDATE po_allocations SET voided_at = CURRENT_TIMESTAMP WHERE payment_id = ? AND voided_at IS NULL'
      ).run(id);
      db.prepare('UPDATE supplier_bill_allocations SET voided_at = CURRENT_TIMESTAMP WHERE payment_id = ? AND voided_at IS NULL').run(id);
      db.prepare(
        'UPDATE payments SET voided_at = CURRENT_TIMESTAMP, voided_by = ?, void_reason = ? WHERE id = ? AND voided_at IS NULL'
      ).run(attribution?.voidedBy ?? null, attribution?.voidReason ?? null, id);
      // ACC-14: reverse the payment's subledger rows (append-only) instead
      // of deleting them. Scoped by reference_no AND transaction_type so a
      // colliding reference cannot touch another party's rows.
      const custRows = db.prepare(
        `SELECT id FROM customer_ledger WHERE reference_no = ? AND voided = 0 AND transaction_type = 'PAYMENT' AND customer_id = ?`
      ).all(existing.payment_no, existing.customer_id) as Array<{ id: number }>;
      for (const row of custRows) {
        ledgerUtils.reverseLedgerEntry('customer_ledger', row.id, `payment ${existing.payment_no} deleted`);
      }
      const supRows = db.prepare(
        `SELECT id FROM supplier_ledger WHERE reference_no = ? AND voided = 0 AND transaction_type = 'PAYMENT' AND supplier_id = ?`
      ).all(existing.payment_no, existing.supplier_id) as Array<{ id: number }>;
      for (const row of supRows) {
        ledgerUtils.reverseLedgerEntry('supplier_ledger', row.id, `payment ${existing.payment_no} deleted`);
      }

      if (existing.supplier_id) {
        // Deleting a payment may leave the running chain inconsistent
        // (mid-chain gap or stale balance); recompute it in full.
        SupplierLedgerModel.rebuildBalances(existing.supplier_id, db);
      }

      // Rule 9: rebuild failures roll back the whole reversal. A warn-only
      // rebuild can leave an invoice showing paid amounts whose payment
      // is voided.
      for (const alloc of allocations) {
        ledgerUtils.calculateInvoiceBalance(alloc.invoice_id);
        ledgerUtils.updateInvoiceStatus(alloc.invoice_id);
      }

      ledgerUtils.recalcCustomerBalanceFromLedger(existing.customer_id);

      ledgerUtils.rebuildLedgerBalances(existing.customer_id);
    })();
  }

  /**
   * C6 (reversal-rules): explicit business name for voiding a payment.
   * Same transactional body as delete(); kept so destructive call sites
   * read as reversals, not row removals.
   */
  static void(db: Database.Database, id: number, voidedBy: number | null, voidReason: string): void {
    this.delete(db, id, { voidedBy, voidReason });
  }

  /**
   * Get payment allocations by payment ID
   */
  static getAllocationsByPaymentId(db: Database.Database, paymentId: number): Array<{ invoice_id: number }> {
    return db.prepare('SELECT invoice_id FROM payment_allocations WHERE payment_id = ?').all(paymentId) as Array<{ invoice_id: number }>;
  }

  /**
   * Get payment allocations by invoice ID
   */
  static getAllocationsByInvoiceId(db: Database.Database, invoiceId: number): Array<{ payment_id: number; amount: number }> {
    return db.prepare(`
      SELECT payment_id, amount FROM payment_allocations WHERE invoice_id = ?
    `).all(invoiceId) as Array<{ payment_id: number; amount: number }>;
  }

  /**
   * Delete payment allocations by payment ID
   */
  static deleteAllocationsByPaymentId(db: Database.Database, paymentId: number): void {
    // C6 (reversal-rules): allocation rows die with the payment reversal,
    // never with a row DELETE. Voided allocation rows are excluded from
    // balance math by voided_at IS NULL.
    db.transaction(() => {
      assertLegacyPaymentAllowed(db, paymentId);
      db.prepare('UPDATE payment_allocations SET voided_at = CURRENT_TIMESTAMP WHERE payment_id = ? AND voided_at IS NULL').run(paymentId);
    }).immediate();
  }

  /**
   * Delete payment allocations by invoice ID
   */
  static deleteAllocationsByInvoiceId(db: Database.Database, invoiceId: number): void {
    // C6 (reversal-rules): void, never delete — allocation history must
    // survive every reversal for auditability.
    db.transaction(() => {
      assertLegacyInvoiceAllocationsAllowed(db, invoiceId);
      db.prepare('UPDATE payment_allocations SET voided_at = CURRENT_TIMESTAMP WHERE invoice_id = ? AND voided_at IS NULL').run(invoiceId);
    }).immediate();
  }

  /**
   * Get total paid for an invoice
   */
  static getTotalPaidByInvoiceId(db: Database.Database, invoiceId: number): number {
    const result = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total_paid
      FROM payment_allocations
      WHERE invoice_id = ? AND voided_at IS NULL
    `).get(invoiceId) as { total_paid: number };
    return result.total_paid;
  }

  /**
   * ERP refund rule (reversal-rules): the cash refundable on an invoice
   * return is capped at what the customer actually collected. Because
   * getTotalPaidByInvoiceId sums allocations INCLUDING prior negative
   * refund allocations, repeated partial returns can never re-refund
   * cash already paid out.
   *
   *   collected = Σ allocations (voided_at IS NULL)   — net of refunds
   *   refundable = max(0, collected)
   *
   * Callers apply: refundAmount = min(netReturn, refundableOnInvoice());
   * any remainder stays as a customer credit on account, not cash out.
   */
  static refundableOnInvoice(db: Database.Database, invoiceId: number): number {
    const collected = parseCurrency(this.getTotalPaidByInvoiceId(db, invoiceId));
    return Math.max(0, collected);
  }
}

export default PaymentModel;
