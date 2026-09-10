-- GL Void Attribution + Append-Only Ledgers Migration (gl-posting-completeness)
--
-- 1. journal_lines: void attribution metadata so voided lines remain
--    explainable against previously-filed trial balances.
-- 2. customer_ledger / supplier_ledger: append-only support columns
--    (voided + reversed_by) so corrections are reversing rows, not deletes.
--
-- Idempotent: safe to re-run on every server start.

-- ============================================================================
-- 1. journal_lines void attribution
-- ============================================================================
ALTER TABLE journal_lines ADD COLUMN voided_at TIMESTAMP;
ALTER TABLE journal_lines ADD COLUMN voided_by INTEGER REFERENCES users(id);
ALTER TABLE journal_lines ADD COLUMN void_reason TEXT;

-- ============================================================================
-- 2. Subledger append-only columns
-- ============================================================================
ALTER TABLE customer_ledger ADD COLUMN voided BOOLEAN DEFAULT 0;
ALTER TABLE customer_ledger ADD COLUMN reversed_by INTEGER REFERENCES customer_ledger(id);

ALTER TABLE supplier_ledger ADD COLUMN voided BOOLEAN DEFAULT 0;
ALTER TABLE supplier_ledger ADD COLUMN reversed_by INTEGER REFERENCES supplier_ledger(id);
