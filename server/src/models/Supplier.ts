import Database from 'better-sqlite3';
import SupplierLedgerModel from './SupplierLedger';

interface Supplier {
  id: number;
  supplier_code: string;
  supplier_name: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  address?: string;
  payment_terms?: string;
  is_active: number;
  created_at?: string;
  updated_at?: string;
  current_balance?: number;
  credit_utilization_percent?: number;
}

interface CreateSupplierDTO {
  supplier_code: string;
  supplier_name: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  address?: string;
  payment_terms?: string;
}

interface UpdateSupplierDTO {
  supplier_name?: string;
  contact_person?: string;
  email?: string;
  phone?: string;
  address?: string;
  payment_terms?: string;
  is_active?: boolean;
}

interface SupplierFilters {
  search?: string;
  status?: string;
}

interface PaginatedResult {
  data: Supplier[];
  total: number;
}

interface LedgerEntry {
  id: number;
  transaction_date: string;
  transaction_type: string;
  reference_no?: string;
  description?: string;
  debit: number;
  credit: number;
  balance: number;
  created_at?: string;
}

const ALLOWED_SORT_COLUMNS = [
  'id', 'supplier_code', 'supplier_name', 'email', 'phone',
  'created_at', 'updated_at', 'is_active', 'current_balance',
  'transaction_date', 'debit', 'credit', 'balance',
];
const ALLOWED_SORT_DIRECTIONS = ['ASC', 'DESC'];

function safeSortBy(sortBy: string | undefined, sortOrder: string | undefined): { sortBy: string; sortOrder: string } {
  const sb = (sortBy || 'supplier_name').trim().toLowerCase();
  const so = (sortOrder || 'ASC').trim().toUpperCase();
  return {
    sortBy: ALLOWED_SORT_COLUMNS.includes(sb) ? sb : 'supplier_name',
    sortOrder: ALLOWED_SORT_DIRECTIONS.includes(so) ? so : 'ASC',
  };
}

class SupplierModel {
  static getAll(filters: SupplierFilters, sortBy: string, sortOrder: string, page: number, limit: number, db: Database.Database): PaginatedResult {
    let query = `
      SELECT
        id, supplier_code, supplier_name, contact_person,
        email, phone, address, payment_terms, is_active,
        created_at, updated_at
      FROM suppliers
      WHERE 1=1
    `;
    const params: unknown[] = [];

    if (filters.search) {
      query += ` AND (supplier_name LIKE ? OR supplier_code LIKE ? OR email LIKE ? OR phone LIKE ? OR contact_person LIKE ?)`;
      const searchTerm = `%${filters.search}%`;
      params.push(searchTerm, searchTerm, searchTerm, searchTerm, searchTerm);
    }

    if (filters.status && filters.status !== 'all') {
      query += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
    }

    const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
    query += ` ORDER BY ${safeBy} ${safeOrder}`;
    const offset = (page - 1) * limit;
    query += ` LIMIT ? OFFSET ?`;
    params.push(limit, offset);

    const data = db.prepare(query).all(...params) as Supplier[];

    let countQuery = `SELECT COUNT(*) as total FROM suppliers WHERE 1=1`;
    const countParams: unknown[] = [];
    if (filters.search) {
      countQuery += ` AND (supplier_name LIKE ? OR supplier_code LIKE ? OR email LIKE ? OR phone LIKE ? OR contact_person LIKE ?)`;
      const searchTerm = `%${filters.search}%`;
      countParams.push(searchTerm, searchTerm, searchTerm, searchTerm, searchTerm);
    }
    if (filters.status && filters.status !== 'all') {
      countQuery += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
    }

    const result = db.prepare(countQuery).get(...countParams) as { total: number };
    return { data, total: result.total };
  }

  static getById(id: number, db: Database.Database): Supplier | undefined {
    return db.prepare('SELECT * FROM suppliers WHERE id = ?').get(id) as Supplier | undefined;
  }

