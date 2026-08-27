import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import * as bcrypt from 'bcrypt';
import logger from '../utils/logger';
import { getNextSequenceNumber } from '../utils/sequence';
import { backfillPurchaseReturns } from '../utils/purchaseReturnBackfill';
import { runBackfillGlPreposting } from '../migrations/backfillGlPreposting';
import { runBackfillInvoiceItemTax } from '../migrations/backfillInvoiceItemTax';

// Fail-closed: tests must never fall through to a shared dev DB by accident
if (process.env.NODE_ENV === 'test' && !process.env.DATABASE_PATH) {
  throw new Error('FATAL: NODE_ENV=test requires DATABASE_PATH to be set (use :memory: or a temp file). Refusing to open a default database.');
}

// Database file path - use DATABASE_PATH env var if set (Electron), otherwise default
const dbDir = process.env.DATABASE_PATH || path.join(__dirname, '../../../database');
const dbPath = path.join(dbDir, 'erp.db');

// Ensure database directory exists
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

// Create database connection
const db = new Database(dbPath, {
  verbose: process.env.NODE_ENV === 'development' ? (msg: string) => logger.debug(msg) : undefined
});

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');

// Performance + safety: balance durability vs speed
db.pragma('synchronous = NORMAL');

// Wait up to 5s instead of failing immediately when locked
db.pragma('busy_timeout = 5000');

// Query cache 16MB; checkpoint WAL every ~400 pages so WAL stays bounded
db.pragma('cache_size = -16000');
db.pragma('wal_autocheckpoint = 400');

// Guarded ALTER helper - replaces silent try/catch{} pattern
function columnExists(table: string, column: string): boolean {
  const cols = db.pragma(`table_info('${table}')`) as Array<{ name: string }>;
  return cols.some((c) => c.name === column);
}
function addColumnIfMissing(table: string, columnDef: string): void {
  const column = columnDef.trim().split(/\s+/)[0];
  if (!columnExists(table, column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${columnDef}`);
  }
}

// ── Migration ledger (schema_migrations) ──────────────────────────────
// Single canonical migrations path; resolves under ts-node (src/config/..)
// and dist (dist/src/config/..).
const MIGRATIONS_DIR = path.resolve(__dirname, '../migrations');

function ensureMigrationsTable(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL,
      checksum TEXT NOT NULL
    )
  `);
}

function fileChecksum(filename: string): string {
  try {
    return crypto.createHash('sha256').update(fs.readFileSync(path.join(MIGRATIONS_DIR, filename))).digest('hex').slice(0, 16);
  } catch {
    return 'inline';
  }
}

/**
 * Ledger runner: skip if recorded; otherwise execute body inside a
 * transaction, record with checksum on success. Any failure aborts the
 * process non-zero BEFORE HTTP listen.
 */
function runLedgered(key: string, fn?: () => void, opts?: { noTxn?: boolean }): void {
  ensureMigrationsTable();
  if (db.prepare('SELECT 1 FROM schema_migrations WHERE filename = ?').get(key)) return;
  const checksum = fileChecksum(key);
  try {
    if (fn) {
      if (opts?.noTxn) {
        // Body manages its own transaction/pragma scope (e.g. FK-off table rebuild)
        fn();
      } else {
        db.transaction(fn)();
      }
    } else {
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, key), 'utf8');
      if (opts?.noTxn) {
        // Table-rebuild migrations need foreign_keys OFF during their DROP
        // (with it ON, dropping `payments` cascades the allocation tables —
        // the PAY-06 data-loss class). PRAGMA is a no-op inside a txn, so
        // these run outside one; the file manages its own transaction.
        db.pragma('foreign_keys = OFF');
        try {
          db.exec(sql);
          db.exec("INSERT INTO schema_migrations (filename, applied_at, checksum) VALUES ('" +
            key.replace(/'/g, "''") + "', '" + new Date().toISOString() + "', '" + checksum + "')");
        } finally {
          db.pragma('foreign_keys = ON');
        }
        if ((db.pragma('foreign_keys', { simple: true }) as number) !== 1) {
          throw new Error(`FATAL: migration '${key}' failed to restore foreign_keys=ON`);
        }
        const n = (db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n;
        db.pragma(`user_version = ${n}`);
        logger.info(`✅ migration applied: ${key} (noTxn)`);
        return;
      }
      db.transaction(() => db.exec(sql))();
    }
    db.prepare('INSERT INTO schema_migrations (filename, applied_at, checksum) VALUES (?, ?, ?)')
      .run(key, new Date().toISOString(), checksum);
    const n = (db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get() as { n: number }).n;
    db.pragma(`user_version = ${n}`);
    logger.info(`✅ migration applied: ${key}`);
  } catch (err: any) {
    logger.error(`FATAL: migration '${key}' failed: ${err.message}`);
    process.exit(1);
  }
}

// Initialize database with schema if tables don't exist
function initializeDatabase(): void {
  logger.info('Checking database initialization...');

  // Check if users table exists
  const tableCheck = db.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='users'
  `).get() as { name: string } | undefined;

  if (!tableCheck) {
    logger.info('Database not initialized. Running migration...');

    const initSQL = fs.readFileSync(
      path.join(MIGRATIONS_DIR, 'init.sql'),
      'utf8'
    );

    db.exec(initSQL);

    logger.info('✅ Database schema created successfully!');

    createDefaultUser();
    createDefaultWarehouse();

    logger.info('✅ Database initialization complete!');
  } else {
    logger.info('✅ Database already initialized.');
  }

  runInvoiceMigration();
  runCustomerARMigrations();
}

function createDefaultUser(): void {
  const existingUser = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');

  if (!existingUser) {
    let defaultPassword = process.env.DEFAULT_ADMIN_PASSWORD;
    if (!defaultPassword && process.env.NODE_ENV !== 'production') {
      // Development: no env var set, fall back to well-known dev credential
      logger.warn('⚠ WARNING: DEFAULT_ADMIN_PASSWORD not set. Using default development fallback (admin123). DO NOT USE IN PRODUCTION.');
      // dev-only, gated by the NODE_ENV check above; production throws instead (docs/README.md, PORTING.md) — mimosa-ignore
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

    logger.info('✅ Default admin user created');
  }
}

function createDefaultWarehouse(): void {
  const existingWarehouse = db.prepare('SELECT id FROM warehouses WHERE warehouse_code = ?').get('WH-001');

  if (!existingWarehouse) {
    const stmt = db.prepare(`
      INSERT INTO warehouses (warehouse_code, warehouse_name, location, is_active)
      VALUES (?, ?, ?, ?)
    `);

    stmt.run('WH-001', 'Main Warehouse', 'Default Location', 1);

    logger.info('✅ Default warehouse created (WH-001)');
  }
}

function runInvoiceMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('invoices')
      WHERE name='discount_scope'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running invoice discount/tax migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-invoice-discount-tax-fields.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Invoice discount/tax migration completed!');
    }
  } catch (error: any) {
    throw new Error('Invoice migration error:: ' + error.message, { cause: error });
  }
}

function runCustomerARMigrations(): void {
  try {
    // Ensure return-tracking columns exist before the balance recalculation
    // below references them (they are otherwise added later by
    // runGLFoundationMigration — too late for first boot).
    if (!columnExists('invoices', 'returned_amount')) {
      db.exec("ALTER TABLE invoices ADD COLUMN returned_amount DECIMAL(15,2) NOT NULL DEFAULT 0");
    }
    if (!columnExists('invoices', 'return_fee')) {
      db.exec('ALTER TABLE invoices ADD COLUMN return_fee DECIMAL(15,2) NOT NULL DEFAULT 0');
    }

    const columnsToCheck = [
      {name: 'credit_limit', sql: 'ALTER TABLE customers ADD COLUMN credit_limit DECIMAL(15,2) DEFAULT 0'},
      {name: 'current_balance', sql: 'ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0'},
      {name: 'opening_balance', sql: 'ALTER TABLE customers ADD COLUMN opening_balance DECIMAL(15,2) DEFAULT 0'},
      {name: 'payment_terms_days', sql: 'ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 14'}
    ];

    for (const column of columnsToCheck) {
      const columnCheck = db.prepare(`
        SELECT COUNT(*) as count FROM pragma_table_info('customers')
        WHERE name=?
      `).get(column.name) as { count: number } | undefined;

      if (!columnCheck || columnCheck.count === 0) {
        logger.info(`Adding missing column: ${column.name}...`);
        db.exec(column.sql);
        logger.info(`✅ Added ${column.name} column successfully!`);
      }
    }

    const ledgerTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='customer_ledger'
    `).get() as { name: string } | undefined;

    if (!ledgerTableCheck) {
      logger.info('Running customer ledger migration...');

      const ledgerSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'create-customer-ledger.sql'),
        'utf8'
      );

      db.exec(ledgerSQL);

      logger.info('✅ Customer ledger migration completed!');
    }

    const allocationsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='payment_allocations'
    `).get() as { name: string } | undefined;

    if (!allocationsTableCheck) {
      logger.info('Running payment allocations migration...');

      const allocationsSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'create-payment-allocations.sql'),
        'utf8'
      );

      db.exec(allocationsSQL);

      logger.info('✅ Payment allocations migration completed!');
    }

    logger.info('Ensuring customer_id values are integers...');
    db.exec(`
      UPDATE invoices SET customer_id = CAST(customer_id AS INTEGER) WHERE typeof(customer_id) = 'text';
      UPDATE payments SET customer_id = CAST(customer_id AS INTEGER) WHERE typeof(customer_id) = 'text';
    `);
    logger.info('✅ Customer ID type fix completed!');

    // Task 3.3 (audit-remediation): invoice balance/status recalculation moved out of
    // boot into the one-time `fn.recalcInvoiceBalances` data migration and the
    // explicit `npm run repair` script. Boot no longer rewrites business rows.


    // INV-09 (boot-task-gating): boot MUST NOT write to stock tables.
    // The former self-heal (rewrite of stock_balances / items.current_stock
    // and deletion of "orphaned" balances) masked every balance-side bug by
    // overwriting them from SUM(stock_movements) on each start. It is now a
    // read-only comparison; discrepancies are logged at startup and exposed
    // read-only on GET /api/admin/health/stock-discrepancies. Repairs happen
    // only via the explicit gated repair scripts.
    logStockDiscrepancies();

    // Task 3.3: payment-ledger description rewrite also moved to the gated
    // repair path (`npm run repair` / fn.paymentLedgerDescriptions backfill).

  } catch (error: any) {
    throw new Error('Customer AR migration error:: ' + error.message, { cause: error });
  }
}

function runExpensesMigration(): void {
  try {
    const expensesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='expenses'
    `).get() as { name: string } | undefined;

    if (!expensesTableCheck) {
      logger.info('Running expenses migration...');

      const expensesSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-expenses-table.sql'),
        'utf8'
      );

      db.exec(expensesSQL);

      logger.info('✅ Expenses migration completed!');
    }

    const categoriesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='expense_categories'
    `).get() as { name: string } | undefined;

    if (!categoriesTableCheck) {
      logger.info('Running expense categories migration...');

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

      logger.info('✅ Expense categories migration completed!');
    }
  } catch (error: any) {
    throw new Error('Expenses migration error:: ' + error.message, { cause: error });
  }
}

function runPurchasesMigration(): void {
  try {
    const purchasesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='purchases'
    `).get() as { name: string } | undefined;

    if (!purchasesTableCheck) {
      logger.info('Running purchases migration...');

      const purchasesSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-purchases-table.sql'),
        'utf8'
      );

      db.exec(purchasesSQL);

      logger.info('✅ Purchases migration completed!');
    }
  } catch (error: any) {
    throw new Error('Purchases migration error:: ' + error.message, { cause: error });
  }
}

function runPurchaseSupplierPaymentMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('purchases')
      WHERE name='supplier_id'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running purchase supplier/payment migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-purchase-supplier-payment.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Purchase supplier/payment migration completed!');
    }

    // The column can exist without the allocations table (partial
    // migration / restored DB) — ensure the table + indexes too. Kept
    // separate from the file above: re-running that file would fail on
    // the duplicate ALTER TABLE ADD COLUMN.
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='purchase_allocations'
    `).get() as { name: string } | undefined;
    if (!tableCheck) {
      logger.info('Adding purchase_allocations table...');
      db.exec(`
        CREATE TABLE IF NOT EXISTS purchase_allocations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payment_id INTEGER NOT NULL,
            purchase_id INTEGER NOT NULL,
            amount DECIMAL(15,2) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
            FOREIGN KEY (purchase_id) REFERENCES purchases(id)
        );
        CREATE INDEX IF NOT EXISTS idx_purchase_allocations_payment ON purchase_allocations(payment_id);
        CREATE INDEX IF NOT EXISTS idx_purchase_allocations_purchase ON purchase_allocations(purchase_id);
        CREATE INDEX IF NOT EXISTS idx_purchases_supplier_id ON purchases(supplier_id);
      `);
      logger.info('✅ purchase_allocations table added');
    }
  } catch (error: any) {
    throw new Error('Purchase supplier/payment migration error:: ' + error.message, { cause: error });
  }
}

function runPurchaseReturnMigration(): void {
  try {
    const hasReturnedQty = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('purchases')
      WHERE name='returned_quantity'
    `).get() as { count: number };

    if (hasReturnedQty.count === 0) {
      logger.info('Running purchase return fields migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-purchase-return-fields.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Purchase return fields migration completed!');
    } else {
      logger.info('✅ Purchase return fields already applied.');
    }
  } catch (error: any) {
    throw new Error('Purchase return fields migration error:: ' + error.message, { cause: error });
  }
}

function runPurchaseReturnsTablesMigration(): void {
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='purchase_returns'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running purchase returns tables migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-purchase-returns-tables.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Purchase returns tables migration completed!');
    } else {
      // Recovery: ensure the stock_movements.purchase_return_id column
      // exists even if the table predates the column (partial migration).
      const hasColumn = db.prepare(`
        SELECT COUNT(*) as count FROM pragma_table_info('stock_movements')
        WHERE name='purchase_return_id'
      `).get() as { count: number };
      if (hasColumn.count === 0) {
        logger.info('Adding missing stock_movements.purchase_return_id column...');
        db.exec('ALTER TABLE stock_movements ADD COLUMN purchase_return_id INTEGER REFERENCES purchase_returns(id)');
        logger.info('✅ stock_movements.purchase_return_id column added');
      }
    }
  } catch (error: any) {
    throw new Error('Purchase returns tables migration error:: ' + error.message, { cause: error });
  }
}

// Backfill purchase_returns / purchase_return_items from the legacy
// negative return movements created by the old flows (see
// utils/purchaseReturnBackfill.ts for the logic — extracted so it is
// unit-testable). Idempotent: only processes unlinked movements.
function runPurchaseReturnsBackfill(): void {
  try {
    const count = backfillPurchaseReturns(db);
    if (count > 0) {
      logger.info(`✅ Backfilled ${count} purchase returns from legacy movements`);
    }
  } catch (error: any) {
    throw new Error('Purchase returns backfill error:: ' + error.message, { cause: error });
  }
}

function runProductionsMigration(): void {
  try {
    const productionsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='productions'
    `).get() as { name: string } | undefined;

    if (!productionsTableCheck) {
      logger.info('Running productions migration...');

      const productionsSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-production-tables.sql'),
        'utf8'
      );

      db.exec(productionsSQL);

      logger.info('✅ Productions migration completed!');
    }
  } catch (error: any) {
    throw new Error('Productions migration error:: ' + error.message, { cause: error });
  }
}

function runBOMMigration(): void {
  try {
    const bomTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='boms'
    `).get() as { name: string } | undefined;

    // Legacy init.sql created bom_items with raw_material_id; the BOM model
    // and this migration's indexes expect item_id. Rename BEFORE applying
    // add-bom-tables.sql so its index on bom_items(item_id) doesn't fail
    // (CREATE TABLE IF NOT EXISTS won't fix an existing legacy table).
    const existingBomItems = db.prepare(`
      SELECT name FROM sqlite_master WHERE type='table' AND name='bom_items'
    `).get() as { name: string } | undefined;
    if (existingBomItems) {
      const hasItemId = (db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('bom_items') WHERE name='item_id'`).get() as { count: number }).count;
      const hasRawMaterialId = (db.prepare(`SELECT COUNT(*) as count FROM pragma_table_info('bom_items') WHERE name='raw_material_id'`).get() as { count: number }).count;
      if (!hasItemId && hasRawMaterialId) {
        logger.info('Renaming bom_items.raw_material_id → item_id...');
        db.exec('ALTER TABLE bom_items RENAME COLUMN raw_material_id TO item_id');
      }
    }

    if (!bomTableCheck) {
      logger.info('Running BOM migration...');

      const bomSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-bom-tables.sql'),
        'utf8'
      );

      db.exec(bomSQL);

      logger.info('✅ BOM migration completed!');
    }
  } catch (error: any) {
    throw new Error('BOM migration error:: ' + error.message, { cause: error });
  }
}

function runBOMItemsColumnMigration(): void {
  // `init.sql` created bom_items with `raw_material_id`, but every
  // BOMModel query joins on `item_id` (the add-bom-tables migration's
  // schema). Fresh DBs from init.sql and pre-existing DBs both keep the
  // old column name unless the server also creates it — rename it
  // in place so the BOM list/detail queries work.
  try {
    const bomItemsExists = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='bom_items'
    `).get() as { name: string } | undefined;
    if (!bomItemsExists) return;

    const hasItemId = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('bom_items')
      WHERE name='item_id'
    `).get() as { count: number };
    if (hasItemId.count > 0) return;

    const hasRawMaterialId = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('bom_items')
      WHERE name='raw_material_id'
    `).get() as { count: number };
    if (hasRawMaterialId.count === 0) return;

    logger.info('Renaming bom_items.raw_material_id → item_id...');
    db.exec('ALTER TABLE bom_items RENAME COLUMN raw_material_id TO item_id');
    logger.info('✅ bom_items.raw_material_id renamed to item_id');
  } catch (error: any) {
    throw new Error('BOM items column migration error:: ' + error.message, { cause: error });
  }
}

function runSalesMigration(): void {
  try {
    // Drop legacy sales table — POS and direct sales now use invoices+invoice_items
    db.exec(`DROP TABLE IF EXISTS sales`);

    // Check and run sales cycle migration (quotations & sales orders)
    const salesCycleCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='quotations'
    `).get() as { name: string } | undefined;

    if (!salesCycleCheck) {
      logger.info('Running sales cycle migration (quotations & sales orders)...');

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
        addColumnIfMissing('sales_orders', 'source_type VARCHAR(20)');
        addColumnIfMissing('sales_orders', 'source_id INTEGER');
        addColumnIfMissing('sales_orders', 'customer_name VARCHAR(200)');
        addColumnIfMissing('invoices', 'source_type VARCHAR(20)');
        addColumnIfMissing('invoices', 'quotation_id INTEGER');
        addColumnIfMissing('invoices', 'customer_name VARCHAR(200)');

        logger.info('✅ Sales cycle migration completed!');
      } catch (migrationError: any) {
        throw new Error('Sales cycle migration error:: ' + migrationError.message, { cause: migrationError });
        }
    }
  } catch (error: any) {
    throw new Error('Sales migration error:: ' + error.message, { cause: error });
  }
}

function runSupplierLedgerMigration(): void {
  try {
    const supplierLedgerTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='supplier_ledger'
    `).get() as { name: string } | undefined;

    if (!supplierLedgerTableCheck) {
      logger.info('Running supplier ledger migration...');

      const supplierLedgerSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'create-supplier-ledger.sql'),
        'utf8'
      );

      db.exec(supplierLedgerSQL);

      logger.info('✅ Supplier ledger migration completed!');
    }
  } catch (error: any) {
    throw new Error('Supplier ledger migration error:: ' + error.message, { cause: error });
  }
}

function runActivityLogMigration(): void {
  try {
    // Check if log_level column exists
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('activity_log')
      WHERE name='log_level'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running activity log enhancement migration...');

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

      logger.info('✅ Activity log enhancement migration completed!');
    }
  } catch (error: any) {
    throw new Error('Activity log migration error:: ' + error.message, { cause: error });
  }
}

function runSupplierPaymentMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('payments')
      WHERE name='supplier_id'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running supplier payment migration...');

      const supplierPaymentSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-supplier-payment-support.sql'),
        'utf8'
      );

      db.exec(supplierPaymentSQL);

      logger.info('✅ Supplier payment migration completed!');
    }

    // Rebuild payments if customer_id is still NOT NULL (partial state from
    // older versions of this migration).
    const notNullCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('payments')
      WHERE name='customer_id' AND "notnull"=1
    `).get() as { count: number };

    if (notNullCheck.count > 0) {
      logger.info('payments.customer_id nullable rebuild pending (runs as its own ledger step)...');
    }
  } catch (error: any) {
    throw new Error('Supplier payment migration error:: ' + error.message, { cause: error });
  }
}

// Table rebuild requiring FK off BEFORE the transaction starts; manages its
// own transaction and always restores foreign_keys=ON.
function runPaymentsCustomerNullableRebuild(): void {
  const notNullCheck = db.prepare(`
    SELECT COUNT(*) as count FROM pragma_table_info('payments')
    WHERE name='customer_id' AND "notnull"=1
  `).get() as { count: number };
  if (notNullCheck.count === 0) return;

  logger.info('Making payments.customer_id nullable...');
  db.pragma('foreign_keys = OFF');
  try {
    db.transaction(() => {
      db.exec(`
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
            purchase_order_id INTEGER REFERENCES purchase_orders(id),
            created_by INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (customer_id) REFERENCES customers(id),
            FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
            FOREIGN KEY (invoice_id) REFERENCES invoices(id),
            FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id),
            FOREIGN KEY (created_by) REFERENCES users(id)
        );
        INSERT INTO payments_new (id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at)
          SELECT id, payment_no, customer_id, supplier_id, invoice_id, payment_date, amount, payment_method, reference_no, notes, purchase_order_id, created_by, created_at FROM payments;
        CREATE INDEX IF NOT EXISTS idx_payments_purchase_order_id ON payments_new(purchase_order_id);
        DROP TABLE payments;
        ALTER TABLE payments_new RENAME TO payments;
        CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON payments(customer_id);
        CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date);
      `);
    })();
  } finally {
    db.pragma('foreign_keys = ON');
  }
  if ((db.pragma('foreign_keys', { simple: true }) as number) !== 1) {
    throw new Error('FATAL: payments rebuild failed to restore PRAGMA foreign_keys=ON');
  }
}

const BATCH_SOURCE_TYPES = "('PRODUCTION','PURCHASE','GOODS_RECEIPT','RETURN','ADJUSTMENT','OPENING','TRANSFER','RECON')";

function runBatchSourceTypeRebuild(): void {
  // INV-10 / INV-22: widen stock_batches.source_type to a disjoint
  // namespace per origin table and re-stamp existing rows.
  const currentCheck = db.prepare(`
    SELECT sql FROM sqlite_master WHERE type='table' AND name='stock_batches'
  `).get() as { sql: string } | undefined;
  if (!currentCheck) return; // fresh DB — add-batch-costing.sql creates the widened schema

  // Detect whether the live CHECK already carries the full namespace
  // (covers both the legacy two-value CHECK and a CHECK-less table).
  const needsWiden = !currentCheck.sql.includes("'GOODS_RECEIPT'")
    || !currentCheck.sql.includes("'ADJUSTMENT'")
    || !currentCheck.sql.includes("'TRANSFER'");
  if (!needsWiden) return;

  logger.info('Rebuilding stock_batches with widened source_type CHECK...');
  db.pragma('foreign_keys = OFF');
  try {
    db.transaction(() => {
      // Re-stamp into disjoint namespaces (INV-10):
      //  - synthetic reconciliation rows (source_id = 0) → RECON
      //  - source_id resolves to goods_receipt_items     → GOODS_RECEIPT
      //  - everything else stays PURCHASE / PRODUCTION as written
      const batchCols = db.prepare(`SELECT name FROM pragma_table_info('stock_batches')`).all() as Array<{ name: string }>;
      const hasExpiry = batchCols.some((c) => c.name === 'expiry_date');
      const hasCreatedAt = batchCols.some((c) => c.name === 'created_at');
      const hasHalted = batchCols.some((c) => c.name === 'halted');
      const hasHaltedReason = batchCols.some((c) => c.name === 'halted_reason');
      const copyCols = [
        'id', 'batch_no', 'item_id', 'warehouse_id',
        `CASE
           WHEN source_type IN ('PURCHASE') AND source_id = 0 THEN 'RECON'
           WHEN source_type = 'PURCHASE' AND source_id > 0
                AND EXISTS (SELECT 1 FROM goods_receipt_items gri WHERE gri.id = stock_batches.source_id)
             THEN 'GOODS_RECEIPT'
           ELSE source_type
         END AS source_type_stamped`,
        'source_id', 'quantity_original', 'quantity_remaining', 'unit_cost', 'received_date',
      ];
      if (hasCreatedAt) copyCols.push(hasExpiry ? 'created_at' : "'' AS created_at");
      if (hasExpiry) copyCols.push('expiry_date');
      if (hasHalted) copyCols.push('halted');
      if (hasHaltedReason) copyCols.push('halted_reason');
      const insertCols = ['id', 'batch_no', 'item_id', 'warehouse_id', 'source_type', 'source_id', 'quantity_original', 'quantity_remaining', 'unit_cost', 'received_date'];
      if (hasCreatedAt) insertCols.push('created_at');
      if (hasExpiry) insertCols.push('expiry_date');
      if (hasHalted) insertCols.push('halted');
      if (hasHaltedReason) insertCols.push('halted_reason');
      // Create the new table without optional columns when the source lacks them.
      const optionalCols: string[] = [];
      if (hasCreatedAt) optionalCols.push('created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
      if (hasExpiry) optionalCols.push('expiry_date DATE');
      // FEFO halt columns (add-item-expiry-tracking.sql) — dropping these
      // silently breaks invoice creation's batch consumption.
      if (hasHalted) optionalCols.push('halted BOOLEAN DEFAULT 0');
      if (hasHaltedReason) optionalCols.push('halted_reason TEXT');
      const newTableSQL = `
        CREATE TABLE stock_batches_new (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            batch_no        VARCHAR(50) UNIQUE NOT NULL,
            item_id         INTEGER NOT NULL REFERENCES items(id),
            warehouse_id    INTEGER NOT NULL REFERENCES warehouses(id),
            source_type     VARCHAR(20) NOT NULL CHECK(source_type IN ${BATCH_SOURCE_TYPES}),
            source_id       INTEGER NOT NULL,
            quantity_original DECIMAL(15,3) NOT NULL DEFAULT 0,
            quantity_remaining DECIMAL(15,3) NOT NULL DEFAULT 0,
            unit_cost       DECIMAL(15,4) NOT NULL DEFAULT 0,
            received_date   DATE NOT NULL${optionalCols.length ? ',\n            ' + optionalCols.join(',\n            ') : ''}
        );
      `;
      db.exec(newTableSQL);
      db.exec(`
        INSERT INTO stock_batches_new (${insertCols.join(', ')})
        SELECT ${copyCols.join(', ')}
        FROM stock_batches;
      `);


      // Post-migration assertion: no row left in an unknown namespace.
      const bad = db.prepare(`
        SELECT COUNT(*) AS n FROM stock_batches_new
        WHERE source_type NOT IN ${BATCH_SOURCE_TYPES.replace(/^\(/, '(')}
           OR (source_type = 'PURCHASE' AND source_id > 0
               AND EXISTS (SELECT 1 FROM goods_receipt_items gri WHERE gri.id = source_id))
      `).get() as { n: number };
      if (bad.n > 0) {
        throw new Error(`${bad.n} stock_batches row(s) failed source_type re-stamping`);
      }

      const countsBefore = (db.prepare('SELECT COUNT(*) AS n FROM stock_batches').get() as { n: number }).n;
      db.exec('DROP TABLE stock_batches');
      db.exec('ALTER TABLE stock_batches_new RENAME TO stock_batches');

      const countsAfter = (db.prepare('SELECT COUNT(*) AS n FROM stock_batches').get() as { n: number }).n;
      if (countsAfter !== countsBefore) {
        throw new Error(`stock_batches rebuild lost rows (${countsBefore} -> ${countsAfter})`);
      }

      // Restore indexes from add-batch-costing.sql (+ expiry index when present).
      db.exec(`
        CREATE INDEX IF NOT EXISTS idx_stock_batches_item ON stock_batches(item_id, warehouse_id);
        CREATE INDEX IF NOT EXISTS idx_stock_batches_source ON stock_batches(source_type, source_id);
        CREATE INDEX IF NOT EXISTS idx_stock_batches_batch_no ON stock_batches(batch_no);
      `);
      if (hasExpiry) {
        db.exec('CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry ON stock_batches(expiry_date) WHERE expiry_date IS NOT NULL');
      }
    })();
  } finally {
    db.pragma('foreign_keys = ON');
  }
  if ((db.pragma('foreign_keys', { simple: true }) as number) !== 1) {
    throw new Error('FATAL: stock_batches rebuild failed to restore PRAGMA foreign_keys=ON');
  }
  logger.info('✅ stock_batches source_type widened and re-stamped');
}

function runStockCoverageReconciliation(): void {
  // One-off reconciliation of known live drift (inventory-integrity Phase 4):
  // stock_batches coverage must equal stock_balances.quantity per
  // (item, warehouse) before the INV-21 CHECK constraints can be applied.
  //  - Over-coverage: trimmed FIFO-newest-first.
  //  - Under-coverage: a RECON layer is minted at the warehouse's inbound
  //    weighted cost with a balancing journal entry.
  // Idempotent: no-op when coverage already matches everywhere.
  const mismatches = db.prepare(`
    SELECT * FROM (
      SELECT sb.item_id, sb.warehouse_id, sb.quantity AS balance_qty,
             COALESCE((SELECT SUM(b.quantity_remaining) FROM stock_batches b
                       WHERE b.item_id = sb.item_id AND b.warehouse_id = sb.warehouse_id), 0) AS covered
      FROM stock_balances sb
    )
    WHERE ABS(balance_qty - covered) > 0.0005
  `).all() as Array<{ item_id: number; warehouse_id: number; balance_qty: number; covered: number }>;

  if (mismatches.length === 0) return;
  logger.info(`Reconciling ${mismatches.length} batch/balance coverage mismatch(es)...`);

  const run = db.transaction(() => {
    for (const m of mismatches) {
      const delta = m.balance_qty - m.covered; // >0 under-covered, <0 over-covered
      if (delta < 0) {
        let toTrim = -delta;
        const layers = db.prepare(`
          SELECT id, quantity_remaining FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
          ORDER BY received_date DESC, id DESC
        `).all(m.item_id, m.warehouse_id) as Array<{ id: number; quantity_remaining: number }>;
        for (const layer of layers) {
          if (toTrim <= 0.0005) break;
          const trim = Math.min(layer.quantity_remaining, toTrim);
          db.prepare('UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?').run(trim, layer.id);
          toTrim -= trim;
        }
        logger.info(`  item ${m.item_id}/wh ${m.warehouse_id}: trimmed over-coverage by ${(-delta).toFixed(3)}`);
      } else {
        const avg = db.prepare(`
          SELECT COALESCE(SUM(quantity * unit_cost) * 1.0 / NULLIF(SUM(quantity), 0), 0) AS cost
          FROM stock_movements
          WHERE item_id = ? AND warehouse_id = ? AND quantity > 0
            AND movement_type IN ('PURCHASE','PRODUCTION')
        `).get(m.item_id, m.warehouse_id) as { cost: number };
        const unitCost = avg.cost > 0 ? avg.cost : ((db.prepare('SELECT standard_cost FROM items WHERE id = ?').get(m.item_id) as { standard_cost: number } | undefined)?.standard_cost || 0);

        const nextNo = getNextSequenceNumber(db, 'BATCH_RECON_last_no');
        db.prepare(`
          INSERT INTO stock_batches (
            batch_no, item_id, warehouse_id, source_type,
            source_id, quantity_original, quantity_remaining,
            unit_cost, received_date
          ) VALUES (?, ?, ?, 'RECON', 0, ?, ?, ?, ?)
        `).run(
          `BATCH-${new Date().getFullYear() % 100}-RECON-${nextNo.toString().padStart(4, '0')}`,
          m.item_id, m.warehouse_id, delta, delta, unitCost,
          new Date().toISOString().split('T')[0]
        );

        const value = delta * unitCost;
        if (value > 0.005 && db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='journal_entries'`).get()) {
          const desc = `Coverage reconciliation: +${delta} units @ ${unitCost} (item ${m.item_id}, warehouse ${m.warehouse_id})`;
          const je = db.prepare(`
            INSERT INTO journal_entries (reference_type, reference_id, entry_date, description, debit_account, credit_account, amount, voided)
            VALUES ('RECON', 0, ?, ?, '1200', '4999', ?, 0)
          `).run(new Date().toISOString().split('T')[0], desc, value);
          const jeId = je.lastInsertRowid as number;
          const invAcc = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1200'`).get() as { id: number } | undefined;
          const adjAcc = db.prepare(`SELECT id FROM chart_of_accounts WHERE code IN ('4999','4000') ORDER BY code DESC LIMIT 1`).get() as { id: number } | undefined;
          if (invAcc && adjAcc) {
            const lines = db.prepare(`
              INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description, line_date)
              VALUES (?, ?, ?, ?, ?, ?)
            `);
            const today = new Date().toISOString().split('T')[0];
            lines.run(jeId, invAcc.id, value, 0, 'Inventory increase (coverage reconciliation)', today);
            lines.run(jeId, adjAcc.id, 0, value, 'Coverage reconciliation adjustment', today);
          }
        }
        logger.info(`  item ${m.item_id}/wh ${m.warehouse_id}: minted RECON layer of ${delta} @ ${unitCost}`);
      }
    }

    // Post-condition: coverage must now match everywhere.
    const remaining = db.prepare(`
      SELECT COUNT(*) AS n FROM (
        SELECT 1 AS ok FROM stock_balances sb
        WHERE ABS(sb.quantity - COALESCE((SELECT SUM(b.quantity_remaining) FROM stock_batches b
                        WHERE b.item_id = sb.item_id AND b.warehouse_id = sb.warehouse_id), 0)) > 0.0005
      )
    `).get() as { n: number };
    if (remaining.n > 0) {
      throw new Error(`${remaining.n} coverage mismatch(es) remain after reconciliation`);
    }
  });
  run();
  logger.info('✅ Batch/balance coverage reconciled');
}

