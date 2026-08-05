-- CURRENT_SCHEMA.sql — machine-exact dump of the live MiniERP database
--   source : server/database/erp.db (the DB the running server uses)
--   content: 59 tables, 2 views, 153 indexes, 2 triggers
--   schema only — seed rows are in SEED_DATA.sql; apply both (see SCHEMA_AND_SEED.md)
--   a full snapshot incl. business data is bundled as server/database/erp.db
PRAGMA foreign_keys = ON;

CREATE TABLE accounting_periods (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    period_name     TEXT UNIQUE NOT NULL,          -- e.g. '2026-01', 'FY2026-Q2'
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
    closed_at       TIMESTAMP,
    closed_by       INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE activity_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    action VARCHAR(50) NOT NULL, -- CREATE, UPDATE, DELETE, LOGIN, LOGOUT
    entity_type VARCHAR(50) NOT NULL, -- Item, PurchaseOrder, SalesOrder, etc.
    entity_id INTEGER,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP, log_level VARCHAR(20) DEFAULT 'INFO', ip_address VARCHAR(45), user_agent TEXT, metadata TEXT, duration_ms INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE bom (
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

CREATE TABLE bom_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE boms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_no VARCHAR(50) UNIQUE NOT NULL,
    bom_name VARCHAR(200) NOT NULL,
    finished_item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL DEFAULT 1,
    description TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chart_of_accounts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    code            TEXT UNIQUE NOT NULL,           -- e.g. '1100', '4000'
    name            TEXT NOT NULL,                  -- e.g. 'Accounts Receivable'
    type            TEXT NOT NULL,                  -- asset | liability | equity | revenue | expense
    normal_balance  TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
    parent_id       INTEGER REFERENCES chart_of_accounts(id),  -- for hierarchies
    text_code       TEXT,                           -- legacy text code for joining old journal_entries
    is_active       BOOLEAN DEFAULT TRUE,
    description     TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE conversations (
    session_id TEXT PRIMARY KEY,
    data TEXT NOT NULL,  -- JSON blob of full session state
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE custom_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  config TEXT NOT NULL,              -- JSON blob
  is_active BOOLEAN DEFAULT 1,
  last_run_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type VARCHAR(50), -- INVOICE, PAYMENT, ADJUSTMENT, OPENING_BALANCE
    reference_no VARCHAR(100),
    debit DECIMAL(15,2) DEFAULT 0,
    credit DECIMAL(15,2) DEFAULT 0,
    balance DECIMAL(15,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE TABLE customers (
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
, credit_limit DECIMAL(15,2) DEFAULT 0, current_balance DECIMAL(15,2) DEFAULT 0, opening_balance DECIMAL(15,2) DEFAULT 0, payment_terms_days INTEGER DEFAULT 14, credit_balance DECIMAL(15,2) NOT NULL DEFAULT 0);

CREATE TABLE dashboard_layouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  layout_name TEXT DEFAULT 'Default',
  blocks TEXT NOT NULL DEFAULT '[]',
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, layout_name)
);

CREATE TABLE demand_forecasts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  forecast_date DATE NOT NULL,
  period TEXT NOT NULL CHECK(period IN ('next_week', 'next_month', 'next_quarter')),
  predicted_quantity REAL NOT NULL,
  confidence_level REAL DEFAULT 0,
  trend_direction TEXT DEFAULT 'stable' CHECK(trend_direction IN ('growing', 'stable', 'declining')),
  trend_percentage REAL DEFAULT 0,
  model_type TEXT DEFAULT 'weighted_moving_average',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, is_manual_override INTEGER DEFAULT 0, override_reason TEXT DEFAULT NULL, override_expires DATE DEFAULT NULL, bias_adjustment REAL DEFAULT NULL, seasonal_multiplier REAL DEFAULT NULL, run_id TEXT DEFAULT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE employee_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL,
    document_name VARCHAR(200) NOT NULL,
    document_type VARCHAR(50),
    document_number VARCHAR(100),
    issue_date DATE,
    expiry_date DATE,
    file_path TEXT,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
);

CREATE TABLE employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_code VARCHAR(50) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(50),
    mobile VARCHAR(50),
    cnic_no VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'Pakistan',
    date_of_birth DATE,
    gender VARCHAR(10),
    department VARCHAR(100),
    designation VARCHAR(100),
    employment_type VARCHAR(50) DEFAULT 'Full-time',
    date_of_joining DATE,
    date_of_leaving DATE,
    salary DECIMAL(15,2) DEFAULT 0,
    bank_name VARCHAR(100),
    bank_account_no VARCHAR(50),
    bank_iban VARCHAR(50),
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(50),
    profile_photo TEXT,
    notes TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE expense_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expense_no VARCHAR(50) UNIQUE NOT NULL,
    expense_category VARCHAR(100) NOT NULL,
    description TEXT,
    amount DECIMAL(15,2) NOT NULL,
    expense_date DATE NOT NULL,
    payment_method VARCHAR(50), -- Cash, Check, Bank Transfer, Card, Credit
    reference_no VARCHAR(100), -- Receipt number, check number, etc.
    vendor_name VARCHAR(200), -- Name of vendor/supplier
    project VARCHAR(100), -- Project or department associated with expense
    status VARCHAR(20) DEFAULT 'Approved', -- Draft, Submitted, Approved, Paid, Cancelled
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE forecast_accuracy (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  forecast_date DATE NOT NULL,
  item_id INTEGER NOT NULL,
  period TEXT NOT NULL CHECK(period IN ('next_week', 'next_month', 'next_quarter')),
  model_type TEXT NOT NULL DEFAULT 'weighted_moving_average',
  predicted_quantity REAL NOT NULL,
  actual_quantity REAL DEFAULT NULL,
  mape REAL DEFAULT NULL,
  mae REAL DEFAULT NULL,
  smape REAL DEFAULT NULL,
  is_override INTEGER DEFAULT 0,
  computed_at DATETIME DEFAULT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE forecast_model_config (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER DEFAULT NULL,
  category TEXT DEFAULT NULL,
  model_type TEXT NOT NULL DEFAULT 'weighted_moving_average',
  ses_alpha REAL DEFAULT NULL,
  holt_alpha REAL DEFAULT NULL,
  holt_beta REAL DEFAULT NULL,
  hw_alpha REAL DEFAULT NULL,
  hw_beta REAL DEFAULT NULL,
  hw_gamma REAL DEFAULT NULL,
  seasonal_periods INTEGER DEFAULT 12,
  service_level REAL DEFAULT 0.95,
  lead_time_days INTEGER DEFAULT 7,
  bias_correction INTEGER DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id),
  CHECK (item_id IS NOT NULL OR category IS NOT NULL)
);

CREATE TABLE forecast_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL UNIQUE,
  run_type TEXT NOT NULL DEFAULT 'auto' CHECK(run_type IN ('auto', 'manual', 'scheduled')),
  started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME DEFAULT NULL,
  items_processed INTEGER DEFAULT 0,
  errors INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'running' CHECK(status IN ('running', 'completed', 'failed')),
  error_message TEXT DEFAULT NULL
);

