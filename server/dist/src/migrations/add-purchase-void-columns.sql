-- Migration: purchase void lifecycle (financial-audit-p0-remediation task 3.1 / PUR-03)
-- Purchases are voided with attribution instead of hard-deleted. Additive
-- columns only; existing rows are unaffected (all NULL = never voided).

ALTER TABLE purchases ADD COLUMN voided_at TEXT;
ALTER TABLE purchases ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE purchases ADD COLUMN void_reason TEXT;
