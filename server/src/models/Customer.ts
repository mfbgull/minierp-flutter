import Database from 'better-sqlite3';

// Whitelist for ORDER BY to prevent SQL injection
const ALLOWED_SORT_COLUMNS = [
  'id', 'customer_code', 'customer_name', 'email', 'phone',
  'created_at', 'updated_at', 'is_active', 'current_balance',
  'credit_limit', 'transaction_date', 'debit', 'credit', 'balance',
];
const ALLOWED_SORT_DIRECTIONS = ['ASC', 'DESC'];

function safeSortBy(sortBy: string | undefined, sortOrder: string | undefined): { sortBy: string; sortOrder: string } {
  const sb = (sortBy || 'id').trim().toLowerCase();
  const so = (sortOrder || 'DESC').trim().toUpperCase();
  return {
    sortBy: ALLOWED_SORT_COLUMNS.includes(sb) ? sb : 'id',
    sortOrder: ALLOWED_SORT_DIRECTIONS.includes(so) ? so : 'DESC',
  };
}

interface Customer {
  id: number;
  customer_code: string;
  customer_name: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  billing_address?: string;
  shipping_address?: string;
  payment_terms?: string;
  payment_terms_days?: number;
  credit_limit?: number;
  current_balance?: number;
  opening_balance?: number;
  is_active?: number;
  created_at?: string;
  updated_at?: string;
}

interface CustomerFilters {
  search?: string;
  status?: string;
}

interface PaginatedResult {
  data: Customer[];
  total: number;
}

interface LedgerEntry {
  id: number;
  transaction_date: string;
  transaction_type: string;
  reference_no?: string;
  debit: number;
  credit: number;
  balance: number;
  description?: string;
  created_at?: string;
  linked_invoice_no?: string;
}

interface CreateCustomerDTO {
  customer_name: string;
  contact_person?: string;
  email?: string;
  phone: string;
  billing_address?: string;
  shipping_address?: string;
  payment_terms?: string;
  payment_terms_days?: number;
  credit_limit?: number;
  opening_balance?: number;
}

interface UpdateCustomerDTO {
  customer_name?: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  billing_address?: string;
  shipping_address?: string;
  payment_terms?: string;
  payment_terms_days?: number;
  credit_limit?: number;
  is_active?: number;
}

