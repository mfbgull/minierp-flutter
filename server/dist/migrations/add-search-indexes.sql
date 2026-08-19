-- Migration: Add search indexes for Global Search
-- Creates indexes on all searchable columns across 13 entity tables
-- Idempotent: CREATE INDEX IF NOT EXISTS

-- Customer search fields
CREATE INDEX IF NOT EXISTS idx_search_customers_name ON customers(customer_name);
CREATE INDEX IF NOT EXISTS idx_search_customers_code ON customers(customer_code);
CREATE INDEX IF NOT EXISTS idx_search_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_search_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_search_customers_contact ON customers(contact_person);

-- Supplier search fields
CREATE INDEX IF NOT EXISTS idx_search_suppliers_name ON suppliers(supplier_name);
CREATE INDEX IF NOT EXISTS idx_search_suppliers_code ON suppliers(supplier_code);
CREATE INDEX IF NOT EXISTS idx_search_suppliers_phone ON suppliers(phone);
CREATE INDEX IF NOT EXISTS idx_search_suppliers_email ON suppliers(email);
CREATE INDEX IF NOT EXISTS idx_search_suppliers_contact ON suppliers(contact_person);

-- Product/item search fields
CREATE INDEX IF NOT EXISTS idx_search_items_name ON items(item_name);
CREATE INDEX IF NOT EXISTS idx_search_items_code ON items(item_code);
CREATE INDEX IF NOT EXISTS idx_search_items_category ON items(category);
CREATE INDEX IF NOT EXISTS idx_search_items_description ON items(description);

-- Invoice search fields
CREATE INDEX IF NOT EXISTS idx_search_invoices_no ON invoices(invoice_no);

-- Purchase order search fields
CREATE INDEX IF NOT EXISTS idx_search_purchase_orders_no ON purchase_orders(po_no);

-- Quotation search fields
CREATE INDEX IF NOT EXISTS idx_search_quotations_no ON quotations(quotation_no);

-- Sales order search fields
CREATE INDEX IF NOT EXISTS idx_search_sales_orders_no ON sales_orders(so_no);

-- Payment search fields
CREATE INDEX IF NOT EXISTS idx_search_payments_no ON payments(payment_no);
CREATE INDEX IF NOT EXISTS idx_search_payments_reference ON payments(reference_no);

-- Warehouse search fields
CREATE INDEX IF NOT EXISTS idx_search_warehouses_name ON warehouses(warehouse_name);
CREATE INDEX IF NOT EXISTS idx_search_warehouses_code ON warehouses(warehouse_code);

-- Employee search fields
CREATE INDEX IF NOT EXISTS idx_search_employees_name ON employees(first_name, last_name);
CREATE INDEX IF NOT EXISTS idx_search_employees_code ON employees(employee_code);

-- Production search fields
CREATE INDEX IF NOT EXISTS idx_search_productions_no ON productions(production_no);

-- BOM search fields
CREATE INDEX IF NOT EXISTS idx_search_boms_no ON boms(bom_no);
