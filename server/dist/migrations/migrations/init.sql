-- ============================================
-- Mini ERP Database Schema
-- SQLite Database - 22 Tables
-- ============================================

-- ============================================
-- CORE TABLES
-- ============================================

-- Users table (1-3 users)
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'user', -- admin, user
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- System settings
CREATE TABLE IF NOT EXISTS settings (
    key VARCHAR(50) PRIMARY KEY,
    value TEXT,
    description TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- INVENTORY MODULE
-- ============================================

-- Items/Products
CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_code VARCHAR(50) UNIQUE NOT NULL,
    item_name VARCHAR(200) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    unit_of_measure VARCHAR(20) DEFAULT 'Nos', -- Nos, Kg, Ltr, Box, etc.
    current_stock DECIMAL(15,3) DEFAULT 0,
    reorder_level DECIMAL(15,3) DEFAULT 0,
    standard_cost DECIMAL(15,2) DEFAULT 0,
    standard_selling_price DECIMAL(15,2) DEFAULT 0,
    is_raw_material BOOLEAN DEFAULT 0,
    is_finished_good BOOLEAN DEFAULT 0,
    is_purchased BOOLEAN DEFAULT 1,
    is_manufactured BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Warehouses/Storage locations
CREATE TABLE IF NOT EXISTS warehouses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    warehouse_code VARCHAR(50) UNIQUE NOT NULL,
    warehouse_name VARCHAR(100) NOT NULL,
    location TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Stock entries (movements)
CREATE TABLE IF NOT EXISTS stock_movements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    movement_no VARCHAR(50) UNIQUE NOT NULL,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    movement_type VARCHAR(50) NOT NULL, -- PURCHASE, SALE, TRANSFER, PRODUCTION, ADJUSTMENT
    quantity DECIMAL(15,3) NOT NULL, -- Positive for IN, Negative for OUT
    unit_cost DECIMAL(15,2),
    reference_doctype VARCHAR(50), -- PurchaseOrder, SalesOrder, WorkOrder
    reference_docno VARCHAR(50),
    remarks TEXT,
    movement_date DATE NOT NULL,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Current stock levels by warehouse
CREATE TABLE IF NOT EXISTS stock_balances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) DEFAULT 0,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    UNIQUE(item_id, warehouse_id)
);

-- ============================================
-- PURCHASING MODULE
-- ============================================

-- Suppliers
CREATE TABLE IF NOT EXISTS suppliers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_code VARCHAR(50) UNIQUE NOT NULL,
    supplier_name VARCHAR(200) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    address TEXT,
    payment_terms VARCHAR(100), -- Net 30, Net 60, COD
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Purchase Orders (Header)
CREATE TABLE IF NOT EXISTS purchase_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_no VARCHAR(50) UNIQUE NOT NULL,
    supplier_id INTEGER NOT NULL,
    po_date DATE NOT NULL,
    expected_delivery_date DATE,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, Submitted, Partially Received, Completed, Cancelled
    total_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    warehouse_id INTEGER,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Purchase Order Items (Detail)
CREATE TABLE IF NOT EXISTS purchase_order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    received_quantity DECIMAL(15,3) DEFAULT 0,
    unit_price DECIMAL(15,2) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Goods Receipt (when items are received)
CREATE TABLE IF NOT EXISTS goods_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    receipt_no VARCHAR(50) UNIQUE NOT NULL,
    po_id INTEGER NOT NULL,
    receipt_date DATE NOT NULL,
    warehouse_id INTEGER NOT NULL,
    remarks TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS goods_receipt_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    receipt_id INTEGER NOT NULL,
    po_item_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    received_quantity DECIMAL(15,3) NOT NULL,
    FOREIGN KEY (receipt_id) REFERENCES goods_receipts(id) ON DELETE CASCADE,
    FOREIGN KEY (po_item_id) REFERENCES purchase_order_items(id),
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- ============================================
-- SALES MODULE
-- ============================================

-- Customers
CREATE TABLE IF NOT EXISTS customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_code VARCHAR(50) UNIQUE NOT NULL,
    customer_name VARCHAR(200) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    billing_address TEXT,
    shipping_address TEXT,
    payment_terms VARCHAR(100),
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Sales Orders (Header)
CREATE TABLE IF NOT EXISTS sales_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    so_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL,
    so_date DATE NOT NULL,
    delivery_date DATE,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, Confirmed, Delivered, Invoiced, Completed, Cancelled
    total_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    warehouse_id INTEGER,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Sales Order Items (Detail)
