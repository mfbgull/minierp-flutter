-- Add purchases table for simple direct purchase recording
CREATE TABLE IF NOT EXISTS purchases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_no VARCHAR(50) UNIQUE NOT NULL,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    unit_cost DECIMAL(15,2) NOT NULL,
    total_cost DECIMAL(15,2) NOT NULL,
    supplier_name VARCHAR(200),
    purchase_date DATE NOT NULL,
    invoice_no VARCHAR(100),
    remarks TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_purchases_item ON purchases(item_id);
CREATE INDEX IF NOT EXISTS idx_purchases_warehouse ON purchases(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(purchase_date);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_name);
CREATE INDEX IF NOT EXISTS idx_purchases_purchase_no ON purchases(purchase_no);