function runStockInvariantChecksRebuild(): void {
  // INV-21: make negative stock and over-covered batches unrepresentable.
  // Table rebuilds (FK off) adding CHECK constraints:
  //   stock_balances:    quantity >= 0
  //   stock_batches:     quantity_remaining >= 0 AND quantity_remaining <= quantity_original
  // Runs AFTER runStockCoverageReconciliation so live data passes the checks.
  const balSql = db.prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name='stock_balances'`).get() as { sql: string } | undefined;
  const batchSql = db.prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name='stock_batches'`).get() as { sql: string } | undefined;
  if (!balSql || !batchSql) return;

  const balNeeds = !balSql.sql.includes('quantity >= 0');
  const batchNeeds = !(batchSql.sql.includes('quantity_remaining <= quantity_original'));
  if (!balNeeds && !batchNeeds) return;

  logger.info('Applying stock invariant CHECK constraints...');

  // Pre-flight: fail loudly if existing data would violate the checks.
  const negBal = (db.prepare('SELECT COUNT(*) AS n FROM stock_balances WHERE quantity < 0').get() as { n: number }).n;
  if (negBal > 0) throw new Error(`${negBal} stock_balances row(s) have negative quantity — reconcile before applying CHECK constraints`);
  const badBatches = (db.prepare(`
    SELECT COUNT(*) AS n FROM stock_batches
    WHERE quantity_remaining < 0 OR quantity_remaining > quantity_original
  `).get() as { n: number }).n;
  if (badBatches > 0) throw new Error(`${badBatches} stock_batches row(s) violate coverage invariants — reconcile before applying CHECK constraints`);

  db.pragma('foreign_keys = OFF');
  try {
    db.transaction(() => {
      if (balNeeds) {
        db.exec(`
          CREATE TABLE stock_balances_new (
              item_id INTEGER NOT NULL REFERENCES items(id),
              warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
              quantity DECIMAL(15,3) NOT NULL DEFAULT 0 CHECK(quantity >= 0),
              last_updated DATETIME,
              PRIMARY KEY (item_id, warehouse_id)
          );
          INSERT INTO stock_balances_new (item_id, warehouse_id, quantity, last_updated)
            SELECT item_id, warehouse_id, quantity, last_updated FROM stock_balances;
          DROP TABLE stock_balances;
          ALTER TABLE stock_balances_new RENAME TO stock_balances;
        `);
      }
      if (batchNeeds) {
        const cols0 = (db.prepare(`SELECT name FROM pragma_table_info('stock_batches')`).all() as Array<{ name: string }>).map(c => c.name);
        const optionalDefs: string[] = [];
        if (cols0.includes('created_at')) optionalDefs.push('created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
        if (cols0.includes('expiry_date')) optionalDefs.push('expiry_date DATE');
        if (cols0.includes('halted')) optionalDefs.push('halted BOOLEAN DEFAULT 0');
        if (cols0.includes('halted_reason')) optionalDefs.push('halted_reason TEXT');
        db.exec(`
          CREATE TABLE stock_batches_inv (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              batch_no VARCHAR(50) UNIQUE NOT NULL,
              item_id INTEGER NOT NULL REFERENCES items(id),
              warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
              source_type VARCHAR(20) NOT NULL CHECK(source_type IN ('PRODUCTION','PURCHASE','GOODS_RECEIPT','RETURN','ADJUSTMENT','OPENING','TRANSFER','RECON')),
              source_id INTEGER NOT NULL,
              quantity_original DECIMAL(15,3) NOT NULL DEFAULT 0,
              quantity_remaining DECIMAL(15,3) NOT NULL DEFAULT 0
                CHECK(quantity_remaining >= 0 AND quantity_remaining <= quantity_original),
              unit_cost DECIMAL(15,4) NOT NULL DEFAULT 0,
              received_date DATE NOT NULL${optionalDefs.length ? ',\n              ' + optionalDefs.join(',\n              ') : ''}
          );
        `);
        // Column-aware copy
        const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_batches')`).all().map((c: any) => c.name);
        const base = ['id','batch_no','item_id','warehouse_id','source_type','source_id','quantity_original','quantity_remaining','unit_cost','received_date'];
        const optional = ['created_at','expiry_date','halted','halted_reason'].filter(c => cols.includes(c));
        const allCols = [...base, ...optional];
        db.exec(`
          INSERT INTO stock_batches_inv (${allCols.join(', ')})
          SELECT ${allCols.join(', ')} FROM stock_batches;
        `);
        db.exec(`
          DROP TABLE stock_batches;
          ALTER TABLE stock_batches_inv RENAME TO stock_batches;
          CREATE INDEX IF NOT EXISTS idx_stock_batches_item ON stock_batches(item_id, warehouse_id);
          CREATE INDEX IF NOT EXISTS idx_stock_batches_source ON stock_batches(source_type, source_id);
          CREATE INDEX IF NOT EXISTS idx_stock_batches_batch_no ON stock_batches(batch_no);
        `);
        if (optional.includes('expiry_date')) {
          db.exec('CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry ON stock_batches(expiry_date) WHERE expiry_date IS NOT NULL');
        }
      }
    })();
  } finally {
    db.pragma('foreign_keys = ON');
  }
  if ((db.pragma('foreign_keys', { simple: true }) as number) !== 1) {
    throw new Error('FATAL: invariant rebuild failed to restore PRAGMA foreign_keys=ON');
  }
  logger.info('✅ Stock invariant CHECK constraints applied');
}

function runPaymentsPurchaseOrderIdMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('payments')
      WHERE name='purchase_order_id'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running payments purchase_order_id migration...');
      const sql = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-payments-purchase-order-id.sql'),
        'utf8'
      );
      db.exec(sql);
      logger.info('✅ Payments purchase_order_id migration completed!');
    }
  } catch (error: any) {
    throw new Error('Payments purchase_order_id migration error:: ' + error.message, { cause: error });
  }
}

function runSupplierBalanceMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('suppliers')
      WHERE name='current_balance'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Adding suppliers.current_balance column...');
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
    logger.info('✅ Suppliers current_balance column ensured');
  } catch (error: any) {
    throw new Error('Supplier balance migration error:: ' + error.message, { cause: error });
  }
}

function runRawMaterialsWarehouseMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('productions')
      WHERE name='raw_materials_warehouse_id'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running raw materials warehouse migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-raw-materials-warehouse.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Raw materials warehouse migration completed!');
    }
  } catch (error: any) {
    throw new Error('Raw materials warehouse migration error:: ' + error.message, { cause: error });
  }
}

function runProductionInputsWarehouseMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('production_inputs')
      WHERE name='warehouse_id'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running production inputs warehouse migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-warehouse-to-production-inputs.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Production inputs warehouse migration completed!');
    }
  } catch (error: any) {
    throw new Error('Production inputs warehouse migration error:: ' + error.message, { cause: error });
  }
}

