-- Salary Payments Migration
-- Tracks salary payments to employees with double-entry GL posting.
--
-- Idempotent: safe to re-run on every server start.

CREATE TABLE IF NOT EXISTS salary_payments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id     INTEGER NOT NULL REFERENCES employees(id),
    amount          DECIMAL(15,2) NOT NULL,
    payment_date    DATE NOT NULL,
    payment_method  TEXT DEFAULT 'bank',     -- 'cash' | 'bank'
    reference_no    TEXT,
    notes           TEXT,
    journal_entry_id INTEGER,                -- links to journal_lines grouping
    status          TEXT DEFAULT 'paid' CHECK (status IN ('paid','cancelled')),
    paid_by         INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_salary_payments_employee ON salary_payments(employee_id);
CREATE INDEX IF NOT EXISTS idx_salary_payments_date ON salary_payments(payment_date);
