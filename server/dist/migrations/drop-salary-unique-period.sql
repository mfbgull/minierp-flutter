-- Salary Payments: drop UNIQUE constraint on (employee_id, pay_period)
-- The old constraint allowed only ONE payment row per employee per month.
-- With the advance/partial payment system, we need multiple rows per month.
-- Each partial/advance payment is its own row; the duplicate guard for
-- 'full' payments is enforced at the application level (controller).

DROP INDEX IF EXISTS idx_salary_payments_unique_period;
