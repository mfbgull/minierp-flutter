-- Salary Payments: add pay_period column + unique index
-- Prevents duplicate salary payments for the same employee in the same month.
-- NOTE: runLedgered records this in schema_migrations, so it only runs once.
-- For manual re-runs, ensure pay_period column doesn't already exist first.

-- Add pay_period column (YYYY-MM format)
ALTER TABLE salary_payments ADD COLUMN pay_period TEXT;

-- Backfill existing rows from payment_date
UPDATE salary_payments
SET pay_period = SUBSTR(payment_date, 1, 7)
WHERE pay_period IS NULL;

-- Unique index: one payment per employee per month
CREATE UNIQUE INDEX IF NOT EXISTS idx_salary_payments_unique_period
  ON salary_payments(employee_id, pay_period);
