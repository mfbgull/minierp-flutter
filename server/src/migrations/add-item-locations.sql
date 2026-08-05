-- Create item_locations table for rack tracking per item per warehouse
-- Date: 2026-04-04

CREATE TABLE IF NOT EXISTS item_locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    rack_no VARCHAR(50) NOT NULL,
    is_primary BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(item_id, warehouse_id, rack_no),
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)
);

-- Create index for common lookups
CREATE INDEX IF NOT EXISTS idx_item_locations_item ON item_locations(item_id);
CREATE INDEX IF NOT EXISTS idx_item_locations_warehouse ON item_locations(warehouse_id);

-- Remove rack_no from items table (if it was added by previous migration)
-- SQLite doesn't support DROP COLUMN directly in older versions, so we skip this
-- The column will remain unused
