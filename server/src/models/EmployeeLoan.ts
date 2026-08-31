import Database from 'better-sqlite3';

export interface EmployeeLoan {
  id: number;
  employee_id: number;
  amount: number;
  balance: number;
  purpose: string | null;
  payment_method: string;
  disbursement_date: string;
  due_date: string | null;
  monthly_installment: number;
  status: 'active' | 'completed' | 'overdue' | 'written_off';
  written_off_amount: number;
  notes: string | null;
  journal_entry_id: number | null;
  created_by: number | null;
  created_at: string;
  updated_at: string;
}

export interface CreateLoanDTO {
  employee_id: number;
  amount: number;
  disbursement_date: string;
  due_date?: string;
  purpose?: string;
  payment_method?: string;
  monthly_installment?: number;
  notes?: string;
  created_by?: number;
}

export interface LoanRepayment {
  id: number;
  loan_id: number;
  employee_id: number;
  amount: number;
  payment_date: string;
  payment_method: string;
  reference_no: string | null;
  notes: string | null;
  repayment_type: 'direct' | 'salary_deduction';
  journal_entry_id: number | null;
  salary_payment_id: number | null;
  created_by: number | null;
  created_at: string;
}

export interface RepayLoanDTO {
  amount: number;
  payment_date: string;
  payment_method?: string;
  reference_no?: string;
  notes?: string;
  salary_payment_id?: number;
  created_by?: number;
}

export interface LoanSummary {
  total_loans: number;
  active_loans: number;
  total_outstanding: number;
  total_repaid: number;
  overdue_loans: number;
}

export class EmployeeLoanModel {

  // ── Create ──────────────────────────────────────────────────

  static create(data: CreateLoanDTO, db: Database.Database): number {
    const result = db.prepare(`
      INSERT INTO employee_loans (
        employee_id, amount, balance, purpose, payment_method,
        disbursement_date, due_date, monthly_installment, status,
        created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
    `).run(
      data.employee_id,
      data.amount,
      data.amount,  // balance starts = amount
      data.purpose || null,
      data.payment_method || 'cash',
      data.disbursement_date,
      data.due_date || null,
      data.monthly_installment || 0,
      data.created_by || null,
    );
    return result.lastInsertRowid as number;
  }

  // ── Read ─────────────────────────────────────────────────────

  static getById(id: number, db: Database.Database): EmployeeLoan | undefined {
    return db.prepare('SELECT * FROM employee_loans WHERE id = ?').get(id) as EmployeeLoan | undefined;
  }

  static getByEmployee(employeeId: number, db: Database.Database): EmployeeLoan[] {
    return db.prepare(
      'SELECT * FROM employee_loans WHERE employee_id = ? ORDER BY disbursement_date DESC'
    ).all(employeeId) as EmployeeLoan[];
  }

  static getActiveByEmployee(employeeId: number, db: Database.Database): EmployeeLoan[] {
    return db.prepare(
      `SELECT * FROM employee_loans WHERE employee_id = ? AND status IN ('active', 'overdue')
       ORDER BY due_date ASC`
    ).all(employeeId) as EmployeeLoan[];
  }

  static getRepayments(loanId: number, db: Database.Database): LoanRepayment[] {
    return db.prepare(
      'SELECT * FROM employee_loan_repayments WHERE loan_id = ? ORDER BY payment_date ASC'
    ).all(loanId) as LoanRepayment[];
  }

  static getRepaymentById(repaymentId: number, db: Database.Database): LoanRepayment | undefined {
    return db.prepare('SELECT * FROM employee_loan_repayments WHERE id = ?').get(repaymentId) as LoanRepayment | undefined;
  }

  static getSummary(employeeId: number, db: Database.Database): LoanSummary {
    const row = db.prepare(`
      SELECT
        COUNT(*) as total_loans,
        SUM(CASE WHEN status IN ('active', 'overdue') THEN 1 ELSE 0 END) as active_loans,
        COALESCE(SUM(CASE WHEN status IN ('active', 'overdue') THEN balance ELSE 0 END), 0) as total_outstanding,
        COALESCE(SUM(CASE WHEN status IN ('active', 'overdue') THEN amount - balance ELSE 0 END), 0) as total_repaid,
        SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END) as overdue_loans
      FROM employee_loans WHERE employee_id = ?
    `).get(employeeId) as LoanSummary;
    return row;
  }

