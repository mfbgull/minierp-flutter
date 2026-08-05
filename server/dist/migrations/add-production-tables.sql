-- Add productions table for manufacturing/production tracking
CREATE TABLE IF NOT EXISTS productions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    production_no VARCHAR(50) UNIQUE NOT NULL,
    output_item_id INTEGER NOT NULL,
    output_quantity DECIMAL(15,3) NOT NULL,
    warehouse_id INTEGER NOT NULL,
    production_date DATE NOT NULL,
    raw_materials_warehouse_id INTEGER,
    bom_id INTEGER,
    overhead_cost DECIMAL(15,2) DEFAULT 0,
    remarks TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (output_item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Add production_inputs table for raw materials consumed
CREATE TABLE IF NOT EXISTS production_inputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    production_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    FOREIGN KEY (production_id) REFERENCES productions(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_productions_output_item ON productions(output_item_id);
CREATE INDEX IF NOT EXISTS idx_productions_warehouse ON productions(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_productions_date ON productions(production_date);
CREATE INDEX IF NOT EXISTS idx_productions_production_no ON productions(production_no);
CREATE INDEX IF NOT EXISTS idx_production_inputs_production ON production_inputs(production_id);
CREATE INDEX IF NOT EXISTS idx_production_inputs_item ON production_inputs(item_id);
