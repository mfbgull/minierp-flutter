-- Add manufacturer_name field to items table
ALTER TABLE items ADD COLUMN manufacturer_name VARCHAR(200);
CREATE INDEX IF NOT EXISTS idx_items_manufacturer_name ON items(manufacturer_name);
