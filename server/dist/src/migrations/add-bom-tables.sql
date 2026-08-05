-- Bill of Materials (BOM) tables
-- A BOM defines the recipe for producing a finished good

-- Disable foreign keys temporarily for migration
PRAGMA foreign_keys = OFF;

-- BOM Header
CREATE TABLE IF NOT EXISTS boms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_no VARCHAR(50) UNIQUE NOT NULL,
    bom_name VARCHAR(200) NOT NULL,
    finished_item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL DEFAULT 1,
    description TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- BOM Items (Raw Materials Required)
CREATE TABLE IF NOT EXISTS bom_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Re-enable foreign keys
PRAGMA foreign_keys = ON;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_boms_finished_item ON boms(finished_item_id);
CREATE INDEX IF NOT EXISTS idx_boms_is_active ON boms(is_active);
CREATE INDEX IF NOT EXISTS idx_bom_items_bom ON bom_items(bom_id);
CREATE INDEX IF NOT EXISTS idx_bom_items_item ON bom_items(item_id);