function runMobileInvoiceMigration(): void {
  try {
    const taxRatesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='tax_rates'
    `).get() as { name: string } | undefined;

    if (!taxRatesTableCheck) {
      logger.info('Running mobile invoice tables migration...');

      const mobileInvoiceSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-mobile-invoice-tables.sql'),
        'utf8'
      );

      db.exec(mobileInvoiceSQL);

      logger.info('✅ Mobile invoice tables migration completed!');
    }
  } catch (error: any) {
    throw new Error('Mobile invoice migration error:: ' + error.message, { cause: error });
  }
}

function runPerformanceIndexesMigration(): void {
  try {
    const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_items_category'
    `).get() as { count: number };

    if (indexCheck.count === 0) {
      logger.info('Running performance indexes migration...');

      const indexSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-performance-indexes.sql'),
        'utf8'
      );

      db.exec(indexSQL);

      logger.info('✅ Performance indexes migration completed!');
    }
  } catch (error: any) {
    throw new Error('Performance indexes migration error:: ' + error.message, { cause: error });
  }
}

function runMissingIndexesMigration(): void {
  try {
    const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_payment_allocations_payment'
    `).get() as { count: number };

    if (indexCheck.count === 0) {
      logger.info('Running missing indexes migration...');

      const indexSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-missing-indexes.sql'),
        'utf8'
      );

      db.exec(indexSQL);

      logger.info('✅ Missing indexes migration completed!');
    }
  } catch (error: any) {
    throw new Error('Missing indexes migration error:: ' + error.message, { cause: error });
  }
}

function runMissingFKIndexesMigration(): void {
  try {
    // Guard on an index this file actually creates (audit-remediation 3.7 —
    // previously pointed at idx_invoices_so_id which nothing creates).
    const indexCheck = db.prepare(`
      SELECT COUNT(*) as count FROM sqlite_master
      WHERE type='index' AND name='idx_invoices_customer_id'
    `).get() as { count: number };

    if (indexCheck.count === 0) {
      logger.info('Running missing FK indexes migration...');

      const indexSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-missing-fk-indexes.sql'),
        'utf8'
      );

      db.exec(indexSQL);

      logger.info('✅ Missing FK indexes migration completed!');
    }
  } catch (error: any) {
    throw new Error('Missing FK indexes migration error:: ' + error.message, { cause: error });
  }
}

function runExpiryTrackingMigration(): void {
  try {
    // Check if migration already applied by looking for the has_expiry column
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('items')
      WHERE name='has_expiry'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running item expiry tracking migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-item-expiry-tracking.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Item expiry tracking migration completed!');
    }
  } catch (error: any) {
    throw new Error('Expiry tracking migration error:: ' + error.message, { cause: error });
  }
}

function runOverrideSaleMigration(): void {
  try {
    const columnCheck = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('invoices') WHERE name='override_sale'`
    ).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running override sale column migration...');
      const sql = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-override-sale-column.sql'),
        'utf8'
      );
      db.exec(sql);
      logger.info('✅ Override sale column migration completed!');
    }
  } catch (error: any) {
    throw new Error('Override sale migration error:: ' + error.message, { cause: error });
  }
}

/**
 * Repair: the INV-10 stock_batches re-stamp rebuild originally preserved
 * created_at/expiry_date but NOT the FEFO halt columns — databases that
 * rebuilt after add-item-expiry-tracking.sql silently lost them, and the
 * ledger marks that migration applied so it never re-ran. Invoice
 * creation's batch consumption (`halted = 0 OR halted IS NULL`) then
 * failed with "no such column: halted". Both rebuilds now preserve the
 * columns; this re-adds them on already-affected databases.
 */
function runBatchHaltColumnsRepairMigration(): void {
  try {
    const cols = (db.prepare(
      `SELECT name FROM pragma_table_info('stock_batches')`
    ).all() as Array<{ name: string }>).map(c => c.name);
    if (!cols.includes('halted')) {
      logger.info('Repairing missing stock_batches.halted column...');
      db.exec('ALTER TABLE stock_batches ADD COLUMN halted BOOLEAN DEFAULT 0');
      logger.info('✅ stock_batches.halted restored');
    }
    if (!cols.includes('halted_reason')) {
      db.exec('ALTER TABLE stock_batches ADD COLUMN halted_reason TEXT');
    }
  } catch (error: any) {
    throw new Error('Batch halt columns repair error:: ' + error.message, { cause: error });
  }
}

function runGLVoidAttributionMigration(): void {
  // Adds journal_lines void attribution (voided_at/voided_by/void_reason)
  // and subledger append-only columns (voided/reversed_by). Idempotent:
  // guarded on the first new column; ALTER TABLE ADD COLUMN statements
  // that would duplicate a column throw, so the whole block is skipped
  // once applied.
  try {
    const hasVoidedAt = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('journal_lines') WHERE name='voided_at'`
    ).get() as { count: number };

    if (hasVoidedAt.count === 0) {
      logger.info('Running GL void-attribution / append-only ledger migration...');
      const sql = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-gl-void-attribution.sql'),
        'utf8'
      );
      db.exec(sql);
      logger.info('✅ GL void-attribution migration completed!');
    }
  } catch (error: any) {
    throw new Error('GL void-attribution migration error:: ' + error.message, { cause: error });
  }
}

// Boot migration sequence - each entry recorded in schema_migrations.
// Historical guards inside each runner make first-boot backfill safe:
// already-applied work no-ops and gets registered without re-executing bodies.
runLedgered('fn.initializeDatabase', initializeDatabase);
runLedgered('fn.runExpensesMigration', runExpensesMigration);
runLedgered('fn.runPurchasesMigration', runPurchasesMigration);
runLedgered('fn.runPurchaseSupplierPaymentMigration', runPurchaseSupplierPaymentMigration);
runLedgered('fn.runPurchaseReturnMigration', runPurchaseReturnMigration);
runLedgered('fn.runPurchaseReturnsTablesMigration', runPurchaseReturnsTablesMigration);
runLedgered('fn.runPurchaseReturnsBackfill', runPurchaseReturnsBackfill);
runLedgered('fn.runProductionsMigration', runProductionsMigration);
runLedgered('fn.runBOMMigration', runBOMMigration);
runLedgered('fn.runBOMItemsColumnMigration', runBOMItemsColumnMigration);
runLedgered('fn.runSalesMigration', runSalesMigration);
runLedgered('fn.runSupplierLedgerMigration', runSupplierLedgerMigration);
runLedgered('fn.runActivityLogMigration', runActivityLogMigration);
runLedgered('fn.runSupplierPaymentMigration', runSupplierPaymentMigration);
runLedgered('fn.runPaymentsPurchaseOrderIdMigration', runPaymentsPurchaseOrderIdMigration);
runLedgered('fn.runSupplierBalanceMigration', runSupplierBalanceMigration);
runLedgered('fn.runRawMaterialsWarehouseMigration', runRawMaterialsWarehouseMigration);
runLedgered('fn.runProductionInputsWarehouseMigration', runProductionInputsWarehouseMigration);
runLedgered('fn.runMobileInvoiceMigration', runMobileInvoiceMigration);
runLedgered('fn.runPerformanceIndexesMigration', runPerformanceIndexesMigration);
runLedgered('fn.runMissingIndexesMigration', runMissingIndexesMigration);
runLedgered('fn.runMissingFKIndexesMigration', runMissingFKIndexesMigration);
runLedgered('fn.runProductionOverheadMigration', runProductionOverheadMigration);
runLedgered('fn.runProductionBOMIdMigration', runProductionBOMIdMigration);
runLedgered('fn.runRolesPermissionsMigration', runRolesPermissionsMigration);
runLedgered('fn.runStockAdjustmentFinancialMigration', runStockAdjustmentFinancialMigration);
runLedgered('fn.runForecastsMigration', runForecastsMigration);
runLedgered('fn.runBatchCostingMigration', runBatchCostingMigration);
runLedgered('fn.runGLFoundationMigration', runGLFoundationMigration);
runLedgered('fn.runSalaryPaymentsMigration', runSalaryPaymentsMigration);
runLedgered('fn.runCreditBalanceMigration', runCreditBalanceMigration);
runLedgered('fn.runEmployeesMigration', runEmployeesMigration);
runLedgered('fn.runPhysicalCountsMigration', runPhysicalCountsMigration);
runLedgered('fn.runForecastEnhancementsMigration', runForecastEnhancementsMigration);
runLedgered('fn.runCustomReportsMigration', runCustomReportsMigration);
runLedgered('fn.runExpiryTrackingMigration', runExpiryTrackingMigration);
runLedgered('fn.runOverrideSaleMigration', runOverrideSaleMigration);
runLedgered('fn.runDashboardLayoutsMigration', runDashboardLayoutsMigration);
runLedgered('fn.runLooseItemMigration', runLooseItemMigration);
runLedgered('fn.runCashAccountsMigration', runCashAccountsMigration);
runLedgered('fn.runOpeningBalancesMigration', runOpeningBalancesMigration);
runLedgered('fn.runUserPreferencesMigration', runUserPreferencesMigration);
// INV-04/INV-05: reconciliation/cleanup moved out of boot — see scripts/repair-stock.ts (boot-task-gating spec)
// INV-04/INV-05: reconciliation/cleanup moved out of boot — see scripts/repair-stock.ts (boot-task-gating spec)
runLedgered('fn.runGLVoidAttributionMigration', runGLVoidAttributionMigration);
// FK-off table rebuild must NOT sit inside another transaction
runLedgered('fn.runPaymentsCustomerNullableRebuild', runPaymentsCustomerNullableRebuild, { noTxn: true });
// stock_batches source_type widening — FK-off table rebuild
runLedgered('fn.runBatchSourceTypeRebuild', runBatchSourceTypeRebuild, { noTxn: true });
runLedgered('add-search-indexes.sql');
// reporting-search-remediation: those indexes can never serve '%term%' LIKE — drop them.
runLedgered('drop-search-indexes.sql');
runLedgered('add-audit-trail-fields.sql');
runLedgered('add-activity-log-purge-permission.sql');
runLedgered('add-invoice-soft-delete.sql');
runLedgered('add-hot-path-indexes.sql');
runLedgered('normalize-payment-methods.sql', undefined, { noTxn: true }); // rebuilds payments — FK off required
runLedgered('add-payments-counterparty-check.sql', undefined, { noTxn: true });
// financial-audit-p0-remediation task 2.4: recover purchase_order_id for
// historical single-PO payments (PAY-06 residue — the rebuild nulled it).
runLedgered('fn.backfillPaymentsPurchaseOrderId', backfillPaymentsPurchaseOrderId);
// financial-audit-p0-remediation task 3.1: purchases get a void lifecycle
// (PUR-03) — voided_at/by/reason, no more hard deletes.
runLedgered('add-purchase-void-columns.sql');
runLedgered('add-purchase-return-batches.sql');
runLedgered('seed-expense-sequence.sql');
// One-time data backfills (audit-remediation 3.2/3.3) — ledgered so they run
// exactly once per database, never again on reboot.
runLedgered('fn.recalcInvoiceBalances', recalcInvoiceBalancesBackfill);
runLedgered('fn.paymentLedgerDescriptions', paymentLedgerDescriptionsBackfill);
runLedgered('fn.recoverPaymentsInvoiceId', recoverPaymentsInvoiceId);
runLedgered('fn.reconcileOrphanedJournalLines', reconcileOrphanedJournalLines);
// GL backfill for documents created before live posting (reporting-search-remediation):
// posts purchases/payments/expenses/salaries + opening capital; skips docs already posted.
runLedgered('fn.backfillGlPreposting', () => runBackfillGlPreposting(db));
// Per-line tax decomposition (report-query-integrity): columns first, then the
// one-time decomposition of stored amounts into net_amount + tax_amount.
runLedgered('add-invoice-item-tax-columns.sql');
runLedgered('fn.backfillInvoiceItemTax', () => runBackfillInvoiceItemTax(db));
// INV-21 prerequisite: reconcile live batch/balance drift before CHECK constraints land
runLedgered('fn.runStockCoverageReconciliation', runStockCoverageReconciliation);
// INV-21: database-level invariants — applied only after live data reconciled
runLedgered('fn.runStockInvariantChecksRebuild', runStockInvariantChecksRebuild, { noTxn: true });
// Repair: re-add stock_batches halted/halted_reason when an older rebuild
// dropped them (FEFO consumption hard-fails without the column).
runLedgered('fn.runBatchHaltColumnsRepairMigration', runBatchHaltColumnsRepairMigration);

// Owner Capital & Withdrawals: equity children 3200/3300 + transaction tables.
runLedgered('add-owner-equity.sql');
// Post-apply assertion — runtime posting resolves these by text_code, so an
// unexpected occupant of either slot must fail the boot, never mis-post.
runLedgered('fn.verifyOwnerEquityAccounts', () => {
  for (const [textCode, expected] of [
    ['owner_capital', '3200'],
    ['owner_drawings', '3300'],
  ] as const) {
    const rows = db.prepare(
      `SELECT code, name, type, normal_balance FROM chart_of_accounts WHERE text_code = ?`
    ).all(textCode) as Array<{ code: string; name: string; type: string; normal_balance: string }>;
    if (rows.length !== 1 || rows[0].code !== expected || rows[0].type !== 'equity') {
      throw new Error(
        `Owner equity account check failed for text_code '${textCode}': expected exactly one ` +
        `equity account ${expected}, found ${JSON.stringify(rows)}`
      );
    }
  }
});

// Rollback support: run if --rollback flag is passed
if (process.argv.includes('--rollback')) {
  const targetMigration = process.argv.find(arg => arg.startsWith('--rollback='));
  if (targetMigration) {
    const migrationName = targetMigration.split('=')[1];
    runRollback(migrationName);
  } else {
    runRollbackAll();
  }
}

export default db;

function runProductionBOMIdMigration(): void {
  try {
    const hasBOMId = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='bom_id'`
    ).get() as { count: number };
    if (!hasBOMId.count) {
      logger.info('Running production bom_id migration...');
      db.prepare(`ALTER TABLE productions ADD COLUMN bom_id INTEGER REFERENCES boms(id)`).run();
      logger.info('✅ Production bom_id migration completed!');
    }
  } catch (error: any) {
    throw new Error('Production bom_id migration error:: ' + error.message, { cause: error });
  }
}

