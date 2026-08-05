-- ============================================
-- Mobile Invoice Tables Migration
-- Creates tables for mobile invoice workflow
-- ============================================

-- ============================================
-- Invoice Drafts Table (Temporary storage for mobile sessions)
-- ============================================
CREATE TABLE IF NOT EXISTS invoice_drafts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id VARCHAR(100) NOT NULL,
    customer_id INTEGER,
    invoice_date DATE,
    due_date DATE,
    terms VARCHAR(50),
    notes TEXT,
    items_data TEXT,  -- JSON array of items
    status VARCHAR(20) DEFAULT 'draft',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME DEFAULT (datetime('now', '+7 days')),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- Index for session lookups
CREATE INDEX IF NOT EXISTS idx_invoice_drafts_session 
ON invoice_drafts(session_id, status) WHERE status = 'draft';

-- Index for expiration cleanup
CREATE INDEX IF NOT EXISTS idx_invoice_drafts_expires 
ON invoice_drafts(expires_at);

-- ============================================
-- Tax Rates Configuration Table
-- ============================================
CREATE TABLE IF NOT EXISTS tax_rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(50) NOT NULL,
    rate DECIMAL(5,2) NOT NULL,
    description TEXT,
    is_default BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert default tax rates if table is empty
INSERT INTO tax_rates (name, rate, description, is_default) 
SELECT 'No Tax', 0, 'No tax applied', 1
WHERE NOT EXISTS (SELECT 1 FROM tax_rates);

INSERT INTO tax_rates (name, rate, description) 
SELECT 'GST 5%', 5, 'Goods and Services Tax 5%'
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE rate = 5);

INSERT INTO tax_rates (name, rate, description) 
SELECT 'GST 10%', 10, 'Goods and Services Tax 10%'
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE rate = 10);

INSERT INTO tax_rates (name, rate, description) 
SELECT 'GST 15%', 15, 'Goods and Services Tax 15%'
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE rate = 15);

INSERT INTO tax_rates (name, rate, description) 
SELECT 'VAT 20%', 20, 'Value Added Tax 20%'
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE rate = 20);

-- ============================================
-- Payment Terms Configuration Table
-- ============================================
CREATE TABLE IF NOT EXISTS payment_terms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(50) NOT NULL,
    days INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    is_default BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert default payment terms if table is empty
INSERT INTO payment_terms (name, days, description, is_default) 
SELECT 'Due on Receipt', 0, 'Payment due immediately', 1
WHERE NOT EXISTS (SELECT 1 FROM payment_terms);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 7', 7, 'Payment due within 7 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 7);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 14', 14, 'Payment due within 14 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 14);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 21', 21, 'Payment due within 21 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 21);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 30', 30, 'Payment due within 30 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 30);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 45', 45, 'Payment due within 45 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 45);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 60', 60, 'Payment due within 60 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 60);

INSERT INTO payment_terms (name, days, description) 
SELECT 'Net 90', 90, 'Payment due within 90 days'
WHERE NOT EXISTS (SELECT 1 FROM payment_terms WHERE days = 90);

-- ============================================
-- Cleanup Job: Delete expired drafts (run periodically)
-- ============================================
-- This can be run as a scheduled task or called via API
DELETE FROM invoice_drafts WHERE expires_at < datetime('now');

-- ============================================
-- Views for Mobile API
-- ============================================

-- View for customer with balance (for mobile selection)
CREATE VIEW IF NOT EXISTS vw_customers_with_balance AS
SELECT 
    c.id,
    c.customer_code,
    c.customer_name,
    c.contact_person,
    c.email,
    c.phone,
    c.billing_address,
    c.payment_terms,
    COALESCE(
        (SELECT SUM(
            CASE 
                WHEN cl.transaction_type IN ('INVOICE', 'SALE') THEN cl.debit - cl.credit
                WHEN cl.transaction_type = 'PAYMENT' THEN cl.credit - cl.debit
                ELSE 0
            END
        ) 
        FROM customer_ledger cl 
        WHERE cl.customer_id = c.id),
        0
    ) as current_balance
FROM customers c
WHERE c.is_active = 1;

-- View for items with stock (for mobile item selection)
CREATE VIEW IF NOT EXISTS vw_items_with_stock AS
SELECT 
    i.id,
    i.item_code,
    i.item_name,
    i.description,
    i.category,
    i.unit_of_measure,
    i.current_stock,
    i.standard_selling_price,
    i.standard_cost,
    CASE 
        WHEN i.is_finished_good = 1 THEN 'Finished Good'
        WHEN i.is_purchased = 1 THEN 'Purchased'
        WHEN i.is_raw_material = 1 THEN 'Raw Material'
        ELSE 'Other'
    END as item_type
FROM items i
WHERE i.is_active = 1
AND i.is_raw_material = 0
AND (i.is_finished_good = 1 OR i.is_purchased = 1);