  static hasRepayments(loanId: number, db: Database.Database): boolean {
    const row = db.prepare('SELECT COUNT(*) as cnt FROM employee_loan_repayments WHERE loan_id = ?').get(loanId) as { cnt: number };
    return row.cnt > 0;
  }

  // ── Update ───────────────────────────────────────────────────

  static updateJournalEntry(loanId: number, journalEntryId: number, db: Database.Database): void {
    db.prepare('UPDATE employee_loans SET journal_entry_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
      .run(journalEntryId, loanId);
  }

  static deductBalance(loanId: number, amount: number, db: Database.Database): void {
    db.prepare(`
      UPDATE employee_loans
      SET balance = balance - ?,
          status = CASE WHEN balance - ? <= 0 THEN 'completed' ELSE status END,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(amount, amount, loanId);
  }

  static setStatus(loanId: number, status: string, db: Database.Database): void {
    db.prepare('UPDATE employee_loans SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
      .run(status, loanId);
  }

  // ── Repayment ────────────────────────────────────────────────

  static addRepayment(data: {
    loan_id: number;
    employee_id: number;
    amount: number;
    payment_date: string;
    payment_method?: string;
    reference_no?: string;
    notes?: string;
    repayment_type: string;
    journal_entry_id?: number;
    salary_payment_id?: number;
    created_by?: number;
  }, db: Database.Database): number {
    const result = db.prepare(`
      INSERT INTO employee_loan_repayments (
        loan_id, employee_id, amount, payment_date, payment_method,
        reference_no, notes, repayment_type, journal_entry_id,
        salary_payment_id, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.loan_id,
      data.employee_id,
      data.amount,
      data.payment_date,
      data.payment_method || 'cash',
      data.reference_no || null,
      data.notes || null,
      data.repayment_type,
      data.journal_entry_id || null,
      data.salary_payment_id || null,
      data.created_by || null,
    );
    return result.lastInsertRowid as number;
  }

  static updateRepaymentJournal(repaymentId: number, journalEntryId: number, db: Database.Database): void {
    db.prepare('UPDATE employee_loan_repayments SET journal_entry_id = ? WHERE id = ?')
      .run(journalEntryId, repaymentId);
  }

  // ── Write-off ────────────────────────────────────────────────

  static writeOff(loanId: number, db: Database.Database): void {
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

  static restoreBalance(loanId: number, amount: number, db: Database.Database): void {
    db.prepare(`
      UPDATE employee_loans
      SET balance = balance + ?,
          status = CASE WHEN status = 'completed' THEN 'active' ELSE status END,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(amount, loanId);
  }

  static restoreFromWriteOff(loanId: number, db: Database.Database): void {
    db.prepare(`
      UPDATE employee_loans
      SET balance = written_off_amount,
          written_off_amount = 0,
          status = 'active',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(loanId);
  }

  static deleteRepayment(repaymentId: number, db: Database.Database): void {
    db.prepare('DELETE FROM employee_loan_repayments WHERE id = ?').run(repaymentId);
  }

  static delete(loanId: number, db: Database.Database): void {
    db.prepare('DELETE FROM employee_loans WHERE id = ?').run(loanId);
  }

  // ── Auto-update overdue status ───────────────────────────────

  static updateOverdueStatuses(db: Database.Database): number {
    const result = db.prepare(`
      UPDATE employee_loans
      SET status = 'overdue', updated_at = CURRENT_TIMESTAMP
      WHERE status = 'active' AND due_date < date('now') AND balance > 0
    `).run();
    return result.changes;
  }

  // ── Dashboard: global active loans ───────────────────────────

  static getGlobalActiveLoans(db: Database.Database): Array<{
    id: number; employee_id: number; employee_code: string;
    employee_name: string; amount: number; balance: number;
    purpose: string | null; status: string; due_date: string | null;
    disbursement_date: string; days_until_due: number;
  }> {
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
    `).all() as any[];
  }

  static getGlobalLoanSummary(db: Database.Database): {
    total_outstanding: number; total_loans: number; overdue_count: number;
  } {
    return db.prepare(`
      SELECT
        COALESCE(SUM(balance), 0) as total_outstanding,
        COUNT(*) as total_loans,
        SUM(CASE WHEN status = 'overdue' THEN 1 ELSE 0 END) as overdue_count
      FROM employee_loans
      WHERE status IN ('active', 'overdue')
    `).get() as any;
  }
}

export default EmployeeLoanModel;
