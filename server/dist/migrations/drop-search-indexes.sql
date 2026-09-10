-- reporting-search-remediation (SRCH-07): drop the plain single-column
-- search indexes added by add-search-indexes.sql. Global search matches
-- with leading-wildcard LIKE ('%term%'), which SQLite can only satisfy
-- via full table scans — a B-tree needs a literal prefix to be usable.
-- The indexes therefore never served a read while taxing writes on 15
-- hot tables. Verified before dropping: no non-search query uses an
-- equality predicate on any of these columns.
DROP INDEX IF EXISTS idx_search_customers_name;
DROP INDEX IF EXISTS idx_search_customers_code;
DROP INDEX IF EXISTS idx_search_customers_phone;
DROP INDEX IF EXISTS idx_search_customers_email;
DROP INDEX IF EXISTS idx_search_customers_contact;
DROP INDEX IF EXISTS idx_search_suppliers_name;
DROP INDEX IF EXISTS idx_search_suppliers_code;
DROP INDEX IF EXISTS idx_search_suppliers_phone;
DROP INDEX IF EXISTS idx_search_suppliers_email;
DROP INDEX IF EXISTS idx_search_suppliers_contact;
DROP INDEX IF EXISTS idx_search_items_name;
DROP INDEX IF EXISTS idx_search_items_code;
DROP INDEX IF EXISTS idx_search_items_category;
DROP INDEX IF EXISTS idx_search_items_description;
DROP INDEX IF EXISTS idx_search_invoices_no;
DROP INDEX IF EXISTS idx_search_purchase_orders_no;
DROP INDEX IF EXISTS idx_search_quotations_no;
DROP INDEX IF EXISTS idx_search_sales_orders_no;
DROP INDEX IF EXISTS idx_search_payments_no;
DROP INDEX IF EXISTS idx_search_payments_reference;
DROP INDEX IF EXISTS idx_search_warehouses_name;
DROP INDEX IF EXISTS idx_search_warehouses_code;
DROP INDEX IF EXISTS idx_search_employees_code;
DROP INDEX IF EXISTS idx_search_productions_no;
DROP INDEX IF EXISTS idx_search_boms_no;
