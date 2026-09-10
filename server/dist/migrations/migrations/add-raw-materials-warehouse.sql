-- Add raw_materials_warehouse_id to productions table to support dual-warehouse production

-- First, add the new column to the productions table
ALTER TABLE productions ADD COLUMN raw_materials_warehouse_id INTEGER;

-- Update existing production records to use the existing warehouse_id for raw materials too (backward compatibility)
UPDATE productions 
SET raw_materials_warehouse_id = warehouse_id 
WHERE raw_materials_warehouse_id IS NULL;

-- Make the new column required (NOT NULL) after populating existing records
-- We'll handle this in the application code to maintain flexibility

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_productions_raw_materials_warehouse ON productions(raw_materials_warehouse_id);

-- Ensure foreign key constraint
PRAGMA foreign_keys = ON;