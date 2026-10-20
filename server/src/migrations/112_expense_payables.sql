CREATE TEMP TABLE expense_payable_account_guard (valid INTEGER NOT NULL CHECK (valid = 1));
INSERT INTO expense_payable_account_guard (valid)
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE code = '2115' AND (
    type <> 'liability' OR normal_balance <> 'credit' OR text_code IS NOT 'expense_payables' OR is_active <> 1
  )
) OR EXISTS (
  SELECT 1 FROM chart_of_accounts WHERE text_code = 'expense_payables' AND code <> '2115'
) THEN 0 ELSE 1 END;
DROP TABLE expense_payable_account_guard;
INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code)
VALUES ('2115', 'Expense Payables', 'liability', 'credit', 'expense_payables');

CREATE TABLE expense_payments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expense_id INTEGER NOT NULL REFERENCES expenses(id),
    payment_date TEXT NOT NULL,
    amount REAL NOT NULL CHECK (amount > 0),
    payment_method TEXT NOT NULL,
    reference_no TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    voided_at TEXT,
    voided_by INTEGER REFERENCES users(id),
    void_reason TEXT
);
CREATE INDEX idx_expense_payments_expense ON expense_payments(expense_id);
CREATE INDEX idx_expense_payments_date ON expense_payments(payment_date);
