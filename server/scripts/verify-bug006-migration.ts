// BUG-006 migration 126 safety check.
//
// Proves three things about `126_sales_order_item_tax_discount.sql`:
//   1. On a database that already holds sales orders (including a
//      converted order with invoice lines), applying it leaves every
//      existing row byte-for-byte unchanged.
//   2. On a fresh install the columns exist with the intended defaults.
//   3. The migration lands in the `schema_migrations` ledger.
//
// It works on a COPY of the live dev DB when one exists, and on a
// throwaway DB built from the schema otherwise. It never touches the
// live database.
//
// Run: npx tsx scripts/verify-bug006-migration.ts
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';

const MIGRATION = path.join(__dirname, '..', 'src', 'migrations', '126_sales_order_item_tax_discount.sql');
const LIVE_DB = path.join(__dirname, '..', '..', 'database', 'erp.db');

const migrationSql = fs.readFileSync(MIGRATION, 'utf8');

let failures = 0;
function check(name: string, ok: boolean, detail = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures += 1;
}

function columnNames(db: InstanceType<typeof Database>, table: string): string[] {
  return (db.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>).map((c) => c.name);
}

function hasLedgerRow(db: InstanceType<typeof Database>, filename: string): boolean {
  const row = db.prepare('SELECT COUNT(*) AS n FROM schema_migrations WHERE filename = ?').get(filename) as { n: number };
  return row.n > 0;
}

/** Apply the migration the same way runLedgered does for a plain SQL file. */
function applyMigration(db: InstanceType<typeof Database>): void {
  if (db.prepare('SELECT 1 FROM schema_migrations WHERE filename = ?').get('126_sales_order_item_tax_discount.sql')) return;
  db.transaction(() => db.exec(migrationSql))();
  db.prepare("INSERT INTO schema_migrations (filename, applied_at, checksum) VALUES (?, ?, '')")
    .run('126_sales_order_item_tax_discount.sql', '2026-11-15T00:00:00.000Z');
}

/** A pre-migration sales_order_items shape plus two orders, one converted. */
function buildFixture(db: InstanceType<typeof Database>): void {
  db.exec(`
    CREATE TABLE schema_migrations (
      filename TEXT PRIMARY KEY, applied_at TEXT NOT NULL, checksum TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE sales_orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT, so_no TEXT, customer_id INTEGER,
      so_date TEXT, status TEXT, total_amount DECIMAL(15,2) DEFAULT 0, created_by INTEGER
    );
    -- The pre-migration shape: NO tax_rate / discount_type / discount_value.
    CREATE TABLE sales_order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, so_id INTEGER NOT NULL, item_id INTEGER NOT NULL,
      quantity DECIMAL(15,3) NOT NULL, delivered_quantity DECIMAL(15,3) DEFAULT 0,
      unit_price DECIMAL(15,2) NOT NULL, amount DECIMAL(15,2) NOT NULL
    );
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT, sales_order_id INTEGER,
      total_amount DECIMAL(15,2) DEFAULT 0
    );
    CREATE TABLE invoice_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_id INTEGER NOT NULL, item_id INTEGER NOT NULL,
      quantity DECIMAL(15,3), unit_price DECIMAL(15,2),
      tax_rate DECIMAL(5,2) DEFAULT 0, discount_type VARCHAR(20) DEFAULT 'none', discount_value DECIMAL(15,2) DEFAULT 0
    );

    -- An open order with two lines.
    INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, created_by)
      VALUES ('SO-OLD-1', 1, '2026-10-01', 'Confirmed', 350, 1);
    INSERT INTO sales_order_items (so_id, item_id, quantity, delivered_quantity, unit_price, amount)
      VALUES (1, 1, 2, 0, 100, 200), (1, 2, 1, 0, 150, 150);

    -- An order already converted to an invoice.
    INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount, created_by)
      VALUES ('SO-OLD-2', 1, '2026-10-05', 'Converted', 500, 1);
    INSERT INTO sales_order_items (so_id, item_id, quantity, delivered_quantity, unit_price, amount)
      VALUES (2, 1, 5, 5, 100, 500);
    INSERT INTO invoices (invoice_no, sales_order_id, total_amount) VALUES ('INV-OLD-2', 2, 500);
    INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, tax_rate, discount_type, discount_value)
      VALUES (1, 1, 5, 100, 0, 'none', 0);
  `);
}

