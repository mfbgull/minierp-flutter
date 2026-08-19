"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// Whitelist for ORDER BY to prevent SQL injection
const ALLOWED_SORT_COLUMNS = [
    'id', 'customer_code', 'customer_name', 'email', 'phone',
    'created_at', 'updated_at', 'is_active', 'current_balance',
    'credit_limit', 'transaction_date', 'debit', 'credit', 'balance',
];
const ALLOWED_SORT_DIRECTIONS = ['ASC', 'DESC'];
function safeSortBy(sortBy, sortOrder) {
    const sb = (sortBy || 'id').trim().toLowerCase();
    const so = (sortOrder || 'DESC').trim().toUpperCase();
    return {
        sortBy: ALLOWED_SORT_COLUMNS.includes(sb) ? sb : 'id',
        sortOrder: ALLOWED_SORT_DIRECTIONS.includes(so) ? so : 'DESC',
    };
}
class CustomerModel {
    static getAll(filters, sortBy, sortOrder, page, limit, db) {
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
        const params = [];
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
        const data = db.prepare(query).all(...params);
        let countQuery = `SELECT COUNT(*) as total FROM customers WHERE 1=1`;
        const countParams = [];
        if (filters.search) {
            countQuery += ` AND (customer_name LIKE ? OR customer_code LIKE ? OR email LIKE ? OR phone LIKE ?)`;
            const searchTerm = `%${filters.search}%`;
            countParams.push(searchTerm, searchTerm, searchTerm, searchTerm);
        }
        if (filters.status && filters.status !== 'all') {
            countQuery += filters.status === 'active' ? ' AND is_active = 1' : ' AND is_active = 0';
        }
        const result = db.prepare(countQuery).get(...countParams);
        return { data, total: result.total };
    }
    static getById(id, db) {
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
    `).get(id);
    }
    static create(data, db) {
        const stmt = db.prepare(`
      INSERT INTO customers (
        customer_code, customer_name, contact_person, email, phone,
        billing_address, shipping_address, payment_terms, payment_terms_days,
        credit_limit, current_balance, opening_balance
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
        const result = stmt.run('', data.customer_name, data.contact_person || '', data.email || '', data.phone, data.billing_address || '', data.shipping_address || '', data.payment_terms || '', data.payment_terms_days || 14, data.credit_limit || 0, data.opening_balance || 0, data.opening_balance || 0);
        return result.lastInsertRowid;
    }
    static updateCode(id, code, db) {
        db.prepare('UPDATE customers SET customer_code = ? WHERE id = ?').run(code, id);
    }
    static update(id, data, db) {
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
    `).run(data.customer_name, data.contact_person, data.email, data.phone, data.billing_address, data.shipping_address, data.payment_terms, data.payment_terms_days, data.credit_limit, data.is_active, id);
    }
    static deactivate(id, db) {
        db.prepare('UPDATE customers SET is_active = 0 WHERE id = ?').run(id);
    }
    static countInvoices(id, db) {
        const result = db.prepare('SELECT COUNT(*) as count FROM invoices WHERE customer_id = ?').get(id);
        return result.count;
    }
    static countPayments(id, db) {
        const result = db.prepare('SELECT COUNT(*) as count FROM payments WHERE customer_id = ?').get(id);
        return result.count;
    }
    static addOpeningBalanceLedger(customerId, customerCode, openingBalance, db) {
        let debit = 0, credit = 0;
        if (openingBalance > 0) {
            debit = openingBalance;
        }
        else {
            credit = Math.abs(openingBalance);
        }
        db.prepare(`
      INSERT INTO customer_ledger (
        customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      ) VALUES (?, date('now'), ?, ?, ?, ?, ?, ?)
    `).run(customerId, 'OPENING_BALANCE', `OPEN-${customerCode}`, debit, credit, openingBalance, 'Opening Balance');
    }
    static getLedger(id, sortBy, sortOrder, db) {
        const { sortBy: safeBy, sortOrder: safeOrder } = safeSortBy(sortBy, sortOrder);
        // `linked_invoice_no` is resolved with scalar subqueries instead of
        // LEFT JOINs so every ledger entry yields exactly ONE row: joining
        // payments → payment_allocations → invoices directly duplicated any
        // entry whose payment was allocated to N invoices (each allocation
        // produced a copy of the row), which inflated the running balance
        // computed from the entries. For PAYMENT entries the linked value is
        // the comma-joined list of every allocated invoice; RETURN entries
        // resolve through their refund/credit payment (matched by notes —
        // refunds carry a negative amount, not the legacy 0) and fall back
        // to the invoice reference the entry itself was written with.
        return db.prepare(`
      SELECT cl.id, cl.transaction_date, cl.transaction_type, cl.reference_no,
        cl.debit, cl.credit, cl.balance, cl.description, cl.created_at,
        CASE
          WHEN cl.transaction_type = 'RETURN' THEN COALESCE(
            (
              SELECT GROUP_CONCAT(i.invoice_no, ', ')
              FROM payments pr
              JOIN payment_allocations pra ON pra.payment_id = pr.id
              JOIN invoices i ON i.id = pra.invoice_id
              WHERE pr.customer_id = cl.customer_id
                AND pr.amount <= 0
                AND pr.notes LIKE '%' || cl.reference_no || '%'
            ),
            cl.reference_no
          )
          ELSE (
            SELECT GROUP_CONCAT(i.invoice_no, ', ')
            FROM payments p
            JOIN payment_allocations pa ON pa.payment_id = p.id
            JOIN invoices i ON i.id = pa.invoice_id
            WHERE p.payment_no = cl.reference_no
          )
        END as linked_invoice_no
      FROM customer_ledger cl
      WHERE cl.customer_id = ?
      ORDER BY cl.${safeBy} ${safeOrder}
    `).all(id);
    }
    static getStatement(id, fromDate, toDate, db) {
        let query = `
      SELECT cl.transaction_date, cl.transaction_type, cl.reference_no,
        cl.debit, cl.credit, cl.balance, cl.description,
        CASE
          WHEN cl.transaction_type = 'RETURN' THEN COALESCE(
            (
              SELECT GROUP_CONCAT(i.invoice_no, ', ')
              FROM payments pr
              JOIN payment_allocations pra ON pra.payment_id = pr.id
              JOIN invoices i ON i.id = pra.invoice_id
              WHERE pr.customer_id = cl.customer_id
                AND pr.amount <= 0
                AND pr.notes LIKE '%' || cl.reference_no || '%'
            ),
            cl.reference_no
          )
          ELSE (
            SELECT GROUP_CONCAT(i.invoice_no, ', ')
            FROM payments p
            JOIN payment_allocations pa ON pa.payment_id = p.id
            JOIN invoices i ON i.id = pa.invoice_id
            WHERE p.payment_no = cl.reference_no
          )
        END as linked_invoice_no
      FROM customer_ledger cl
      WHERE cl.customer_id = ?
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
        let openingBalanceQuery = 'SELECT balance FROM customer_ledger WHERE customer_id = ?';
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
        return db.prepare('SELECT id, customer_name, current_balance FROM customers WHERE id = ?').get(id);
    }
    static getAllIds(db) {
        const customers = db.prepare('SELECT id FROM customers').all();
        return customers.map(c => c.id);
    }
    static recalculateBalance(id, db) {
        const balanceResult = db.prepare(`
      SELECT COALESCE(SUM(balance_amount), 0) as total_balance
      FROM invoices
      WHERE customer_id = ? AND status IN ('Unpaid', 'Partially Paid', 'Overdue')
    `).get(id);
        db.prepare('UPDATE customers SET current_balance = ? WHERE id = ?').run(balanceResult.total_balance, id);
    }
}
exports.default = CustomerModel;
//# sourceMappingURL=Customer.js.map