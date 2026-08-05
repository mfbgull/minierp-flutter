-- Add discount and tax fields to invoices and invoice_items tables

-- Add discount fields to invoices table
ALTER TABLE invoices ADD COLUMN discount_scope VARCHAR(20) DEFAULT 'invoice'; -- 'invoice' or 'item'
ALTER TABLE invoices ADD COLUMN discount_type VARCHAR(20) DEFAULT 'percentage'; -- 'percentage' or 'flat'
ALTER TABLE invoices ADD COLUMN discount_value DECIMAL(15,2) DEFAULT 0;
ALTER TABLE invoices ADD COLUMN terms TEXT; -- Terms & Conditions

-- Add discount and tax fields to invoice_items table
ALTER TABLE invoice_items ADD COLUMN tax_rate DECIMAL(5,2) DEFAULT 0; -- Tax percentage
ALTER TABLE invoice_items ADD COLUMN discount_type VARCHAR(20) DEFAULT 'percentage'; -- 'percentage' or 'flat'
ALTER TABLE invoice_items ADD COLUMN discount_value DECIMAL(15,2) DEFAULT 0;

-- Add company information to settings (if not exists)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
('company_name', 'Mini ERP', 'Company name for invoices'),
('company_email', 'support@minierp.com', 'Company email for invoices'),
('company_phone', '+1 123 456 7890', 'Company phone for invoices'),
('company_address', '456 Enterprise Ave, BC 12345', 'Company address for invoices'),
('company_tax_id', 'TAX-123456789', 'Company tax ID for invoices');