function runProductionOverheadMigration(): void {
  try {
    const hasOverheadCost = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='overhead_cost'`
    ).get() as { count: number };
    if (!hasOverheadCost.count) {
      logger.info('Running production overhead_cost migration...');
      db.prepare(`ALTER TABLE productions ADD COLUMN overhead_cost DECIMAL(15,2) DEFAULT 0`).run();
      logger.info('✅ Production overhead_cost migration completed!');
    }
  } catch (error: any) {
    throw new Error('Production overhead migration error:: ' + error.message, { cause: error });
  }
}

function runRolesPermissionsMigration(): void {
  try {
    const rolesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='roles'
    `).get() as { name: string } | undefined;

    if (!rolesTableCheck) {
      logger.info('Running roles and permissions migration...');

      const rolesPermissionsSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-roles-permissions.sql'),
        'utf8'
      );

      db.exec(rolesPermissionsSQL);

      logger.info('✅ Roles and permissions migration completed!');
    }

    // Always seed — backfills missing permissions for existing databases
    seedDefaultPermissions();
  } catch (error: any) {
    throw new Error('Roles and permissions migration error:: ' + error.message, { cause: error });
  }
}

function seedDefaultPermissions(): void {
  try {
    logger.info('Seeding default permissions...');

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

      // Purchase Returns
      { name: 'purchase_returns:read', module: 'purchase_returns', action: 'read', description: 'View purchase returns' },
      { name: 'purchase_returns:create', module: 'purchase_returns', action: 'create', description: 'Create purchase returns' },
      { name: 'purchase_returns:void', module: 'purchase_returns', action: 'void', description: 'Void purchase returns' },

      // Expenses
      { name: 'expenses:read', module: 'expenses', action: 'read', description: 'View expenses' },
      { name: 'expenses:create', module: 'expenses', action: 'create', description: 'Create expenses' },
      { name: 'expenses:update', module: 'expenses', action: 'update', description: 'Update expenses' },
      { name: 'expenses:approve', module: 'expenses', action: 'approve', description: 'Approve and pay expenses' },

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

    // Task 1.5: reports:create must exist for the reconciliation-save gate.
    db.prepare(`
      INSERT OR IGNORE INTO permissions (permission_name, module, action, description)
      VALUES ('reports:create', 'reports', 'create', 'Create/save reports and reconciliations')
    `).run();

    // Insert permissions
    for (const perm of permissions) {
      db.prepare(`
        INSERT OR IGNORE INTO permissions (permission_name, module, action, description)
        VALUES (?, ?, ?, ?)
      `).run(perm.name, perm.module, perm.action, perm.description);
    }

    // Task 3.5 (audit-remediation): seed grants ONLY for roles that have no
    // role_permissions yet. Roles with existing grants (admin-configured) are
    // never touched on reboot — the old always-grant behavior silently
    // re-added revoked permissions after every restart.
    const roleHasNoPerms = (roleId: number): boolean =>
      ((db.prepare('SELECT COUNT(*) AS n FROM role_permissions WHERE role_id = ?').get(roleId) as { n: number }).n === 0);

    // Assign all permissions to Admin role — only when it has none yet
    const adminRole = db.prepare('SELECT id FROM roles WHERE role_name = ?').get('Admin') as { id: number } | undefined;
    if (adminRole && roleHasNoPerms(adminRole.id)) {
      const allPermissions = db.prepare('SELECT id FROM permissions').all() as { id: number }[];
      for (const perm of allPermissions) {
        db.prepare(`
          INSERT INTO role_permissions (role_id, permission_id)
          VALUES (?, ?)
        `).run(adminRole.id, perm.id);
      }
      logger.info(`Seeded ${allPermissions.length} permission(s) to Admin role (was empty)`);
    }

    // Assign read-only permissions to User role — only when it has none yet
    const userRole = db.prepare('SELECT id FROM roles WHERE role_name = ?').get('User') as { id: number } | undefined;
    if (userRole && roleHasNoPerms(userRole.id)) {
      const readPermissions = db.prepare(`
        SELECT id FROM permissions WHERE action = 'read'
        AND module NOT IN ('roles', 'settings')
      `).all() as { id: number }[];
      for (const perm of readPermissions) {
        db.prepare(`
          INSERT INTO role_permissions (role_id, permission_id)
          VALUES (?, ?)
        `).run(userRole.id, perm.id);
      }
      logger.info(`Seeded ${readPermissions.length} read permission(s) to User role (was empty)`);
    }

    // Grant reports:create to Admin and Manager even on pre-seeded roles.
    const rcPerm = db.prepare(`SELECT id FROM permissions WHERE permission_name = 'reports:create'`).get() as { id: number } | undefined;
    if (rcPerm) {
      for (const roleName of ['Admin', 'Manager']) {
        const role = db.prepare('SELECT id FROM roles WHERE role_name = ?').get(roleName) as { id: number } | undefined;
        if (role) {
          db.prepare(`INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)`).run(role.id, rcPerm.id);
        }
      }
    }
    logger.info('✅ Default permissions seeded successfully!');
  } catch (error: any) {
    throw new Error('Seed default permissions error:: ' + error.message, { cause: error });
  }
}

function runStockAdjustmentFinancialMigration(): void {
  try {
    // Step 1: Ensure journal_entries table exists (must be created before FK reference)
    const hasJournalTable = db.prepare(
      `SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='journal_entries'`
    ).get() as { count: number };

    if (hasJournalTable.count === 0) {
      logger.info('Creating journal_entries table...');
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
      logger.info('journal_entries table created');
    }

    // Step 2: Add stock_movements columns if missing
    const hasFinancialValue = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='financial_value'`
    ).get() as { count: number };

    if (hasFinancialValue.count === 0) {
      logger.info('Adding financial columns to stock_movements...');
      db.exec(`
        ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0;
        ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE;
        ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id);
      `);
      logger.info('Financial columns added to stock_movements');
    } else {
      // Recovery: Check for missing journal_entry_id column (partial migration fix)
      const hasJournalEntryId = db.prepare(
        `SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='journal_entry_id'`
      ).get() as { count: number };

      if (hasJournalEntryId.count === 0) {
        logger.info('Adding missing journal_entry_id column...');
        db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
        logger.info('journal_entry_id column added');
      }
    }
  } catch (error: any) {
    throw new Error('Stock adjustment financial migration error:: ' + error.message, { cause: error });
  }
}

function runGLFoundationMigration(): void {
  // Phase 1 of the GL refactor: chart_of_accounts, journal_lines,
  // and accounting_periods. See migrations/add-gl-foundation.sql for
  // schema and seed. The auto-open period is also handled in the SQL.
  try {
    const migrationSQL = fs.readFileSync(
      path.join(MIGRATIONS_DIR, 'add-gl-foundation.sql'),
      'utf8'
    );
    db.exec(migrationSQL);
    logger.info('✅ GL foundation migration applied (chart_of_accounts, journal_lines, accounting_periods)');
  } catch (error: any) {
    throw new Error('GL foundation migration error:: ' + error.message, { cause: error });
  }

  // Add returned_amount column to invoices (idempotent – added in v3.1)
  try {
    const hasReturnedAmt = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('invoices') WHERE name='returned_amount'`
    ).get() as { count: number };
    if (hasReturnedAmt.count === 0) {
      db.exec("ALTER TABLE invoices ADD COLUMN returned_amount DECIMAL(15,2) NOT NULL DEFAULT 0");
      logger.info('✅ returned_amount column added to invoices');
    }
  } catch (error: any) {
    throw new Error('returned_amount migration error:: ' + error.message, { cause: error });
  }

  // Add return_fee column to invoices (idempotent — restocking fee tracking)
  try {
    const hasReturnFee = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('invoices') WHERE name='return_fee'`
    ).get() as { count: number };
    if (hasReturnFee.count === 0) {
      db.exec("ALTER TABLE invoices ADD COLUMN return_fee DECIMAL(15,2) NOT NULL DEFAULT 0");
      logger.info('✅ return_fee column added to invoices');
    }
  } catch (error: any) {
    throw new Error('return_fee migration error:: ' + error.message, { cause: error });
  }

  // Add returned_qty column to invoice_items (per-item return tracking)
  try {
    const hasReturnedQty = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('invoice_items') WHERE name='returned_qty'`
    ).get() as { count: number };
    if (hasReturnedQty.count === 0) {
      db.exec("ALTER TABLE invoice_items ADD COLUMN returned_qty DECIMAL(15,3) NOT NULL DEFAULT 0");
      logger.info('✅ returned_qty column added to invoice_items');
    }
  } catch (error: any) {
    throw new Error('returned_qty migration error:: ' + error.message, { cause: error });
  }
}

