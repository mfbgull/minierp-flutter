/** TEMPORARY scratch probe 2 — delete after use. */
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

const TABLES = [
  'invoices', 'invoice_items', 'stock_movements', 'stock_batches', 'stock_balances',
  'purchases', 'expenses', 'opening_balances', 'suppliers', 'customers',
  'items', 'warehouses', 'supplier_ledger', 'accounting_periods', 'settings',
];

it('probe ddl', () => {
  const db = createFixtureDb();
  for (const t of TABLES) {
    const row = db.prepare(`SELECT sql FROM sqlite_master WHERE type='table' AND name = ?`).get(t) as { sql: string } | undefined;
    console.log(`\n===== ${t} =====\n${row?.sql ?? 'MISSING'}`);
  }
  console.log('\n===== NOTNULL-without-default columns per table =====');
  for (const t of TABLES) {
    const info = db.pragma(`table_info(${t})`) as { name: string; notnull: number; dflt_value: string | null; pk: number }[];
    const req = info.filter((c) => c.notnull === 1 && c.dflt_value === null && c.pk === 0).map((c) => c.name);
    console.log(`${t}: ${req.join(', ')}`);
  }
  expect(true).toBe(true);
});