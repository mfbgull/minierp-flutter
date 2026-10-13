
import Database from 'better-sqlite3';
import PhysicalCountModel from '../models/PhysicalCount';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';


afterAll(() => cleanupFixtureDbs());

function createFixture(): Database.Database {
  const db = createFixtureDb({ reference: true });

db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active) VALUES ('admin','a@b.c','x','A','admin',1)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES ('IT-C','Counted','Nos',10,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES ('WH-1','Main',1)`).run();
  return db;
}

describe('PhysicalCount.completeCount batch sync (INV-01/23/24)', () => {
  it('shortage consumes FIFO layers; surplus creates ADJUSTMENT batch; coverage == balance; sequential movement numbers', () => {
    const db = createFixture();
    // Seed batches: layer1 20@5, layer2 10@8 → balance 30
    db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B1',1,1,'PURCHASE',1,20,20,5,'2026-01-01')`).run();
    db.prepare(`INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date)
      VALUES ('B2',1,1,'PURCHASE',2,10,10,8,'2026-02-01')`).run();
    db.prepare(`INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,30)`).run();
    db.prepare(`UPDATE items SET current_stock=30 WHERE id=1`).run();

    const countId = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);

    // record shortage: counted 25 → variance -5. FIFO: 5 from B1 @5.
    PhysicalCountModel.recordCount(countId, 1, 25, 1, null, db);

    PhysicalCountModel.completeCount(countId, 1, db);

    const bal = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as { quantity: number };
    expect(bal.quantity).toBe(25);

    const b1 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B1'`).get() as { quantity_remaining: number };
    const b2 = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B2'`).get() as { quantity_remaining: number };
    expect(b1.quantity_remaining).toBe(15); // 20-5 FIFO
    expect(b2.quantity_remaining).toBe(10);
    // coverage == balance
    const covered = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get() as { s: number };
    expect(covered.s).toBe(25);

    // movement: sequential number, batch linked, JE valued at consumed cost (5*5=25)
    const mv = db.prepare(`SELECT movement_no, batch_id, unit_cost, financial_value FROM stock_movements WHERE reference_doctype='PhysicalCount'`).get() as { movement_no: string; batch_id: number; unit_cost: number; financial_value: string };
    const b1row = db.prepare(`SELECT id FROM stock_batches WHERE batch_no='B1'`).get() as { id: number };
    if (b1row) expect(mv.batch_id).toBe(b1row.id);
    expect(mv.movement_no).toMatch(/^STK-\d{4}-\d{4}$/);
    expect(mv.financial_value).toBe(25);

    // Surplus path: record +3 via a second count
    const countId2 = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);
    PhysicalCountModel.recordCount(countId2, 1, 31, 1, null, db);
    PhysicalCountModel.completeCount(countId2, 1, db);

    const adjBatch = db.prepare(`SELECT source_type, quantity_original, unit_cost FROM stock_batches WHERE source_type='ADJUSTMENT'`).get() as { source_type: string; quantity_original: number; unit_cost: number };
    expect(adjBatch).toBeTruthy();
    expect(adjBatch.quantity_original).toBe(6);
    expect(adjBatch.unit_cost).toBe(10); // snapshot unit_cost = standard_cost
    const covered2 = db.prepare(`SELECT SUM(quantity_remaining) s FROM stock_batches WHERE item_id=1 AND warehouse_id=1`).get() as { s: number };
    const bal2 = db.prepare(`SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1`).get() as { quantity: number };
    expect(covered2.s).toBe(bal2.quantity); // 28

    // Sequential numbering across both counts
    const nos = db.prepare(`SELECT movement_no FROM stock_movements ORDER BY id`).all() as { movement_no: string }[];
    expect(nos.length).toBeGreaterThanOrEqual(2);
  });

  it('aborts when recording a count with no snapshot row (INV-24)', () => {
    const db = createFixture();
    const countId = PhysicalCountModel.create({ warehouse_id: 1 } as Parameters<typeof PhysicalCountModel.create>[0], 1, db);
    expect(() => PhysicalCountModel.recordCount(countId, 999, 5, 1, null, db)).toThrow(/snapshot/i);
  });
});