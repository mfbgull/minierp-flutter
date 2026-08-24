"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const SupplierLedger_1 = __importDefault(require("./SupplierLedger"));
const ALLOWED_SORT_COLUMNS = [
    'id', 'supplier_code', 'supplier_name', 'email', 'phone',
    'created_at', 'updated_at', 'is_active', 'current_balance',
    'transaction_date', 'debit', 'credit', 'balance',
];
const ALLOWED_SORT_DIRECTIONS = ['ASC', 'DESC'];
function safeSortBy(sortBy, sortOrder) {
    const sb = (sortBy || 'supplier_name').trim().toLowerCase();
    const so = (sortOrder || 'ASC').trim().toUpperCase();
    return {
        sortBy: ALLOWED_SORT_COLUMNS.includes(sb) ? sb : 'supplier_name',
        sortOrder: ALLOWED_SORT_DIRECTIONS.includes(so) ? so : 'ASC',
    };
}
class SupplierModel {
    static getAll(filters, sortBy, sortOrder, page, limit, db) {
        let query = `
      SELECT
        id, supplier_code, supplier_name, contact_person,
        email, phone, address, payment_terms, is_active,
        created_at, updated_at
      FROM suppliers
      WHERE 1=1
    `;
        const params = [];
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
        const data = db.prepare(query).all(...params);
        let countQuery = `SELECT COUNT(*) as total FROM suppliers WHERE 1=1`;
        const countParams = [];
        if (filters.search) {
            countQuery += ` AND (supplier_name LIKE ? OR supplier_code LIKE ? OR email LIKE ? OR phone LIKE ? OR contact_person LIKE ?)`;
            const searchTerm = `%${filters.search}%`;
            countParams.push(searchTerm, searchTerm, searchTerm, searchTerm, searchTerm);
        }
        if (filters.status && filters.status !== 'all') {
            countQuery += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
        }
        const result = db.prepare(countQuery).get(...countParams);
        return { data, total: result.total };
    }
    static getById(id, db) {
        return db.prepare('SELECT * FROM suppliers WHERE id = ?').get(id);
    }
    static create(data, db) {
        const result = db.prepare(`
      INSERT INTO suppliers (
        supplier_code, supplier_name, contact_person,
        email, phone, address, payment_terms
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(data.supplier_code, data.supplier_name, data.contact_person || null, data.email || null, data.phone || null, data.address || null, data.payment_terms || null);
        return result.lastInsertRowid;
    }
    static update(id, data, db) {
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
    `).run(data.supplier_name || null, data.contact_person || null, data.email || null, data.phone || null, data.address || null, data.payment_terms || null, data.is_active !== undefined ? (data.is_active ? 1 : 0) : 1, id);
    }
    static delete(id, db) {
        return db.prepare('DELETE FROM suppliers WHERE id = ?').run(id);
    }
    static countPurchaseOrders(supplierId, db) {
        return db.prepare('SELECT COUNT(*) as count FROM purchase_orders WHERE supplier_id = ?').get(supplierId);
    }
    static getLedger(id, sortBy, sortOrder, db, page = 1, limit = 0) {
        const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
        // Task 8.7: bounded pagination; limit 0 keeps the legacy unbounded shape.
        const countRow = db.prepare('SELECT COUNT(*) AS c FROM supplier_ledger WHERE supplier_id = ?').get(id);
        const total = countRow.c;
        let pageSql = '';
        const params = [id];
        if (limit > 0) {
            pageSql = ' LIMIT ? OFFSET ?';
            params.push(limit, (Math.max(1, page) - 1) * limit);
        }
        const rows = db.prepare(`
      SELECT id, supplier_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description, created_at
      FROM supplier_ledger
      WHERE supplier_id = ?
      ORDER BY ${safeBy} ${safeOrder}${pageSql}
    `).all(...params);
        return { rows, total };
    }
    static getStatement(id, fromDate, toDate, db) {
        let query = `
      SELECT transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      FROM supplier_ledger
      WHERE supplier_id = ?
    `;
        const params = [id];
        if (fromDate) {
            query += ' AND transaction_date >= ?';
            params.push(fromDate);
        }
        if (toDate) {
            query += ' AND transaction_date <= ?';
            params.push(toDate);
        }
        query += ' ORDER BY transaction_date ASC';
        const transactions = db.prepare(query).all(...params);
        let openingBalanceQuery = 'SELECT balance FROM supplier_ledger WHERE supplier_id = ?';
        const openingBalanceParams = [id];
        if (fromDate) {
            openingBalanceQuery += ' AND transaction_date < ? ORDER BY transaction_date DESC LIMIT 1';
            openingBalanceParams.push(fromDate);
        }
        else {
            openingBalanceQuery += ' ORDER BY transaction_date DESC LIMIT 1';
        }
        const openingBalanceResult = db.prepare(openingBalanceQuery).get(...openingBalanceParams);
        return { transactions, openingBalance: openingBalanceResult ? openingBalanceResult.balance : 0 };
    }
    static getBalance(id, db) {
        const result = db.prepare(`
      SELECT s.id, s.supplier_name, COALESCE(sl.balance, 0) as current_balance
      FROM suppliers s
      LEFT JOIN supplier_ledger sl ON s.id = sl.supplier_id AND sl.id = (
        SELECT MAX(id) FROM supplier_ledger WHERE supplier_id = s.id
      )
      WHERE s.id = ?
    `).get(id);
        return result;
    }
    static getAllIds(db) {
        const suppliers = db.prepare('SELECT id FROM suppliers').all();
        return suppliers.map(s => s.id);
    }
    static recalculateBalance(id, db) {
        SupplierLedger_1.default.rebuildBalances(id, db);
    }
}
exports.default = SupplierModel;
//# sourceMappingURL=Supplier.js.map