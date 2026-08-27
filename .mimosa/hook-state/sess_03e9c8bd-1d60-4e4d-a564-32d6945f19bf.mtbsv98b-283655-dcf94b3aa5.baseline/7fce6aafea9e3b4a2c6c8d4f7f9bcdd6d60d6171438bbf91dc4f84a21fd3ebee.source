import Database from 'better-sqlite3';
import { getNextSequenceNumber } from '../utils/sequence';
import ledgerUtils from '../utils/ledgerUtils';
import AccountingService from '../services/accountingService';
import { parseCurrency, subtractCurrency } from '../utils/currency';
import logger from '../utils/logger';
import SupplierLedgerModel from './SupplierLedger';
import { isValidPaymentMethod } from '../services/cashService';

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
  po_allocations: Array<{ po_id: string; amount: number }>;
  purchase_allocations?: Array<{ purchase_id: string; amount: number }>;
  userId: number;
}

// Static class for Payment model operations
export class PaymentModel {
  /**
   * Generate payment number using sequence utility.
   * Re-syncs from the actual max in the table on every call to prevent
   * duplicate payment_no errors when data is manually inserted or restored.
   */
  static generatePaymentNo(db: Database.Database): string {
    // Use numeric MAX (not string MAX) so PAY1000 sorts after PAY999.
    // String comparison would make PAY999 > PAY1000, causing duplicate generation.
    const maxResult = db.prepare(
      `SELECT MAX(CAST(SUBSTR(payment_no, 4) AS INTEGER)) as max_val FROM payments WHERE payment_no LIKE 'PAY%'`
    ).get() as { max_val: number | null } | undefined;
    const maxNo = maxResult?.max_val ?? 0;

    const currentSetting = db.prepare("SELECT value FROM settings WHERE key = 'PAY_last_no'").get() as { value: string } | undefined;
    const currentSeq = currentSetting ? parseInt(currentSetting.value, 10) || 0 : 0;

    if (maxNo > currentSeq) {
      db.prepare("UPDATE settings SET value = ?, updated_at = CURRENT_TIMESTAMP WHERE key = 'PAY_last_no'").run(maxNo.toString());
    }

    const nextNo = getNextSequenceNumber(db, 'PAY_last_no');
    return `PAY${String(nextNo).padStart(3, '0')}`;
  }

