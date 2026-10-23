import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import PhysicalCountModel from '../models/PhysicalCount';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `PhysicalCount.getAll` (CRAP 72). Covers the
 * default and explicit pagination, search, sort whitelist/fallback, and the
 * count envelope.
 */
function createFixture(): Database.Database {
  const db = createFixtureDb();
  db.prepare(`
    INSERT INTO warehouses (id, warehouse_code, warehouse_name)
    VALUES (1, 'WH-1', 'Warehouse One'), (2, 'WH-2', 'Warehouse Two')
  `).run();
  const insert = db.prepare(`
    INSERT INTO physical_counts (count_no, count_date, warehouse_id, status)
    VALUES (?, ?, ?, ?)
  `);
  insert.run('PC-1', '2026-01-01', 1, 'Draft');
  insert.run('PC-2', '2026-02-01', 2, 'In Progress');
  insert.run('PC-3', '2026-03-01', 1, 'Completed');
  return db;
}

describe('PhysicalCountModel.getAll', () => {
  it('returns the default page and total', () => {
    const db = createFixture();
    const result = PhysicalCountModel.getAll({}, db);
    expect(result.total).toBe(3);
    expect(result.pageNum).toBe(1);
    expect(result.limitNum).toBe(10);
    expect(result.rows).toHaveLength(3);
    db.close();
  });

  it('searches count number, warehouse name and status', () => {
    const db = createFixture();
    for (const term of ['PC-2', 'Warehouse Two', 'Completed']) {
      const result = PhysicalCountModel.getAll({ search: term }, db);
      expect(result.total).toBe(1);
      expect(result.rows[0].count_no).toBe(
        term === 'PC-2' ? 'PC-2' : term === 'Completed' ? 'PC-3' : 'PC-2',
      );
    }
    db.close();
  });

  it('honors a whitelisted ascending sort', () => {
    const db = createFixture();
    const result = PhysicalCountModel.getAll(
      { sortBy: 'count_date', sortOrder: 'ASC' },
      db,
    );
    expect(result.rows.map((row) => row.count_no)).toEqual([
      'PC-1',
      'PC-2',
      'PC-3',
    ]);
    db.close();
  });

  it('falls back to the default sort for invalid parameters and paginates', () => {
    const db = createFixture();
    const result = PhysicalCountModel.getAll(
      {
        sortBy: 'count_date; DROP TABLE x',
        sortOrder: 'sideways',
        page: 2,
        limit: 1,
      },
      db,
    );
    expect(result.total).toBe(3);
    expect(result.pageNum).toBe(2);
    expect(result.limitNum).toBe(1);
    expect(result.rows).toHaveLength(1);
    db.close();
  });
});
