"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmployeeLoanModel = void 0;
class EmployeeLoanModel {
    // ── Create ──────────────────────────────────────────────────
    static create(data, db) {
        const result = db.prepare(`
      INSERT INTO employee_loans (
        employee_id, amount, balance, purpose, payment_method,
        disbursement_date, due_date, monthly_installment, status,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
    `).run(data.employee_id, data.amount, data.amount, // balance starts = amount
        data.purpose || null, data.payment_method || 'cash', data.disbursement_date, data.due_date || null, data.monthly_installment || 0, data.created_by || null);
        return result.lastInsertRowid;
    }
    // ── Read ─────────────────────────────────────────────────────
    static getById(id, db) {
        return db.prepare('SELECT * FROM employee_loans WHERE id = ?').get(id);
    }
    static getByEmployee(employeeId, db) {
        return db.prepare('SELECT * FROM employee_loans WHERE employee_id = ? ORDER BY disbursement_date DESC').all(employeeId);
    }
    static getActiveByEmployee(employeeId, db) {
        return db.prepare(`SELECT * FROM employee_loans WHERE employee_id = ? AND status IN ('active', 'overdue')
       ORDER BY due_date ASC`).all(employeeId);
    }
    static getRepayments(loanId, db) {
        return db.prepare('SELECT * FROM employee_loan_repayments WHERE loan_id = ? ORDER BY payment_date ASC').all(loanId);
    }
    static getRepaymentById(repaymentId, db) {
        return db.prepare('SELECT * FROM employee_loan_repayments WHERE id = ?').get(repaymentId);
    }
    static getSummary(employeeId, db) {
        const row = db.prepare(`
      SELECT
        COUNT(*) as total_loans,
        SUM(CASE WHEN status IN ('active', 'overdue') THEN 1 ELSE 0 END) as active_loans,
        COALESCE(SUM(CASE WHEN status IN ('active', 'overdue') THEN balance ELSE 0 END), 0) as total_outstanding,
        COALESCE(SUM(CASE WHEN status IN ('active', 'overdue') THEN amount - balance ELSE 0 END), 0) as total_repaid,
        SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END) as overdue_loans
      FROM employee_loans WHERE employee_id = ?
    `).get(employeeId);
        return row;
    }
    static hasRepayments(loanId, db) {
        const row = db.prepare('SELECT COUNT(*) as cnt FROM employee_loan_repayments WHERE loan_id = ?').get(loanId);
        return row.cnt > 0;
    }
    // ── Update ───────────────────────────────────────────────────
    static updateJournalEntry(loanId, journalEntryId, db) {
        db.prepare('UPDATE employee_loans SET journal_entry_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
            .run(journalEntryId, loanId);
    }
    static deductBalance(loanId, amount, db) {
        db.prepare(`
      UPDATE employee_loans
      SET balance = balance - ?,
          status = CASE WHEN balance - ? <= 0 THEN 'completed' ELSE status END,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(amount, amount, loanId);
    }
    static setStatus(loanId, status, db) {
        db.prepare('UPDATE employee_loans SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
            .run(status, loanId);
    }
    // ── Repayment ────────────────────────────────────────────────
    static addRepayment(data, db) {
        const result = db.prepare(`
      INSERT INTO employee_loan_repayments (
        loan_id, employee_id, amount, payment_date, payment_method,
        reference_no, notes, repayment_type, journal_entry_id,
        salary_payment_id, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.loan_id, data.employee_id, data.amount, data.payment_date, data.payment_method || 'cash', data.reference_no || null, data.notes || null, data.repayment_type, data.journal_entry_id || null, data.salary_payment_id || null, data.created_by || null);
        return result.lastInsertRowid;
    }
    static updateRepaymentJournal(repaymentId, journalEntryId, db) {
        db.prepare('UPDATE employee_loan_repayments SET journal_entry_id = ? WHERE id = ?')
            .run(journalEntryId, repaymentId);
    }
    // ── Write-off ────────────────────────────────────────────────
    static writeOff(loanId, db) {
        db.prepare(`
      UPDATE employee_loans
      SET written_off_amount = balance,
          balance = 0,
          status = 'written_off',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(loanId);
    }
    // ── Void / Restore ───────────────────────────────────────────
    static restoreBalance(loanId, amount, db) {
        db.prepare(`
      UPDATE employee_loans
      SET balance = balance + ?,
          status = CASE WHEN status = 'completed' THEN 'active' ELSE status END,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(amount, loanId);
    }
    static restoreFromWriteOff(loanId, db) {
        db.prepare(`
      UPDATE employee_loans
      SET balance = written_off_amount,
          written_off_amount = 0,
          status = 'active',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(loanId);
    }
    static deleteRepayment(repaymentId, db) {
        db.prepare('DELETE FROM employee_loan_repayments WHERE id = ?').run(repaymentId);
    }
    static delete(loanId, db) {
        db.prepare('DELETE FROM employee_loans WHERE id = ?').run(loanId);
    }
    // ── Auto-update overdue status ───────────────────────────────
    static updateOverdueStatuses(db) {
        const result = db.prepare(`
      UPDATE employee_loans
      SET status = 'overdue', updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active' AND due_date < date('now') AND balance > 0
    `).run();
        return result.changes;
    }
    // ── Dashboard: global active loans ───────────────────────────
    static getGlobalActiveLoans(db) {
        // Auto-update overdue first
        EmployeeLoanModel.updateOverdueStatuses(db);
        return db.prepare(`
      SELECT
        el.id, el.employee_id, el.amount, el.balance, el.purpose,
        el.status, el.due_date, el.disbursement_date,
        e.employee_code,
        (e.first_name || ' ' || e.last_name) as employee_name,
        CAST(julianday(el.due_date) - julianday('now') AS INTEGER) as days_until_due
      FROM employee_loans el
      JOIN employees e ON e.id = el.employee_id
      WHERE el.status IN ('active', 'overdue')
      ORDER BY el.due_date ASC
    `).all();
    }
    static getGlobalLoanSummary(db) {
        return db.prepare(`
      SELECT
        COALESCE(SUM(balance), 0) as total_outstanding,
        COUNT(*) as total_loans,
        SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END) as overdue_count
      FROM employee_loans
      WHERE status IN ('active', 'overdue')
    `).get();
    }
}
exports.EmployeeLoanModel = EmployeeLoanModel;
exports.default = EmployeeLoanModel;
