-- BUG-006: sales order lines carry a tax rate and a discount.
--
-- The order form already collects both, but the server had nowhere to
-- store them, so they were silently dropped and the order total was the
-- bare qty x price sum. Mirror the invoice_items columns exactly
-- (add-invoice-discount-tax-fields.sql) so the two sides cannot drift
-- apart again.
--
-- NO BACKFILL on purpose. Every existing row behaves as 0 / 'none' / 0,
-- which is exactly what these defaults give. Backfilling nothing is
-- correct, and it avoids touching historical rows.
--
-- 'none' (not 'percentage') is the default: it is the value
-- SalesOrderModel.convertToInvoice already hardcoded, so an old order
-- converts to the same invoice as before this migration.

ALTER TABLE sales_order_items ADD COLUMN tax_rate DECIMAL(5,2) DEFAULT 0;
ALTER TABLE sales_order_items ADD COLUMN discount_type VARCHAR(20) DEFAULT 'none';
ALTER TABLE sales_order_items ADD COLUMN discount_value DECIMAL(15,2) DEFAULT 0;
