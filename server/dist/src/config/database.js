"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const bcrypt = __importStar(require("bcrypt"));
const logger_1 = __importDefault(require("../utils/logger"));
// Database file path - use DATABASE_PATH env var if set (Electron), otherwise default
const dbDir = process.env.DATABASE_PATH || path_1.default.join(__dirname, '../../../database');
const dbPath = path_1.default.join(dbDir, 'erp.db');
// Ensure database directory exists
if (!fs_1.default.existsSync(dbDir)) {
    fs_1.default.mkdirSync(dbDir, { recursive: true });
}
// Create database connection
const db = new better_sqlite3_1.default(dbPath, {
    verbose: process.env.NODE_ENV === 'development' ? (msg) => logger_1.default.debug(msg) : undefined
});
// Enable foreign keys
db.pragma('foreign_keys = ON');
// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');
// Performance + safety: balance durability vs speed
db.pragma('synchronous = NORMAL');
// Wait up to 5s instead of failing immediately when locked
db.pragma('busy_timeout = 5000');
// Initialize database with schema if tables don't exist
function initializeDatabase() {
    logger_1.default.info('Checking database initialization...');
    // Check if users table exists
    const tableCheck = db.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='users'
  `).get();
    if (!tableCheck) {
        logger_1.default.info('Database not initialized. Running migration...');
        const initSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/init.sql'), 'utf8');
        db.exec(initSQL);
        logger_1.default.info('✅ Database schema created successfully!');
        createDefaultUser();
        createDefaultWarehouse();
        seedDemoData();
        logger_1.default.info('✅ Database initialization complete!');
    }
    else {
        logger_1.default.info('✅ Database already initialized.');
    }
    runInvoiceMigration();
    runCustomerARMigrations();
}
function createDefaultUser() {
    const existingUser = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
    if (!existingUser) {
        let defaultPassword = process.env.DEFAULT_ADMIN_PASSWORD;
        if (!defaultPassword && process.env.NODE_ENV !== 'production') {
            // Development: no env var set, fall back to well-known dev credential
            logger_1.default.warn('⚠ WARNING: DEFAULT_ADMIN_PASSWORD not set. Using default development fallback (admin123). DO NOT USE IN PRODUCTION.');
            defaultPassword = 'admin123';
        }
        if (!defaultPassword) {
            throw new Error('FATAL: DEFAULT_ADMIN_PASSWORD environment variable must be set');
        }
        const passwordHash = bcrypt.hashSync(defaultPassword, 12);
        const stmt = db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
        stmt.run('admin', 'admin@minierp.local', passwordHash, 'Administrator', 'admin', 1);
        logger_1.default.info('✅ Default admin user created');
    }
}
function createDefaultWarehouse() {
    const existingWarehouse = db.prepare('SELECT id FROM warehouses WHERE warehouse_code = ?').get('WH-001');
    if (!existingWarehouse) {
        const stmt = db.prepare(`
      INSERT INTO warehouses (warehouse_code, warehouse_name, location, is_active)
      VALUES (?, ?, ?, ?)
    `);
        stmt.run('WH-001', 'Main Warehouse', 'Default Location', 1);
        logger_1.default.info('✅ Default warehouse created (WH-001)');
    }
}
// Seed a minimal demo dataset on a freshly created database so a new
// install has something to work with out of the box.
function seedDemoData() {
    try {
        const admin = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
        // Walk-in customer (default cash/POS customer)
        const existingCustomer = db.prepare('SELECT id FROM customers WHERE customer_code = ?').get('WALKIN');
        if (!existingCustomer) {
            db.prepare(`
        INSERT INTO customers (customer_code, customer_name, is_active)
        VALUES (?, ?, ?)
      `).run('WALKIN', 'Walkin Customer', 1);
            logger_1.default.info('✅ Demo customer created (Walkin Customer)');
        }
        // Demo supplier
        const existingSupplier = db.prepare('SELECT id FROM suppliers WHERE supplier_code = ?').get('DEMO-SUP');
        if (!existingSupplier) {
            db.prepare(`
        INSERT INTO suppliers (supplier_code, supplier_name, is_active)
        VALUES (?, ?, ?)
      `).run('DEMO-SUP', 'Demo supplier', 1);
            logger_1.default.info('✅ Demo supplier created (Demo supplier)');
        }
        // Demonstration product
        const existingItem = db.prepare('SELECT id FROM items WHERE item_code = ?').get('WIDGET-A');
        if (!existingItem) {
            db.prepare(`
        INSERT INTO items (
          item_code, item_name, category, unit_of_measure,
          standard_cost, standard_selling_price,
          is_purchased, is_finished_good, is_active, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run('WIDGET-A', 'Widget A', 'General', 'Nos', 0, 0, 1, 1, 1, admin?.id ?? null);
            logger_1.default.info('✅ Demo product created (Widget A)');
        }
    }
    catch (error) {
        logger_1.default.error('Demo seed data error:', error.message);
    }
}
function runInvoiceMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('invoices')
      WHERE name='discount_scope'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running invoice discount/tax migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-invoice-discount-tax-fields.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Invoice discount/tax migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Invoice migration error:', error.message);
    }
}
function runCustomerARMigrations() {
    try {
        const columnsToCheck = [
            { name: 'credit_limit', sql: 'ALTER TABLE customers ADD COLUMN credit_limit DECIMAL(15,2) DEFAULT 0' },
            { name: 'current_balance', sql: 'ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0' },
            { name: 'opening_balance', sql: 'ALTER TABLE customers ADD COLUMN opening_balance DECIMAL(15,2) DEFAULT 0' },
            { name: 'payment_terms_days', sql: 'ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 14' }
        ];
        for (const column of columnsToCheck) {
            const columnCheck = db.prepare(`
        SELECT COUNT(*) as count FROM pragma_table_info('customers')
        WHERE name=?
      `).get(column.name);
            if (!columnCheck || columnCheck.count === 0) {
                logger_1.default.info(`Adding missing column: ${column.name}...`);
                db.exec(column.sql);
                logger_1.default.info(`✅ Added ${column.name} column successfully!`);
            }
        }
        const ledgerTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='customer_ledger'
    `).get();
        if (!ledgerTableCheck) {
            logger_1.default.info('Running customer ledger migration...');
            const ledgerSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/create-customer-ledger.sql'), 'utf8');
            db.exec(ledgerSQL);
            logger_1.default.info('✅ Customer ledger migration completed!');
        }
        const allocationsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='payment_allocations'
    `).get();
        if (!allocationsTableCheck) {
            logger_1.default.info('Running payment allocations migration...');
            const allocationsSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/create-payment-allocations.sql'), 'utf8');
            db.exec(allocationsSQL);
            logger_1.default.info('✅ Payment allocations migration completed!');
        }
        logger_1.default.info('Ensuring customer_id values are integers...');
        db.exec(`
      UPDATE invoices SET customer_id = CAST(customer_id AS INTEGER) WHERE typeof(customer_id) = 'text';
      UPDATE payments SET customer_id = CAST(customer_id AS INTEGER) WHERE typeof(customer_id) = 'text';
    `);
        logger_1.default.info('✅ Customer ID type fix completed!');
        logger_1.default.info('Recalculating invoice balances from payment allocations...');
        // Cap returned_amount at total_amount to prevent over-returns
        db.exec(`UPDATE invoices SET returned_amount = total_amount WHERE returned_amount > total_amount AND total_amount > 0;`);
        db.exec(`
      UPDATE invoices SET
        paid_amount = COALESCE((
          SELECT SUM(pa.amount)
          FROM payment_allocations pa
          WHERE pa.invoice_id = invoices.id
        ), 0),
        balance_amount = MAX(0, total_amount - COALESCE((
          SELECT SUM(pa.amount)
          FROM payment_allocations pa
          WHERE pa.invoice_id = invoices.id
        ), 0) - COALESCE(returned_amount, 0) + COALESCE(return_fee, 0))
        `);
        db.exec(`
      UPDATE invoices SET status = 'Returned' WHERE returned_amount >= total_amount AND total_amount > 0;
      UPDATE invoices SET status = 'Partially Returned' WHERE returned_amount > 0 AND returned_amount < total_amount AND total_amount > 0;
      UPDATE invoices SET status = 'Paid' WHERE balance_amount <= 0 AND total_amount > 0 AND (returned_amount IS NULL OR returned_amount = 0);
      UPDATE invoices SET status = 'Partially Paid' WHERE balance_amount > 0 AND balance_amount < total_amount AND paid_amount > 0 AND (returned_amount IS NULL OR returned_amount = 0);
      UPDATE invoices SET status = 'Unpaid' WHERE (paid_amount = 0 OR paid_amount IS NULL) AND (returned_amount IS NULL OR returned_amount = 0) AND total_amount > 0;
    `);
        logger_1.default.info('✅ Invoice balance recalculation completed!');
        logger_1.default.info('Recalculating stock balances from movements...');
        const movementSums = db.prepare(`
      SELECT item_id, warehouse_id, SUM(quantity) as total_qty
      FROM stock_movements
      GROUP BY item_id, warehouse_id
    `).all();
        for (const sum of movementSums) {
            const existing = db.prepare('SELECT id, quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(sum.item_id, sum.warehouse_id);
            if (existing) {
                if (existing.quantity !== sum.total_qty) {
                    const item = db.prepare('SELECT item_code FROM items WHERE id = ?').get(sum.item_id);
                    const wh = db.prepare('SELECT warehouse_code FROM warehouses WHERE id = ?').get(sum.warehouse_id);
                    logger_1.default.info(`Fixing ${item?.item_code} in ${wh?.warehouse_code}: ${existing.quantity} -> ${sum.total_qty}`);
                    db.prepare('UPDATE stock_balances SET quantity = ?, last_updated = CURRENT_TIMESTAMP WHERE id = ?').run(sum.total_qty, existing.id);
                }
            }
            else {
                db.prepare('INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)').run(sum.item_id, sum.warehouse_id, sum.total_qty);
            }
        }
        const orphanedBalances = db.prepare(`
      SELECT sb.id, i.item_code, w.warehouse_code
      FROM stock_balances sb
      JOIN items i ON sb.item_id = i.id
      JOIN warehouses w ON sb.warehouse_id = w.id
      WHERE NOT EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.item_id = sb.item_id AND sm.warehouse_id = sb.warehouse_id
      )
    `).all();
        for (const orphan of orphanedBalances) {
            logger_1.default.info(`Removing orphaned balance: ${orphan.item_code} in ${orphan.warehouse_code}`);
            db.prepare('DELETE FROM stock_balances WHERE id = ?').run(orphan.id);
        }
        logger_1.default.info('✅ Stock balances recalculated from movements!');
        logger_1.default.info('Syncing item current_stock from stock_balances...');
        db.exec(`
      UPDATE items SET current_stock = (
        SELECT COALESCE(SUM(quantity), 0)
        FROM stock_balances
        WHERE stock_balances.item_id = items.id
      )
    `);
        logger_1.default.info('✅ Item stock synced from warehouse balances!');
        logger_1.default.info('Fixing payment ledger descriptions...');
        const paymentLedgerEntries = db.prepare(`
      SELECT cl.id, cl.reference_no, cl.description
      FROM customer_ledger cl
      WHERE cl.transaction_type = 'PAYMENT'
        AND cl.description LIKE 'Payment against %'
    `).all();
        for (const entry of paymentLedgerEntries) {
            const match = entry.description.match(/Payment against (.+)/);
            if (match) {
                const invoiceRefs = match[1].split(',').map((s) => s.trim());
                const invoiceNumbers = invoiceRefs.map((ref) => {
                    if (/[a-zA-Z]/.test(ref)) {
                        return ref;
                    }
                    const invoiceId = parseInt(ref, 10);
                    if (!isNaN(invoiceId)) {
                        const invoice = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId);
                        return invoice ? invoice.invoice_no : `Invoice #${invoiceId}`;
                    }
                    return ref;
                });
                const newDescription = `Payment against ${invoiceNumbers.join(', ')}`;
                if (newDescription !== entry.description) {
                    db.prepare('UPDATE customer_ledger SET description = ? WHERE id = ?').run(newDescription, entry.id);
                }
            }
        }
        logger_1.default.info('✅ Payment ledger descriptions fixed!');
    }
    catch (error) {
        logger_1.default.error('Customer AR migration error:', error.message);
    }
}
function runExpensesMigration() {
    try {
        const expensesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='expenses'
    `).get();
        if (!expensesTableCheck) {
            logger_1.default.info('Running expenses migration...');
            const expensesSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-expenses-table.sql'), 'utf8');
            db.exec(expensesSQL);
            logger_1.default.info('✅ Expenses migration completed!');
        }
        const categoriesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='expense_categories'
    `).get();
        if (!categoriesTableCheck) {
            logger_1.default.info('Running expense categories migration...');
            const categorySQL = `
        CREATE TABLE IF NOT EXISTS expense_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_name VARCHAR(100) UNIQUE NOT NULL,
          description TEXT,
          is_active BOOLEAN DEFAULT 1,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        INSERT OR IGNORE INTO expense_categories (category_name, description) VALUES
        ('Office Supplies', 'Stationery, printing, office materials'),
        ('Travel', 'Transportation, accommodation, meals during business travel'),
        ('Utilities', 'Electricity, water, internet, phone bills'),
        ('Rent', 'Office or warehouse rental expenses'),
        ('Salaries', 'Employee salaries and wages'),
        ('Marketing', 'Advertising, promotion, marketing expenses'),
        ('Maintenance', 'Equipment maintenance, repair costs'),
        ('Insurance', 'Business insurance premiums'),
        ('Taxes', 'Tax payments and fees'),
        ('Professional Services', 'Consulting, legal, accounting fees'),
        ('Training', 'Employee training and development'),
        ('Equipment', 'Purchase of equipment and tools'),
        ('Fuel', 'Fuel expenses for company vehicles'),
        ('Meals', 'Business meals and entertainment'),
        ('Other', 'Miscellaneous business expenses');
      `;
            db.exec(categorySQL);
            logger_1.default.info('✅ Expense categories migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Expenses migration error:', error.message);
    }
}
function runPurchasesMigration() {
    try {
        const purchasesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='purchases'
    `).get();
        if (!purchasesTableCheck) {
            logger_1.default.info('Running purchases migration...');
            const purchasesSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-purchases-table.sql'), 'utf8');
            db.exec(purchasesSQL);
            logger_1.default.info('✅ Purchases migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Purchases migration error:', error.message);
    }
}
function runPurchaseReturnMigration() {
    try {
        const hasReturnedQty = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('purchases')
      WHERE name='returned_quantity'
    `).get();
        if (hasReturnedQty.count === 0) {
            logger_1.default.info('Running purchase return fields migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-purchase-return-fields.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Purchase return fields migration completed!');
        }
        else {
            logger_1.default.info('✅ Purchase return fields already applied.');
        }
    }
    catch (error) {
        logger_1.default.error('Purchase return fields migration error:', error.message);
    }
}
function runProductionsMigration() {
    try {
        const productionsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='productions'
    `).get();
        if (!productionsTableCheck) {
            logger_1.default.info('Running productions migration...');
            const productionsSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-production-tables.sql'), 'utf8');
            db.exec(productionsSQL);
            logger_1.default.info('✅ Productions migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Productions migration error:', error.message);
    }
}
function runBOMMigration() {
    try {
        const bomTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='boms'
    `).get();
        if (!bomTableCheck) {
            logger_1.default.info('Running BOM migration...');
            const bomSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-bom-tables.sql'), 'utf8');
            db.exec(bomSQL);
            logger_1.default.info('✅ BOM migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('BOM migration error:', error.message);
    }
}
function runSalesMigration() {
    try {
        // Drop legacy sales table — POS and direct sales now use invoices+invoice_items
        db.exec(`DROP TABLE IF EXISTS sales`);
        // Check and run sales cycle migration (quotations & sales orders)
        const salesCycleCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='quotations'
    `).get();
        if (!salesCycleCheck) {
            logger_1.default.info('Running sales cycle migration (quotations & sales orders)...');
            try {
                // Create quotations table
                db.exec(`
          CREATE TABLE IF NOT EXISTS quotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            quotation_no VARCHAR(50) UNIQUE NOT NULL,
            customer_id INTEGER NOT NULL,
            customer_name VARCHAR(200),
            quotation_date DATE NOT NULL,
            expiry_date DATE,
            status VARCHAR(20) DEFAULT 'Draft',
            source_type VARCHAR(20),
            total_amount DECIMAL(15,2) DEFAULT 0,
            notes TEXT,
            terms TEXT,
            warehouse_id INTEGER,
            created_by INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `);
                // Create quotation_items table
                db.exec(`
          CREATE TABLE IF NOT EXISTS quotation_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            quotation_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            item_code VARCHAR(50),
            item_name VARCHAR(200),
            quantity DECIMAL(15,3) NOT NULL,
            unit_price DECIMAL(15,2) NOT NULL,
            discount_type VARCHAR(20) DEFAULT 'none',
            discount_value DECIMAL(15,2) DEFAULT 0,
            tax_rate DECIMAL(5,2) DEFAULT 0,
            amount DECIMAL(15,2) NOT NULL
          )
        `);
                // Add columns to existing tables if not exist
                try {
                    db.exec(`ALTER TABLE sales_orders ADD COLUMN source_type VARCHAR(20)`);
                }
                catch { }
                try {
                    db.exec(`ALTER TABLE sales_orders ADD COLUMN source_id INTEGER`);
                }
                catch { }
                try {
                    db.exec(`ALTER TABLE sales_orders ADD COLUMN customer_name VARCHAR(200)`);
                }
                catch { }
                try {
                    db.exec(`ALTER TABLE invoices ADD COLUMN source_type VARCHAR(20)`);
                }
                catch { }
                try {
                    db.exec(`ALTER TABLE invoices ADD COLUMN quotation_id INTEGER`);
                }
                catch { }
                try {
                    db.exec(`ALTER TABLE invoices ADD COLUMN customer_name VARCHAR(200)`);
                }
                catch { }
                logger_1.default.info('✅ Sales cycle migration completed!');
            }
            catch (migrationError) {
                logger_1.default.error('Sales cycle migration error:', String(migrationError));
            }
        }
    }
    catch (error) {
        logger_1.default.error('Sales migration error:', error.message);
    }
}
function runSupplierLedgerMigration() {
    try {
        const supplierLedgerTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='supplier_ledger'
    `).get();
        if (!supplierLedgerTableCheck) {
            logger_1.default.info('Running supplier ledger migration...');
            const supplierLedgerSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/create-supplier-ledger.sql'), 'utf8');
            db.exec(supplierLedgerSQL);
            logger_1.default.info('✅ Supplier ledger migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Supplier ledger migration error:', error.message);
    }
}
function runActivityLogMigration() {
    try {
        // Check if log_level column exists
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('activity_log')
      WHERE name='log_level'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running activity log enhancement migration...');
            // Add new columns
            db.exec(`ALTER TABLE activity_log ADD COLUMN log_level VARCHAR(20) DEFAULT 'INFO'`);
            db.exec(`ALTER TABLE activity_log ADD COLUMN ip_address VARCHAR(45)`);
            db.exec(`ALTER TABLE activity_log ADD COLUMN user_agent TEXT`);
            db.exec(`ALTER TABLE activity_log ADD COLUMN metadata TEXT`);
            db.exec(`ALTER TABLE activity_log ADD COLUMN duration_ms INTEGER`);
            // Create indexes
            db.exec(`CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON activity_log(created_at)`);
            db.exec(`CREATE INDEX IF NOT EXISTS idx_activity_log_user_created_at ON activity_log(user_id, created_at)`);
            db.exec(`CREATE INDEX IF NOT EXISTS idx_activity_log_entity_created_at ON activity_log(entity_type, entity_id, created_at)`);
            db.exec(`CREATE INDEX IF NOT EXISTS idx_activity_log_action ON activity_log(action)`);
            db.exec(`CREATE INDEX IF NOT EXISTS idx_activity_log_log_level ON activity_log(log_level)`);
            logger_1.default.info('✅ Activity log enhancement migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Activity log migration error:', error.message);
    }
}
function runSupplierPaymentMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('payments')
      WHERE name='supplier_id'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running supplier payment migration...');
            const supplierPaymentSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-supplier-payment-support.sql'), 'utf8');
            db.exec(supplierPaymentSQL);
            logger_1.default.info('✅ Supplier payment migration completed!');
        }
        // Rebuild payments if customer_id is still NOT NULL (partial state from
        // older versions of this migration).
        const notNullCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('payments')
      WHERE name='customer_id' AND "notnull"=1
    `).get();
        if (notNullCheck.count > 0) {
            logger_1.default.info('Making payments.customer_id nullable...');
            db.exec(`
        PRAGMA foreign_keys=OFF;
        BEGIN TRANSACTION;
        CREATE TABLE payments_new (
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
        INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at)
          SELECT id, payment_no, customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, created_by, created_at FROM payments;
        DROP TABLE payments;
        ALTER TABLE payments_new RENAME TO payments;
        CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);
        CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
        COMMIT;
        PRAGMA foreign_keys=ON;
      `);
            logger_1.default.info('✅ payments.customer_id is now nullable');
        }
    }
    catch (error) {
        logger_1.default.error('Supplier payment migration error:', error.message);
    }
}
function runSupplierBalanceMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('suppliers')
      WHERE name='current_balance'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Adding suppliers.current_balance column...');
            db.exec(`ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0`);
        }
        // Backfill from ledger balance where available (latest row = running balance;
        // MAX(balance) overstates after payments reduce the balance)
        db.exec(`
      UPDATE suppliers SET current_balance = (
        SELECT COALESCE(sl.balance, 0)
        FROM supplier_ledger sl
        WHERE sl.supplier_id = suppliers.id
        ORDER BY sl.id DESC
        LIMIT 1
      )
    `);
        logger_1.default.info('✅ Suppliers current_balance column ensured');
    }
    catch (error) {
        logger_1.default.error('Supplier balance migration error:', error.message);
    }
}
function runRawMaterialsWarehouseMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('productions')
      WHERE name='raw_materials_warehouse_id'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running raw materials warehouse migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-raw-materials-warehouse.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Raw materials warehouse migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Raw materials warehouse migration error:', error.message);
    }
}
function runProductionInputsWarehouseMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('production_inputs')
      WHERE name='warehouse_id'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running production inputs warehouse migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-warehouse-to-production-inputs.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Production inputs warehouse migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Production inputs warehouse migration error:', error.message);
    }
}
function runMobileInvoiceMigration() {
    try {
        const taxRatesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='tax_rates'
    `).get();
        if (!taxRatesTableCheck) {
            logger_1.default.info('Running mobile invoice tables migration...');
            const mobileInvoiceSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-mobile-invoice-tables.sql'), 'utf8');
            db.exec(mobileInvoiceSQL);
            logger_1.default.info('✅ Mobile invoice tables migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Mobile invoice migration error:', error.message);
    }
}
function runPerformanceIndexesMigration() {
    try {
        const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_items_category'
    `).get();
        if (indexCheck.count === 0) {
            logger_1.default.info('Running performance indexes migration...');
            const indexSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-performance-indexes.sql'), 'utf8');
            db.exec(indexSQL);
            logger_1.default.info('✅ Performance indexes migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Performance indexes migration error:', error.message);
    }
}
function runMissingIndexesMigration() {
    try {
        const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_payment_allocations_payment'
    `).get();
        if (indexCheck.count === 0) {
            logger_1.default.info('Running missing indexes migration...');
            const indexSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-missing-indexes.sql'), 'utf8');
            db.exec(indexSQL);
            logger_1.default.info('✅ Missing indexes migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Missing indexes migration error:', error.message);
    }
}
function runMissingFKIndexesMigration() {
    try {
        const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_invoices_so_id'
    `).get();
        if (indexCheck.count === 0) {
            logger_1.default.info('Running missing FK indexes migration...');
            const indexSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-missing-fk-indexes.sql'), 'utf8');
            db.exec(indexSQL);
            logger_1.default.info('✅ Missing FK indexes migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Missing FK indexes migration error:', error.message);
    }
}
initializeDatabase();
runExpensesMigration();
runPurchasesMigration();
runPurchaseReturnMigration();
runProductionsMigration();
runBOMMigration();
runSalesMigration();
runSupplierLedgerMigration();
runActivityLogMigration();
runSupplierPaymentMigration();
runSupplierBalanceMigration();
runRawMaterialsWarehouseMigration();
runProductionInputsWarehouseMigration();
runMobileInvoiceMigration();
runPerformanceIndexesMigration();
runMissingIndexesMigration();
runMissingFKIndexesMigration();
runProductionOverheadMigration();
runProductionBOMIdMigration();
runRolesPermissionsMigration();
runStockAdjustmentFinancialMigration();
runForecastsMigration();
runMissingFKIndexesMigration();
runBatchCostingMigration();
runGLFoundationMigration();
runSalaryPaymentsMigration();
runCreditBalanceMigration();
runEmployeesMigration();
runPhysicalCountsMigration();
runForecastEnhancementsMigration();
runCustomReportsMigration();
runDashboardLayoutsMigration();
runLooseItemMigration();
runCashAccountsMigration();
runOpeningBalancesMigration();
runUserPreferencesMigration();
// Rollback support: run if --rollback flag is passed
if (process.argv.includes('--rollback')) {
    const targetMigration = process.argv.find(arg => arg.startsWith('--rollback='));
    if (targetMigration) {
        const migrationName = targetMigration.split('=')[1];
        runRollback(migrationName);
    }
    else {
        runRollbackAll();
    }
}
exports.default = db;
function runProductionBOMIdMigration() {
    try {
        const hasBOMId = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='bom_id'`).get();
        if (!hasBOMId.count) {
            logger_1.default.info('Running production bom_id migration...');
            db.prepare(`ALTER TABLE productions ADD COLUMN bom_id INTEGER REFERENCES boms(id)`).run();
            logger_1.default.info('✅ Production bom_id migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Production bom_id migration error:', error.message);
    }
}
function runProductionOverheadMigration() {
    try {
        const hasOverheadCost = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='overhead_cost'`).get();
        if (!hasOverheadCost.count) {
            logger_1.default.info('Running production overhead_cost migration...');
            db.prepare(`ALTER TABLE productions ADD COLUMN overhead_cost DECIMAL(15,2) DEFAULT 0`).run();
            logger_1.default.info('✅ Production overhead_cost migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Production overhead migration error:', error.message);
    }
}
function runRolesPermissionsMigration() {
    try {
        const rolesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='roles'
    `).get();
        if (!rolesTableCheck) {
            logger_1.default.info('Running roles and permissions migration...');
            const rolesPermissionsSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-roles-permissions.sql'), 'utf8');
            db.exec(rolesPermissionsSQL);
            logger_1.default.info('✅ Roles and permissions migration completed!');
        }
        // Always seed — backfills missing permissions for existing databases
        seedDefaultPermissions();
    }
    catch (error) {
        logger_1.default.error('Roles and permissions migration error:', error.message);
    }
}
function seedDefaultPermissions() {
    try {
        logger_1.default.info('Seeding default permissions...');
        // Define all permissions by module
        const permissions = [
            // Dashboard
            { name: 'dashboard:read', module: 'dashboard', action: 'read', description: 'View dashboard' },
            { name: 'dashboard_layouts:read', module: 'dashboard', action: 'read', description: 'View dashboard layouts' },
            { name: 'dashboard_layouts:create', module: 'dashboard', action: 'create', description: 'Create dashboard layouts' },
            { name: 'dashboard_layouts:update', module: 'dashboard', action: 'update', description: 'Update dashboard layouts' },
            { name: 'dashboard_layouts:delete', module: 'dashboard', action: 'delete', description: 'Delete dashboard layouts' },
            // Users
            { name: 'users:read', module: 'users', action: 'read', description: 'View users' },
            { name: 'users:create', module: 'users', action: 'create', description: 'Create users' },
            { name: 'users:update', module: 'users', action: 'update', description: 'Update users' },
            { name: 'users:delete', module: 'users', action: 'delete', description: 'Delete users' },
            // Inventory
            { name: 'inventory:read', module: 'inventory', action: 'read', description: 'View inventory' },
            { name: 'inventory:create', module: 'inventory', action: 'create', description: 'Create inventory items' },
            { name: 'inventory:update', module: 'inventory', action: 'update', description: 'Update inventory items' },
            { name: 'inventory:delete', module: 'inventory', action: 'delete', description: 'Delete inventory items' },
            // Customers
            { name: 'customers:read', module: 'customers', action: 'read', description: 'View customers' },
            { name: 'customers:create', module: 'customers', action: 'create', description: 'Create customers' },
            { name: 'customers:update', module: 'customers', action: 'update', description: 'Update customers' },
            { name: 'customers:delete', module: 'customers', action: 'delete', description: 'Delete customers' },
            // Suppliers
            { name: 'suppliers:read', module: 'suppliers', action: 'read', description: 'View suppliers' },
            { name: 'suppliers:create', module: 'suppliers', action: 'create', description: 'Create suppliers' },
            { name: 'suppliers:update', module: 'suppliers', action: 'update', description: 'Update suppliers' },
            { name: 'suppliers:delete', module: 'suppliers', action: 'delete', description: 'Delete suppliers' },
            // Sales
            { name: 'sales:read', module: 'sales', action: 'read', description: 'View sales' },
            { name: 'sales:create', module: 'sales', action: 'create', description: 'Create sales' },
            { name: 'sales:update', module: 'sales', action: 'update', description: 'Update sales' },
            { name: 'sales:delete', module: 'sales', action: 'delete', description: 'Delete sales' },
            // Sales Orders
            { name: 'sales_orders:read', module: 'sales_orders', action: 'read', description: 'View sales orders' },
            { name: 'sales_orders:create', module: 'sales_orders', action: 'create', description: 'Create sales orders' },
            { name: 'sales_orders:update', module: 'sales_orders', action: 'update', description: 'Update sales orders' },
            { name: 'sales_orders:delete', module: 'sales_orders', action: 'delete', description: 'Delete sales orders' },
            // Quotations
            { name: 'quotations:read', module: 'quotations', action: 'read', description: 'View quotations' },
            { name: 'quotations:create', module: 'quotations', action: 'create', description: 'Create quotations' },
            { name: 'quotations:update', module: 'quotations', action: 'update', description: 'Update quotations' },
            { name: 'quotations:delete', module: 'quotations', action: 'delete', description: 'Delete quotations' },
            // Invoices
            { name: 'invoices:read', module: 'invoices', action: 'read', description: 'View invoices' },
            { name: 'invoices:create', module: 'invoices', action: 'create', description: 'Create invoices' },
            { name: 'invoices:update', module: 'invoices', action: 'update', description: 'Update invoices' },
            { name: 'invoices:delete', module: 'invoices', action: 'delete', description: 'Delete invoices' },
            // Payments
            { name: 'payments:read', module: 'payments', action: 'read', description: 'View payments' },
            { name: 'payments:create', module: 'payments', action: 'create', description: 'Create payments' },
            { name: 'payments:update', module: 'payments', action: 'update', description: 'Update payments' },
            { name: 'payments:delete', module: 'payments', action: 'delete', description: 'Delete payments' },
            // Purchases
            { name: 'purchases:read', module: 'purchases', action: 'read', description: 'View purchases' },
            { name: 'purchases:create', module: 'purchases', action: 'create', description: 'Create purchases' },
            { name: 'purchases:update', module: 'purchases', action: 'update', description: 'Update purchases' },
            { name: 'purchases:delete', module: 'purchases', action: 'delete', description: 'Delete purchases' },
            // Purchase Orders
            { name: 'purchase_orders:read', module: 'purchase_orders', action: 'read', description: 'View purchase orders' },
            { name: 'purchase_orders:create', module: 'purchase_orders', action: 'create', description: 'Create purchase orders' },
            { name: 'purchase_orders:update', module: 'purchase_orders', action: 'update', description: 'Update purchase orders' },
            { name: 'purchase_orders:delete', module: 'purchase_orders', action: 'delete', description: 'Delete purchase orders' },
            // Expenses
            { name: 'expenses:read', module: 'expenses', action: 'read', description: 'View expenses' },
            { name: 'expenses:create', module: 'expenses', action: 'create', description: 'Create expenses' },
            { name: 'expenses:update', module: 'expenses', action: 'update', description: 'Update expenses' },
            { name: 'expenses:delete', module: 'expenses', action: 'delete', description: 'Delete expenses' },
            // Production
            { name: 'production:read', module: 'production', action: 'read', description: 'View production' },
            { name: 'production:create', module: 'production', action: 'create', description: 'Create production' },
            { name: 'production:update', module: 'production', action: 'update', description: 'Update production' },
            { name: 'production:delete', module: 'production', action: 'delete', description: 'Delete production' },
            // Bill of Materials (BOM)
            { name: 'bom:read', module: 'bom', action: 'read', description: 'View BOMs' },
            { name: 'bom:create', module: 'bom', action: 'create', description: 'Create BOMs' },
            { name: 'bom:update', module: 'bom', action: 'update', description: 'Update BOMs' },
            { name: 'bom:delete', module: 'bom', action: 'delete', description: 'Delete BOMs' },
            // Reports
            { name: 'reports:read', module: 'reports', action: 'read', description: 'View reports' },
            // Settings
            { name: 'settings:read', module: 'settings', action: 'read', description: 'View settings' },
            { name: 'settings:update', module: 'settings', action: 'update', description: 'Update settings' },
            // Roles & Permissions
            { name: 'roles:read', module: 'roles', action: 'read', description: 'View roles' },
            { name: 'roles:create', module: 'roles', action: 'create', description: 'Create roles' },
            { name: 'roles:update', module: 'roles', action: 'update', description: 'Update roles' },
            { name: 'roles:delete', module: 'roles', action: 'delete', description: 'Delete roles' },
            // Employees
            { name: 'employees:read', module: 'employees', action: 'read', description: 'View employees' },
            { name: 'employees:create', module: 'employees', action: 'create', description: 'Create employees' },
            { name: 'employees:update', module: 'employees', action: 'update', description: 'Update employees' },
            { name: 'employees:delete', module: 'employees', action: 'delete', description: 'Delete employees' },
            // Forecasts
            { name: 'forecasts:read', module: 'forecasts', action: 'read', description: 'View forecasts' },
            { name: 'forecasts:create', module: 'forecasts', action: 'create', description: 'Generate forecasts' },
            // Point of Sale (POS)
            { name: 'pos:read', module: 'pos', action: 'read', description: 'View POS transactions' },
            { name: 'pos:create', module: 'pos', action: 'create', description: 'Create POS sales' },
            // Activity Log
            { name: 'activity_log:read', module: 'activity_log', action: 'read', description: 'View activity logs' },
            // Integrations
            { name: 'integrations:read', module: 'integrations', action: 'read', description: 'View integration settings' },
            { name: 'integrations:update', module: 'integrations', action: 'update', description: 'Update integration settings' },
            // Accounting
            { name: 'accounting:read', module: 'accounting', action: 'read', description: 'View accounting data' },
        ];
        // Insert permissions
        for (const perm of permissions) {
            db.prepare(`
        INSERT OR IGNORE INTO permissions (permission_name, module, action, description)
        VALUES (?, ?, ?, ?)
      `).run(perm.name, perm.module, perm.action, perm.description);
        }
        // Assign all permissions to Admin role
        const adminRole = db.prepare('SELECT id FROM roles WHERE role_name = ?').get('Admin');
        const allPermissions = db.prepare('SELECT id FROM permissions').all();
        for (const perm of allPermissions) {
            db.prepare(`
        INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
        VALUES (?, ?)
      `).run(adminRole.id, perm.id);
        }
        // Assign read-only permissions to User role
        const userRole = db.prepare('SELECT id FROM roles WHERE role_name = ?').get('User');
        const readPermissions = db.prepare(`
      SELECT id FROM permissions WHERE action = 'read'
      AND module NOT IN ('roles', 'settings')
    `).all();
        for (const perm of readPermissions) {
            db.prepare(`
        INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
        VALUES (?, ?)
      `).run(userRole.id, perm.id);
        }
        logger_1.default.info('✅ Default permissions seeded successfully!');
    }
    catch (error) {
        logger_1.default.error('Seed default permissions error:', error.message);
    }
}
function runStockAdjustmentFinancialMigration() {
    try {
        // Step 1: Ensure journal_entries table exists (must be created before FK reference)
        const hasJournalTable = db.prepare(`SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='journal_entries'`).get();
        if (hasJournalTable.count === 0) {
            logger_1.default.info('Creating journal_entries table...');
            db.exec(`
        CREATE TABLE IF NOT EXISTS journal_entries (
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
        CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON journal_entries(reference_type, reference_id);
        CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date);
        CREATE INDEX IF NOT EXISTS idx_journal_entries_accounts ON journal_entries(debit_account, credit_account, voided);
      `);
            logger_1.default.info('journal_entries table created');
        }
        // Step 2: Add stock_movements columns if missing
        const hasFinancialValue = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='financial_value'`).get();
        if (hasFinancialValue.count === 0) {
            logger_1.default.info('Adding financial columns to stock_movements...');
            db.exec(`
        ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0;
        ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE;
        ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id);
      `);
            logger_1.default.info('Financial columns added to stock_movements');
        }
        else {
            // Recovery: Check for missing journal_entry_id column (partial migration fix)
            const hasJournalEntryId = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='journal_entry_id'`).get();
            if (hasJournalEntryId.count === 0) {
                logger_1.default.info('Adding missing journal_entry_id column...');
                db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
                logger_1.default.info('journal_entry_id column added');
            }
        }
    }
    catch (error) {
        logger_1.default.error('Stock adjustment financial migration error:', error.message);
    }
}
function runGLFoundationMigration() {
    // Phase 1 of the GL refactor: chart_of_accounts, journal_lines,
    // and accounting_periods. See migrations/add-gl-foundation.sql for
    // schema and seed. The auto-open period is also handled in the SQL.
    try {
        const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-gl-foundation.sql'), 'utf8');
        db.exec(migrationSQL);
        logger_1.default.info('✅ GL foundation migration applied (chart_of_accounts, journal_lines, accounting_periods)');
    }
    catch (error) {
        logger_1.default.error('GL foundation migration error:', error.message);
    }
    // Add returned_amount column to invoices (idempotent – added in v3.1)
    try {
        const hasReturnedAmt = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('invoices') WHERE name='returned_amount'`).get();
        if (hasReturnedAmt.count === 0) {
            db.exec("ALTER TABLE invoices ADD COLUMN returned_amount DECIMAL(15,2) NOT NULL DEFAULT 0");
            logger_1.default.info('✅ returned_amount column added to invoices');
        }
    }
    catch (error) {
        logger_1.default.error('returned_amount migration error:', error.message);
    }
    // Add return_fee column to invoices (idempotent — restocking fee tracking)
    try {
        const hasReturnFee = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('invoices') WHERE name='return_fee'`).get();
        if (hasReturnFee.count === 0) {
            db.exec("ALTER TABLE invoices ADD COLUMN return_fee DECIMAL(15,2) NOT NULL DEFAULT 0");
            logger_1.default.info('✅ return_fee column added to invoices');
        }
    }
    catch (error) {
        logger_1.default.error('return_fee migration error:', error.message);
    }
    // Add returned_qty column to invoice_items (per-item return tracking)
    try {
        const hasReturnedQty = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('invoice_items') WHERE name='returned_qty'`).get();
        if (hasReturnedQty.count === 0) {
            db.exec("ALTER TABLE invoice_items ADD COLUMN returned_qty DECIMAL(15,3) NOT NULL DEFAULT 0");
            logger_1.default.info('✅ returned_qty column added to invoice_items');
        }
    }
    catch (error) {
        logger_1.default.error('returned_qty migration error:', error.message);
    }
}
function runBatchCostingMigration() {
    try {
        // Step 1: Create stock_batches table (if not exists)
        const stockBatchesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='stock_batches'
    `).get();
        if (!stockBatchesTableCheck) {
            logger_1.default.info('Running batch costing migration...');
            const batchSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-batch-costing.sql'), 'utf8');
            db.exec(batchSQL);
            logger_1.default.info('✅ stock_batches table created!');
        }
        // Step 2: Add batch_id column to stock_movements
        const smBatchIdCheck = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='batch_id'`).get();
        if (!smBatchIdCheck.count) {
            logger_1.default.info('Adding batch_id to stock_movements...');
            db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
            logger_1.default.info('✅ batch_id added to stock_movements');
        }
        // Step 3: Add batch columns to productions
        const prodBatchIdCheck = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='batch_id'`).get();
        if (!prodBatchIdCheck.count) {
            logger_1.default.info('Adding batch columns to productions...');
            db.exec('ALTER TABLE productions ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
            db.exec('ALTER TABLE productions ADD COLUMN batch_no VARCHAR(50)');
            db.exec('ALTER TABLE productions ADD COLUMN unit_cost DECIMAL(15,4) DEFAULT 0');
            db.exec('ALTER TABLE productions ADD COLUMN total_material_cost DECIMAL(15,4) DEFAULT 0');
            db.exec('ALTER TABLE productions ADD COLUMN total_batch_cost DECIMAL(15,4) DEFAULT 0');
            logger_1.default.info('✅ Batch columns added to productions');
        }
        // Step 4: Add batch columns to purchases
        const purchBatchIdCheck = db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('purchases') WHERE name='batch_id'`).get();
        if (!purchBatchIdCheck.count) {
            logger_1.default.info('Adding batch columns to purchases...');
            db.exec('ALTER TABLE purchases ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
            db.exec('ALTER TABLE purchases ADD COLUMN batch_no VARCHAR(50)');
            logger_1.default.info('✅ Batch columns added to purchases');
        }
        logger_1.default.info('✅ Batch costing migration completed!');
    }
    catch (error) {
        logger_1.default.error('Batch costing migration error:', error.message);
    }
}
function runCreditBalanceMigration() {
    try {
        const hasCreditBalance = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('customers')
      WHERE name='credit_balance'
    `).get();
        if (hasCreditBalance.count === 0) {
            logger_1.default.info('Running credit balance migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-credit-balance.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Credit balance column added to customers table!');
        }
    }
    catch (error) {
        logger_1.default.error('Credit balance migration error:', error.message);
    }
}
function runForecastsMigration() {
    try {
        const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='demand_forecasts'
    `).get();
        if (!tableCheck) {
            logger_1.default.info('Running demand forecasts migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-demand-forecasts.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Demand forecasts migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Demand forecasts migration error:', error.message);
    }
}
function runEmployeesMigration() {
    try {
        const employeesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='employees'
    `).get();
        if (!employeesTableCheck) {
            logger_1.default.info('Running employees migration...');
            const employeesSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../../migrations/add-employees-table.sql'), 'utf8');
            db.exec(employeesSQL);
            logger_1.default.info('✅ Employees migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Employees migration error:', error.message);
    }
}
function runSalaryPaymentsMigration() {
    try {
        const salaryTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='salary_payments'
    `).get();
        if (!salaryTableCheck) {
            logger_1.default.info('Running salary payments migration...');
            const salarySQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-salary-payments.sql'), 'utf8');
            db.exec(salarySQL);
            logger_1.default.info('✅ Salary payments migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Salary payments migration error:', error.message);
    }
}
function runPhysicalCountsMigration() {
    try {
        const physicalCountsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='physical_counts'
    `).get();
        if (!physicalCountsTableCheck) {
            logger_1.default.info('Running physical counts migration...');
            const physicalCountsSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-physical-counts.sql'), 'utf8');
            db.exec(physicalCountsSQL);
            logger_1.default.info('✅ Physical counts migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Physical counts migration error:', error.message);
    }
}
function runCustomReportsMigration() {
    try {
        const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='custom_reports'
    `).get();
        if (!tableCheck) {
            logger_1.default.info('Running custom reports migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-custom-reports.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Custom reports migration completed!');
            // Seed 5 report templates
            seedReportTemplates();
        }
    }
    catch (error) {
        logger_1.default.error('Custom reports migration error:', error.message);
    }
}
function seedReportTemplates() {
    try {
        logger_1.default.info('Seeding report templates...');
        const templates = [
            {
                name: 'Sales Summary',
                description: 'Invoice sales grouped by month with totals',
                config: {
                    entity: 'invoices',
                    columns: [
                        { field: 'invoice_date', alias: 'Date' },
                        { field: 'invoice_no', alias: 'Invoice #' },
                        { field: 'customer_name', alias: 'Customer' },
                        { field: 'total_amount', alias: 'Total' },
                        { field: 'status', alias: 'Status' },
                    ],
                    filters: [],
                    sort: [{ field: 'invoice_date', direction: 'desc' }],
                },
            },
            {
                name: 'Inventory Status',
                description: 'Current stock levels with items below reorder level highlighted',
                config: {
                    entity: 'items',
                    columns: [
                        { field: 'item_code', alias: 'Code' },
                        { field: 'item_name', alias: 'Item' },
                        { field: 'category', alias: 'Category' },
                        { field: 'current_stock', alias: 'Stock' },
                        { field: 'reorder_level', alias: 'Min Stock' },
                    ],
                    filters: [],
                    sort: [{ field: 'current_stock', direction: 'asc' }],
                },
            },
            {
                name: 'Customer Aging',
                description: 'Outstanding invoices by customer with aging',
                config: {
                    entity: 'invoices',
                    columns: [
                        { field: 'customer_name', alias: 'Customer' },
                        { field: 'invoice_no', alias: 'Invoice' },
                        { field: 'due_date', alias: 'Due Date' },
                        { field: 'balance_amount', alias: 'Balance' },
                        { field: 'status', alias: 'Status' },
                    ],
                    filters: [
                        {
                            field: 'status',
                            operator: 'in_list',
                            value: ['Unpaid', 'Overdue', 'Partially Paid'],
                        },
                    ],
                    sort: [{ field: 'due_date', direction: 'asc' }],
                },
            },
            {
                name: 'Top Customers',
                description: 'Customers ranked by total invoice amount',
                config: {
                    entity: 'invoices',
                    columns: [
                        { field: 'customer_name', alias: 'Customer' },
                    ],
                    computedColumns: [
                        { name: 'total_invoiced', expression: 'SUM(total_amount)', type: 'number' },
                        { name: 'invoice_count', expression: 'COUNT(id)', type: 'number' },
                    ],
                    groupBy: { enabled: true, fields: ['customer_name'] },
                    sort: [{ field: 'total_invoiced', direction: 'desc' }],
                    filters: [
                        { field: 'status', operator: 'not_equals', value: 'Cancelled' },
                    ],
                },
            },
            {
                name: 'Stock Valuation',
                description: 'Inventory value calculated from stock × cost',
                config: {
                    entity: 'items',
                    columns: [
                        { field: 'item_code', alias: 'Code' },
                        { field: 'item_name', alias: 'Item' },
                        { field: 'category', alias: 'Category' },
                        { field: 'current_stock', alias: 'Qty' },
                        { field: 'standard_cost', alias: 'Unit Cost' },
                    ],
                    computedColumns: [
                        { name: 'stock_value', expression: 'ROUND(current_stock * standard_cost, 2)', type: 'number' },
                    ],
                    filters: [],
                    sort: [{ field: 'stock_value', direction: 'desc' }],
                },
            },
        ];
        const insert = db.prepare(`
      INSERT OR IGNORE INTO custom_reports (user_id, name, description, config)
      VALUES (0, ?, ?, ?)
    `);
        for (const t of templates) {
            insert.run(t.name, t.description, JSON.stringify(t.config));
        }
        logger_1.default.info('✅ Report templates seeded!');
    }
    catch (error) {
        logger_1.default.error('Seed report templates error:', error.message);
    }
}
function runForecastEnhancementsMigration() {
    try {
        // Check if forecast_model_config table exists — if so, migration already ran
        const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='forecast_model_config'
    `).get();
        if (!tableCheck) {
            logger_1.default.info('Running forecast enhancements migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/enhance-forecasts.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Forecast enhancements migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Forecast enhancements migration error:', error.message);
    }
}
function runDashboardLayoutsMigration() {
    try {
        const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='dashboard_layouts'
    `).get();
        if (!tableCheck) {
            logger_1.default.info('Running dashboard layouts migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/dashboard-layouts.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Dashboard layouts migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Dashboard layouts migration error:', error.message);
    }
}
function runCashAccountsMigration() {
    // Idempotent by construction (INSERT OR IGNORE + CREATE IF NOT EXISTS
    // in the SQL), so it runs on every server start like the GL foundation
    // migration — no column/table pre-check needed.
    try {
        const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-cash-accounts.sql'), 'utf8');
        db.exec(migrationSQL);
        logger_1.default.info('✅ Cash accounts migration applied (Easypaisa/JazzCash/UPaisa accounts + cash_reconciliations)');
    }
    catch (error) {
        logger_1.default.error('Cash accounts migration error:', error.message);
    }
}
function runOpeningBalancesMigration() {
    // Idempotent (CREATE IF NOT EXISTS + INSERT OR IGNORE) — runs on every
    // server start so the seed rows exist before any cash computation.
    try {
        const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-opening-balances.sql'), 'utf8');
        db.exec(migrationSQL);
        logger_1.default.info('✅ Opening balances migration applied (per-account seed balances)');
    }
    catch (error) {
        logger_1.default.error('Opening balances migration error:', error.message);
    }
}
function runLooseItemMigration() {
    try {
        const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('items')
      WHERE name='sale_type'
    `).get();
        if (columnCheck.count === 0) {
            logger_1.default.info('Running loose item support migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-loose-item-support.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ Loose item support migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('Loose item support migration error:', error.message);
    }
}
function runUserPreferencesMigration() {
    // Per-user date-range picker preferences (week start, default range,
    // custom presets) — date-range-picker-spec.md §6.1.
    try {
        const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='user_preferences'
    `).get();
        if (!tableCheck) {
            logger_1.default.info('Running user preferences migration...');
            const migrationSQL = fs_1.default.readFileSync(path_1.default.join(__dirname, '../migrations/add-user-preferences.sql'), 'utf8');
            db.exec(migrationSQL);
            logger_1.default.info('✅ User preferences migration completed!');
        }
    }
    catch (error) {
        logger_1.default.error('User preferences migration error:', error.message);
    }
}
function runRollback(migrationName) {
    const rollbackFile = path_1.default.join(__dirname, '../migrations/rollbacks/rollback-' + migrationName + '.sql');
    if (!fs_1.default.existsSync(rollbackFile)) {
        logger_1.default.error(`Rollback file not found: ${rollbackFile}`);
        process.exit(1);
    }
    logger_1.default.info(`Running rollback for migration: ${migrationName}`);
    try {
        const rollbackSQL = fs_1.default.readFileSync(rollbackFile, 'utf8');
        db.exec(rollbackSQL);
        logger_1.default.info(`✅ Rollback completed for: ${migrationName}`);
    }
    catch (error) {
        logger_1.default.error(`Rollback error for ${migrationName}:`, error.message);
        process.exit(1);
    }
}
function runRollbackAll() {
    const rollbacksDir = path_1.default.join(__dirname, '../migrations/rollbacks');
    if (!fs_1.default.existsSync(rollbacksDir)) {
        logger_1.default.error('Rollbacks directory not found');
        process.exit(1);
    }
    const files = fs_1.default.readdirSync(rollbacksDir).filter(f => f.endsWith('.sql')).sort().reverse();
    logger_1.default.info(`Running ${files.length} rollbacks in reverse order...`);
    for (const file of files) {
        const migrationName = file.replace('rollback-', '').replace('.sql', '');
        logger_1.default.info(`Rolling back: ${migrationName}`);
        try {
            const rollbackSQL = fs_1.default.readFileSync(path_1.default.join(rollbacksDir, file), 'utf8');
            db.exec(rollbackSQL);
            logger_1.default.info(`✅ Rolled back: ${migrationName}`);
        }
        catch (error) {
            logger_1.default.error(`Rollback error for ${migrationName}:`, error.message);
        }
    }
    logger_1.default.info('✅ All rollbacks completed');
}
//# sourceMappingURL=database.js.map