  /**
   * Get payment by ID
   */
  static getById(db: Database.Database, id: number): any {
    const payment = db.prepare(`
      SELECT p.id, p.payment_no, p.customer_id, c.customer_name, p.supplier_id, p.invoice_id, i.invoice_no,
             p.payment_date, p.amount, p.payment_method, p.reference_no, p.notes, p.created_at,
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts,
             GROUP_CONCAT(pa.id, ',') as allocation_ids
      FROM payments p LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE p.id = ? GROUP BY p.id
    `).get(id) as {
      id: number; payment_no: string; customer_id: number; customer_name: string; supplier_id: number | null;
      invoice_id: number | null;
      invoice_no: string | null; payment_date: string; amount: number; payment_method: string;
      reference_no: string; notes: string; created_at: string; allocated_invoices: string | null;
      allocation_amounts: string | null; allocation_ids: string | null; allocations?: Array<{ id: number; payment_id: number; invoice_id: number; invoice_no: string; amount: number }>;
    } | undefined;

    if (payment && payment.allocated_invoices) {
      payment.allocations = db.prepare(`
        SELECT pa.id, pa.payment_id, pa.invoice_id, i.invoice_no, pa.amount
        FROM payment_allocations pa LEFT JOIN invoices i ON pa.invoice_id = i.id
        WHERE pa.payment_id = ? ORDER BY pa.id
      `).all(id) as Array<{ id: number; payment_id: number; invoice_id: number; invoice_no: string; amount: number }>;
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
             GROUP_CONCAT(pa.invoice_id, ',') as allocated_invoices,
             GROUP_CONCAT(pa.amount, ',') as allocation_amounts
      FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      LEFT JOIN invoices i ON p.invoice_id = i.id
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      WHERE 1=1
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
      WHERE 1=1
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
  static getUnifiedPayments(db: Database.Database, filters: UnifiedPaymentFilters = {}): { payments: any[]; total: number; pageNum: number; limitNum: number } {
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
             COALESCE(p.created_at, p.payment_date) sort_created_at
      FROM payments p
      LEFT JOIN customers c ON p.customer_id = c.id
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      UNION ALL
      SELECT 'expense', e.id, e.expense_no, e.expense_date, ABS(e.amount),
             ${PaymentModel.unifiedMethodSql('e.payment_method')}, 'expense',
             COALESCE(e.vendor_name, e.expense_category) party, NULL party_id, NULL party_type,
             e.status, e.description,
             COALESCE(e.created_at, e.expense_date)
      FROM expenses e WHERE e.status = 'Paid'
      UNION ALL
      SELECT 'salary', sp.id, 'SAL-' || sp.id, sp.payment_date, ABS(sp.amount),
             ${PaymentModel.unifiedMethodSql('sp.payment_method')}, 'salary',
             TRIM(sp_emp.first_name || ' ' || sp_emp.last_name) party, sp.employee_id party_id, 'employee' party_type,
             sp.status, sp.notes,
             COALESCE(sp.created_at, sp.payment_date)
      FROM salary_payments sp LEFT JOIN employees sp_emp ON sp_emp.id = sp.employee_id
      UNION ALL
      SELECT 'owner_capital', oc.id, oc.capital_no, oc.capital_date, ABS(oc.amount),
             ${PaymentModel.unifiedMethodSql('oc.payment_method')}, 'owner_capital',
             'Owner' party, NULL party_id, NULL party_type,
             oc.status, oc.note,
             COALESCE(oc.created_at, oc.capital_date)
      FROM owner_capital oc WHERE oc.status = 'posted'
      UNION ALL
      SELECT 'owner_withdrawal', ow.id, ow.withdrawal_no, ow.withdrawal_date, ABS(ow.amount),
             ${PaymentModel.unifiedMethodSql('ow.payment_method')}, 'owner_withdrawal',
             'Owner' party, NULL party_id, NULL party_type,
             ow.status, ow.note,
             COALESCE(ow.created_at, ow.withdrawal_date)
      FROM owner_withdrawals ow WHERE ow.status = 'posted' AND ow.kind = 'cash'
    `;

    const directionSql = `CASE type
        WHEN 'customer' THEN 'in' WHEN 'owner_capital' THEN 'in'
        WHEN 'supplier' THEN 'out' WHEN 'expense' THEN 'out'
        WHEN 'salary' THEN 'out' WHEN 'owner_withdrawal' THEN 'out'
        ELSE 'unknown' END`;

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
      .all(...params, limitNum, (pageNum - 1) * limitNum) as any[];

    const totalRow = db.prepare(`${ctes} SELECT COUNT(*) AS total FROM unified ${whereSql}`)
      .get(...params) as { total: number };

    return { payments: rows, total: totalRow.total, pageNum, limitNum };
  }

  /**
   * Create a new payment
   */
  static create(db: Database.Database, data: CreatePaymentDTO): number {
    return db.transaction(() => {
      // Input validation
      if (!data.customer_id || data.customer_id <= 0) {
        throw new Error('Valid customer_id is required');
      }
      if (!data.amount || data.amount <= 0) {
        throw new Error('Payment amount must be greater than 0');
      }
      if (!data.payment_date) {
        throw new Error('Payment date is required');
      }
      // CASH-02 (task 1.4): reject unrecognized payment methods outright
      if (!isValidPaymentMethod(data.payment_method)) {
        throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
      }
      if (!data.invoice_allocations || data.invoice_allocations.length === 0) {
        throw new Error('At least one invoice allocation is required');
      }

      // Validate customer exists
      const customer = db.prepare('SELECT id FROM customers WHERE id = ?').get(data.customer_id);
      if (!customer) {
        throw new Error(`Customer ${data.customer_id} not found`);
      }

      // Validate each allocated invoice exists
      for (const alloc of data.invoice_allocations) {
        const invoiceId = parseInt(alloc.invoice_id, 10);
        const invoice = db.prepare('SELECT id, customer_id FROM invoices WHERE id = ?').get(invoiceId) as { id: number; customer_id: number } | undefined;
        if (!invoice) {
          throw new Error(`Invoice ${invoiceId} not found`);
        }
        if (invoice.customer_id !== data.customer_id) {
          throw new Error(`Invoice ${invoiceId} does not belong to customer ${data.customer_id}`);
        }
        if (!alloc.amount || alloc.amount <= 0) {
          throw new Error(`Allocation amount for invoice ${invoiceId} must be greater than 0`);
        }
      }

      const paymentNo = this.generatePaymentNo(db);

      const paymentResult = db.prepare(`
        INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, reference_no, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(paymentNo, data.customer_id, data.payment_date, data.amount, data.payment_method || 'Cash', data.reference_no || '', data.notes || '');

      const paymentId = paymentResult.lastInsertRowid as number;

      for (const alloc of data.invoice_allocations) {
        const invoiceId = parseInt(alloc.invoice_id, 10);
        db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)').run(paymentId, invoiceId, alloc.amount);
        ledgerUtils.calculateInvoiceBalance(invoiceId);
        ledgerUtils.updateInvoiceStatus(invoiceId);
      }

      const currentBalance = db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(data.customer_id) as { current_balance: number };
      const newBalance = subtractCurrency(parseCurrency(currentBalance.current_balance), parseCurrency(data.amount));

      const invoiceNumbers = data.invoice_allocations.map((alloc) => {
        const invoiceId = parseInt(alloc.invoice_id, 10);
        const inv = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId) as { invoice_no: string } | undefined;
        return inv?.invoice_no || `Invoice #${invoiceId}`;
      });

      db.prepare(`
        INSERT INTO customer_ledger (customer_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(data.customer_id, data.payment_date, 'PAYMENT', paymentNo, 0, data.amount, newBalance, `Payment against ${invoiceNumbers.join(', ')}`);

      // GL Phase-2 wiring: post the payment to the journal so the
      // new TB and BS pick it up. The customer_ledger above is the
      // sub-ledger; this is the GL posting. Both must happen in the
      // same transaction for atomicity.
      AccountingService.postPaymentEntry(db, {
        paymentId,
        paymentNo,
        amount: parseCurrency(data.amount),
        paymentDate: data.payment_date,
        paymentMethod: data.payment_method,
        customerId: data.customer_id,
        userId: data.userId,
      });

      ledgerUtils.recalcCustomerBalanceFromLedger(data.customer_id);

      return paymentId;
    })();
  }

  static createSupplierPayment(db: Database.Database, data: CreateSupplierPaymentDTO): number {
    return db.transaction(() => {
      if (!data.supplier_id || data.supplier_id <= 0) {
        throw new Error('Valid supplier_id is required');
      }
      if (!data.amount || data.amount <= 0) {
        throw new Error('Payment amount must be greater than 0');
      }
      if (!data.payment_date) {
        throw new Error('Payment date is required');
      }
      // CASH-02 (task 1.4): same method whitelist as the customer path.
      if (!isValidPaymentMethod(data.payment_method)) {
        throw new Error(`Invalid payment_method "${data.payment_method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
      }
      const poAllocs = data.po_allocations || [];
      const purchaseAllocs = data.purchase_allocations || [];
      if (poAllocs.length === 0 && purchaseAllocs.length === 0) {
        throw new Error('At least one PO or purchase allocation is required');
      }

      const supplier = db.prepare('SELECT id FROM suppliers WHERE id = ?').get(data.supplier_id);
      if (!supplier) {
        throw new Error(`Supplier ${data.supplier_id} not found`);
      }

      for (const alloc of poAllocs) {
        const poId = parseInt(alloc.po_id, 10);
        const po = db.prepare(`
          SELECT po.id, po.supplier_id, po.total_amount, COALESCE(SUM(pa.amount), 0) as paid_amount
          FROM purchase_orders po
          LEFT JOIN po_allocations pa ON pa.po_id = po.id
          WHERE po.id = ? GROUP BY po.id
        `).get(poId) as { id: number; supplier_id: number; total_amount: number; paid_amount: number } | undefined;
        if (!po) {
          throw new Error(`Purchase order ${poId} not found`);
        }
        if (po.supplier_id !== data.supplier_id) {
          throw new Error(`PO ${poId} does not belong to supplier ${data.supplier_id}`);
        }
        if (!alloc.amount || alloc.amount <= 0) {
          throw new Error(`Allocation amount for PO ${poId} must be greater than 0`);
        }
        const remainingBalance = Math.max(0, parseCurrency(po.total_amount) - parseCurrency(po.paid_amount));
        if (parseCurrency(alloc.amount) > remainingBalance) {
          throw new Error(
            `Allocation amount (${parseCurrency(alloc.amount).toFixed(2)}) for PO ${poId} exceeds the remaining balance (${remainingBalance.toFixed(2)})`
          );
        }
      }

      for (const alloc of purchaseAllocs) {
        const purchaseId = parseInt(alloc.purchase_id, 10);
        const purchase = db.prepare(`
          SELECT p.id, p.supplier_id, p.total_cost, COALESCE(SUM(pa.amount), 0) as paid_amount
          FROM purchases p
          LEFT JOIN purchase_allocations pa ON pa.purchase_id = p.id
          WHERE p.id = ? GROUP BY p.id
        `).get(purchaseId) as { id: number; supplier_id: number | null; total_cost: number; paid_amount: number } | undefined;
        if (!purchase) {
          throw new Error(`Purchase ${purchaseId} not found`);
        }
        if (!purchase.supplier_id || purchase.supplier_id !== data.supplier_id) {
          throw new Error(`Purchase ${purchaseId} does not belong to supplier ${data.supplier_id}`);
        }
        if (!alloc.amount || alloc.amount <= 0) {
          throw new Error(`Allocation amount for purchase ${purchaseId} must be greater than 0`);
        }
        const remainingBalance = Math.max(0, parseCurrency(purchase.total_cost) - parseCurrency(purchase.paid_amount));
        if (parseCurrency(alloc.amount) > remainingBalance) {
          throw new Error(
            `Allocation amount (${parseCurrency(alloc.amount).toFixed(2)}) for purchase ${purchaseId} exceeds the remaining balance (${remainingBalance.toFixed(2)})`
          );
        }
      }

      const paymentNo = this.generatePaymentNo(db);

      // When the payment settles exactly one PO (and no purchases), reflect it on
      // the denormalized payments.purchase_order_id so PO-level reporting joins
      // correctly. Multi-PO / mixed allocations stay NULL — the column is
      // single-valued and po_allocations remains the authoritative record.
      const singlePoId =
        poAllocs.length === 1 && purchaseAllocs.length === 0
          ? parseInt(poAllocs[0].po_id, 10)
          : null;

      const paymentResult = db.prepare(`
        INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        paymentNo,
        data.supplier_id,
        data.payment_date,
        data.amount,
        data.payment_method || 'Cash',
        data.reference_no || '',
        data.notes || '',
        singlePoId,
      );

      const paymentId = paymentResult.lastInsertRowid as number;

      for (const alloc of poAllocs) {
        const poId = parseInt(alloc.po_id, 10);
        db.prepare('INSERT INTO po_allocations (payment_id, po_id, amount) VALUES (?, ?, ?)').run(paymentId, poId, alloc.amount);
      }

      for (const alloc of purchaseAllocs) {
        const purchaseId = parseInt(alloc.purchase_id, 10);
        db.prepare('INSERT INTO purchase_allocations (payment_id, purchase_id, amount) VALUES (?, ?, ?)').run(paymentId, purchaseId, alloc.amount);
      }

      const currentBalance = SupplierLedgerModel.getBalance(data.supplier_id, db);
      const newBalance = currentBalance - parseCurrency(data.amount);

      const poNumbers = poAllocs.map((alloc) => {
        const poId = parseInt(alloc.po_id, 10);
        const po = db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(poId) as { po_no: string } | undefined;
        return po?.po_no || `PO #${poId}`;
      });
      const purchaseNumbers = purchaseAllocs.map((alloc) => {
        const purchaseId = parseInt(alloc.purchase_id, 10);
        const p = db.prepare('SELECT purchase_no FROM purchases WHERE id = ?').get(purchaseId) as { purchase_no: string } | undefined;
        return p?.purchase_no || `Purchase #${purchaseId}`;
      });
      const references = [...poNumbers, ...purchaseNumbers];

