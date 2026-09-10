-- Add warehouse_id column to production_inputs table
-- This allows tracking which warehouse raw materials are consumed from

ALTER TABLE production_inputs ADD COLUMN warehouse_id INTEGER;

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_production_inputs_warehouse ON production_inputs(warehouse_id);

-- Add foreign key constraint (SQLite doesn't enforce FK in ALTER TABLE, but we document it)
-- FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)
