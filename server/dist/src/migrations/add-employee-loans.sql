-- Employee Loans Migration
-- Tracks loans advanced to employees with GL posting and flexible repayment.
--
-- Idempotent: safe to re-run on every server start.

-- ── 1. New GL accounts ────────────────────────────────────────

-- Asset: money the company is owed by employees
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('1300', 'Employee Loan Receivable', 'asset', 'debit', 'employee_loan_receivable', 'Loans advanced to employees');

-- Expense: forgiven loan balances (write-offs)
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('6300', 'Loan Write-off', 'expense', 'debit', 'loan_write_off', 'Employee loans written off / forgiven');

-- ── 2. employee_loans table ───────────────────────────────────

CREATE TABLE IF NOT EXISTS employee_loans (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id     INTEGER NOT NULL REFERENCES employees(id),
    amount          REAL NOT NULL,                   -- total loan amount disbursed
    balance         REAL NOT NULL,                   -- remaining balance
    purpose         TEXT,                            -- e.g. "Medical", "Personal"
    payment_method  TEXT DEFAULT 'cash',             -- cash | bank
    disbursement_date TEXT NOT NULL,                 -- YYYY-MM-DD
    due_date        TEXT,                            -- YYYY-MM-DD
    monthly_installment REAL DEFAULT 0,              -- suggested monthly amount
    status          TEXT NOT NULL DEFAULT 'active'   -- active | completed | overdue | written_off
        CHECK (status IN ('active', 'completed', 'overdue', 'written_off')),
    written_off_amount REAL DEFAULT 0,              -- amount forgiven
    notes           TEXT,
    journal_entry_id INTEGER,                        -- GL journal entry for disbursement
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_employee_loans_employee ON employee_loans(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_loans_status ON employee_loans(status);

-- ── 3. employee_loan_repayments table ─────────────────────────

CREATE TABLE IF NOT EXISTS employee_loan_repayments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id         INTEGER NOT NULL REFERENCES employee_loans(id),
    employee_id     INTEGER NOT NULL REFERENCES employees(id),
    amount          REAL NOT NULL,                   -- repayment amount
    payment_date    TEXT NOT NULL,                   -- YYYY-MM-DD
    payment_method  TEXT DEFAULT 'cash',             -- cash | bank
    reference_no    TEXT,
    notes           TEXT,
    repayment_type  TEXT NOT NULL DEFAULT 'direct'   -- direct | salary_deduction
        CHECK (repayment_type IN ('direct', 'salary_deduction')),
    journal_entry_id INTEGER,                        -- GL journal entry (direct only)
    salary_payment_id INTEGER,                       -- linked salary payment (salary_deduction only)
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_loan_repayments_loan ON employee_loan_repayments(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_repayments_employee ON employee_loan_repayments(employee_id);