class CustomerModel {
  static getAll(filters: CustomerFilters, sortBy: string, sortOrder: string, page: number, limit: number, db: Database.Database): PaginatedResult {
    let query = `
      SELECT
        id, customer_code, customer_name, contact_person, email, phone,
        billing_address, shipping_address, payment_terms, payment_terms_days,
        credit_limit, current_balance,
        CASE
          WHEN credit_limit > 0 THEN ROUND((current_balance / credit_limit) * 100,2)
          ELSE 0
        END as credit_utilization_percent,
        is_active, created_at, updated_at
      FROM customers
      WHERE 1=1
    `;
    const params: unknown[] = [];

    if (filters.search) {
      query += ` AND (customer_name LIKE ? OR customer_code LIKE ? OR email LIKE ? OR phone LIKE ?)`;
      const searchTerm = `%${filters.search}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm);
    }

    if (filters.status && filters.status !== 'all') {
      query += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
    }

    const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
    query += ` ORDER BY ${safeBy} ${safeOrder}`;
    const offset = (page - 1) * limit;
    query += ` LIMIT ? OFFSET ?`;
    params.push(limit, offset);

    const data = db.prepare(query).all(...params) as Customer[];

    let countQuery = `SELECT COUNT(*) as total FROM customers WHERE 1=1`;
    const countParams: unknown[] = [];
    if (filters.search) {
      countQuery += ` AND (customer_name LIKE ? OR customer_code LIKE ? OR email LIKE ? OR phone LIKE ?)`;
      const searchTerm = `%${filters.search}%`;
      countParams.push(searchTerm, searchTerm, searchTerm, searchTerm);
    }
    if (filters.status && filters.status !== 'all') {
      countQuery += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
    }

    const result = db.prepare(countQuery).get(...countParams) as { total: number };
    return { data, total: result.total };
  }

  static getById(id: string | string[] | number, db: Database.Database): Customer | undefined {
    const resolvedId = Array.isArray(id) ? id[0] : id;
    return db.prepare(`
      SELECT
        id, customer_code, customer_name, contact_person, email, phone,
        billing_address, shipping_address, payment_terms, payment_terms_days,
        credit_limit, current_balance, opening_balance,
        CASE
          WHEN credit_limit > 0 THEN ROUND((current_balance / credit_limit) * 100,2)
          ELSE 0
        END as credit_utilization_percent,
        is_active, created_at, updated_at
      FROM customers
      WHERE id = ?
    `).get(id) as Customer | undefined;
  }

  static create(data: CreateCustomerDTO, db: Database.Database): number {
    const stmt = db.prepare(`
      INSERT INTO customers (
        customer_code, customer_name, contact_person, email, phone,
        billing_address, shipping_address, payment_terms, payment_terms_days,
        credit_limit, current_balance, opening_balance
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      '', data.customer_name, data.contact_person || '', data.email || '',
      data.phone, data.billing_address || '', data.shipping_address || '',
      data.payment_terms || '', data.payment_terms_days || 14,
      data.credit_limit || 0, data.opening_balance || 0, data.opening_balance || 0
    );
    return result.lastInsertRowid as number;
  }

  static updateCode(id: number, code: string, db: Database.Database): void {
    db.prepare('UPDATE customers SET customer_code = ? WHERE id = ?').run(code, id);
  }

  static update(id: string | string[] | number, data: UpdateCustomerDTO, db: Database.Database): void {
    db.prepare(`
      UPDATE customers SET
        customer_name = COALESCE(?, customer_name),
        contact_person = COALESCE(?, contact_person),
        email = COALESCE(?, email),
        phone = COALESCE(?, phone),
        billing_address = COALESCE(?, billing_address),
        shipping_address = COALESCE(?, shipping_address),
        payment_terms = COALESCE(?, payment_terms),
        payment_terms_days = COALESCE(?, payment_terms_days),
        credit_limit = COALESCE(?, credit_limit),
        is_active = COALESCE(?, is_active),
        updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(
      data.customer_name, data.contact_person, data.email, data.phone,
      data.billing_address, data.shipping_address, data.payment_terms,
      data.payment_terms_days, data.credit_limit, data.is_active, id
    );
  }

  static deactivate(id: string | string[] | number, db: Database.Database): void {
    db.prepare('UPDATE customers SET is_active = 0 WHERE id = ?').run(id);
  }

  static countInvoices(id: string | string[] | number, db: Database.Database): number {
    const result = db.prepare('SELECT COUNT(*) as count FROM invoices WHERE customer_id = ?').get(id) as { count: number };
    return result.count;
  }

  static countPayments(id: string | string[] | number, db: Database.Database): number {
    const result = db.prepare('SELECT COUNT(*) as count FROM payments WHERE customer_id = ?').get(id) as { count: number };
    return result.count;
  }

  static addOpeningBalanceLedger(customerId: number, customerCode: string, openingBalance: number, db: Database.Database): void {
    let debit = 0, credit = 0;
    if (openingBalance > 0) {
      debit = openingBalance;
    } else {
      credit = Math.abs(openingBalance);
    }
    db.prepare(`
      INSERT INTO customer_ledger (
        customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      ) VALUES (?, date('now'), ?, ?, ?, ?, ?, ?)
    `).run(
      customerId, 'OPENING_BALANCE', `OPEN-${customerCode}`,
      debit, credit, openingBalance, 'Opening Balance'
    );
  }

  static getLedger(id: string | string[] | number, sortBy: string, sortOrder: string, db: Database.Database): LedgerEntry[] {
    const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
    return db.prepare(`
      SELECT cl.id, cl.transaction_date, cl.transaction_type, cl.reference_no,
        cl.debit, cl.credit, cl.balance, cl.description, cl.created_at,
        COALESCE(
          inv_adjust.invoice_no,
          inv_return.invoice_no,
          inv_direct.invoice_no
        ) as linked_invoice_no
      FROM customer_ledger cl
      LEFT JOIN payments p ON cl.reference_no = p.payment_no
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      LEFT JOIN invoices inv_direct ON pa.invoice_id = inv_direct.id
      LEFT JOIN payments p_return ON cl.transaction_type = 'RETURN'
        AND cl.customer_id = p_return.customer_id
        AND p_return.amount = 0
        AND p_return.notes LIKE '%' || cl.reference_no || '%'
      LEFT JOIN payment_allocations pa_return ON p_return.id = pa_return.payment_id
      LEFT JOIN invoices inv_return ON pa_return.invoice_id = inv_return.id
      LEFT JOIN payments p_adjust ON cl.transaction_type = 'RETURN'
        AND cl.customer_id = p_adjust.customer_id
        AND p_adjust.amount = 0
        AND p_adjust.payment_method = 'Credit'
        AND p_adjust.notes LIKE '%' || cl.reference_no || '%'
      LEFT JOIN payment_allocations pa_adjust ON p_adjust.id = pa_adjust.payment_id
      LEFT JOIN invoices inv_adjust ON pa_adjust.invoice_id = inv_adjust.id
      WHERE cl.customer_id = ?
      ORDER BY cl.${safeBy} ${safeOrder}
    `).all(id) as LedgerEntry[];
  }

  static getStatement(id: string | string[] | number, fromDate: string | undefined, toDate: string | undefined, db: Database.Database): { transactions: LedgerEntry[]; openingBalance: number } {
    let query = `
      SELECT cl.transaction_date, cl.transaction_type, cl.reference_no,
        cl.debit, cl.credit, cl.balance, cl.description,
        COALESCE(
          inv_adjust.invoice_no,
          inv_return.invoice_no,
          inv_direct.invoice_no
        ) as linked_invoice_no
      FROM customer_ledger cl
      LEFT JOIN payments p ON cl.reference_no = p.payment_no
      LEFT JOIN payment_allocations pa ON p.id = pa.payment_id
      LEFT JOIN invoices inv_direct ON pa.invoice_id = inv_direct.id
      LEFT JOIN payments p_return ON cl.transaction_type = 'RETURN'
        AND cl.customer_id = p_return.customer_id
        AND p_return.amount = 0
        AND p_return.notes LIKE '%' || cl.reference_no || '%'
      LEFT JOIN payment_allocations pa_return ON p_return.id = pa_return.payment_id
      LEFT JOIN invoices inv_return ON pa_return.invoice_id = inv_return.id
      LEFT JOIN payments p_adjust ON cl.transaction_type = 'RETURN'
        AND cl.customer_id = p_adjust.customer_id
        AND p_adjust.amount = 0
        AND p_adjust.payment_method = 'Credit'
        AND p_adjust.notes LIKE '%' || cl.reference_no || '%'
      LEFT JOIN payment_allocations pa_adjust ON p_adjust.id = pa_adjust.payment_id
      LEFT JOIN invoices inv_adjust ON pa_adjust.invoice_id = inv_adjust.id
      WHERE cl.customer_id = ?
    `;
    const params: unknown[] = [id];

    if (fromDate) {
      query += ' AND transaction_date >= ?';
      params.push(fromDate);
    }
    if (toDate) {
      query += ' AND transaction_date <= ?';
      params.push(toDate);
    }
    query += ' ORDER BY transaction_date ASC';

    const transactions = db.prepare(query).all(...params) as LedgerEntry[];

    let openingBalanceQuery = 'SELECT balance FROM customer_ledger WHERE customer_id = ?';
    const openingBalanceParams: unknown[] = [id];
    if (fromDate) {
      openingBalanceQuery += ' AND transaction_date < ? ORDER BY transaction_date DESC LIMIT 1';
      openingBalanceParams.push(fromDate);
    } else {
      openingBalanceQuery += ' ORDER BY transaction_date DESC LIMIT 1';
    }

    const openingBalanceResult = db.prepare(openingBalanceQuery).get(...openingBalanceParams) as { balance: number } | undefined;
    return { transactions, openingBalance: openingBalanceResult ? openingBalanceResult.balance : 0 };
  }

  static getBalance(id: string | string[] | number, db: Database.Database): { id: number; customer_name: string; current_balance: number } | undefined {
    return db.prepare('SELECT id, customer_name, current_balance FROM customers WHERE id = ?').get(id) as { id: number; customer_name: string; current_balance: number } | undefined;
  }

  static getAllIds(db: Database.Database): number[] {
    const customers = db.prepare('SELECT id FROM customers').all() as { id: number }[];
    return customers.map(c => c.id);
  }

  static recalculateBalance(id: number, db: Database.Database): void {
    const balanceResult = db.prepare(`
      SELECT COALESCE(SUM(balance_amount), 0) as total_balance
      FROM invoices
      WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid', 'Overdue')
    `).get(id) as { total_balance: number };
    db.prepare('UPDATE customers SET current_balance = ? WHERE id = ?').run(balanceResult.total_balance, id);
  }
}

export default CustomerModel;