CREATE TABLE IF NOT EXISTS sales_order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    so_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    delivered_quantity DECIMAL(15,3) DEFAULT 0,
    unit_price DECIMAL(15,2) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (so_id) REFERENCES sales_orders(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Invoices (Header)
CREATE TABLE IF NOT EXISTS invoices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL,
    so_id INTEGER, -- Can be null for direct invoices
    invoice_date DATE NOT NULL,
    due_date DATE,
    status VARCHAR(20) DEFAULT 'Unpaid', -- Unpaid, Partially Paid, Paid, Overdue
    total_amount DECIMAL(15,2) DEFAULT 0,
    paid_amount DECIMAL(15,2) DEFAULT 0,
    balance_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (so_id) REFERENCES sales_orders(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Invoice Items (Detail)
CREATE TABLE IF NOT EXISTS invoice_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Payments received
CREATE TABLE IF NOT EXISTS payments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL,
    invoice_id INTEGER,
    payment_date DATE NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    payment_method VARCHAR(50), -- Cash, Check, Bank Transfer, Card
    reference_no VARCHAR(100),
    notes TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- ============================================
-- MANUFACTURING MODULE
-- ============================================

-- Bill of Materials (Header)
CREATE TABLE IF NOT EXISTS bom (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_no VARCHAR(50) UNIQUE NOT NULL,
    finished_item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) DEFAULT 1, -- BOM produces this quantity
    is_active BOOLEAN DEFAULT 1,
    notes TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (finished_item_id) REFERENCES items(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- BOM Items (Raw materials needed)
CREATE TABLE IF NOT EXISTS bom_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_id INTEGER NOT NULL,
    raw_material_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL, -- Quantity needed per BOM quantity
    unit_cost DECIMAL(15,2),
    FOREIGN KEY (bom_id) REFERENCES bom(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_material_id) REFERENCES items(id)
);

-- Work Orders (Production orders)
CREATE TABLE IF NOT EXISTS work_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wo_no VARCHAR(50) UNIQUE NOT NULL,
    bom_id INTEGER NOT NULL,
    finished_item_id INTEGER NOT NULL,
    planned_quantity DECIMAL(15,3) NOT NULL,
    produced_quantity DECIMAL(15,3) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, In Progress, Completed, Cancelled
    start_date DATE,
    expected_completion_date DATE,
    actual_completion_date DATE,
    warehouse_id INTEGER, -- Where finished goods will be stored
    notes TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (bom_id) REFERENCES bom(id),
    FOREIGN KEY (finished_item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Material consumption tracking
CREATE TABLE IF NOT EXISTS material_consumption (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wo_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    consumed_quantity DECIMAL(15,3) NOT NULL,
    consumption_date DATE NOT NULL,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (wo_id) REFERENCES work_orders(id),
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- ============================================
-- AUDIT & ACTIVITY LOG
-- ============================================

CREATE TABLE IF NOT EXISTS activity_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    action VARCHAR(50) NOT NULL, -- CREATE, UPDATE, DELETE, LOGIN, LOGOUT
    entity_type VARCHAR(50) NOT NULL, -- Item, PurchaseOrder, SalesOrder, etc.
    entity_id INTEGER,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX IF NOT EXISTS idx_items_code ON items(item_code);
CREATE INDEX IF NOT EXISTS idx_items_category ON items(category);
CREATE INDEX IF NOT EXISTS idx_items_active ON items(is_active);

CREATE INDEX IF NOT EXISTS idx_stock_movements_item ON stock_movements(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse ON stock_movements(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_date ON stock_movements(movement_date);
CREATE INDEX IF NOT EXISTS idx_stock_movements_type ON stock_movements(movement_type);

CREATE INDEX IF NOT EXISTS idx_stock_balances_item ON stock_balances(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_balances_warehouse ON stock_balances(warehouse_id);

CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_po_date ON purchase_orders(po_date);

CREATE INDEX IF NOT EXISTS idx_so_customer ON sales_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_so_status ON sales_orders(status);
CREATE INDEX IF NOT EXISTS idx_so_date ON sales_orders(so_date);

CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(invoice_date);

CREATE INDEX IF NOT EXISTS idx_wo_status ON work_orders(status);
CREATE INDEX IF NOT EXISTS idx_wo_item ON work_orders(finished_item_id);

CREATE INDEX IF NOT EXISTS idx_activity_log_user ON activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_entity ON activity_log(entity_type, entity_id);