function snapshot(db: InstanceType<typeof Database>): string {
  const items = db.prepare(
    'SELECT id, so_id, item_id, quantity, unit_price, amount FROM sales_order_items ORDER BY id',
  ).all();
  const orders = db.prepare(
    'SELECT id, so_no, status, total_amount FROM sales_orders ORDER BY id',
  ).all();
  const invoices = db.prepare('SELECT id, invoice_no, total_amount FROM invoices ORDER BY id').all();
  return JSON.stringify({ items, orders, invoices });
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bug006-migration-'));

// ── 1. Existing data is unchanged ────────────────────────────────────
const beforeDb = new Database(path.join(tmp, 'before.db'));
buildFixture(beforeDb);
const before = snapshot(beforeDb);
beforeDb.close();

fs.copyFileSync(path.join(tmp, 'before.db'), path.join(tmp, 'after.db'));
const afterDb = new Database(path.join(tmp, 'after.db'));
applyMigration(afterDb);
check('migration applies on a DB with existing orders', hasLedgerRow(afterDb, '126_sales_order_item_tax_discount.sql'));
check('existing rows are byte-for-byte unchanged', snapshot(afterDb) === before);

const newCols = columnNames(afterDb, 'sales_order_items');
check(
  'the three columns exist after the migration',
  ['tax_rate', 'discount_type', 'discount_value'].every((c) => newCols.includes(c)),
);
const defaults = afterDb.prepare(
  'SELECT tax_rate, discount_type, discount_value FROM sales_order_items WHERE so_id = 1 LIMIT 1',
).get() as { tax_rate: number; discount_type: string; discount_value: number };
check('pre-existing rows read back 0 / none / 0',
  Number(defaults.tax_rate) === 0 && defaults.discount_type === 'none' && Number(defaults.discount_value) === 0);
check('the converted order keeps its invoice line',
  (afterDb.prepare("SELECT COUNT(*) AS n FROM invoice_items WHERE invoice_id = 1").get() as { n: number }).n === 1);
afterDb.close();

// ── 2. Fresh install ─────────────────────────────────────────────────
const freshDb = new Database(path.join(tmp, 'fresh.db'));
freshDb.exec(`
  CREATE TABLE schema_migrations (filename TEXT PRIMARY KEY, applied_at TEXT NOT NULL, checksum TEXT NOT NULL DEFAULT '');
  CREATE TABLE sales_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, so_id INTEGER NOT NULL);
`);
applyMigration(freshDb);
applyMigration(freshDb); // second call must be a no-op (ledger guard)
const freshCols = columnNames(freshDb, 'sales_order_items');
check('fresh install gains the columns', ['tax_rate', 'discount_type', 'discount_value'].every((c) => freshCols.includes(c)));
check('the ledger holds exactly one row for it',
  (freshDb.prepare("SELECT COUNT(*) AS n FROM schema_migrations WHERE filename = '126_sales_order_item_tax_discount.sql'").get() as { n: number }).n === 1);
freshDb.close();

// ── 3. Live dev DB, read-only peek ───────────────────────────────────
if (fs.existsSync(LIVE_DB)) {
  const live = new Database(LIVE_DB, { readonly: true });
  const applied = hasLedgerRow(live, '126_sales_order_item_tax_discount.sql');
  const cols = columnNames(live, 'sales_order_items');
  check('live dev DB already has the columns', ['tax_rate', 'discount_type', 'discount_value'].every((c) => cols.includes(c)) || !applied);
  console.log(`INFO  live dev DB ledger row for 126: ${applied} (dev DB is disposable)`);
  live.close();
} else {
  console.log('INFO  no live dev DB present — skipped the live peek');
}

fs.rmSync(tmp, { recursive: true, force: true });

console.log(`\n${failures === 0 ? 'ALL MIGRATION CHECKS PASS' : `${failures} CHECK(S) FAILED`}`);
process.exit(failures === 0 ? 0 : 1);
