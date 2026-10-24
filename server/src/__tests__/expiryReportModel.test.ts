import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import ReportsModel from '../models/Reports';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `Reports.getExpiryReport` (CRAP 56).
 * Covers expired/expiring/normal classification, the default and explicit
 * threshold, warehouse filtering, and status filtering.
 */
function isoDateOffset(days: number): string {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().split('T')[0];
}

function createFixture(): Database.Database {
  const db = createFixtureDb();
  db.prepare(`
    INSERT INTO warehouses (id, warehouse_code, warehouse_name)
    VALUES (1, 'WH-1', 'Warehouse One'), (2, 'WH-2', 'Warehouse Two')
  `).run();
  db.prepare(`
    INSERT INTO items (id, item_code, item_name, unit_of_measure, has_expiry)
    VALUES (1, 'EXP-1', 'Expiry item', 'Nos', 1)
  `).run();
  const insert = db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date,
      expiry_date, halted
    ) VALUES (?, 1, ?, 'PURCHASE', 1, ?, ?, 10, '2026-01-01', ?, 0)
  `);
  insert.run('B-EXPIRED', 1, 5, 5, isoDateOffset(-5));
  insert.run('B-EXPIRING', 1, 4, 4, isoDateOffset(10));
  insert.run('B-NORMAL', 2, 3, 3, isoDateOffset(100));
  insert.run('B-ZERO', 1, 0, 0, isoDateOffset(5));
  return db;
}

describe('ReportsModel.getExpiryReport', () => {
  it('classifies rows with the default threshold and filters a warehouse', () => {
    const db = createFixture();
    const all = ReportsModel.getExpiryReport(db);
    expect(all.map((row) => [row.batch_no, row.status])).toEqual([
      ['B-EXPIRED', 'expired'],
      ['B-EXPIRING', 'expiring'],
      ['B-NORMAL', 'normal'],
    ]);
    expect(ReportsModel.getExpiryReport(db, { warehouseId: 2 })).toHaveLength(1);
    db.close();
  });

  it('honors an explicit threshold', () => {
    const db = createFixture();
    const rows = ReportsModel.getExpiryReport(db, { thresholdDays: 5 });
    expect(
      rows.map((row) => [row.batch_no, row.status]),
    ).toEqual([
      ['B-EXPIRED', 'expired'],
      ['B-EXPIRING', 'normal'],
      ['B-NORMAL', 'normal'],
    ]);
    db.close();
  });

  it('filters a known status and ignores an unknown one', () => {
    const db = createFixture();
    expect(
      ReportsModel.getExpiryReport(db, { status: 'expired' }).map(
        (row) => row.batch_no,
      ),
    ).toEqual(['B-EXPIRED']);
    expect(
      ReportsModel.getExpiryReport(db, { status: 'bogus' }),
    ).toHaveLength(3);
    db.close();
  });
});
