-- report-query-integrity (reporting-search-remediation):
-- per-line tax decomposition columns. `amount` is tax-inclusive on all
-- current writer paths, so the tax summary needs the stored exclusive
-- parts instead of re-deriving tax from a taxed base.
ALTER TABLE invoice_items ADD COLUMN net_amount DECIMAL(15,2) NOT NULL DEFAULT 0;
ALTER TABLE invoice_items ADD COLUMN tax_amount DECIMAL(15,2) NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_invoice_items_tax ON invoice_items(invoice_id, tax_amount);