function runBatchCostingMigration(): void {
  try {
    // Step 1: Create stock_batches table (if not exists)
    const stockBatchesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='stock_batches'
    `).get() as { name: string } | undefined;

    if (!stockBatchesTableCheck) {
      logger.info('Running batch costing migration...');

      const batchSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-batch-costing.sql'),
        'utf8'
      );

      db.exec(batchSQL);

      logger.info('✅ stock_batches table created!');
    }

    // Step 2: Add batch_id column to stock_movements
    const smBatchIdCheck = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('stock_movements') WHERE name='batch_id'`
    ).get() as { count: number };
    if (!smBatchIdCheck.count) {
      logger.info('Adding batch_id to stock_movements...');
      db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
      logger.info('✅ batch_id added to stock_movements');
    }

    // Step 3: Add batch columns to productions
    const prodBatchIdCheck = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('productions') WHERE name='batch_id'`
    ).get() as { count: number };
    if (!prodBatchIdCheck.count) {
      logger.info('Adding batch columns to productions...');
      db.exec('ALTER TABLE productions ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
      db.exec('ALTER TABLE productions ADD COLUMN batch_no VARCHAR(50)');
      db.exec('ALTER TABLE productions ADD COLUMN unit_cost DECIMAL(15,4) DEFAULT 0');
      db.exec('ALTER TABLE productions ADD COLUMN total_material_cost DECIMAL(15,4) DEFAULT 0');
      db.exec('ALTER TABLE productions ADD COLUMN total_batch_cost DECIMAL(15,4) DEFAULT 0');
      logger.info('✅ Batch columns added to productions');
    }

    // Step 4: Add batch columns to purchases
    const purchBatchIdCheck = db.prepare(
      `SELECT COUNT(*) as count FROM pragma_table_info('purchases') WHERE name='batch_id'`
    ).get() as { count: number };
    if (!purchBatchIdCheck.count) {
      logger.info('Adding batch columns to purchases...');
      db.exec('ALTER TABLE purchases ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
      db.exec('ALTER TABLE purchases ADD COLUMN batch_no VARCHAR(50)');
      logger.info('✅ Batch columns added to purchases');
    }

    logger.info('✅ Batch costing migration completed!');
  } catch (error: any) {
    throw new Error('Batch costing migration error:: ' + error.message, { cause: error });
  }
}

function runCreditBalanceMigration(): void {
  try {
    const hasCreditBalance = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('customers')
      WHERE name='credit_balance'
    `).get() as { count: number };

    if (hasCreditBalance.count === 0) {
      logger.info('Running credit balance migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-credit-balance.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Credit balance column added to customers table!');
    }
  } catch (error: any) {
    throw new Error('Credit balance migration error:: ' + error.message, { cause: error });
  }
}

function runForecastsMigration(): void {
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='demand_forecasts'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running demand forecasts migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-demand-forecasts.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Demand forecasts migration completed!');
    }
  } catch (error: any) {
    throw new Error('Demand forecasts migration error:: ' + error.message, { cause: error });
  }
}

function runEmployeesMigration(): void {
  try {
    const employeesTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='employees'
    `).get() as { name: string } | undefined;

    if (!employeesTableCheck) {
      logger.info('Running employees migration...');

      const employeesSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-employees-table.sql'),
        'utf8'
      );

      db.exec(employeesSQL);

      logger.info('✅ Employees migration completed!');
    }
  } catch (error: any) {
    throw new Error('Employees migration error:: ' + error.message, { cause: error });
  }
}

function runSalaryPaymentsMigration(): void {
  try {
    const salaryTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='salary_payments'
    `).get() as { name: string } | undefined;

    if (!salaryTableCheck) {
      logger.info('Running salary payments migration...');

      const salarySQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-salary-payments.sql'),
        'utf8'
      );

      db.exec(salarySQL);

      logger.info('✅ Salary payments migration completed!');
    }
  } catch (error: any) {
    throw new Error('Salary payments migration error:: ' + error.message, { cause: error });
  }
}

function runPhysicalCountsMigration(): void {
  try {
    const physicalCountsTableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='physical_counts'
    `).get() as { name: string } | undefined;

    if (!physicalCountsTableCheck) {
      logger.info('Running physical counts migration...');

      const physicalCountsSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-physical-counts.sql'),
        'utf8'
      );

      db.exec(physicalCountsSQL);

      logger.info('✅ Physical counts migration completed!');
    }
  } catch (error: any) {
    throw new Error('Physical counts migration error:: ' + error.message, { cause: error });
  }
}

function runCustomReportsMigration(): void {
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='custom_reports'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running custom reports migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-custom-reports.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Custom reports migration completed!');

      // Seed 5 report templates
      seedReportTemplates();
    }
  } catch (error: any) {
    throw new Error('Custom reports migration error:: ' + error.message, { cause: error });
  }
}

function seedReportTemplates(): void {
  try {
    logger.info('Seeding report templates...');

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

    logger.info('✅ Report templates seeded!');
  } catch (error: any) {
    throw new Error('Seed report templates error:: ' + error.message, { cause: error });
  }
}

function runForecastEnhancementsMigration(): void {
  try {
    // Check if forecast_model_config table exists — if so, migration already ran
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='forecast_model_config'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running forecast enhancements migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'enhance-forecasts.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Forecast enhancements migration completed!');
    }
  } catch (error: any) {
    throw new Error('Forecast enhancements migration error:: ' + error.message, { cause: error });
  }
}

function runDashboardLayoutsMigration(): void {
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='dashboard_layouts'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running dashboard layouts migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'dashboard-layouts.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Dashboard layouts migration completed!');
    }
  } catch (error: any) {
    throw new Error('Dashboard layouts migration error:: ' + error.message, { cause: error });
  }
}

function runCashAccountsMigration(): void {
  // Idempotent by construction (INSERT OR IGNORE + CREATE IF NOT EXISTS
  // in the SQL), so it runs on every server start like the GL foundation
  // migration — no column/table pre-check needed.
  try {
    const migrationSQL = fs.readFileSync(
      path.join(MIGRATIONS_DIR, 'add-cash-accounts.sql'),
      'utf8'
    );
    db.exec(migrationSQL);
    logger.info('✅ Cash accounts migration applied (Easypaisa/JazzCash/UPaisa accounts + cash_reconciliations)');
  } catch (error: any) {
    throw new Error('Cash accounts migration error:: ' + error.message, { cause: error });
  }
}

function runOpeningBalancesMigration(): void {
  // Idempotent (CREATE IF NOT EXISTS + INSERT OR IGNORE) — runs on every
  // server start so the seed rows exist before any cash computation.
  try {
    const migrationSQL = fs.readFileSync(
      path.join(MIGRATIONS_DIR, 'add-opening-balances.sql'),
      'utf8'
    );
    db.exec(migrationSQL);
    logger.info('✅ Opening balances migration applied (per-account seed balances)');
  } catch (error: any) {
    throw new Error('Opening balances migration error:: ' + error.message, { cause: error });
  }
}

function runLooseItemMigration(): void {
  try {
    const columnCheck = db.prepare(`
      SELECT COUNT(*) as count FROM pragma_table_info('items')
      WHERE name='sale_type'
    `).get() as { count: number };

    if (columnCheck.count === 0) {
      logger.info('Running loose item support migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-loose-item-support.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ Loose item support migration completed!');
    }
  } catch (error: any) {
    throw new Error('Loose item support migration error:: ' + error.message, { cause: error });
  }
}

function runUserPreferencesMigration(): void {
  // Per-user date-range picker preferences (week start, default range,
  // custom presets) — date-range-picker-spec.md §6.1.
  try {
    const tableCheck = db.prepare(`
      SELECT name FROM sqlite_master
      WHERE type='table' AND name='user_preferences'
    `).get() as { name: string } | undefined;

    if (!tableCheck) {
      logger.info('Running user preferences migration...');

      const migrationSQL = fs.readFileSync(
        path.join(MIGRATIONS_DIR, 'add-user-preferences.sql'),
        'utf8'
      );

      db.exec(migrationSQL);

      logger.info('✅ User preferences migration completed!');
    }
  } catch (error: any) {
    throw new Error('User preferences migration error:: ' + error.message, { cause: error });
  }
}

export interface StockDiscrepancy {
  item_id: number;
  item_code: string;
  warehouse_id: number;
  warehouse_code: string;
  balance_quantity: number | null;
  movement_sum: number;
}

/** Read-only comparison of stock_balances vs SUM(stock_movements). */
export function getStockDiscrepancies(): StockDiscrepancy[] {
  const rows = db.prepare(`
    SELECT
      sm.item_id,
      i.item_code,
      sm.warehouse_id,
      w.warehouse_code,
      sb.quantity AS balance_quantity,
      COALESCE(SUM(sm.quantity), 0) AS movement_sum
    FROM stock_movements sm
    JOIN items i ON i.id = sm.item_id
    JOIN warehouses w ON w.id = sm.warehouse_id
    LEFT JOIN stock_balances sb
      ON sb.item_id = sm.item_id AND sb.warehouse_id = sm.warehouse_id
    GROUP BY sm.item_id, sm.warehouse_id
    HAVING ABS(COALESCE(sb.quantity, 0) - COALESCE(SUM(sm.quantity), 0)) > 0.0005
    ORDER BY sm.item_id, sm.warehouse_id
  `).all() as StockDiscrepancy[];
  return rows;
}

function logStockDiscrepancies(): void {
  const discrepancies = getStockDiscrepancies();
  if (discrepancies.length === 0) {
    logger.info('✅ Stock balances consistent with movements');
    return;
  }
  logger.warn(`⚠ ${discrepancies.length} stock balance discrepanc(ies) detected (NOT auto-repaired — run the gated repair script to fix):`);
  for (const d of discrepancies) {
    logger.warn(`  item ${d.item_code} (${d.item_id}) in ${d.warehouse_code} (${d.warehouse_id}): balance=${d.balance_quantity ?? 'none'} movements=${d.movement_sum}`);
  }
}

function recalcInvoiceBalancesBackfill(): void {
  // One-time backfill (audit-remediation 3.3): recompute invoice paid /
  // balance / status from payment_allocations. Runs ONCE per database via
  // the migration ledger; never on subsequent boots.
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
  logger.info('✅ Invoice balances recalculated from allocations (one-time backfill)');
}

function paymentLedgerDescriptionsBackfill(): void {
  // One-time backfill: rewrite 'Payment against <id>' descriptions to carry
  // real invoice numbers.
  const entries = db.prepare(`
    SELECT cl.id, cl.reference_no, cl.description
    FROM customer_ledger cl
    WHERE cl.transaction_type = 'PAYMENT'
      AND cl.description LIKE 'Payment against %'
  `).all() as { id: number; reference_no: string; description: string }[];

  for (const entry of entries) {
    const match = entry.description.match(/Payment against (.+)/);
    if (!match) continue;
    const invoiceRefs = match[1].split(',').map((s: string) => s.trim());
    const invoiceNumbers = invoiceRefs.map((ref: string) => {
      if (/[a-zA-Z]/.test(ref)) return ref;
      const invoiceId = parseInt(ref, 10);
      if (!isNaN(invoiceId)) {
        const invoice = db.prepare('SELECT invoice_no FROM invoices WHERE id = ?').get(invoiceId) as { invoice_no: string } | undefined;
        return invoice ? invoice.invoice_no : `Invoice #${invoiceId}`;
      }
      return ref;
    });
    const newDescription = `Payment against ${invoiceNumbers.join(', ')}`;
    if (newDescription !== entry.description) {
      db.prepare('UPDATE customer_ledger SET description = ? WHERE id = ?').run(newDescription, entry.id);
    }
  }
  logger.info(`✅ Payment ledger descriptions fixed (${entries.length} scanned, one-time backfill)`);
}

