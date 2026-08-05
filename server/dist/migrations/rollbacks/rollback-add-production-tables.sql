-- Rollback: Production tables
-- Reverts: add-production-tables.sql

DROP INDEX IF EXISTS idx_production_outputs_production;
DROP INDEX IF EXISTS idx_production_inputs_production;
DROP INDEX IF EXISTS idx_productions_date;
DROP INDEX IF EXISTS idx_productions_status;
DROP INDEX IF EXISTS idx_productions_bom;
DROP INDEX IF EXISTS idx_productions_warehouse;

DROP TABLE IF EXISTS production_outputs;
DROP TABLE IF EXISTS production_inputs;
DROP TABLE IF EXISTS productions;
