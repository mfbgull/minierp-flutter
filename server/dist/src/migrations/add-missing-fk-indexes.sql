-- Migration: Add missing foreign key indexes for join performance
-- These indexes speed up JOINs on foreign key columns that are commonly queried

-- Invoices: customer_id is joined against customers.id
CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON invoices(customer_id);

-- Work orders: finished_item_id is joined against items.id for WO→item lookups
CREATE INDEX IF NOT EXISTS idx_work_orders_finished_item_id ON work_orders(finished_item_id);

-- Purchase order items: po_id for PO detail lookups
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po_id ON purchase_order_items(po_id);

-- Sales orders: customer_id for customer-based lookups
CREATE INDEX IF NOT EXISTS idx_sales_orders_customer_id ON sales_orders(customer_id);

-- Sales order items: so_id for SO detail lookups
CREATE INDEX IF NOT EXISTS idx_sales_order_items_so_id ON sales_order_items(so_id);

-- Payments: customer_id for customer payment history
CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);

-- Stock movements: item_id and warehouse_id for inventory tracking
CREATE INDEX IF NOT EXISTS idx_stock_movements_item_id ON stock_movements(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse_id ON stock_movements(warehouse_id);

-- Stock balances: item_id and warehouse_id for stock lookups
CREATE INDEX IF NOT EXISTS idx_stock_balances_item_id ON stock_balances(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_balances_warehouse_id ON stock_balances(warehouse_id);

-- BOM items: bom_id for BOM detail lookups
CREATE INDEX IF NOT EXISTS idx_bom_items_bom_id ON bom_items(bom_id);

-- Productions: output_item_id for production item lookups
CREATE INDEX IF NOT EXISTS idx_productions_output_item_id ON productions(output_item_id);

-- Purchase orders: supplier_id for supplier order history
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON purchase_orders(supplier_id);

-- Analyze to update query planner statistics
ANALYZE invoices;
ANALYZE work_orders;
ANALYZE purchase_order_items;
ANALYZE sales_orders;
ANALYZE sales_order_items;
ANALYZE payments;
ANALYZE stock_movements;
ANALYZE stock_balances;
ANALYZE bom_items;
ANALYZE productions;
ANALYZE purchase_orders;
ANALYZE expenses;
