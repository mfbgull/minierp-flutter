-- C5 (reversal-rules): employee loans and repayments post GL and move
-- cash, so they are voided (with attribution), never hard-deleted.
-- Additive columns only; NULL = never voided.

ALTER TABLE employee_loans ADD COLUMN voided_at TEXT;
ALTER TABLE employee_loans ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE employee_loans ADD COLUMN void_reason TEXT;

ALTER TABLE employee_loan_repayments ADD COLUMN voided_at TEXT;
ALTER TABLE employee_loan_repayments ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE employee_loan_repayments ADD COLUMN void_reason TEXT;
