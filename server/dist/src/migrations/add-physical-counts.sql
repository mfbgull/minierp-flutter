-- Physical Count (Stock Take) tables
-- Enables periodic physical inventory counting and reconciliation

-- Physical count sessions (header)
CREATE TABLE IF NOT EXISTS physical_counts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    count_no VARCHAR(50) UNIQUE NOT NULL,
    count_date DATE NOT NULL,
    warehouse_id INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, In Progress, Completed, Cancelled
    notes TEXT,
    created_by INTEGER,
    completed_by INTEGER,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id),
    FOREIGN KEY (completed_by) REFERENCES users(id)
);

-- Physical count line items
CREATE TABLE IF NOT EXISTS physical_count_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    count_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    system_quantity DECIMAL(15,3) NOT NULL, -- Snapshot at count time
    counted_quantity DECIMAL(15,3), -- NULL until counted
    variance DECIMAL(15,3), -- counted - system (computed)
    unit_cost DECIMAL(15,2), -- For variance valuation
    variance_value DECIMAL(15,2), -- variance * unit_cost
    adjustment_posted BOOLEAN DEFAULT FALSE,
    adjustment_movement_id INTEGER, -- FK to stock_movements after adjustment
    counted_at DATETIME,
    counted_by INTEGER,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (count_id) REFERENCES physical_counts(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (counted_by) REFERENCES users(id),
    FOREIGN KEY (adjustment_movement_id) REFERENCES stock_movements(id),
    UNIQUE(count_id, item_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_physical_counts_warehouse ON physical_counts(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_physical_counts_status ON physical_counts(status);
CREATE INDEX IF NOT EXISTS idx_physical_counts_date ON physical_counts(count_date);
CREATE INDEX IF NOT EXISTS idx_physical_count_items_count ON physical_count_items(count_id);
CREATE INDEX IF NOT EXISTS idx_physical_count_items_item ON physical_count_items(item_id);
