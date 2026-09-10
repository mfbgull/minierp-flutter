-- Rollback: Supplier ledger table
-- Reverts: create-supplier-ledger.sql

DROP INDEX IF EXISTS idx_supplier_ledger_supplier;
DROP INDEX IF EXISTS idx_supplier_ledger_date;
DROP INDEX IF EXISTS idx_supplier_ledger_type;
DROP INDEX IF EXISTS idx_supplier_ledger_reference;
DROP TABLE IF EXISTS supplier_ledger;
