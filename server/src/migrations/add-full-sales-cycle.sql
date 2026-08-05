-- ============================================
-- Full Sales Cycle Migration
-- Adds Quotations and enhances Sales Orders with source tracking
-- ============================================

-- ============================================
-- QUOTATIONS TABLE (NEW)
-- ============================================

CREATE TABLE IF NOT EXISTS quotations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quotation_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL,
    customer_name VARCHAR(200), -- Denormalized for quick display
    quotation_date DATE NOT NULL,
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, Sent, Accepted, Expired, Converted, Rejected
    source_type VARCHAR(20), -- 'DIRECT' or NULL
    total_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    terms TEXT,
    warehouse_id INTEGER,
    created_by INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS quotation_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quotation_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    item_code VARCHAR(50), -- Denormalized for quick display
    item_name VARCHAR(200), -- Denormalized for quick display
    quantity DECIMAL(15,3) NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    discount_type VARCHAR(20) DEFAULT 'none', -- 'none', 'percentage', 'amount'
    discount_value DECIMAL(15,2) DEFAULT 0,
    tax_rate DECIMAL(5,2) DEFAULT 0,
    amount DECIMAL(15,2) NOT NULL, -- Line total after discount and tax
    FOREIGN KEY (quotation_id) REFERENCES quotations(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- ============================================
-- ENHANCE SALES ORDERS (ADD SOURCE TRACKING)
-- ============================================

-- Add source_type column (QUOTATION, DIRECT, or NULL)
ALTER TABLE sales_orders ADD COLUMN source_type VARCHAR(20);

-- Add source_id column (references quotations.id when source_type is 'QUOTATION')
ALTER TABLE sales_orders ADD COLUMN source_id INTEGER;

-- Add customer_name denormalized field for quick display
ALTER TABLE sales_orders ADD COLUMN customer_name VARCHAR(200);

-- ============================================
-- ENHANCE INVOICES (ADD SOURCE TYPE)
-- ============================================

-- Add source_type column (SALES_ORDER, DIRECT, or NULL)
ALTER TABLE invoices ADD COLUMN source_type VARCHAR(20);

-- Add quotation_id for direct link (if created from quotation via SO)
ALTER TABLE invoices ADD COLUMN quotation_id INTEGER;

-- Add customer_name denormalized field for quick display
ALTER TABLE invoices ADD COLUMN customer_name VARCHAR(200);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Quotations indexes
CREATE INDEX IF NOT EXISTS idx_quotations_customer ON quotations(customer_id);
CREATE INDEX IF NOT EXISTS idx_quotations_status ON quotations(status);
CREATE INDEX IF NOT EXISTS idx_quotations_date ON quotations(quotation_date);
CREATE INDEX IF NOT EXISTS idx_quotations_expiry ON quotations(expiry_date);
CREATE INDEX IF NOT EXISTS idx_quotations_no ON quotations(quotation_no);

-- Quotation items indexes
CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation ON quotation_items(quotation_id);
CREATE INDEX IF NOT EXISTS idx_quotation_items_item ON quotation_items(item_id);

-- Sales orders source indexes
CREATE INDEX IF NOT EXISTS idx_sales_orders_source ON sales_orders(source_type, source_id);

-- Invoices source indexes
CREATE INDEX IF NOT EXISTS idx_invoices_source ON invoices(source_type, source_id, quotation_id);

-- ============================================
-- UPDATE EXISTING RECORDS
-- ============================================

-- Mark existing sales orders as 'DIRECT' source type
UPDATE sales_orders SET source_type = 'DIRECT' WHERE source_type IS NULL;

-- Mark existing invoices as 'SALES_ORDER' if they have so_id, otherwise 'DIRECT'
UPDATE invoices SET source_type = 'SALES_ORDER' WHERE so_id IS NOT NULL AND source_type IS NULL;
UPDATE invoices SET source_type = 'DIRECT' WHERE so_id IS NULL AND source_type IS NULL;

-- ============================================
-- ACTIVITY LOG ENTRIES FOR MIGRATION
-- ============================================

INSERT INTO activity_log (user_id, action, entity_type, entity_id, description, created_at)
SELECT 
    1 as user_id,
    'UPDATE' as action,
    'SalesOrder' as entity_type,
    id as entity_id,
    'Marked as DIRECT source type during full sales cycle migration' as description,
    CURRENT_TIMESTAMP as created_at
FROM sales_orders;

INSERT INTO activity_log (user_id, action, entity_type, entity_id, description, created_at)
SELECT 
    1 as user_id,
    'UPDATE' as action,
    'Invoice' as entity_type,
    id as entity_id,
    'Marked with source type during full sales cycle migration' as description,
    CURRENT_TIMESTAMP as created_at
FROM invoices;
