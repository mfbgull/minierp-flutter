-- C6 (reversal-rules): payments and salary_payments moved money (GL +
-- cash) so they can never be hard-deleted. Void with attribution instead.
-- Additive columns only; existing rows are unaffected (NULL = never voided).

ALTER TABLE payments ADD COLUMN voided_at TEXT;
ALTER TABLE payments ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE payments ADD COLUMN void_reason TEXT;

ALTER TABLE salary_payments ADD COLUMN voided_at TEXT;
ALTER TABLE salary_payments ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE salary_payments ADD COLUMN void_reason TEXT;

-- Allocation rows die with the payment reversal; keep them (no cascade
-- delete on void) and stamp them so allocation-reading reports can exclude
-- reversed rows by data rather than by inference.
ALTER TABLE payment_allocations ADD COLUMN voided_at TEXT;
ALTER TABLE purchase_allocations ADD COLUMN voided_at TEXT;
ALTER TABLE po_allocations ADD COLUMN voided_at TEXT;