CREATE TABLE forecast_seasonal_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_name TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  multiplier REAL NOT NULL DEFAULT 1.0,
  applies_to_category TEXT DEFAULT NULL,
  applies_to_item_id INTEGER DEFAULT NULL,
  is_recurring INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (applies_to_item_id) REFERENCES items(id)
);

CREATE TABLE goods_receipt_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    receipt_id INTEGER NOT NULL,
    po_item_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    received_quantity DECIMAL(15,3) NOT NULL,
    FOREIGN KEY (receipt_id) REFERENCES goods_receipts(id) ON DELETE CASCADE,
    FOREIGN KEY (po_item_id) REFERENCES purchase_order_items(id),
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE goods_receipts (
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

CREATE TABLE invoice_drafts (
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

CREATE TABLE invoice_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    amount DECIMAL(15,2) NOT NULL, tax_rate DECIMAL(5,2) DEFAULT 0, discount_type VARCHAR(20) DEFAULT 'percentage', discount_value DECIMAL(15,2) DEFAULT 0, returned_qty DECIMAL(15,3) NOT NULL DEFAULT 0,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE invoices (
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
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, source_type VARCHAR(20), quotation_id INTEGER, customer_name VARCHAR(200), discount_scope VARCHAR(20) DEFAULT 'invoice', discount_type VARCHAR(20) DEFAULT 'percentage', discount_value DECIMAL(15,2) DEFAULT 0, terms TEXT, returned_amount DECIMAL(15,2) NOT NULL DEFAULT 0, return_fee DECIMAL(15,2) NOT NULL DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (so_id) REFERENCES sales_orders(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE item_locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    rack_no VARCHAR(50) NOT NULL,
    is_primary BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(item_id, warehouse_id, rack_no),
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)
);

CREATE TABLE items (
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
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, rack_no VARCHAR(50), sale_type TEXT NOT NULL DEFAULT 'packed' CHECK(sale_type IN ('packed','loose')), qty_decimal_precision INTEGER NOT NULL DEFAULT 0, rounding_step REAL DEFAULT NULL,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE journal_entries (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          reference_type  TEXT NOT NULL,
          reference_id    INTEGER NOT NULL,
          entry_date      DATE NOT NULL,
          description     TEXT,
          debit_account   TEXT NOT NULL,
          credit_account  TEXT NOT NULL,
          amount          DECIMAL(15,4) NOT NULL,
          created_by      INTEGER REFERENCES users(id),
          voided          BOOLEAN DEFAULT FALSE,
          created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

CREATE TABLE journal_lines (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL,             -- logical grouping; no FK to journal_entries since that table may be missing for fresh installs
    account_id      INTEGER NOT NULL REFERENCES chart_of_accounts(id),
    debit           DECIMAL(15,4) NOT NULL DEFAULT 0,
    credit          DECIMAL(15,4) NOT NULL DEFAULT 0,
    description     TEXT,
    line_date       DATE NOT NULL,
    reference_type  TEXT,
    reference_id    INTEGER,
    voided          BOOLEAN DEFAULT FALSE,
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (debit = 0 OR credit = 0),               -- a line is either debit or credit, not both
    CHECK (debit >= 0 AND credit >= 0)
);

CREATE TABLE material_consumption (
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

CREATE TABLE payment_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL,
    invoice_id INTEGER NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id)
);

CREATE TABLE payment_terms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(50) NOT NULL,
    days INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    is_default BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "payments" (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_no VARCHAR(50) UNIQUE NOT NULL,
            customer_id INTEGER,
            supplier_id INTEGER REFERENCES suppliers(id),
            invoice_id INTEGER,
            payment_date DATE NOT NULL,
            amount DECIMAL(15,2) NOT NULL,
            payment_method VARCHAR(50),
            reference_no VARCHAR(100),
            notes TEXT,
            created_by INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (customer_id) REFERENCES customers(id),
            FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
            FOREIGN KEY (invoice_id) REFERENCES invoices(id),
            FOREIGN KEY (created_by) REFERENCES users(id)
        );

CREATE TABLE permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    permission_name VARCHAR(100) UNIQUE NOT NULL,
    module VARCHAR(50) NOT NULL, -- e.g., 'users', 'inventory', 'sales', 'purchases', etc.
    action VARCHAR(20) NOT NULL, -- 'read', 'create', 'update', 'delete', 'approve', etc.
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE physical_count_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    count_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    system_quantity DECIMAL(15,3) NOT NULL, -- Snapshot at count time
    counted_quantity DECIMAL(15,3), -- NULL until counted
    variance DECIMAL(15,3), -- counted - system (computed)
    unit_cost DECIMAL(15,2), -- For variance valuation
    variance_value DECIMAL(15,2), -- variance * unit_cost
    adjustment_posted BOOLEAN DEFAULT FALSE,
    adjustment_movement_id INTEGER, -- FK to stock_movements after adjustment
    counted_at DATETIME,
    counted_by INTEGER,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (count_id) REFERENCES physical_counts(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (counted_by) REFERENCES users(id),
    FOREIGN KEY (adjustment_movement_id) REFERENCES stock_movements(id),
    UNIQUE(count_id, item_id)
);

CREATE TABLE physical_counts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    count_no VARCHAR(50) UNIQUE NOT NULL,
    count_date DATE NOT NULL,
    warehouse_id INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, In Progress, Completed, Cancelled
    notes TEXT,
    created_by INTEGER,
    completed_by INTEGER,
    completed_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id),
    FOREIGN KEY (completed_by) REFERENCES users(id)
);

CREATE TABLE po_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL,
    po_id INTEGER NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(id)
);