  static create(data: CreateSupplierDTO, db: Database.Database): number {
    const result = db.prepare(`
      INSERT INTO suppliers (
        supplier_code, supplier_name, contact_person,
        email, phone, address, payment_terms
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.supplier_code,
      data.supplier_name,
      data.contact_person || null,
      data.email || null,
      data.phone || null,
      data.address || null,
      data.payment_terms || null
    );
    return result.lastInsertRowid as number;
  }

  static update(id: number, data: UpdateSupplierDTO, db: Database.Database): Database.RunResult {
    return db.prepare(`
      UPDATE suppliers SET
        supplier_name = ?,
        contact_person = ?,
        email = ?,
        phone = ?,
        address = ?,
        payment_terms = ?,
        is_active = ?,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(
      data.supplier_name || null,
      data.contact_person || null,
      data.email || null,
      data.phone || null,
      data.address || null,
      data.payment_terms || null,
      data.is_active !== undefined ? (data.is_active ? 1 : 0) : 1,
      id
    );
  }

  static delete(id: number, db: Database.Database): Database.RunResult {
    return db.prepare('DELETE FROM suppliers WHERE id = ?').run(id);
  }

  static countPurchaseOrders(supplierId: number, db: Database.Database): { count: number } {
    return db.prepare('SELECT COUNT(*) as count FROM purchase_orders WHERE supplier_id = ?').get(supplierId) as { count: number };
  }

  static getLedger(id: number, sortBy: string, sortOrder: string, db: Database.Database, page = 1, limit = 0, fromDate?: string, toDate?: string): { rows: LedgerEntry[]; total: number } {
    const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
    // Task 8.7: bounded pagination; limit 0 keeps the legacy unbounded shape.
    // Active-set parity with the customer ledger (and SupplierLedgerModel's
    // getBalance/rebuildBalances): voided originals and their reversal rows
    // are audit-only and never listed. Optional inclusive date bounds follow
    // the statement convention (transaction_date >= from AND <= to), applied
    // to both the count and the page query so the envelope stays consistent.
    const dateConditions: string[] = [];
    const dateParams: string[] = [];
    if (fromDate) {
      dateConditions.push('transaction_date >= ?');
      dateParams.push(fromDate);
    }
    if (toDate) {
      dateConditions.push('transaction_date <= ?');
      dateParams.push(toDate);
    }
    const dateSql = dateConditions.length ? ` AND ${dateConditions.join(' AND ')}` : '';

    const activeSql = ' WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL';
    const countRow = db.prepare(
      'SELECT COUNT(*) AS c FROM supplier_ledger' + activeSql + dateSql
    ).get(id, ...dateParams) as { c: number };
    const total = countRow.c;

    let pageSql = '';
    const params: Array<string | number> = [id, ...dateParams];
    if (limit > 0) {
      pageSql = ' LIMIT ? OFFSET ?';
      params.push(limit, (Math.max(1, page) - 1) * limit);
    }

    const rows = db.prepare(`
      SELECT id, supplier_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description, created_at
      FROM supplier_ledger${activeSql}${dateSql}
      ORDER BY ${safeBy} ${safeOrder}${pageSql}
    `).all(...params) as LedgerEntry[];
    return { rows, total };
  }

  static getStatement(id: number, fromDate: string | undefined, toDate: string | undefined, db: Database.Database): { transactions: LedgerEntry[]; openingBalance: number } {
    // Active-set parity with the customer statement (and the authoritative
    // balance in SupplierLedgerModel): voided originals and their reversal
    // rows never appear on a statement.
    let query = `
      SELECT transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      FROM supplier_ledger
      WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL
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
    // (transaction_date, id) tiebreaker mirrors the customer statement and
    // the balance-chain order the stored balances were computed in.
    query += ' ORDER BY transaction_date ASC, id ASC';

    const transactions = db.prepare(query).all(...params) as LedgerEntry[];

    // Full-history statements (fromDate omitted) start from zero — the
    // stored running balance of the LATEST row is the closing position, not
    // an opening one, and seeding a statement with it double-counts once the
    // controller adds the in-window net. When a range is active the opening
    // is the stored balance of the last active row strictly before fromDate
    // (deterministic (transaction_date DESC, id DESC) tiebreaker).
    let openingBalance = 0;
    if (fromDate) {
      const openingBalanceResult = db.prepare(
        'SELECT balance FROM supplier_ledger WHERE supplier_id = ? AND voided = 0 AND reversed_by IS NULL AND transaction_date < ? ORDER BY transaction_date DESC, id DESC LIMIT 1'
      ).get(id, fromDate) as { balance: number } | undefined;
      openingBalance = openingBalanceResult ? openingBalanceResult.balance : 0;
    }

    return { transactions, openingBalance };
  }

  static getBalance(id: number, db: Database.Database): { id: number; supplier_name: string; current_balance: number } | undefined {
    const result = db.prepare(`
      SELECT s.id, s.supplier_name, COALESCE(sl.balance, 0) as current_balance
      FROM suppliers s
      LEFT JOIN supplier_ledger sl ON s.id = sl.supplier_id AND sl.id = (
        SELECT MAX(id) FROM supplier_ledger WHERE supplier_id = s.id
      )
      WHERE s.id = ?
    `).get(id) as { id: number; supplier_name: string; current_balance: number } | undefined;
    return result;
  }

  static getAllIds(db: Database.Database): number[] {
    const suppliers = db.prepare('SELECT id FROM suppliers').all() as { id: number }[];
    return suppliers.map(s => s.id);
  }

  static recalculateBalance(id: number, db: Database.Database): void {
    SupplierLedgerModel.rebuildBalances(id, db);
  }
}

export default SupplierModel;