      db.prepare(`
        INSERT INTO supplier_ledger (supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(data.supplier_id, data.payment_date, 'PAYMENT', paymentNo, 0, data.amount, newBalance, `Payment against ${references.join(', ')}`);

      db.prepare('UPDATE suppliers SET current_balance = ? WHERE id = ?').run(newBalance, data.supplier_id);

      // GL posting (ACC-03): Dr 2000 AP / Cr cash-per-method. Without this
      // the cash the business paid out never leaves GL account 1000.
      // Funds guard: reject payouts that would overdraw the selected
      // account as of the payment date.
      const fundsCashCode = AccountingService._cashOrBankAccountCode(data.payment_method);
      const fundsAccount = AccountingService.getAccountByCode(db, fundsCashCode);
      if (!fundsAccount) {
        throw new Error(`Chart of accounts is missing required account: ${fundsCashCode}`);
      }
      AccountingService.assertSufficientFunds(db, {
        accountId: fundsAccount.id,
        amount: parseCurrency(data.amount),
        asOfDate: data.payment_date,
        label: `supplier payment ${paymentNo}`,
      });
      AccountingService.postSupplierPaymentEntry(db, {
        paymentId,
        paymentNo,
        amount: parseCurrency(data.amount),
        paymentDate: data.payment_date,
        paymentMethod: data.payment_method,
        userId: data.userId,
      });

      return paymentId;
    })();
  }

  /**
   * Update payment
   */
  static update(db: Database.Database, id: number, data: { payment_date?: string; amount?: number; payment_method?: string; reference_no?: string; notes?: string }): void {
    const existing = this.getById(db, id);
    if (!existing) throw new Error('Payment not found');

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

    const methodChanged = data.payment_method !== undefined &&
      data.payment_method.toLowerCase() !== String(existing.payment_method).toLowerCase();

    db.transaction(() => {
      db.prepare(`
        UPDATE payments SET
          payment_date = COALESCE(?, payment_date),
          payment_method = COALESCE(?, payment_method), reference_no = COALESCE(?, reference_no),
          notes = COALESCE(?, notes) WHERE id = ?
      `).run(data.payment_date, data.payment_method, data.reference_no, data.notes, id);

      // Method change moves money between accounts → GL void + repost only.
      if (methodChanged && existing.customer_id) {
        AccountingService.voidJournalLinesByReference(db, 'PAYMENT', id);
        const finalPayment = this.getById(db, id);
        if (finalPayment) {
          AccountingService.postPaymentEntry(db, {
            paymentId: id,
            paymentNo: finalPayment.payment_no,
            amount: parseCurrency(finalPayment.amount),
            paymentDate: finalPayment.payment_date,
            paymentMethod: finalPayment.payment_method,
            customerId: existing.customer_id,
          });
        }
      }
    })();
  }

  /**
   * Delete payment
   */
  static delete(db: Database.Database, id: number): void {
    const existing = this.getById(db, id);
    if (!existing) throw new Error('Payment not found');

    db.transaction(() => {
      // GL consistency (ACC-09): the payment's journal lines (Dr Cash /
      // Cr AR, or supplier-side) must not survive as active orphans once
      // the payment row is gone.
      AccountingService.voidJournalLinesByReference(db, 'PAYMENT', id);

      const allocations = db.prepare('SELECT * FROM payment_allocations WHERE payment_id = ?').all(id) as Array<{ invoice_id: number }>;
      db.prepare('DELETE FROM payment_allocations WHERE payment_id = ?').run(id);
      db.prepare('DELETE FROM purchase_allocations WHERE payment_id = ?').run(id);
      db.prepare('DELETE FROM payments WHERE id = ?').run(id);
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

      for (const alloc of allocations) {
        try {
          ledgerUtils.calculateInvoiceBalance(alloc.invoice_id);
          ledgerUtils.updateInvoiceStatus(alloc.invoice_id);
        } catch (err) {
          logger.warn('Payment.delete: failed to update invoice balance', { invoice_id: alloc.invoice_id, error: err instanceof Error ? err.message : err });
        }
      }

      try { ledgerUtils.recalcCustomerBalanceFromLedger(existing.customer_id); } catch (err) {
        logger.warn('Payment.delete: failed to update customer balance', { customer_id: existing.customer_id, error: err instanceof Error ? err.message : err });
      }

      try { ledgerUtils.rebuildLedgerBalances(existing.customer_id); } catch (err) {
        logger.warn('Payment.delete: failed to rebuild ledger balances', { customer_id: existing.customer_id, error: err instanceof Error ? err.message : err });
      }
    })();
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
    db.prepare('DELETE FROM payment_allocations WHERE payment_id = ?').run(paymentId);
  }

  /**
   * Delete payment allocations by invoice ID
   */
  static deleteAllocationsByInvoiceId(db: Database.Database, invoiceId: number): void {
    db.prepare('DELETE FROM payment_allocations WHERE invoice_id = ?').run(invoiceId);
  }

  /**
   * Get total paid for an invoice
   */
  static getTotalPaidByInvoiceId(db: Database.Database, invoiceId: number): number {
    const result = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total_paid
      FROM payment_allocations
      WHERE invoice_id = ?
    `).get(invoiceId) as { total_paid: number };
    return result.total_paid;
  }
}

export default PaymentModel;