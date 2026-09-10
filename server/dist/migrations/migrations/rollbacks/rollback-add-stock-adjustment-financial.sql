-- Rollback: Stock adjustment financial
-- Reverts: add-stock-adjustment-financial.sql

DROP INDEX IF EXISTS idx_journal_entries_accounts;
DROP INDEX IF EXISTS idx_journal_entries_date;
DROP INDEX IF EXISTS idx_journal_entries_reference;
DROP TABLE IF EXISTS journal_entries;

ALTER TABLE stock_movements DROP COLUMN IF EXISTS financial_value;
ALTER TABLE stock_movements DROP COLUMN IF EXISTS financial_posted;
ALTER TABLE stock_movements DROP COLUMN IF EXISTS journal_entry_id;
