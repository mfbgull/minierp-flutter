-- Rollback: Invoice discount/tax fields
-- Reverts: add-invoice-discount-tax-fields.sql

ALTER TABLE invoices DROP COLUMN IF EXISTS discount_scope;
ALTER TABLE invoices DROP COLUMN IF EXISTS discount_type;
ALTER TABLE invoices DROP COLUMN IF EXISTS discount_value;
ALTER TABLE invoices DROP COLUMN IF EXISTS terms;

ALTER TABLE invoice_items DROP COLUMN IF EXISTS tax_rate;
ALTER TABLE invoice_items DROP COLUMN IF EXISTS discount_type;
ALTER TABLE invoice_items DROP COLUMN IF EXISTS discount_value;

DELETE FROM settings WHERE key IN ('company_name', 'company_email', 'company_phone', 'company_address', 'company_tax_id');
