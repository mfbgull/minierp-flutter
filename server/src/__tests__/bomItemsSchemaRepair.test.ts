import Database from 'better-sqlite3';
import { describe, expect, it } from '@jest/globals';
import { repairLegacyBOMItemsSchema } from '../config/database';

/**
 * Fallow health remediation — the legacy bom_items foreign key.
 *
 * init.sql created bom_items.bom_id REFERENCES bom(id); BOMModel writes to
 * boms. The repair migrates legacy headers, rebuilds the table with the
 * documented FKs, and archives every original row.
 */
function createLegacyDb(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  db.exec(`
    CREATE TABLE users (id INTEGER PRIMARY KEY);
    CREATE TABLE items (
      id INTEGER PRIMARY KEY,
      item_code TEXT NOT NULL
    );
    CREATE TABLE bom (
      id INTEGER PRIMARY KEY,
      bom_no TEXT UNIQUE NOT NULL,
      finished_item_id INTEGER NOT NULL,
      quantity DECIMAL DEFAULT 1,
      is_active BOOLEAN DEFAULT 1,
      notes TEXT,
      created_by INTEGER,
      created_at DATETIME,
      updated_at DATETIME,
      FOREIGN KEY (finished_item_id) REFERENCES items(id),
      FOREIGN KEY (created_by) REFERENCES users(id)
    );
    CREATE TABLE bom_items (
      id INTEGER PRIMARY KEY,
      bom_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      quantity DECIMAL NOT NULL,
      unit_cost DECIMAL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (bom_id) REFERENCES bom(id) ON DELETE CASCADE,
      FOREIGN KEY (item_id) REFERENCES items(id)
    );
    CREATE TABLE boms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bom_no TEXT UNIQUE NOT NULL,
      bom_name TEXT NOT NULL,
      finished_item_id INTEGER NOT NULL,
      quantity DECIMAL NOT NULL DEFAULT 1,
      description TEXT,
      is_active BOOLEAN DEFAULT 1,
      created_by INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);
  db.prepare('INSERT INTO users (id) VALUES (1)').run();
  db.prepare('INSERT INTO items (id, item_code) VALUES (10, ?)').run('IT-10');
  db.prepare('INSERT INTO items (id, item_code) VALUES (20, ?)').run('IT-20');
  return db;
}

describe('repairLegacyBOMItemsSchema', () => {
  it('migrates legacy headers and rebuilds bom_items with the right FKs', () => {
    const db = createLegacyDb();
    db.prepare(`
      INSERT INTO bom (id, bom_no, finished_item_id, quantity, notes, created_by)
      VALUES (1, 'BOM-LEG-1', 10, 2, 'legacy note', 1)
    `).run();
    db.prepare(`
      INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost, created_at)
      VALUES (1, 1, 10, 2, 5, '2026-01-01 00:00:00')
    `).run();
    db.prepare(`
      INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost, created_at)
      VALUES (2, 1, 20, 3, 7, '2026-01-01 00:00:00')
    `).run();

    repairLegacyBOMItemsSchema(db);

    const fks = db
      .prepare(`PRAGMA foreign_key_list('bom_items')`)
      .all() as Array<{ table: string }>;
    expect(fks.map((fk) => fk.table).sort()).toEqual(['boms', 'items']);

    const bom = db
      .prepare(`SELECT bom_no, bom_name, description, created_by FROM boms`)
      .get() as {
      bom_no: string;
      bom_name: string;
      description: string;
      created_by: number;
    };
    expect(bom).toEqual({
      bom_no: 'BOM-LEG-1',
      bom_name: 'BOM-LEG-1',
      description: 'legacy note',
      created_by: 1,
    });

    const items = db
      .prepare(
        `SELECT id, bom_id, item_id, quantity, unit_cost
         FROM bom_items ORDER BY id`,
      )
      .all();
    expect(items).toEqual([
      { id: 1, bom_id: 1, item_id: 10, quantity: 2, unit_cost: 5 },
      { id: 2, bom_id: 1, item_id: 20, quantity: 3, unit_cost: 7 },
    ]);
    expect(
      (db.prepare('SELECT COUNT(*) AS count FROM bom_items_legacy').get() as {
        count: number;
      }).count,
    ).toBe(2);

    // Idempotent: a second boot sees the repaired FK and does nothing.
    repairLegacyBOMItemsSchema(db);
    expect(
      (db.prepare('SELECT COUNT(*) AS count FROM bom_items').get() as {
        count: number;
      }).count,
    ).toBe(2);

    db.close();
  });

  it('remaps a colliding legacy id and archives unmappable lines', () => {
    const db = createLegacyDb();
    db.prepare(`
      INSERT INTO boms (id, bom_no, bom_name, finished_item_id, quantity, created_by)
      VALUES (1, 'BOM-OTHER', 'Other BOM', 10, 1, 1)
    `).run();
    db.prepare(`
      INSERT INTO bom (id, bom_no, finished_item_id, quantity, created_by)
      VALUES (1, 'BOM-LEG-1', 10, 2, 1)
    `).run();
    db.prepare(`
      INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost)
      VALUES (1, 1, 10, 2, 5)
    `).run();
    // A legacy database with foreign keys previously disabled can carry an
    // orphaned material reference; preserve it in the archive.
    db.pragma('foreign_keys = OFF');
    db.prepare(`
      INSERT INTO bom_items (id, bom_id, item_id, quantity, unit_cost)
      VALUES (2, 1, 999, 3, 7)
    `).run();
    db.pragma('foreign_keys = ON');

    repairLegacyBOMItemsSchema(db);

    const legacyBom = db
      .prepare(`SELECT id FROM boms WHERE bom_no = 'BOM-LEG-1'`)
      .get() as { id: number };
    expect(legacyBom.id).not.toBe(1);

    const migrated = db
      .prepare(`SELECT bom_id, item_id FROM bom_items`)
      .all();
    expect(migrated).toEqual([{ bom_id: legacyBom.id, item_id: 10 }]);
    expect(
      (db.prepare('SELECT COUNT(*) AS count FROM bom_items_legacy').get() as {
        count: number;
      }).count,
    ).toBe(2);

    db.close();
  });
});
