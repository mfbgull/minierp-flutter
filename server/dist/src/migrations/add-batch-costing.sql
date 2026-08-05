-- Batch Costing System
-- Tracks inventory by cost layer (batch) for FIFO cost calculations
-- Each production run or purchase receipt creates a new batch

-- Main batch table: one row per cost layer
CREATE TABLE IF NOT EXISTS stock_batches (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_no        VARCHAR(50) UNIQUE NOT NULL,
    item_id         INTEGER NOT NULL REFERENCES items(id),
    warehouse_id    INTEGER NOT NULL REFERENCES warehouses(id),
    source_type     VARCHAR(20) NOT NULL CHECK(source_type IN ('PRODUCTION','PURCHASE')),
    source_id       INTEGER NOT NULL,
    quantity_original DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_remaining DECIMAL(15,3) NOT NULL DEFAULT 0,
    unit_cost       DECIMAL(15,4) NOT NULL DEFAULT 0,
    received_date   DATE NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_stock_batches_item ON stock_batches(item_id, warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_source ON stock_batches(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_batch_no ON stock_batches(batch_no);

-- Note: ALTER TABLE statements for existing tables (stock_movements, productions, purchases)
-- are handled by the migration function in database.ts with column existence checks.