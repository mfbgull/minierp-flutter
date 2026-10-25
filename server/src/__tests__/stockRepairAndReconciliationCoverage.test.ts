import { beforeEach, describe, expect, it } from '@jest/globals';
import Database from 'better-sqlite3';
import db from '../config/database';
import {
  repairLegacyBOMItemsSchema,
  runBatchSourceTypeRebuild,
  runStockCoverageReconciliation,
} from '../config/database';

/**
 * Fallow health remediation — `runBatchSourceTypeRebuild` (CRAP 210),
 * `runStockCoverageReconciliation` mismatch branches and
 * `repairLegacyBOMItemsSchema` legacy-shape branches.
 */

function legacyBatchDb(extraColumns = false): Database.Database {
  const mem = new Database(':memory:');
  mem.exec(`
    CREATE TABLE items (id INTEGER PRIMARY KEY);
    CREATE TABLE warehouses (id INTEGER PRIMARY KEY);
    CREATE TABLE goods_receipt_items (id INTEGER PRIMARY KEY);
    CREATE TABLE stock_batches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_no TEXT UNIQUE NOT NULL,
      item_id INTEGER NOT NULL,
      warehouse_id INTEGER NOT NULL,
      source_type TEXT NOT NULL CHECK(source_type IN ('PURCHASE','PRODUCTION')),
      source_id INTEGER NOT NULL,
      quantity_original REAL NOT NULL DEFAULT 0,
      quantity_remaining REAL NOT NULL DEFAULT 0,
      unit_cost REAL NOT NULL DEFAULT 0,
      received_date TEXT NOT NULL
    );
  `);
  if (extraColumns) {
    mem.exec(`
      ALTER TABLE stock_batches ADD COLUMN created_at TIMESTAMP;
      ALTER TABLE stock_batches ADD COLUMN expiry_date DATE;
      ALTER TABLE stock_batches ADD COLUMN halted BOOLEAN;
      ALTER TABLE stock_batches ADD COLUMN halted_reason TEXT;
    `);
  }
  mem.prepare('INSERT INTO items (id) VALUES (1)').run();
  mem.prepare('INSERT INTO warehouses (id) VALUES (1)').run();
  mem.prepare('INSERT INTO goods_receipt_items (id) VALUES (9)').run();
  const insert = mem.prepare(
    `INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id, quantity_original, quantity_remaining, unit_cost, received_date)
     VALUES (?, 1, 1, ?, ?, 2, 2, 5, '2026-01-01')`
  );
  insert.run('LEG-RECON', 'PURCHASE', 0);
  insert.run('LEG-GR', 'PURCHASE', 9);
  insert.run('LEG-PROD', 'PRODUCTION', 7);
  return mem;
}

describe('runBatchSourceTypeRebuild', () => {
  it('widens a legacy CHECK and re-stamps every namespace', () => {
    const mem = legacyBatchDb();

    runBatchSourceTypeRebuild(mem);

    const rows = mem
      .prepare('SELECT batch_no, source_type FROM stock_batches ORDER BY id')
      .all() as Array<{ batch_no: string; source_type: string }>;
    expect(rows).toEqual([
      { batch_no: 'LEG-RECON', source_type: 'RECON' },
      { batch_no: 'LEG-GR', source_type: 'GOODS_RECEIPT' },
      { batch_no: 'LEG-PROD', source_type: 'PRODUCTION' },
    ]);
    const sql = (
      mem.prepare(`SELECT sql FROM sqlite_master WHERE name = 'stock_batches'`).get() as {
        sql: string;
      }
    ).sql;
    expect(sql).toContain("'RECON'");
    mem.close();
  });

  it('keeps optional columns that the legacy table carried', () => {
    const mem = legacyBatchDb(true);
    mem.prepare(
      `UPDATE stock_batches SET created_at = '2026-01-02', expiry_date = '2027-01-01',
         halted = 1, halted_reason = 'qa' WHERE batch_no = 'LEG-PROD'`
    ).run();

    runBatchSourceTypeRebuild(mem);

    const row = mem
      .prepare(
        `SELECT created_at, expiry_date, halted, halted_reason FROM stock_batches
         WHERE batch_no = 'LEG-PROD'`
      )
      .get() as Record<string, unknown>;
    expect(row).toMatchObject({
      created_at: '2026-01-02',
      expiry_date: '2027-01-01',
      halted: 1,
      halted_reason: 'qa',
    });
    mem.close();
  });

  it('no-ops when the table is already widened', () => {
    const mem = legacyBatchDb();
    runBatchSourceTypeRebuild(mem);
    expect(() => runBatchSourceTypeRebuild(mem)).not.toThrow();
    mem.close();
  });
});

