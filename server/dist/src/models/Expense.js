"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const accountingService_1 = __importDefault(require("../services/accountingService"));
const sequence_1 = require("../utils/sequence");
function generateExpenseNo(db, expenseDate) {
    const date = new Date(expenseDate);
    const year = date.getFullYear().toString().slice(-2);
    const month = String(date.getMonth() + 1).padStart(2, '0');
    // EXP-05 (task 5.4): the shared atomic counter replaces the old
    // read-modify-write over MAX(expense_no), which ran outside any
    // transaction and reused numbers after deletion. Callers wrap this in
    // the same transaction as the INSERT. Counters are seeded from existing
    // maxima by migrations/seed-expense-sequence.sql.
    const nextNo = (0, sequence_1.getNextSequenceNumber)(db, `EXP_last_no_${year}${month}`);
    return `EXP-${year}${month}-${String(nextNo).padStart(4, '0')}`;
}
function create(db, data) {
    const expenseId = db.transaction(() => {
        const result = db.prepare(`
      INSERT INTO expenses (
        expense_no, expense_category, description, amount, expense_date,
        payment_method, reference_no, vendor_name, project, status, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.expense_no, data.expense_category, data.description, data.amount, data.expense_date, data.payment_method || null, data.reference_no || null, data.vendor_name || null, data.project || null, data.status, data.created_by);
        const newId = result.lastInsertRowid;
        // GL posting (ACC-04): Dr 6000 Operating Expenses /
        // Cr cash-per-method. Expenses default to Approved on entry, so
        // posting at creation matches when the cash effect occurs.
        accountingService_1.default.postExpenseEntry(db, {
            expenseId: newId,
            expenseNo: data.expense_no,
            amount: data.amount,
            expenseDate: data.expense_date,
            paymentMethod: data.payment_method || 'cash',
            userId: data.created_by,
        });
        return newId;
    })();
    return expenseId;
}
function getAll(db, filters = {}) {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;
    const offset = (pageNum - 1) * limitNum;
    let query = `
    SELECT e.id, e.expense_no, e.expense_category, e.description, e.amount,
           e.expense_date, e.payment_method, e.reference_no, e.vendor_name,
           e.project, e.status, e.created_at, u.full_name as created_by_name
    FROM expenses e LEFT JOIN users u ON e.created_by = u.id WHERE 1=1
  `;
    const params = [];
    if (filters.category) {
        query += ' AND e.expense_category = ?';
        params.push(filters.category);
    }
    if (filters.status) {
        query += ' AND e.status = ?';
        params.push(filters.status);
    }
    if (filters.vendor) {
        query += ' AND e.vendor_name LIKE ?';
        params.push(`%${filters.vendor}%`);
    }
    if (filters.from_date) {
        query += ' AND e.expense_date >= ?';
        params.push(filters.from_date);
    }
    if (filters.to_date) {
        query += ' AND e.expense_date <= ?';
        params.push(filters.to_date);
    }
    if (filters.search) {
        const term = `%${filters.search}%`;
        query += ' AND (e.description LIKE ? OR e.expense_category LIKE ? OR e.vendor_name LIKE ?)';
        params.push(term, term, term);
    }
    // Sort — whitelisted via sqlSanitizer (default matches pre-paging
    // behavior: newest expense first).
    const sortBy = filters.sortBy || 'e.expense_date';
    const sortOrder = filters.sortOrder || 'DESC';
    query += ` ORDER BY ${sortBy} ${sortOrder} LIMIT ? OFFSET ?`;
    params.push(limitNum, offset);
    return db.prepare(query).all(...params);
}
function getCount(db, filters = {}) {
    let query = 'SELECT COUNT(*) as count FROM expenses e WHERE 1=1';
    const params = [];
    if (filters.category) {
        query += ' AND e.expense_category = ?';
        params.push(filters.category);
    }
    if (filters.status) {
        query += ' AND e.status = ?';
        params.push(filters.status);
    }
    if (filters.vendor) {
        query += ' AND e.vendor_name LIKE ?';
        params.push(`%${filters.vendor}%`);
    }
    if (filters.from_date) {
        query += ' AND e.expense_date >= ?';
        params.push(filters.from_date);
    }
    if (filters.to_date) {
        query += ' AND e.expense_date <= ?';
        params.push(filters.to_date);
    }
    if (filters.search) {
        const term = `%${filters.search}%`;
        query += ' AND (e.description LIKE ? OR e.expense_category LIKE ? OR e.vendor_name LIKE ?)';
        params.push(term, term, term);
    }
    const result = db.prepare(query).get(...params);
    return result.count;
}
function getById(db, id) {
    return db.prepare(`
    SELECT e.id, e.expense_no, e.expense_category, e.description, e.amount,
           e.expense_date, e.payment_method, e.reference_no, e.vendor_name,
           e.project, e.status, e.created_at, e.updated_at, u.full_name as created_by_name
    FROM expenses e LEFT JOIN users u ON e.created_by = u.id WHERE e.id = ?
  `).get(id);
}
function update(db, id, data) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Expense not found');
    db.prepare(`
    UPDATE expenses SET
      expense_category = ?, description = ?, amount = ?, expense_date = ?,
      payment_method = ?, reference_no = ?, vendor_name = ?, project = ?,
      status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
  `).run(data.expense_category || existing.expense_category, data.description || existing.description, data.amount !== undefined ? data.amount : existing.amount, data.expense_date || existing.expense_date, data.payment_method || existing.payment_method, data.reference_no || existing.reference_no, data.vendor_name || existing.vendor_name, data.project || existing.project, data.status || existing.status, id);
}
function deleteExpense(db, id) {
    const existing = getById(db, id);
    if (!existing)
        throw new Error('Expense not found');
    db.prepare('DELETE FROM expenses WHERE id = ?').run(id);
}
function getByDateRange(db, from_date, to_date) {
    const expenses = db.prepare(`
    SELECT e.id, e.expense_no, e.expense_category, e.description, e.amount,
           e.expense_date, e.payment_method, e.reference_no, e.vendor_name,
           e.project, e.status, e.created_at, u.full_name as created_by_name
    FROM expenses e LEFT JOIN users u ON e.created_by = u.id
    WHERE e.expense_date BETWEEN ? AND ? ORDER BY e.expense_date DESC
  `).all(from_date, to_date);
    const total = db.prepare('SELECT SUM(amount) as total FROM expenses WHERE expense_date BETWEEN ? AND ?').get(from_date, to_date);
    return { expenses, total_amount: parseFloat(total?.total?.toString() || '0') };
}
function getByCategory(db, category, from_date, to_date) {
    let query = `
    SELECT e.id, e.expense_no, e.expense_category, e.description, e.amount,
           e.expense_date, e.payment_method, e.reference_no, e.vendor_name,
           e.project, e.status, e.created_at, u.full_name as created_by_name
    FROM expenses e LEFT JOIN users u ON e.created_by = u.id WHERE e.expense_category = ?
  `;
    const params = [category];
    if (from_date && to_date) {
        query += ' AND e.expense_date BETWEEN ? AND ?';
        params.push(from_date, to_date);
    }
    query += ' ORDER BY e.expense_date DESC';
    const expenses = db.prepare(query).all(...params);
    let totalQuery = 'SELECT SUM(amount) as total FROM expenses WHERE expense_category = ?';
    const totalParams = [category];
    if (from_date && to_date) {
        totalQuery += ' AND expense_date BETWEEN ? AND ?';
        totalParams.push(from_date, to_date);
    }
    const total = db.prepare(totalQuery).get(...totalParams);
    return { expenses, total_amount: parseFloat(total?.total?.toString() || '0') };
}
function getSummary(db, from_date, to_date) {
    let query = 'SELECT expense_category, COUNT(*) as count, SUM(amount) as total_amount FROM expenses WHERE 1=1';
    const params = [];
    if (from_date && to_date) {
        query += ' AND expense_date BETWEEN ? AND ?';
        params.push(from_date, to_date);
    }
    query += ' GROUP BY expense_category ORDER BY total_amount DESC';
    const categorySummary = db.prepare(query).all(...params);
    let overallQuery = 'SELECT COUNT(*) as total_expenses, SUM(amount) as total_amount FROM expenses WHERE 1=1';
    const overallParams = [];
    if (from_date && to_date) {
        overallQuery += ' AND expense_date BETWEEN ? AND ?';
        overallParams.push(from_date, to_date);
    }
    const overall = db.prepare(overallQuery).get(...overallParams);
    return { category_summary: categorySummary, overall_summary: overall };
}
function getAllCategories(db) {
    return db.prepare('SELECT id, category_name, description, is_active, created_at, updated_at FROM expense_categories ORDER BY category_name').all();
}
function getCategoryById(db, id) {
    return db.prepare('SELECT * FROM expense_categories WHERE id = ?').get(id);
}
function createCategory(db, data) {
    const existing = db.prepare('SELECT id FROM expense_categories WHERE category_name = ?').get(data.category_name);
    if (existing)
        throw new Error('Expense category already exists');
    const result = db.prepare('INSERT INTO expense_categories (category_name, description) VALUES (?, ?)').run(data.category_name, data.description || '');
    return result.lastInsertRowid;
}
function updateCategory(db, id, data) {
    const existing = getCategoryById(db, id);
    if (!existing)
        throw new Error('Expense category not found');
    if (data.category_name && data.category_name !== existing.category_name) {
        const duplicate = db.prepare('SELECT id FROM expense_categories WHERE category_name = ? AND id != ?').get(data.category_name, id);
        if (duplicate)
            throw new Error('Expense category name already exists');
    }
    db.prepare(`
    UPDATE expense_categories SET
      category_name = COALESCE(?, category_name), description = COALESCE(?, description),
      is_active = COALESCE(?, is_active), updated_at = CURRENT_TIMESTAMP WHERE id = ?
  `).run(data.category_name, data.description, data.is_active, id);
}
function deleteCategory(db, id) {
    const existing = getCategoryById(db, id);
    if (!existing)
        throw new Error('Expense category not found');
    const count = db.prepare('SELECT COUNT(*) as count FROM expenses WHERE expense_category = ?').get(existing.category_name);
    if (count.count > 0)
        throw new Error('Cannot delete expense category. It is being used by existing expenses.');
    db.prepare('DELETE FROM expense_categories WHERE id = ?').run(id);
}
function getStatusOptions() {
    return [
        { value: 'Draft', label: 'Draft' },
        { value: 'Submitted', label: 'Submitted' },
        { value: 'Approved', label: 'Approved' },
        { value: 'Paid', label: 'Paid' },
        { value: 'Cancelled', label: 'Cancelled' }
    ];
}
function getPaymentMethodOptions() {
    return [
        { value: 'Cash', label: 'Cash' },
        { value: 'Check', label: 'Check' },
        { value: 'Bank Transfer', label: 'Bank Transfer' },
        { value: 'Easypaisa', label: 'Easypaisa' },
        { value: 'JazzCash', label: 'JazzCash' },
        { value: 'UPaisa', label: 'UPaisa' },
        { value: 'Credit Card', label: 'Credit Card' },
        { value: 'Debit Card', label: 'Debit Card' },
        { value: 'Online Transfer', label: 'Online Transfer' },
        { value: 'Other', label: 'Other' }
    ];
}
exports.default = {
    generateExpenseNo,
    create,
    getAll,
    getCount,
    getById,
    update,
    delete: deleteExpense,
    getByDateRange,
    getByCategory,
    getSummary,
    getAllCategories,
    getCategoryById,
    createCategory,
    updateCategory,
    deleteCategory,
    getStatusOptions,
    getPaymentMethodOptions,
};
//# sourceMappingURL=Expense.js.map