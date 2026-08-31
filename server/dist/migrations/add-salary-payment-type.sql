-- Salary Payments: add payment_type column
-- Distinguishes full salary payments from advances and partial payments.
-- Idempotent: safe to re-run on every server start.

ALTER TABLE salary_payments ADD COLUMN payment_type TEXT DEFAULT 'full'
  CHECK (payment_type IN ('full', 'advance', 'partial'));
