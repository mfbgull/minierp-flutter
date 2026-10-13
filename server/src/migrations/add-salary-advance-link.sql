ALTER TABLE salary_payments ADD COLUMN parent_payment_id INTEGER REFERENCES salary_payments(id);
CREATE INDEX idx_salary_payments_parent ON salary_payments(parent_payment_id);

INSERT INTO chart_of_accounts (code, name, type, normal_balance, text_code, description)
VALUES ('1310', 'Employee Salary Advances', 'asset', 'debit', 'employee_salary_advances', 'Unearned salary advances receivable');
