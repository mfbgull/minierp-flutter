-- Rollback: Production inputs warehouse
-- Reverts: add-warehouse-to-production-inputs.sql

DROP INDEX IF EXISTS idx_production_inputs_warehouse;
ALTER TABLE production_inputs DROP COLUMN IF EXISTS warehouse_id;
