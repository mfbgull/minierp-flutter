import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import db, { applyPendingMigrations } from '../config/database';

it('preserves existing stock and recovers only proven historical transfer links', () => {
  const fixture = new Database(':memory:');
  fixture.pragma('foreign_keys = ON');
  try {
    fixture.exec(`
      CREATE TABLE items(id INTEGER PRIMARY KEY, item_name TEXT);
      CREATE TABLE stock_batches(id INTEGER PRIMARY KEY, item_id INTEGER, source_type TEXT,
        source_id INTEGER, quantity_original REAL, quantity_remaining REAL, unit_cost REAL);
      CREATE TABLE stock_movements(id INTEGER PRIMARY KEY, batch_id INTEGER, movement_type TEXT, quantity REAL);
      INSERT INTO items VALUES (1, 'Existing item');
      INSERT INTO stock_batches VALUES
        (1,1,'PURCHASE',10,8,0,5),
        (2,1,'TRANSFER',20,3,3,5),
        (3,1,'TRANSFER',21,5,5,5);
      INSERT INTO stock_movements VALUES (20,1,'EXPIRY_TRANSFER',-3),(21,1,'TRANSFER',-5);
    `);
    const before = fixture.prepare('SELECT * FROM stock_batches ORDER BY id').all();
    fixture.exec(fs.readFileSync(path.join(__dirname, '../migrations/122_item_manufacturer_batch_sources.sql'), 'utf8'));
    expect(fixture.prepare('SELECT * FROM items').all()).toEqual([{ id: 1, item_name: 'Existing item', manufacturer_name: null }]);
    expect(fixture.prepare('SELECT * FROM stock_batches ORDER BY id').all()).toEqual(before);
    expect(fixture.prepare('SELECT batch_id,source_batch_id,quantity FROM stock_batch_sources').all()).toEqual([
      { batch_id: 2, source_batch_id: 1, quantity: 3 },
    ]);
    expect(fixture.pragma('foreign_key_check')).toEqual([]);
  } finally {
    fixture.close();
  }
});

it('does not reapply the migration when pending migrations are checked again', () => {
  applyPendingMigrations();
  applyPendingMigrations();
  expect(db.prepare('SELECT COUNT(*) AS n FROM schema_migrations WHERE filename = ?')
    .get('122_item_manufacturer_batch_sources.sql')).toEqual({ n: 1 });
});
