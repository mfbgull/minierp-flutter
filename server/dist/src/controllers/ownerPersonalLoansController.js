"use strict";
// Owner Personal Loans Controller — purely record-keeping, no GL impact.
// Manages personal loans the owner gives to friends, family, customers, suppliers.
// No journal entries, no chart_of_accounts modifications, no accounting flow.
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const sequence_1 = require("../utils/sequence");
// ── Helpers ──────────────────────────────────────────────────
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
function fail(res, error, fallback) {
    const message = error instanceof Error ? error.message : String(error);
    const clientErrors = [
        'not found', 'Not found', 'must be', 'required',
        'Cannot delete', 'Cannot deactivate', 'Cannot merge',
        'exceeds', 'duplicate', 'already exists', 'Invalid',
    ];
    if (clientErrors.some((m) => message.toLowerCase().includes(m.toLowerCase()))) {
        res.status(400).json({ success: false, error: message });
        return;
    }
    logger_1.default.error(`${fallback}:`, error);
    res.status(500).json({ success: false, error: fallback });
}
// ── Loans CRUD ───────────────────────────────────────────────
function listLoans(req, res) {
    try {
        const page = parseInt((0, queryUtils_1.getQueryParam)(req.query.page)) || 1;
        const limit = parseInt((0, queryUtils_1.getQueryParam)(req.query.limit)) || 10;
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const status = (0, queryUtils_1.getQueryParam)(req.query.status);
        const from_date = (0, queryUtils_1.getQueryParam)(req.query.from_date);
        const to_date = (0, queryUtils_1.getQueryParam)(req.query.to_date);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy) || 'loan_date';
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder) || 'DESC';
        const allowedSorts = {
            loan_date: 'opl.loan_date',
            amount: 'opl.amount',
            balance: 'opl.balance',
            status: 'opl.status',
            loan_no: 'opl.loan_no',
            borrower_name: 'opl.borrower_name',
            created_at: 'opl.created_at',
        };
        const sortCol = allowedSorts[sortBy] || 'opl.loan_date';
        const sortDir = sortOrder.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';
        let where = 'WHERE 1=1';
        const params = [];
        if (search) {
            where += ' AND (opl.borrower_name LIKE ? OR opl.loan_no LIKE ? OR opl.purpose LIKE ?)';
            const term = `%${search}%`;
            params.push(term, term, term);
        }
        if (status) {
            where += ' AND opl.status = ?';
            params.push(status);
        }
        if (from_date) {
            where += ' AND opl.loan_date >= ?';
            params.push(from_date);
        }
        if (to_date) {
            where += ' AND opl.loan_date <= ?';
            params.push(to_date);
        }
        // Count
        const countRow = database_1.default.prepare(`SELECT COUNT(*) as cnt FROM owner_personal_loans opl ${where}`).get(...params);
        const totalItems = countRow.cnt;
        const totalPages = Math.ceil(totalItems / limit);
        const offset = (page - 1) * limit;
        // Data
        const rows = database_1.default.prepare(`
      SELECT
        opl.*,
        COALESCE(r.repaid_amount, 0) as repaid_amount,
        COALESCE(r.repayment_count, 0) as repayment_count,
        u.full_name as created_by_name
      FROM owner_personal_loans opl
      LEFT JOIN (
        SELECT loan_id, SUM(amount) as repaid_amount, COUNT(*) as repayment_count
        FROM owner_personal_loan_repayments
        GROUP BY loan_id
      ) r ON r.loan_id = opl.id
      LEFT JOIN users u ON u.id = opl.created_by
      ${where}
      ORDER BY ${sortCol} ${sortDir}
      LIMIT ? OFFSET ?
    `).all(...params, limit, offset);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: page,
                totalPages,
                totalItems,
                hasNext: page < totalPages,
                hasPrev: page > 1,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch personal loans');
    }
}
function createLoan(req, res) {
    try {
        const userId = req.user.id;
        const { borrower_name, borrower_id, borrower_type, amount, currency, loan_date, due_date, purpose, notes } = req.body;
        // Validate
        if (!borrower_name || typeof borrower_name !== 'string' || borrower_name.trim().length === 0) {
            res.status(400).json({ success: false, error: 'borrower_name is required' });
            return;
        }
        const parsedAmount = Number(amount);
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
            res.status(400).json({ success: false, error: 'Amount must be a positive number' });
            return;
        }
        if (!loan_date || !DATE_RE.test(String(loan_date))) {
            res.status(400).json({ success: false, error: 'A valid loan_date (YYYY-MM-DD) is required' });
            return;
        }
        if (due_date && !DATE_RE.test(String(due_date))) {
            res.status(400).json({ success: false, error: 'due_date must be YYYY-MM-DD' });
            return;
        }
        let loanId;
        let loanNo;
        database_1.default.transaction(() => {
            loanNo = (0, sequence_1.generateDocNo)(database_1.default, 'PL');
            // Auto-create borrower if not provided
            let finalBorrowerId = borrower_id || null;
            const finalBorrowerType = borrower_type || null;
            if (!finalBorrowerId && borrower_name.trim()) {
                const existing = database_1.default.prepare(`SELECT id FROM owner_personal_loan_borrowers WHERE name = ? AND linked_type IS NULL AND linked_id IS NULL`).get(borrower_name.trim());
                if (existing) {
                    finalBorrowerId = existing.id;
                }
                else {
                    const r = database_1.default.prepare(`INSERT INTO owner_personal_loan_borrowers (name, linked_type, linked_id) VALUES (?, NULL, NULL)`).run(borrower_name.trim());
                    finalBorrowerId = r.lastInsertRowid;
                }
            }
            const result = database_1.default.prepare(`
        INSERT INTO owner_personal_loans
          (loan_no, borrower_name, borrower_id, borrower_type, amount, balance, currency, loan_date, due_date, purpose, status, notes, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
      `).run(loanNo, borrower_name.trim(), finalBorrowerId, finalBorrowerType, parsedAmount, parsedAmount, // balance starts = amount
            currency || 'PKR', loan_date, due_date || null, purpose || null, notes || null, userId);
            loanId = result.lastInsertRowid;
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoan', loanId, `Created personal loan ${loanNo} (${parsedAmount})`, userId, {
            loan_no: loanNo, amount: parsedAmount, borrower_name: borrower_name.trim(),
        });
        req.activityLogged = true;
        res.status(201).json({
            success: true,
            data: {
                id: loanId,
                loan_no: loanNo,
                borrower_name: borrower_name.trim(),
                amount: parsedAmount,
                balance: parsedAmount,
                currency: currency || 'PKR',
                status: 'pending',
                loan_date,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to create personal loan');
    }
}
function getLoanDetail(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const loan = database_1.default.prepare(`
      SELECT
        opl.*,
        COALESCE(r.repaid_amount, 0) as repaid_amount,
        COALESCE(r.repayment_count, 0) as repayment_count,
        u.full_name as created_by_name
      FROM owner_personal_loans opl
      LEFT JOIN (
        SELECT loan_id, SUM(amount) as repaid_amount, COUNT(*) as repayment_count
        FROM owner_personal_loan_repayments
        GROUP BY loan_id
      ) r ON r.loan_id = opl.id
      LEFT JOIN users u ON u.id = opl.created_by
      WHERE opl.id = ?
    `).get(id);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Personal loan not found' });
            return;
        }
        const repayments = database_1.default.prepare(`
      SELECT opr.*, u.full_name as created_by_name
      FROM owner_personal_loan_repayments opr
      LEFT JOIN users u ON u.id = opr.created_by
      WHERE opr.loan_id = ?
      ORDER BY opr.payment_date ASC
    `).all(id);
        res.json({
            success: true,
            data: { ...loan, repayments },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch personal loan detail');
    }
}
function updateLoan(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const { borrower_name, amount, due_date, purpose, notes, status, balance } = req.body;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loans WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Personal loan not found' });
            return;
        }
        // Validate amount if changing
        if (amount !== undefined) {
            const parsedAmount = Number(amount);
            if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
                res.status(400).json({ success: false, error: 'Amount must be a positive number' });
                return;
            }
            const repaid = existing.amount - existing.balance;
            if (parsedAmount < repaid) {
                res.status(400).json({ success: false, error: 'Amount cannot be less than repaid amount' });
                return;
            }
        }
        // Validate status if changing
        if (status !== undefined) {
            const allowedStatuses = ['pending', 'partial', 'settled', 'written_off'];
            if (!allowedStatuses.includes(status)) {
                res.status(400).json({ success: false, error: `Invalid status. Must be one of: ${allowedStatuses.join(', ')}` });
                return;
            }
        }
        database_1.default.transaction(() => {
            const updates = [];
            const values = [];
            if (borrower_name !== undefined) {
                updates.push('borrower_name = ?');
                values.push(borrower_name.trim());
            }
            if (amount !== undefined) {
                updates.push('amount = ?');
                values.push(Number(amount));
            }
            if (due_date !== undefined) {
                updates.push('due_date = ?');
                values.push(due_date || null);
            }
            if (purpose !== undefined) {
                updates.push('purpose = ?');
                values.push(purpose || null);
            }
            if (notes !== undefined) {
                updates.push('notes = ?');
                values.push(notes || null);
            }
            if (status !== undefined) {
                updates.push('status = ?');
                values.push(status);
            }
            if (balance !== undefined) {
                updates.push('balance = ?');
                values.push(Number(balance));
            }
            if (updates.length > 0) {
                updates.push('updated_at = CURRENT_TIMESTAMP');
                values.push(id);
                database_1.default.prepare(`UPDATE owner_personal_loans SET ${updates.join(', ')} WHERE id = ?`).run(...values);
            }
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoan', id, `Updated personal loan ${existing.loan_no}`, userId);
        req.activityLogged = true;
        const updated = database_1.default.prepare('SELECT * FROM owner_personal_loans WHERE id = ?').get(id);
        res.json({ success: true, data: updated });
    }
    catch (error) {
        fail(res, error, 'Failed to update personal loan');
    }
}
function deleteLoan(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loans WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Personal loan not found' });
            return;
        }
        // Check for repayments
        const repCount = database_1.default.prepare('SELECT COUNT(*) as cnt FROM owner_personal_loan_repayments WHERE loan_id = ?').get(id);
        if (repCount.cnt > 0) {
            res.status(400).json({ success: false, error: 'Cannot delete loan with repayment history' });
            return;
        }
        database_1.default.prepare('DELETE FROM owner_personal_loans WHERE id = ?').run(id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoan', id, `Deleted personal loan ${existing.loan_no}`, userId);
        req.activityLogged = true;
        res.json({ success: true, message: 'Loan deleted successfully' });
    }
    catch (error) {
        fail(res, error, 'Failed to delete personal loan');
    }
}
// ── Repayments ───────────────────────────────────────────────
function addRepayment(req, res) {
    try {
        const loanId = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const { amount, payment_date, notes } = req.body;
        const loan = database_1.default.prepare('SELECT * FROM owner_personal_loans WHERE id = ?').get(loanId);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Personal loan not found' });
            return;
        }
        if (loan.status === 'settled' || loan.status === 'written_off') {
            res.status(400).json({ success: false, error: 'Cannot record repayment on settled or written-off loan' });
            return;
        }
        const parsedAmount = Number(amount);
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
            res.status(400).json({ success: false, error: 'Amount must be a positive number' });
            return;
        }
        if (parsedAmount > loan.balance) {
            res.status(400).json({ success: false, error: 'Repayment exceeds loan balance' });
            return;
        }
        if (!payment_date || !DATE_RE.test(String(payment_date))) {
            res.status(400).json({ success: false, error: 'A valid payment_date (YYYY-MM-DD) is required' });
            return;
        }
        let repaymentId;
        let newBalance;
        let newStatus;
        database_1.default.transaction(() => {
            // Insert repayment
            const result = database_1.default.prepare(`
        INSERT INTO owner_personal_loan_repayments (loan_id, amount, payment_date, notes, created_by)
        VALUES (?, ?, ?, ?, ?)
      `).run(loanId, parsedAmount, payment_date, notes || null, userId);
            repaymentId = result.lastInsertRowid;
            // Update loan balance
            newBalance = loan.balance - parsedAmount;
            // Auto-compute status
            if (newBalance <= 0) {
                newStatus = 'settled';
                newBalance = 0;
            }
            else if (parsedAmount > 0) {
                newStatus = 'partial';
            }
            else {
                newStatus = loan.status;
            }
            database_1.default.prepare(`
        UPDATE owner_personal_loans SET balance = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
      `).run(newBalance, newStatus, loanId);
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoan', loanId, `Recorded repayment of ${parsedAmount} on loan ${loan.loan_no}`, userId);
        req.activityLogged = true;
        res.status(201).json({
            success: true,
            data: {
                id: repaymentId,
                amount: parsedAmount,
                loan_balance: newBalance,
                loan_status: newStatus,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to record repayment');
    }
}
function deleteRepayment(req, res) {
    try {
        const loanId = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const repId = parseInt((0, queryUtils_1.getRouteParam)(req.params.repId), 10);
        const userId = req.user.id;
        const repayment = database_1.default.prepare('SELECT * FROM owner_personal_loan_repayments WHERE id = ? AND loan_id = ?').get(repId, loanId);
        if (!repayment) {
            res.status(404).json({ success: false, error: 'Repayment not found' });
            return;
        }
        const loan = database_1.default.prepare('SELECT * FROM owner_personal_loans WHERE id = ?').get(loanId);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Personal loan not found' });
            return;
        }
        let newBalance;
        let newStatus;
        database_1.default.transaction(() => {
            // Delete repayment
            database_1.default.prepare('DELETE FROM owner_personal_loan_repayments WHERE id = ?').run(repId);
            // Restore balance
            newBalance = loan.balance + repayment.amount;
            // Recompute status
            const totalRepaid = loan.amount - newBalance;
            if (newBalance >= loan.amount) {
                newStatus = 'pending';
            }
            else if (newBalance <= 0) {
                newStatus = 'settled';
                newBalance = 0;
            }
            else {
                newStatus = 'partial';
            }
            database_1.default.prepare(`
        UPDATE owner_personal_loans SET balance = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
      `).run(newBalance, newStatus, loanId);
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoan', loanId, `Deleted repayment ${repId} from loan ${loan.loan_no}`, userId);
        req.activityLogged = true;
        res.json({
            success: true,
            data: {
                loan_balance: newBalance,
                loan_status: newStatus,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to delete repayment');
    }
}
// ── Summary ──────────────────────────────────────────────────
function summary(_req, res) {
    try {
        const row = database_1.default.prepare(`
      SELECT
        COALESCE(SUM(amount), 0) as total_lent,
        COALESCE(SUM(amount - balance), 0) as total_repaid,
        COALESCE(SUM(balance), 0) as total_pending,
        SUM(CASE WHEN status IN ('pending', 'partial') THEN 1 ELSE 0 END) as active_count,
        SUM(CASE WHEN status = 'settled' THEN 1 ELSE 0 END) as settled_count,
        SUM(CASE WHEN status = 'written_off' THEN 1 ELSE 0 END) as written_off_count
      FROM owner_personal_loans
    `).get();
        const currencyBreakdown = database_1.default.prepare(`
      SELECT
        currency,
        SUM(amount) as total_lent,
        SUM(balance) as total_pending
      FROM owner_personal_loans
      WHERE status IN ('pending', 'partial')
      GROUP BY currency
    `).all();
        res.json({
            success: true,
            data: {
                total_lent: row.total_lent,
                total_repaid: row.total_repaid,
                total_pending: row.total_pending,
                active_count: row.active_count || 0,
                settled_count: row.settled_count || 0,
                written_off_count: row.written_off_count || 0,
                currency_breakdown: currencyBreakdown,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch personal loan summary');
    }
}
// ── Borrowers ────────────────────────────────────────────────
function listBorrowers(req, res) {
    try {
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const status = (0, queryUtils_1.getQueryParam)(req.query.status);
        let where = 'WHERE 1=1';
        const params = [];
        if (search) {
            where += ' AND opb.name LIKE ?';
            params.push(`%${search}%`);
        }
        if (status === 'active') {
            where += ' AND opb.is_active = 1';
        }
        else if (status === 'inactive') {
            where += ' AND opb.is_active = 0';
        }
        else {
            // Default: only active
            where += ' AND opb.is_active = 1';
        }
        const rows = database_1.default.prepare(`
      SELECT
        opb.*,
        COALESCE(l.loan_count, 0) as loan_count,
        COALESCE(l.total_lent, 0) as total_lent,
        COALESCE(l.total_pending, 0) as total_pending
      FROM owner_personal_loan_borrowers opb
      LEFT JOIN (
        SELECT
          borrower_id,
          COUNT(*) as loan_count,
          SUM(amount) as total_lent,
          SUM(balance) as total_pending
        FROM owner_personal_loans
        GROUP BY borrower_id
      ) l ON l.borrower_id = opb.id
      ${where}
      ORDER BY opb.name ASC
    `).all(...params);
        res.json({ success: true, data: rows });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch borrowers');
    }
}
function createBorrower(req, res) {
    try {
        const userId = req.user.id;
        const { name, phone, linked_type, linked_id } = req.body;
        if (!name || typeof name !== 'string' || name.trim().length === 0) {
            res.status(400).json({ success: false, error: 'Borrower name is required' });
            return;
        }
        // Upsert: check if borrower already exists
        const existing = database_1.default.prepare(`SELECT id FROM owner_personal_loan_borrowers WHERE name = ? AND linked_type IS ? AND linked_id IS ?`).get(name.trim(), linked_type || null, linked_id || null);
        if (existing) {
            const borrower = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(existing.id);
            res.json({ success: true, data: borrower });
            return;
        }
        const result = database_1.default.prepare(`
      INSERT INTO owner_personal_loan_borrowers (name, phone, linked_type, linked_id)
      VALUES (?, ?, ?, ?)
    `).run(name.trim(), phone || null, linked_type || null, linked_id || null);
        const borrower = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(result.lastInsertRowid);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', result.lastInsertRowid, `Created borrower: ${name.trim()}`, userId);
        req.activityLogged = true;
        res.status(201).json({ success: true, data: borrower });
    }
    catch (error) {
        fail(res, error, 'Failed to create borrower');
    }
}
function updateBorrower(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const { name, phone, linked_type, linked_id } = req.body;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Borrower not found' });
            return;
        }
        if (name !== undefined && (!name || name.trim().length === 0)) {
            res.status(400).json({ success: false, error: 'Borrower name cannot be empty' });
            return;
        }
        // Check for duplicate
        const checkName = name !== undefined ? name.trim() : existing.name;
        const checkType = linked_type !== undefined ? linked_type : existing.linked_type;
        const checkId = linked_id !== undefined ? linked_id : existing.linked_id;
        const dup = database_1.default.prepare(`SELECT id FROM owner_personal_loan_borrowers WHERE name = ? AND linked_type IS ? AND linked_id IS ? AND id != ?`).get(checkName, checkType || null, checkId || null, id);
        if (dup) {
            res.status(400).json({ success: false, error: 'A borrower with this name and link already exists' });
            return;
        }
        const updates = [];
        const values = [];
        if (name !== undefined) {
            updates.push('name = ?');
            values.push(name.trim());
        }
        if (phone !== undefined) {
            updates.push('phone = ?');
            values.push(phone || null);
        }
        if (linked_type !== undefined) {
            updates.push('linked_type = ?');
            values.push(linked_type || null);
        }
        if (linked_id !== undefined) {
            updates.push('linked_id = ?');
            values.push(linked_id || null);
        }
        if (updates.length > 0) {
            values.push(id);
            database_1.default.prepare(`UPDATE owner_personal_loan_borrowers SET ${updates.join(', ')} WHERE id = ?`).run(...values);
        }
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', id, `Updated borrower: ${checkName}`, userId);
        req.activityLogged = true;
        const updated = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        res.json({ success: true, data: updated });
    }
    catch (error) {
        fail(res, error, 'Failed to update borrower');
    }
}
function deactivateBorrower(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Borrower not found' });
            return;
        }
        if (!existing.is_active) {
            res.status(400).json({ success: false, error: 'Borrower is already deactivated' });
            return;
        }
        // Check for loans
        const loanCount = database_1.default.prepare('SELECT COUNT(*) as cnt FROM owner_personal_loans WHERE borrower_id = ?').get(id);
        if (loanCount.cnt > 0) {
            res.status(400).json({ success: false, error: 'Cannot deactivate borrower with existing loans. Close or transfer loans first.' });
            return;
        }
        database_1.default.prepare('UPDATE owner_personal_loan_borrowers SET is_active = 0 WHERE id = ?').run(id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', id, `Deactivated borrower: ${existing.name}`, userId);
        req.activityLogged = true;
        res.json({ success: true, message: 'Borrower deactivated' });
    }
    catch (error) {
        fail(res, error, 'Failed to deactivate borrower');
    }
}
function reactivateBorrower(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Borrower not found' });
            return;
        }
        database_1.default.prepare('UPDATE owner_personal_loan_borrowers SET is_active = 1 WHERE id = ?').run(id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', id, `Reactivated borrower: ${existing.name}`, userId);
        req.activityLogged = true;
        const updated = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        res.json({ success: true, data: updated });
    }
    catch (error) {
        fail(res, error, 'Failed to reactivate borrower');
    }
}
function unlinkBorrower(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const existing = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Borrower not found' });
            return;
        }
        if (!existing.linked_type) {
            res.status(400).json({ success: false, error: 'Borrower is not linked to any customer or supplier' });
            return;
        }
        database_1.default.prepare('UPDATE owner_personal_loan_borrowers SET linked_type = NULL, linked_id = NULL WHERE id = ?').run(id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', id, `Unlinked borrower: ${existing.name}`, userId);
        req.activityLogged = true;
        const updated = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(id);
        res.json({ success: true, data: updated });
    }
    catch (error) {
        fail(res, error, 'Failed to unlink borrower');
    }
}
function mergeBorrowers(req, res) {
    try {
        const sourceId = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const { target_borrower_id } = req.body;
        if (!target_borrower_id) {
            res.status(400).json({ success: false, error: 'target_borrower_id is required' });
            return;
        }
        const source = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(sourceId);
        if (!source) {
            res.status(404).json({ success: false, error: 'Source borrower not found' });
            return;
        }
        const target = database_1.default.prepare('SELECT * FROM owner_personal_loan_borrowers WHERE id = ?').get(target_borrower_id);
        if (!target) {
            res.status(404).json({ success: false, error: 'Target borrower not found' });
            return;
        }
        if (!target.is_active) {
            res.status(400).json({ success: false, error: 'Target borrower must be active' });
            return;
        }
        if (sourceId === target_borrower_id) {
            res.status(400).json({ success: false, error: 'Cannot merge a borrower into itself' });
            return;
        }
        let mergedLoans;
        database_1.default.transaction(() => {
            // Reassign loans
            const result = database_1.default.prepare(`
        UPDATE owner_personal_loans
        SET borrower_id = ?, borrower_name = ?, borrower_type = ?, updated_at = CURRENT_TIMESTAMP
        WHERE borrower_id = ?
      `).run(target.id, target.name, target.linked_type, sourceId);
            mergedLoans = result.changes;
            // Deactivate source
            database_1.default.prepare('UPDATE owner_personal_loan_borrowers SET is_active = 0 WHERE id = ?').run(sourceId);
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'PersonalLoanBorrower', sourceId, `Merged borrower ${source.name} into ${target.name} (${mergedLoans} loans)`, userId);
        req.activityLogged = true;
        res.json({
            success: true,
            data: {
                merged_loans: mergedLoans,
                source_deactivated: true,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to merge borrowers');
    }
}
// ── Export ───────────────────────────────────────────────────
exports.default = {
    listLoans,
    createLoan,
    getLoanDetail,
    updateLoan,
    deleteLoan,
    addRepayment,
    deleteRepayment,
    summary,
    listBorrowers,
    createBorrower,
    updateBorrower,
    deactivateBorrower,
    reactivateBorrower,
    unlinkBorrower,
    mergeBorrowers,
};
