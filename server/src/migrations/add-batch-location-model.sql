-- ============================================
-- Batch Location Model Migration
-- Feature flag: feature_batch_locations
-- ============================================

-- 1. Locations table
CREATE TABLE IF NOT EXISTS locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    location_code VARCHAR(50) NOT NULL,
    location_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(warehouse_id, location_code)
);

CREATE INDEX IF NOT EXISTS idx_locations_warehouse ON locations(warehouse_id);

-- 2. Seed default location for each existing warehouse
INSERT OR IGNORE INTO locations (warehouse_id, location_code, location_name)
SELECT id, 'DEFAULT', warehouse_name FROM warehouses;

-- 3. Feature flag
INSERT OR IGNORE INTO settings (key, value) VALUES ('feature_batch_locations', '0');

-- 4. batch_stock_by_location
CREATE TABLE IF NOT EXISTS batch_stock_by_location (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    location_id INTEGER NOT NULL REFERENCES locations(id),
    quantity_physical DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_reserved DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_available DECIMAL(15,3) NOT NULL DEFAULT 0,
    status_override VARCHAR(20),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(batch_id, location_id)
);

CREATE INDEX IF NOT EXISTS idx_batch_stock_batch ON batch_stock_by_location(batch_id);
CREATE INDEX IF NOT EXISTS idx_batch_stock_location ON batch_stock_by_location(location_id);

-- 5. stock_reservations
CREATE TABLE IF NOT EXISTS stock_reservations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL REFERENCES items(id),
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    location_id INTEGER REFERENCES locations(id),
    batch_id INTEGER REFERENCES stock_batches(id),
    quantity_reserved DECIMAL(15,3) NOT NULL,
    reference_doctype VARCHAR(30) NOT NULL,
    reference_docno VARCHAR(50) NOT NULL,
    reference_line_id INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    released_at DATETIME,
    consumed_at DATETIME
);

CREATE INDEX IF NOT EXISTS idx_reservations_ref ON stock_reservations(reference_doctype, reference_docno, reference_line_id);
CREATE INDEX IF NOT EXISTS idx_reservations_item_wh ON stock_reservations(item_id, warehouse_id, location_id);
CREATE INDEX IF NOT EXISTS idx_reservations_status ON stock_reservations(status);

-- 6. invoice_return_batches
CREATE TABLE IF NOT EXISTS invoice_return_batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_return_id INTEGER NOT NULL,
    invoice_item_id INTEGER NOT NULL,
    batch_id INTEGER NOT NULL REFERENCES stock_batches(id),
    location_id INTEGER NOT NULL REFERENCES locations(id),
    quantity DECIMAL(15,3) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_invoice_return_batches_return ON invoice_return_batches(invoice_return_id);
CREATE INDEX IF NOT EXISTS idx_invoice_return_batches_batch ON invoice_return_batches(batch_id);

-- 7. stock_balances extension
ALTER TABLE stock_balances ADD COLUMN quantity_physical DECIMAL(15,3);
ALTER TABLE stock_balances ADD COLUMN quantity_reserved DECIMAL(15,3);
ALTER TABLE stock_balances ADD COLUMN quantity_available DECIMAL(15,3);

-- 8. Trigger to maintain quantity_available = MAX(0, physical - reserved)
CREATE TRIGGER IF NOT EXISTS trg_batch_stock_available
AFTER UPDATE OF quantity_physical, quantity_reserved ON batch_stock_by_location
FOR EACH ROW
BEGIN
  UPDATE batch_stock_by_location
  SET quantity_available = MAX(0, NEW.quantity_physical - NEW.quantity_reserved)
  WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_batch_stock_available_insert
AFTER INSERT ON batch_stock_by_location
FOR EACH ROW
BEGIN
  UPDATE batch_stock_by_location
  SET quantity_available = MAX(0, NEW.quantity_physical - NEW.quantity_reserved)
  WHERE id = NEW.id;
END;

-- 9. Composite index for allocation queries (task 1.9)
CREATE INDEX IF NOT EXISTS idx_batch_stock_alloc
  ON batch_stock_by_location(item_id, warehouse_id, status_override, quantity_available);

-- 11. Extend purchase_return_batches with location_id
ALTER TABLE purchase_return_batches ADD COLUMN IF NOT EXISTS location_id INTEGER REFERENCES locations(id);
