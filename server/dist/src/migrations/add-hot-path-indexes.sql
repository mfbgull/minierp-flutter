-- Migration: hot-path indexes + redundant index cleanup (audit-remediation 8.1 / PERF-01, PERF-07)

CREATE INDEX IF NOT EXISTS idx_customers_customer_name ON customers(customer_name);
CREATE INDEX IF NOT EXISTS idx_suppliers_supplier_name ON suppliers(supplier_name);
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings("key");
CREATE INDEX IF NOT EXISTS idx_invoices_due_date ON invoices(due_date);
CREATE INDEX IF NOT EXISTS idx_invoices_status_date ON invoices(status, invoice_date);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_cust_date ON customer_ledger(customer_id, transaction_date, id);
CREATE INDEX IF NOT EXISTS idx_customer_ledger_cust_id ON customer_ledger(customer_id, id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_item_wh_date ON stock_movements(item_id, warehouse_id, movement_date);

-- PERF-07: drop redundant duplicate indexes (same table+columns as the
-- canonical *_id-named index). Drop-list verified against live schema.
DROP INDEX IF EXISTS idx_bom_items_bom;
DROP INDEX IF EXISTS idx_invoices_customer;
DROP INDEX IF EXISTS idx_productions_output_item;
DROP INDEX IF EXISTS idx_po_supplier;
DROP INDEX IF EXISTS idx_so_customer;
DROP INDEX IF EXISTS idx_stock_balances_item;
DROP INDEX IF EXISTS idx_stock_balances_warehouse;
DROP INDEX IF EXISTS idx_stock_movements_item;
DROP INDEX IF EXISTS idx_stock_movements_warehouse;
DROP INDEX IF EXISTS idx_wo_item;
