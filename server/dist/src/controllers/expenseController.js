"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const Expense_1 = __importDefault(require("../models/Expense"));
function createExpense(req, res) {
    try {
        const { expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project } = req.body;
        const userId = req.user.id;
        if (!expense_category || !amount || !expense_date) {
            res.status(400).json({ success: false, error: 'Expense category, amount, and expense date are required' });
            return;
        }
        const parsedAmount = parseFloat(amount);
        if (isNaN(parsedAmount) || parsedAmount <= 0) {
            res.status(400).json({ success: false, error: 'Amount must be a positive number' });
            return;
        }
        // EXP-03 (task 5.2): client-supplied status is ignored — new expenses
        // start as Draft and move through the transition matrix in updateExpense.
        // EXP-04 (task 5.3): category must exist in expense_categories.
        const categoryExists = database_1.default.prepare('SELECT id FROM expense_categories WHERE category_name = ? COLLATE NOCASE').get(String(expense_category).trim());
        if (!categoryExists) {
            const valid = database_1.default.prepare('SELECT category_name FROM expense_categories ORDER BY category_name').all()
                .map((r) => r.category_name);
            res.status(400).json({ success: false, error: `Unknown expense category '${expense_category}' — valid categories: ${valid.join(', ')}` });
            return;
        }
        // EXP-05 (task 5.4): numbering comes from the shared settings counter
        // inside the same transaction as the INSERT — the old MAX(expense_no)
        // scan was non-atomic outside any transaction.
        let expenseId;
        let expenseNo;
        database_1.default.transaction(() => {
            expenseNo = Expense_1.default.generateExpenseNo(database_1.default, expense_date);
            expenseId = Expense_1.default.create(database_1.default, {
                expense_no: expenseNo, expense_category: String(expense_category).trim(), description: description || '',
                amount: parsedAmount, expense_date, payment_method, reference_no, vendor_name,
                project, status: 'Draft', created_by: userId,
            });
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EXPENSE_CREATE, 'Expense', expenseId, `Created expense: ${expenseNo} - ${expense_category} ($${parsedAmount})`, userId, { expense_no: expenseNo, expense_category, amount: parsedAmount, vendor_name });
        req.activityLogged = true;
        res.status(201).json({
            success: true, message: 'Expense created successfully',
            data: { id: expenseId, expense_no: expenseNo, expense_category, description, amount: parsedAmount, expense_date, payment_method, reference_no, vendor_name, project, status: 'Draft', created_by: userId }
        });
    }
    catch (error) {
        logger_1.default.error('Error creating expense:', error);
        res.status(500).json({ success: false, error: 'Failed to create expense' });
    }
}
function getExpenses(req, res) {
    try {
        const pageParam = (0, queryUtils_1.getQueryParam)(req.query.page);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const categoryParam = (0, queryUtils_1.getQueryParam)(req.query.category);
        const statusParam = (0, queryUtils_1.getQueryParam)(req.query.status);
        const vendorParam = (0, queryUtils_1.getQueryParam)(req.query.vendor);
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.from_date);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.to_date);
        const searchParam = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)(sortBy || 'e.expense_date', sortOrder || 'DESC', sqlSanitizer_1.EXPENSE_SORT_COLUMNS, 'e.expense_date', 'DESC');
        const filters = {
            page: parseInt(pageParam) || 1,
            limit: parseInt(limitParam) || 10,
            category: categoryParam,
            status: statusParam,
            vendor: vendorParam,
            from_date: fromDateParam,
            to_date: toDateParam,
            search: searchParam,
            sortBy: sortParams.column,
            sortOrder: sortParams.order,
        };
        const expenses = Expense_1.default.getAll(database_1.default, filters);
        const totalCount = Expense_1.default.getCount(database_1.default, filters);
        const pageNum = filters.page;
        const limitNum = filters.limit;
        res.json({
            success: true,
            data: expenses,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(totalCount / limitNum),
                totalItems: totalCount,
                hasNext: pageNum < Math.ceil(totalCount / limitNum),
                hasPrev: pageNum > 1,
            },
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching expenses:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expenses' });
    }
}
function getExpenseById(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const expense = Expense_1.default.getById(database_1.default, id);
        if (!expense) {
            res.status(404).json({ success: false, error: 'Expense not found' });
            return;
        }
        res.json({ success: true, data: expense });
    }
    catch (error) {
        logger_1.default.error('Error fetching expense:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expense' });
    }
}
// EXP-03 (task 5.2): the expense status machine.
const EXPENSE_STATUSES = ['Draft', 'Submitted', 'Approved', 'Paid', 'Cancelled'];
const EXPENSE_TRANSITIONS = {
    Draft: ['Submitted', 'Cancelled'],
    Submitted: ['Approved', 'Cancelled'],
    Approved: ['Paid', 'Cancelled'],
    Paid: [],
    Cancelled: [],
};
function updateExpense(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const { expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project } = req.body;
        const targetStatus = req.body.status;
        const existing = Expense_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Expense not found' });
            return;
        }
        const currentStatus = String(existing.status);
        // Status transition validation.
        if (targetStatus !== undefined && targetStatus !== currentStatus) {
            if (!EXPENSE_STATUSES.includes(targetStatus)) {
                res.status(400).json({ success: false, error: `Invalid status '${targetStatus}' — use one of: ${EXPENSE_STATUSES.join(', ')}` });
                return;
            }
            if (!EXPENSE_TRANSITIONS[currentStatus]?.includes(targetStatus)) {
                res.status(400).json({
                    success: false,
                    error: `Cannot move an expense from ${currentStatus} to ${targetStatus} — allowed: ${EXPENSE_TRANSITIONS[currentStatus]?.join(', ') || '(none; terminal state)'}`,
                });
                return;
            }
            // Approvals are a control point: moving into Approved/Paid requires
            // expenses:approve (Admin bypasses in the middleware itself).
            if ((targetStatus === 'Approved' || targetStatus === 'Paid') && req.user.role !== 'admin') {
                const perm = database_1.default.prepare(`
          SELECT 1 FROM role_permissions rp
          JOIN permissions p ON p.id = rp.permission_id
          JOIN users u ON u.role_id = rp.role_id
          WHERE u.id = ? AND p.permission_name = 'expenses:approve'
          LIMIT 1
        `).get(req.user.id);
                if (!perm) {
                    res.status(403).json({ success: false, error: 'The expenses:approve permission is required to approve or pay expenses' });
                    return;
                }
            }
        }
        // Immutability: Approved/Paid documents reject field edits. Only the
        // documented reversal (→ Cancelled) is possible.
        const isLocked = currentStatus === 'Approved' || currentStatus === 'Paid';
        const hasFieldEdits = [expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project]
            .some((v) => v !== undefined);
        if (isLocked && hasFieldEdits && (targetStatus === undefined || targetStatus === currentStatus)) {
            res.status(400).json({
                success: false,
                error: `A ${currentStatus.toLowerCase()} expense is immutable — cancel it and record a new one to change its details`,
            });
            return;
        }
        // Category validation on edit too (task 5.3).
        if (expense_category !== undefined) {
            const categoryExists = database_1.default.prepare('SELECT id FROM expense_categories WHERE category_name = ? COLLATE NOCASE').get(String(expense_category).trim());
            if (!categoryExists) {
                res.status(400).json({ success: false, error: `Unknown expense category '${expense_category}'` });
                return;
            }
        }
        Expense_1.default.update(database_1.default, id, {
            expense_category: isLocked && targetStatus !== 'Cancelled' ? undefined : expense_category,
            description: isLocked && targetStatus !== 'Cancelled' ? undefined : description,
            amount: !isLocked || targetStatus === 'Cancelled' ? (amount !== undefined ? parseFloat(amount) : undefined) : undefined,
            expense_date: isLocked && targetStatus !== 'Cancelled' ? undefined : expense_date,
            payment_method: isLocked && targetStatus !== 'Cancelled' ? undefined : payment_method,
            reference_no: isLocked && targetStatus !== 'Cancelled' ? undefined : reference_no,
            vendor_name: isLocked && targetStatus !== 'Cancelled' ? undefined : vendor_name,
            project: isLocked && targetStatus !== 'Cancelled' ? undefined : project,
            status: targetStatus,
        });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EXPENSE_UPDATE, 'Expense', id, `Updated expense: ${existing.expense_no}${targetStatus ? ` → ${targetStatus}` : ''}`, req.user.id, { expense_no: existing.expense_no, changes: Object.keys(req.body).filter(k => req.body[k] !== undefined), from_status: currentStatus, to_status: targetStatus });
        req.activityLogged = true;
        res.json({ success: true, message: 'Expense updated successfully', data: Expense_1.default.getById(database_1.default, id) });
    }
    catch (error) {
        logger_1.default.error('Error updating expense:', error);
        res.status(500).json({ success: false, error: 'Failed to update expense' });
    }
}
function getExpensesByDateRange(req, res) {
    try {
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.from_date);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.to_date);
        const from_date = fromDateParam;
        const to_date = toDateParam;
        if (!from_date || !to_date) {
            res.status(400).json({ success: false, error: 'from_date and to_date are required' });
            return;
        }
        const result = Expense_1.default.getByDateRange(database_1.default, from_date, to_date);
        res.json({ success: true, data: result.expenses, summary: { total_expenses: result.expenses.length, total_amount: result.total_amount } });
    }
    catch (error) {
        logger_1.default.error('Error fetching expenses by date range:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expenses by date range' });
    }
}
function getExpensesByCategory(req, res) {
    try {
        const { category } = req.params;
        const categoryParam = Array.isArray(category) ? category[0] : category;
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.from_date);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.to_date);
        const result = Expense_1.default.getByCategory(database_1.default, categoryParam, fromDateParam, toDateParam);
        res.json({ success: true, data: result.expenses, summary: { category: categoryParam, total_expenses: result.expenses.length, total_amount: result.total_amount } });
    }
    catch (error) {
        logger_1.default.error('Error fetching expenses by category:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expenses by category' });
    }
}
function getExpenseSummary(req, res) {
    try {
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.from_date);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.to_date);
        const summary = Expense_1.default.getSummary(database_1.default, fromDateParam, toDateParam);
        res.json({ success: true, data: { category_summary: summary.category_summary, overall_summary: summary.overall_summary } });
    }
    catch (error) {
        logger_1.default.error('Error fetching expense summary:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expense summary' });
    }
}
function getExpenseCategories(req, res) {
    try {
        const categories = Expense_1.default.getAllCategories(database_1.default);
        res.json({ success: true, data: categories });
    }
    catch (error) {
        logger_1.default.error('Error fetching expense categories:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch expense categories' });
    }
}
function createExpenseCategory(req, res) {
    try {
        const { category_name, description } = req.body;
        if (!category_name) {
            res.status(400).json({ success: false, error: 'Category name is required' });
            return;
        }
        const id = Expense_1.default.createCategory(database_1.default, { category_name, description });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EXPENSE_CATEGORY_CREATE, 'ExpenseCategory', id, `Created expense category: ${category_name}`, req.user.id);
        req.activityLogged = true;
        res.status(201).json({ success: true, message: 'Expense category created successfully', data: { id, category_name, description: description || '', is_active: 1 } });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to create expense category';
        if (message.includes('already exists')) {
            res.status(400).json({ success: false, error: message });
            return;
        }
        logger_1.default.error('Error creating expense category:', error);
        res.status(500).json({ success: false, error: 'Failed to create expense category' });
    }
}
function updateExpenseCategory(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const { category_name, description, is_active } = req.body;
        const existing = Expense_1.default.getCategoryById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Expense category not found' });
            return;
        }
        Expense_1.default.updateCategory(database_1.default, id, { category_name, description, is_active });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EXPENSE_CATEGORY_UPDATE, 'ExpenseCategory', id, `Updated expense category: ${existing.category_name}`, req.user.id);
        req.activityLogged = true;
        res.json({ success: true, message: 'Expense category updated successfully', data: Expense_1.default.getCategoryById(database_1.default, id) });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to update expense category';
        if (message.includes('not found')) {
            res.status(404).json({ success: false, error: message });
            return;
        }
        if (message.includes('already exists')) {
            res.status(400).json({ success: false, error: message });
            return;
        }
        logger_1.default.error('Error updating expense category:', error);
        res.status(500).json({ success: false, error: 'Failed to update expense category' });
    }
}
function deleteExpenseCategory(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const existing = Expense_1.default.getCategoryById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Expense category not found' });
            return;
        }
        Expense_1.default.deleteCategory(database_1.default, id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EXPENSE_CATEGORY_DELETE, 'ExpenseCategory', id, `Deleted expense category: ${existing.category_name}`, req.user.id);
        req.activityLogged = true;
        res.json({ success: true, message: 'Expense category deleted successfully' });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to delete expense category';
        if (message.includes('not found') || message.includes('being used')) {
            res.status(400).json({ success: false, error: message });
            return;
        }
        logger_1.default.error('Error deleting expense category:', error);
        res.status(500).json({ success: false, error: 'Failed to delete expense category' });
    }
}
function getExpenseStatusOptions(req, res) {
    res.json({ success: true, data: Expense_1.default.getStatusOptions() });
}
function getExpensePaymentMethodOptions(req, res) {
    res.json({ success: true, data: Expense_1.default.getPaymentMethodOptions() });
}
exports.default = {
    createExpense, getExpenses, getExpenseById, updateExpense,
    getExpensesByDateRange, getExpensesByCategory, getExpenseSummary,
    getExpenseCategories, createExpenseCategory, updateExpenseCategory, deleteExpenseCategory,
    getExpenseStatusOptions, getExpensePaymentMethodOptions,
};
//# sourceMappingURL=expenseController.js.map