describe('runStockCoverageReconciliation mismatches', () => {
  let underItem = 0;
  let overItem = 0;
  let warehouseId = 0;

  beforeEach(() => {
    db.prepare('DELETE FROM batch_stock_by_location').run();
    db.prepare('DELETE FROM stock_balances').run();
    db.prepare('DELETE FROM stock_batches').run();
    const warehouse = db
      .prepare(
        `INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('COV-WH', 'Coverage WH')`
      )
      .run();
    warehouseId = Number(warehouse.lastInsertRowid);
    underItem = Number(
      db
        .prepare(
          `INSERT INTO items (item_code, item_name, standard_cost)
           VALUES ('COV-UNDER', 'Under', 10)`
        )
        .run().lastInsertRowid
    );
    overItem = Number(
      db
        .prepare(
          `INSERT INTO items (item_code, item_name, standard_cost)
           VALUES ('COV-OVER', 'Over', 4)`
        )
        .run().lastInsertRowid
    );
    const balance = db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)`
    );
    balance.run(underItem, warehouseId, 5);
    balance.run(overItem, warehouseId, 2);
    db.prepare(
      `INSERT INTO stock_batches (
         batch_no, item_id, warehouse_id, source_type, source_id,
         quantity_original, quantity_remaining, unit_cost, received_date
       ) VALUES ('COV-OVER-BATCH', ?, ?, 'PURCHASE', 1, 5, 5, 4, '2026-01-01')`
    ).run(overItem, warehouseId);
  });

  it('mints under-coverage and trims over-coverage, then stays idempotent', () => {
    runStockCoverageReconciliation(db);

    const under = db
      .prepare(
        `SELECT source_type, quantity_remaining, unit_cost FROM stock_batches
         WHERE item_id = ?`
      )
      .get(underItem) as {
      source_type: string;
      quantity_remaining: number;
      unit_cost: number;
    };
    expect(under).toEqual({ source_type: 'RECON', quantity_remaining: 5, unit_cost: 10 });

    const over = db
      .prepare(
        `SELECT SUM(quantity_remaining) AS q FROM stock_batches WHERE item_id = ?`
      )
      .get(overItem) as { q: number };
    expect(over.q).toBe(2);

    const entry = db
      .prepare(
        `SELECT amount FROM journal_entries
         WHERE reference_type = 'RECON' ORDER BY id DESC LIMIT 1`
      )
      .get() as { amount: number } | undefined;
    expect(entry?.amount).toBe(50);

    const batchesBefore = (
      db.prepare('SELECT COUNT(*) AS n FROM stock_batches').get() as { n: number }
    ).n;
    runStockCoverageReconciliation(db);
    expect(
      (db.prepare('SELECT COUNT(*) AS n FROM stock_batches').get() as { n: number }).n
    ).toBe(batchesBefore);
  });
});

interface LegacyShape {
  unitCost: boolean;
  createdAt: boolean;
}

function legacyBomDb(shape: LegacyShape): Database.Database {
  const mem = new Database(':memory:');
  mem.exec(`
    CREATE TABLE users (id INTEGER PRIMARY KEY);
    CREATE TABLE items (id INTEGER PRIMARY KEY);
    CREATE TABLE bom (
      id INTEGER PRIMARY KEY,
      bom_no TEXT,
      finished_item_id INTEGER,
      quantity REAL,
      is_active INTEGER,
      notes TEXT,
      created_by INTEGER,
      created_at TEXT,
      updated_at TEXT
    );
    CREATE TABLE boms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bom_no TEXT UNIQUE NOT NULL,
      bom_name TEXT NOT NULL,
      finished_item_id INTEGER NOT NULL,
      quantity REAL NOT NULL DEFAULT 1,
      description TEXT,
      is_active INTEGER DEFAULT 1,
      created_by INTEGER,
      created_at TEXT,
      updated_at TEXT
    );
  `);
  const cols = ['id INTEGER PRIMARY KEY', 'bom_id INTEGER REFERENCES bom(id)', 'item_id INTEGER', 'quantity REAL NOT NULL'];
  if (shape.unitCost) cols.push('unit_cost REAL');
  if (shape.createdAt) cols.push('created_at TEXT');
  mem.exec(`CREATE TABLE bom_items (${cols.join(', ')})`);
  mem.prepare('INSERT INTO users (id) VALUES (7)').run();
  mem.prepare('INSERT INTO items (id) VALUES (1)').run();
  mem.prepare('INSERT INTO items (id) VALUES (2)').run();
  return mem;
}

describe('repairLegacyBOMItemsSchema legacy shapes', () => {
  it('roughly migrates headers and items when every legacy column exists', () => {
    const mem = legacyBomDb({ unitCost: true, createdAt: true });
    mem.prepare(
      `INSERT INTO bom (id, bom_no, finished_item_id, quantity, is_active, notes, created_by)
       VALUES (1, 'BOM-LEG-1', 1, 2, 1, 'legacy', 7)`
    ).run();
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (2, '')`).run();
    // The second header's generated number already exists => reuse branch.
    mem.prepare(
      `INSERT INTO boms (id, bom_no, bom_name, finished_item_id, quantity)
       VALUES (5, 'BOM-2', 'existing', 1, 1)`
    ).run();
    const insert = mem.prepare(
      `INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost, created_at)
       VALUES (?, ?, ?, ?, 3, '2026-01-01')`
    );
    insert.run(1, 1, 1, 2);
    insert.run(2, 1, 999, 1); // orphan item
    insert.run(3, 2, 2, 1);

    repairLegacyBOMItemsSchema(mem);

    expect(
      (mem.prepare('SELECT COUNT(*) AS n FROM bom_items').get() as { n: number }).n
    ).toBe(2);
    expect(
      (mem.prepare('SELECT COUNT(*) AS n FROM bom_items_legacy').get() as { n: number }).n
    ).toBe(3);
    mem.close();
  });

  it('allocates a fresh header id and falls back to defaults', () => {
    const mem = legacyBomDb({ unitCost: true, createdAt: true });
    mem.prepare(
      `INSERT INTO boms (id, bom_no, bom_name, finished_item_id, quantity)
       VALUES (1, 'BOM-TAKEN', 'taken', 1, 1)`
    ).run();
    mem.prepare(`INSERT INTO bom (id, bom_no, finished_item_id) VALUES (1, 'BOM-NEW', 1)`).run();
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (2, NULL)`).run();

    repairLegacyBOMItemsSchema(mem);

    const headers = mem
      .prepare('SELECT id, bom_no, quantity, is_active, created_by FROM boms ORDER BY bom_no')
      .all() as Array<Record<string, unknown>>;
    expect(headers).toEqual([
      { id: 3, bom_no: 'BOM-2', quantity: 1, is_active: 1, created_by: 7 },
      expect.objectContaining({ id: 2, bom_no: 'BOM-NEW', quantity: 1, is_active: 1, created_by: 7 }),
      { id: 1, bom_no: 'BOM-TAKEN', quantity: 1, is_active: 1, created_by: null },
    ]);
    mem.close();
  });

  it('handles unit_cost-only legacy tables', () => {
    const mem = legacyBomDb({ unitCost: true, createdAt: false });
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (1, 'BOM-U')`).run();
    mem.prepare(`INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost) VALUES (1, 1, 1, 1, 5)`).run();

    repairLegacyBOMItemsSchema(mem);

    expect(
      mem.prepare('SELECT unit_cost FROM bom_items WHERE id = 1').get()
    ).toEqual({ unit_cost: 5 });
    mem.close();
  });

  it('handles created_at-only legacy tables', () => {
    const mem = legacyBomDb({ unitCost: false, createdAt: true });
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (1, 'BOM-C')`).run();
    mem.prepare(`INSERT INTO bom_items (id, bom_id, item_id, quantity, created_at) VALUES (1, 1, 1, 1, '2026-02-02')`).run();

    repairLegacyBOMItemsSchema(mem);

    expect(
      mem.prepare('SELECT created_at FROM bom_items WHERE id = 1').get()
    ).toEqual({ created_at: '2026-02-02' });
    mem.close();
  });

  it('handles legacy tables with neither optional column', () => {
    const mem = legacyBomDb({ unitCost: false, createdAt: false });
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (1, 'BOM-N')`).run();
    mem.prepare(`INSERT INTO bom_items (id, bom_id, item_id, quantity) VALUES (1, 1, 1, 1)`).run();

    repairLegacyBOMItemsSchema(mem);

    expect(mem.prepare('SELECT unit_cost, created_at FROM bom_items WHERE id = 1').get()).toEqual({
      unit_cost: null,
      created_at: expect.any(String),
    });
    mem.close();
  });

  it('refuses to overwrite an existing archive', () => {
    const mem = legacyBomDb({ unitCost: true, createdAt: true });
    mem.exec('CREATE TABLE bom_items_legacy (id INTEGER PRIMARY KEY)');
    mem.prepare(`INSERT INTO bom (id, bom_no) VALUES (1, 'BOM-X')`).run();
    mem.prepare(`INSERT INTO bom_items (id, bom_id, item_id, quantity) VALUES (1, 1, 1, 1)`).run();

    expect(() => repairLegacyBOMItemsSchema(mem)).toThrow(
      'bom_items_legacy already exists'
    );
    mem.close();
  });

  it('ignores tables that already use the current schema', () => {
    const mem = new Database(':memory:');
    mem.exec(`
      CREATE TABLE items (id INTEGER PRIMARY KEY);
      CREATE TABLE boms (id INTEGER PRIMARY KEY, bom_no TEXT);
      CREATE TABLE bom_items (id INTEGER PRIMARY KEY, bom_id INTEGER REFERENCES boms(id), item_id INTEGER, quantity REAL NOT NULL);
    `);
    expect(() => repairLegacyBOMItemsSchema(mem)).not.toThrow();
    mem.close();
  });
});