function recoverPaymentsInvoiceId(): void {
  // Task 3.2 (audit-remediation / MIG-02): the historical payments rebuild
  // dropped payments.invoice_id. Recover it from payment_allocations where
  // each allocation set maps to exactly one invoice.
  const candidates = db.prepare(`
    SELECT pa.payment_id, MIN(pa.invoice_id) AS first_invoice, MAX(pa.invoice_id) AS last_invoice,
           COUNT(DISTINCT pa.invoice_id) AS n_invoices
    FROM payment_allocations pa
    JOIN payments p ON p.id = pa.payment_id
    WHERE p.invoice_id IS NULL
    GROUP BY pa.payment_id
  `).all() as Array<{ payment_id: number; first_invoice: number; last_invoice: number; n_invoices: number }>;

  let recovered = 0;
  for (const c of candidates) {
    if (c.n_invoices !== 1) continue; // ambiguous — leave NULL
    db.prepare('UPDATE payments SET invoice_id = ? WHERE id = ? AND invoice_id IS NULL')
      .run(c.first_invoice, c.payment_id);
    recovered++;
  }

  if (recovered > 0) {
    logger.info(`✅ Recovered invoice_id on ${recovered} payment(s) from payment_allocations`);
    try {
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (NULL, 'DATA_RECOVERY', 'payment', NULL, ?)
      `).run(`Migration recovered payments.invoice_id for ${recovered} payment(s) from payment_allocations`);
    } catch { /* activity_log schema may predate this migration — non-fatal */ }
  }
}

function backfillPaymentsPurchaseOrderId(): void {
  // Task 2.4 (financial-audit-p0-remediation / PAY-06 residue): the
  // historical payments rebuild nulled purchase_order_id. Recover it for
  // single-PO payments — exactly one distinct po_allocations.po_id and no
  // purchase allocations (mirrors supplier-payment-po-link spec).
  const candidates = db.prepare(`
    SELECT p.id AS payment_id, MIN(pa.po_id) AS first_po, MAX(pa.po_id) AS last_po,
           COUNT(DISTINCT pa.po_id) AS n_pos
    FROM payments p
    JOIN po_allocations pa ON pa.payment_id = p.id
    WHERE p.supplier_id IS NOT NULL
      AND p.purchase_order_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM purchase_allocations pca WHERE pca.payment_id = p.id)
    GROUP BY p.id
  `).all() as Array<{ payment_id: number; first_po: number; last_po: number; n_pos: number }>;

  let recovered = 0;
  for (const c of candidates) {
    if (c.n_pos !== 1) continue; // multi-PO / ambiguous — stays NULL per spec
    db.prepare('UPDATE payments SET purchase_order_id = ? WHERE id = ? AND purchase_order_id IS NULL')
      .run(c.first_po, c.payment_id);
    recovered++;
  }

  if (recovered > 0) {
    logger.info(`✅ Backfilled payments.purchase_order_id on ${recovered} single-PO payment(s) from po_allocations`);
    try {
      db.prepare(`
        INSERT INTO activity_log (user_id, action, entity_type, entity_id, description)
        VALUES (NULL, 'DATA_RECOVERY', 'payment', NULL, ?)
      `).run(`Migration backfilled payments.purchase_order_id for ${recovered} payment(s) from po_allocations`);
    } catch { /* activity_log schema may predate this migration — non-fatal */ }
  }
}

function reconcileOrphanedJournalLines(): void {
  // Task 5.4 (AUD-06): repair historical damage from hard-deleted invoices —
  // void journal_lines whose reference document no longer exists, and NULL
  // dangling journal_entry_id links on stock_movements. Post-condition:
  // non-voided journal_lines must balance per entry; startup fails otherwise.
  const orphans = db.prepare(`
    SELECT jl.id FROM journal_lines jl
    LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE jl.voided = 0
      AND (je.id IS NULL OR (
        je.reference_type = 'INVOICE' AND je.reference_id IS NOT NULL AND
        NOT EXISTS (SELECT 1 FROM invoices i WHERE i.id = je.reference_id)
      ))
  `).all() as Array<{ id: number }>;

  if (orphans.length > 0) {
    logger.warn(`Voiding ${orphans.length} orphaned journal_line(s) from hard-deleted documents`);
    const v = db.prepare('UPDATE journal_lines SET voided = 1, void_reason = ? WHERE id = ?');
    for (const o of orphans) v.run('orphaned document reconciled', o.id);
  }

  const dangling = db.prepare(`
    SELECT sm.id FROM stock_movements sm
    LEFT JOIN journal_entries je ON je.id = sm.journal_entry_id
    WHERE sm.journal_entry_id IS NOT NULL AND je.id IS NULL
  `).all() as Array<{ id: number }>;
  if (dangling.length > 0) {
    logger.warn(`Clearing ${dangling.length} dangling stock_movements.journal_entry_id reference(s)`);
    const u = db.prepare('UPDATE stock_movements SET journal_entry_id = NULL WHERE id = ?');
    for (const d of dangling) u.run(d.id);
  }

  // Post-condition: every non-voided line set must balance per journal entry.
  const imbalanced = db.prepare(`
    SELECT je.id, SUM(jl.debit) AS dr, SUM(jl.credit) AS cr
    FROM journal_entries je JOIN journal_lines jl ON jl.journal_entry_id = je.id
    WHERE jl.voided = 0
    GROUP BY je.id
    HAVING ABS(SUM(jl.debit) - SUM(jl.credit)) > 0.005
  `).all() as Array<{ id: number; dr: number; cr: number }>;
  if (imbalanced.length > 0) {
    throw new Error(`Trial balance integrity violated: ${imbalanced.length} unbalanced journal_entries after reconciliation`);
  }
}

function runRollback(migrationName: string): void {
  // --rollback=<name> is operator-supplied; restrict to safe filename characters
  // so the joined path cannot traverse out of the rollbacks directory.
  if (!/^[A-Za-z0-9._-]+$/.test(migrationName)) {
    logger.error(`Invalid migration name: ${migrationName}`);
    process.exit(1);
  }
  const rollbackFile = path.join(MIGRATIONS_DIR, 'rollbacks/rollback-' + migrationName + '.sql'); // mimosa-ignore
  if (!fs.existsSync(rollbackFile)) {
    logger.error(`Rollback file not found: ${rollbackFile}`);
    process.exit(1);
  }
  logger.info(`Running rollback for migration: ${migrationName}`);
  try {
    const rollbackSQL = fs.readFileSync(rollbackFile, 'utf8');
    db.exec(rollbackSQL);
    logger.info(`✅ Rollback completed for: ${migrationName}`);
  } catch (error: any) {
    logger.error(`Rollback error for ${migrationName}:`, error.message);
    process.exit(1);
  }
}

function runRollbackAll(): void {
  const rollbacksDir = path.join(MIGRATIONS_DIR, 'rollbacks');
  if (!fs.existsSync(rollbacksDir)) {
    logger.error('Rollbacks directory not found');
    process.exit(1);
  }
  const files = fs.readdirSync(rollbacksDir).filter(f => f.endsWith('.sql')).sort().reverse();
  logger.info(`Running ${files.length} rollbacks in reverse order...`);
  for (const file of files) {
    const migrationName = file.replace('rollback-', '').replace('.sql', '');
    logger.info(`Rolling back: ${migrationName}`);
    try {
      const rollbackSQL = fs.readFileSync(path.join(rollbacksDir, file), 'utf8');
      db.exec(rollbackSQL);
      logger.info(`✅ Rolled back: ${migrationName}`);
    } catch (error: any) {
      logger.error(`Rollback error for ${migrationName}:`, error.message);
    }
  }
  logger.info('✅ All rollbacks completed');
}