CREATE TABLE production_inputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    production_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL, warehouse_id INTEGER,
    FOREIGN KEY (production_id) REFERENCES productions(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE productions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    production_no VARCHAR(50) UNIQUE NOT NULL,
    output_item_id INTEGER NOT NULL,
    output_quantity DECIMAL(15,3) NOT NULL,
    warehouse_id INTEGER NOT NULL,
    production_date DATE NOT NULL,
    remarks TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, raw_materials_warehouse_id INTEGER, overhead_cost DECIMAL(15,2) DEFAULT 0, bom_id INTEGER REFERENCES boms(id), batch_id INTEGER REFERENCES stock_batches(id), batch_no VARCHAR(50), unit_cost DECIMAL(15,4) DEFAULT 0, total_material_cost DECIMAL(15,4) DEFAULT 0, total_batch_cost DECIMAL(15,4) DEFAULT 0,
    FOREIGN KEY (output_item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE purchase_order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    received_quantity DECIMAL(15,3) DEFAULT 0,
    unit_price DECIMAL(15,2) NOT NULL,
    amount DECIMAL(15,2) NOT NULL, returned_quantity DECIMAL(15,3) NOT NULL DEFAULT 0,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE purchase_orders (
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

CREATE TABLE purchases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_no VARCHAR(50) UNIQUE NOT NULL,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) NOT NULL,
    unit_cost DECIMAL(15,2) NOT NULL,
    total_cost DECIMAL(15,2) NOT NULL,
    supplier_name VARCHAR(200),
    purchase_date DATE NOT NULL,
    invoice_no VARCHAR(100),
    remarks TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, batch_id INTEGER REFERENCES stock_batches(id), batch_no VARCHAR(50), returned_quantity DECIMAL(15,3) NOT NULL DEFAULT 0,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE quotation_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quotation_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    item_code VARCHAR(50), -- Denormalized for quick display
    item_name VARCHAR(200), -- Denormalized for quick display
    quantity DECIMAL(15,3) NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    discount_type VARCHAR(20) DEFAULT 'none', -- 'none', 'percentage', 'amount'
    discount_value DECIMAL(15,2) DEFAULT 0,
    tax_rate DECIMAL(5,2) DEFAULT 0,
    amount DECIMAL(15,2) NOT NULL, -- Line total after discount and tax
    FOREIGN KEY (quotation_id) REFERENCES quotations(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

CREATE TABLE quotations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quotation_no VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL,
    customer_name VARCHAR(200), -- Denormalized for quick display
    quotation_date DATE NOT NULL,
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'Draft', -- Draft, Sent, Accepted, Expired, Converted, Rejected
    source_type VARCHAR(20), -- 'DIRECT' or NULL
    total_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    terms TEXT,
    warehouse_id INTEGER,
    created_by INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE role_permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role_id INTEGER NOT NULL,
    permission_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
    UNIQUE(role_id, permission_id)
);

CREATE TABLE roles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT 0, -- System roles (Admin, User) cannot be deleted
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE salary_payments (id INTEGER PRIMARY KEY AUTOINCREMENT, employee_id INTEGER NOT NULL REFERENCES employees(id), amount DECIMAL(15,2) NOT NULL, payment_date DATE NOT NULL, payment_method TEXT DEFAULT 'bank', reference_no TEXT, notes TEXT, journal_entry_id INTEGER, status TEXT DEFAULT 'paid' CHECK (status IN ('paid','cancelled')), paid_by INTEGER REFERENCES users(id), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

CREATE TABLE sales_order_items (
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

CREATE TABLE sales_orders (
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
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, source_type VARCHAR(20), source_id INTEGER, customer_name VARCHAR(200),
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE settings (
    key VARCHAR(50) PRIMARY KEY,
    value TEXT,
    description TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stock_balances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    quantity DECIMAL(15,3) DEFAULT 0,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    UNIQUE(item_id, warehouse_id)
);

CREATE TABLE stock_batches (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_no        VARCHAR(50) UNIQUE NOT NULL,
    item_id         INTEGER NOT NULL REFERENCES items(id),
    warehouse_id    INTEGER NOT NULL REFERENCES warehouses(id),
    source_type     VARCHAR(20) NOT NULL CHECK(source_type IN ('PRODUCTION','PURCHASE')),
    source_id       INTEGER NOT NULL,
    quantity_original DECIMAL(15,3) NOT NULL DEFAULT 0,
    quantity_remaining DECIMAL(15,3) NOT NULL DEFAULT 0,
    unit_cost       DECIMAL(15,4) NOT NULL DEFAULT 0,
    received_date   DATE NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stock_movements (
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
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP, journal_entry_id INTEGER REFERENCES journal_entries(id), financial_value DECIMAL(15,4) DEFAULT 0, financial_posted BOOLEAN DEFAULT FALSE, batch_id INTEGER REFERENCES stock_batches(id),
    FOREIGN KEY (item_id) REFERENCES items(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE supplier_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL,
    transaction_date DATE NOT NULL,
    transaction_type VARCHAR(50), -- PURCHASE_ORDER, RECEIPT, PAYMENT, ADJUSTMENT, OPENING_BALANCE
    reference_no VARCHAR(100),
    debit DECIMAL(15,2) DEFAULT 0,
    credit DECIMAL(15,2) DEFAULT 0,
    balance DECIMAL(15,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
);

CREATE TABLE suppliers (
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
, current_balance DECIMAL(15,2) DEFAULT 0);

CREATE TABLE tax_rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(50) NOT NULL,
    rate DECIMAL(5,2) NOT NULL,
    description TEXT,
    is_default BOOLEAN DEFAULT 0,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'user', -- admin, user
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
, role_id INTEGER REFERENCES roles(id));

CREATE TABLE warehouses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    warehouse_code VARCHAR(50) UNIQUE NOT NULL,
    warehouse_name VARCHAR(100) NOT NULL,
    location TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
, num_racks INTEGER DEFAULT 0);

CREATE TABLE work_orders (
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

CREATE VIEW vw_customers_with_balance AS SELECT c.id,c.customer_code,c.customer_name,c.contact_person,c.email,c.phone,c.billing_address,c.payment_terms,COALESCE((SELECT SUM(CASE WHEN cl.transaction_type IN ('INVOICE','SALE') THEN cl.debit-cl.credit WHEN cl.transaction_type='PAYMENT' THEN cl.credit-cl.debit ELSE 0 END) FROM customer_ledger cl WHERE cl.customer_id=c.id),0) as current_balance FROM customers c WHERE c.is_active=1;

CREATE VIEW vw_items_with_stock AS
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

CREATE INDEX idx_activity_log_action ON activity_log(action);
CREATE INDEX idx_activity_log_created_at ON activity_log(created_at);
CREATE INDEX idx_activity_log_entity ON activity_log(entity_type, entity_id);
CREATE INDEX idx_activity_log_user ON activity_log(user_id);
CREATE INDEX idx_activity_log_user_id ON activity_log(user_id);
CREATE INDEX idx_bom_items_bom ON bom_items(bom_id);
CREATE INDEX idx_bom_items_item ON bom_items(item_id);
CREATE INDEX idx_boms_finished_item ON boms(finished_item_id);
CREATE INDEX idx_boms_is_active ON boms(is_active);
CREATE INDEX idx_coa_code ON chart_of_accounts(code);
CREATE INDEX idx_coa_text_code ON chart_of_accounts(text_code);
CREATE INDEX idx_coa_type ON chart_of_accounts(type);
CREATE INDEX idx_custom_reports_active ON custom_reports(is_active);
CREATE INDEX idx_custom_reports_user ON custom_reports(user_id);
CREATE INDEX idx_customer_ledger_customer ON customer_ledger(customer_id);
CREATE INDEX idx_customer_ledger_date ON customer_ledger(transaction_date);
CREATE INDEX idx_customer_ledger_reference ON customer_ledger(reference_no);
CREATE INDEX idx_customer_ledger_type ON customer_ledger(transaction_type);
CREATE INDEX idx_customers_code ON customers(customer_code);
CREATE INDEX idx_customers_name ON customers(customer_name);
CREATE INDEX idx_dashboard_layouts_active ON dashboard_layouts(is_active);
CREATE INDEX idx_dashboard_layouts_user_id ON dashboard_layouts(user_id);
CREATE INDEX idx_employee_documents_employee ON employee_documents(employee_id);
CREATE INDEX idx_employees_active ON employees(is_active);
CREATE INDEX idx_employees_department ON employees(department);
CREATE INDEX idx_employees_designation ON employees(designation);
CREATE INDEX idx_expenses_category ON expenses(expense_category);
CREATE INDEX idx_expenses_created_by ON expenses(created_by);
CREATE INDEX idx_expenses_date ON expenses(expense_date);
CREATE INDEX idx_expenses_status ON expenses(status);
CREATE INDEX idx_forecast_accuracy_date ON forecast_accuracy(forecast_date);
CREATE INDEX idx_forecast_accuracy_item ON forecast_accuracy(item_id, forecast_date);
CREATE INDEX idx_forecast_accuracy_model ON forecast_accuracy(model_type);
CREATE UNIQUE INDEX idx_forecast_config_category ON forecast_model_config(category);
CREATE UNIQUE INDEX idx_forecast_config_item ON forecast_model_config(item_id);
CREATE INDEX idx_forecast_runs_created ON forecast_runs(started_at);
CREATE INDEX idx_forecast_runs_status ON forecast_runs(status);
CREATE INDEX idx_forecast_runs_type ON forecast_runs(run_type);
CREATE INDEX idx_forecasts_item_date ON demand_forecasts(item_id, forecast_date);
CREATE INDEX idx_forecasts_item_period ON demand_forecasts(item_id, period);
CREATE INDEX idx_goods_receipt_items_item_id ON goods_receipt_items(item_id);
CREATE INDEX idx_goods_receipt_items_receipt_id ON goods_receipt_items(receipt_id);
CREATE INDEX idx_goods_receipts_po_id ON goods_receipts(po_id);
CREATE INDEX idx_invoice_drafts_expires 
ON invoice_drafts(expires_at);
CREATE INDEX idx_invoice_drafts_session 
ON invoice_drafts(session_id, status) WHERE status = 'draft';
CREATE INDEX idx_invoice_items_invoice_id ON invoice_items(invoice_id);
CREATE INDEX idx_invoice_items_item_id ON invoice_items(item_id);
CREATE INDEX idx_invoices_customer ON invoices(customer_id);
CREATE INDEX idx_invoices_customer_id ON invoices(customer_id);
CREATE INDEX idx_invoices_date ON invoices(invoice_date);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);
CREATE INDEX idx_invoices_so_id ON invoices(so_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_status_date ON invoices(status, invoice_date);
CREATE INDEX idx_item_locations_item ON item_locations(item_id);
CREATE INDEX idx_item_locations_warehouse ON item_locations(warehouse_id);
CREATE INDEX idx_items_active ON items(is_active);
CREATE INDEX idx_items_category ON items(category);
CREATE INDEX idx_items_code ON items(item_code);
CREATE INDEX idx_items_created_by ON items(created_by);
CREATE INDEX idx_items_item_code ON items(item_code);
CREATE INDEX idx_items_reorder_level ON items(reorder_level) WHERE current_stock <= reorder_level;
CREATE INDEX idx_journal_entries_accounts ON journal_entries(debit_account, credit_account, voided);
CREATE INDEX idx_journal_entries_date ON journal_entries(entry_date);
CREATE INDEX idx_journal_entries_reference ON journal_entries(reference_type, reference_id);
CREATE INDEX idx_journal_lines_account ON journal_lines(account_id);
CREATE INDEX idx_journal_lines_date ON journal_lines(line_date);
CREATE INDEX idx_journal_lines_entry ON journal_lines(journal_entry_id);
CREATE INDEX idx_journal_lines_reference ON journal_lines(reference_type, reference_id);
CREATE INDEX idx_material_consumption_item_id ON material_consumption(item_id);
CREATE INDEX idx_material_consumption_wo_id ON material_consumption(wo_id);
CREATE INDEX idx_payment_allocations_invoice ON payment_allocations(invoice_id);
CREATE INDEX idx_payment_allocations_payment ON payment_allocations(payment_id);
CREATE INDEX idx_payments_customer_id ON payments(customer_id);
CREATE INDEX idx_payments_date ON payments(payment_date);
CREATE INDEX idx_periods_dates ON accounting_periods(start_date, end_date);
CREATE INDEX idx_periods_status ON accounting_periods(status);
CREATE INDEX idx_permissions_module ON permissions(module);
CREATE INDEX idx_physical_count_items_count ON physical_count_items(count_id);
CREATE INDEX idx_physical_count_items_item ON physical_count_items(item_id);
CREATE INDEX idx_physical_counts_date ON physical_counts(count_date);
CREATE INDEX idx_physical_counts_status ON physical_counts(status);
CREATE INDEX idx_physical_counts_warehouse ON physical_counts(warehouse_id);
CREATE INDEX idx_po_allocations_payment ON po_allocations(payment_id);
CREATE INDEX idx_po_allocations_po ON po_allocations(po_id);
CREATE INDEX idx_po_date ON purchase_orders(po_date);
CREATE INDEX idx_po_items_returned_quantity ON purchase_order_items(returned_quantity);
CREATE INDEX idx_po_status ON purchase_orders(status);
CREATE INDEX idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX idx_production_inputs_item ON production_inputs(item_id);
CREATE INDEX idx_production_inputs_production ON production_inputs(production_id);
CREATE INDEX idx_production_inputs_warehouse ON production_inputs(warehouse_id);
CREATE INDEX idx_productions_date ON productions(production_date);
CREATE INDEX idx_productions_output_item ON productions(output_item_id);
CREATE INDEX idx_productions_output_item_id ON productions(output_item_id);
CREATE INDEX idx_productions_production_no ON productions(production_no);
CREATE INDEX idx_productions_raw_materials_warehouse ON productions(raw_materials_warehouse_id);
CREATE INDEX idx_productions_warehouse ON productions(warehouse_id);
CREATE INDEX idx_purchase_order_items_po_id ON purchase_order_items(po_id);
CREATE INDEX idx_purchase_orders_supplier_id ON purchase_orders(supplier_id);
CREATE INDEX idx_purchases_date ON purchases(purchase_date);
CREATE INDEX idx_purchases_item ON purchases(item_id);
CREATE INDEX idx_purchases_purchase_no ON purchases(purchase_no);
CREATE INDEX idx_purchases_returned_quantity ON purchases(returned_quantity);
CREATE INDEX idx_purchases_supplier ON purchases(supplier_name);
CREATE INDEX idx_purchases_warehouse ON purchases(warehouse_id);
CREATE INDEX idx_quotation_items_item ON quotation_items(item_id);
CREATE INDEX idx_quotation_items_quotation ON quotation_items(quotation_id);
CREATE INDEX idx_quotations_customer ON quotations(customer_id);
CREATE INDEX idx_quotations_date ON quotations(quotation_date);
CREATE INDEX idx_quotations_expiry ON quotations(expiry_date);
CREATE INDEX idx_quotations_no ON quotations(quotation_no);
CREATE INDEX idx_quotations_status ON quotations(status);
CREATE INDEX idx_quotations_warehouse_id ON quotations(warehouse_id);
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_id);
CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);
CREATE INDEX idx_salary_payments_date ON salary_payments(payment_date);
CREATE INDEX idx_salary_payments_employee ON salary_payments(employee_id);
CREATE INDEX idx_sales_order_items_so_id ON sales_order_items(so_id);
CREATE INDEX idx_sales_orders_customer_id ON sales_orders(customer_id);
CREATE INDEX idx_sales_orders_source ON sales_orders(source_type, source_id);
CREATE INDEX idx_seasonal_events_category ON forecast_seasonal_events(applies_to_category);
CREATE INDEX idx_seasonal_events_dates ON forecast_seasonal_events(start_date, end_date);
CREATE INDEX idx_so_customer ON sales_orders(customer_id);
CREATE INDEX idx_so_date ON sales_orders(so_date);
CREATE INDEX idx_so_status ON sales_orders(status);
CREATE INDEX idx_stock_balances_item ON stock_balances(item_id);
CREATE INDEX idx_stock_balances_item_id ON stock_balances(item_id);
CREATE INDEX idx_stock_balances_item_warehouse ON stock_balances(item_id, warehouse_id);
CREATE INDEX idx_stock_balances_warehouse ON stock_balances(warehouse_id);
CREATE INDEX idx_stock_balances_warehouse_id ON stock_balances(warehouse_id);
CREATE INDEX idx_stock_batches_batch_no ON stock_batches(batch_no);
CREATE INDEX idx_stock_batches_item ON stock_batches(item_id, warehouse_id);
CREATE INDEX idx_stock_batches_source ON stock_batches(source_type, source_id);
CREATE INDEX idx_stock_movements_date ON stock_movements(movement_date);
CREATE INDEX idx_stock_movements_item ON stock_movements(item_id);
CREATE INDEX idx_stock_movements_item_id ON stock_movements(item_id);
CREATE INDEX idx_stock_movements_item_warehouse ON stock_movements(item_id, warehouse_id);
CREATE INDEX idx_stock_movements_return_ref ON stock_movements(reference_doctype, reference_docno);
CREATE INDEX idx_stock_movements_type ON stock_movements(movement_type);
CREATE INDEX idx_stock_movements_warehouse ON stock_movements(warehouse_id);
CREATE INDEX idx_stock_movements_warehouse_id ON stock_movements(warehouse_id);
CREATE INDEX idx_supplier_ledger_date ON supplier_ledger(transaction_date);
CREATE INDEX idx_supplier_ledger_reference ON supplier_ledger(reference_no);
CREATE INDEX idx_supplier_ledger_supplier ON supplier_ledger(supplier_id);
CREATE INDEX idx_supplier_ledger_type ON supplier_ledger(transaction_type);
CREATE INDEX idx_suppliers_code ON suppliers(supplier_code);
CREATE INDEX idx_suppliers_name ON suppliers(supplier_name);
CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_wo_item ON work_orders(finished_item_id);
CREATE INDEX idx_wo_status ON work_orders(status);
CREATE INDEX idx_work_orders_bom_id ON work_orders(bom_id);
CREATE INDEX idx_work_orders_finished_item_id ON work_orders(finished_item_id);

CREATE TRIGGER trg_employees_updated_at
AFTER UPDATE ON employees
FOR EACH ROW
BEGIN
    UPDATE employees SET updated_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;
CREATE TRIGGER trg_employee_documents_updated_at
AFTER UPDATE ON employee_documents
FOR EACH ROW
BEGIN
    UPDATE employee_documents SET updated_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;
