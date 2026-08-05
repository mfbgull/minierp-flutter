-- Add num_racks to warehouses and rack_no to items
-- Date: 2026-04-04

ALTER TABLE warehouses ADD COLUMN num_racks INTEGER DEFAULT 0;
ALTER TABLE items ADD COLUMN rack_no VARCHAR(50);
