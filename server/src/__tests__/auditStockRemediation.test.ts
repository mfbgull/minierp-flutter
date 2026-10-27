import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

describe('audited count and production economics', () => {
  let cookie: string;
  let warehouse: number;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  });
  afterEach(() => {
    db.prepare("UPDATE settings SET value='0' WHERE key='feature_batch_locations'").run();
    expectAllInvariantsHold('audited count/production fixture', db);
    expect(db.prepare(`SELECT journal_entry_id FROM journal_lines WHERE voided=0 GROUP BY journal_entry_id
      HAVING ABS(SUM(debit-credit))>0.005`).all()).toEqual([]);
  });
  async function post(url: string, body: object) {
    return request(app).post(url).set('Cookie', cookie).send(body);
  }
  function net(code: string) {
    return Math.round((db.prepare(`SELECT COALESCE(SUM(j.debit-j.credit),0) AS n FROM journal_lines j
      JOIN chart_of_accounts a ON a.id=j.account_id WHERE a.code=? AND j.voided=0`).get(code) as { n: number }).n * 100);
  }
  async function count(items: Array<[number, number]>) {
    const created = await post('/api/inventory/physical-counts', { warehouse_id: warehouse, count_date: '2026-09-03' });
    expect(created.status).toBe(201);
    for (const [item_id, counted_quantity] of items) {
      expect((await post(`/api/inventory/physical-counts/${created.body.id}/items`, { item_id, counted_quantity })).status).toBe(200);
    }
    const completed = await post(`/api/inventory/physical-counts/${created.body.id}/complete`, {});
    expect(completed.body.error).toBeUndefined();
    expect(completed.status).toBe(200);
    return created.body.id as number;
  }
  it('F-025 partial correction preserves omitted shortage and its journal', async () => {
    const a = await createItem('Partial A', cookie);
    const b = await createItem('Partial B', cookie);
    await purchaseStock(a, warehouse, 2, 20, cookie);
    await purchaseStock(b, warehouse, 10, 10, cookie);
    const id = await count([[a, 1], [b, 8]]);
    const original = db.prepare('SELECT * FROM physical_count_items WHERE count_id=? AND item_id=?').get(id, b);
    const before = net('1200');
    const res = await post(`/api/inventory/physical-counts/${id}/correct`, { corrections: [{ item_id: a, counted_quantity: 2 }] });
    expect(res.status).toBe(200);
    expect(db.prepare('SELECT quantity FROM stock_balances WHERE item_id=? AND warehouse_id=?').get(b, warehouse)).toEqual({ quantity: 8 });
    expect(db.prepare('SELECT * FROM physical_count_items WHERE count_id=? AND item_id=?').get(id, b)).toEqual(original);
    expect(net('1200') - before).toBe(2000);
  });
  it.each([false, true])('F-024 restores exact 5@10 + 3@20 layers (locations=%s)', async locations => {
    db.prepare("UPDATE settings SET value=? WHERE key='feature_batch_locations'").run(locations ? '1' : '0');
    const item = await createItem(`Layers ${locations}`, cookie);
    await purchaseStock(item, warehouse, 5, 10, cookie);
    await purchaseStock(item, warehouse, 5, 20, cookie, '2026-09-02');
    if (locations) {
      // Explicit location fixture: direct purchases do not assign bins.
      db.prepare("INSERT OR IGNORE INTO locations(warehouse_id,location_code,location_name) VALUES(?,'DEFAULT','Count bin')").run(warehouse);
      db.prepare(`INSERT INTO batch_stock_by_location(batch_id,location_id,quantity_physical,quantity_reserved,quantity_available)
        SELECT b.id,l.id,b.quantity_remaining,0,b.quantity_remaining FROM stock_batches b JOIN locations l ON l.warehouse_id=b.warehouse_id
        WHERE b.item_id=? AND l.location_code='DEFAULT'`).run(item);
      db.prepare('UPDATE stock_balances SET quantity_physical=quantity,quantity_available=quantity,quantity_reserved=0 WHERE item_id=?').run(item);
    }
    const id = await count([[item, 2]]);
    expect(db.prepare('SELECT variance_value FROM physical_count_items WHERE count_id=? AND item_id=?').get(id, item)).toEqual({ variance_value: -110 });
    const before = net('1200');
    const res = await post(`/api/inventory/physical-counts/${id}/correct`, { corrections: [{ item_id: item, counted_quantity: 8 }] });
    expect(res.status).toBe(200);
    expect(db.prepare('SELECT quantity_remaining,unit_cost FROM stock_batches WHERE item_id=? ORDER BY id').all(item))
      .toEqual([{ quantity_remaining: 3, unit_cost: 10 }, { quantity_remaining: 5, unit_cost: 20 }]);
    expect(net('1200') - before).toBe(9000);
    expect(db.prepare('SELECT variance_value FROM physical_count_items WHERE count_id=? AND item_id=?').get(id, item)).toEqual({ variance_value: -20 });
    if (locations) {
      expect((db.prepare(`SELECT SUM(b.quantity_physical) AS n FROM batch_stock_by_location b JOIN stock_batches s ON s.id=b.batch_id WHERE s.item_id=?`).get(item) as { n: number }).n).toBe(8);
    }
    db.prepare("UPDATE settings SET value='0' WHERE key='feature_batch_locations'").run();
  });
  it('F-022 two cents across four outputs stays nonnegative and clears exactly', async () => {
    const raw = await createItem('Tiny pool raw', cookie);
    await purchaseStock(raw, warehouse, 1, 0.02, cookie);
    const outputs = [];
    for (let n = 0; n < 4; n++) {
      const item = await createItem(`Tiny output ${n}`, cookie);
      db.prepare('UPDATE items SET is_manufactured=1,standard_selling_price=1 WHERE id=?').run(item);
      outputs.push({ item_id: item, quantity: 1 });
    }
    const before = net('1200');
    const res = await post('/api/productions', { warehouse_id: warehouse, production_date: '2026-09-20', input_items: [{ item_id: raw, quantity: 1 }], outputs });
    expect(res.status).toBe(201);
    const costs = db.prepare('SELECT allocated_cost FROM production_outputs ORDER BY id').all() as Array<{ allocated_cost: number }>;
    expect(costs.every(row => row.allocated_cost >= 0)).toBe(true);
    expect(costs.reduce((sum, row) => sum + Math.round(row.allocated_cost * 100), 0)).toBe(2);
    expect(net('1200')).toBe(before);
    expect(net('7000')).toBe(0);
  });
  it('F-024 location surplus completion and reversal keep master and bins equal', async () => {
    db.prepare("UPDATE settings SET value='1' WHERE key='feature_batch_locations'").run();
    const item = await createItem('Surplus bins', cookie);
    db.prepare('UPDATE items SET standard_cost=10 WHERE id=?').run(item);
    await purchaseStock(item, warehouse, 2, 10, cookie);
    db.prepare("INSERT OR IGNORE INTO locations(warehouse_id,location_code,location_name) VALUES(?,'DEFAULT','Surplus bin')").run(warehouse);
    db.prepare(`INSERT INTO batch_stock_by_location(batch_id,location_id,quantity_physical,quantity_reserved,quantity_available)
      SELECT b.id,l.id,b.quantity_remaining,0,b.quantity_remaining FROM stock_batches b JOIN locations l ON l.warehouse_id=b.warehouse_id
      WHERE b.item_id=? AND l.location_code='DEFAULT'`).run(item);
    db.prepare('UPDATE stock_balances SET quantity_physical=quantity,quantity_available=quantity,quantity_reserved=0 WHERE item_id=?').run(item);
    const id = await count([[item, 3]]);
    const quantity = () => db.prepare(`SELECT SUM(l.quantity_physical) AS physical FROM batch_stock_by_location l JOIN stock_batches b ON b.id=l.batch_id WHERE b.item_id=?`).get(item);
    expect(quantity()).toEqual({ physical: 3 });
    expect((await post(`/api/inventory/physical-counts/${id}/correct`, { corrections: [{ item_id: item, counted_quantity: 2 }] })).status).toBe(200);
    expect(quantity()).toEqual({ physical: 2 });
    expect(db.prepare('SELECT SUM(quantity_remaining) AS quantity FROM stock_batches WHERE item_id=?').get(item)).toEqual({ quantity: 2 });
  });
  it('preserves original surplus valuation after a mixed-layer shortage', async () => {
    const item = await createItem('Snapshot cost', cookie);
    db.prepare('UPDATE items SET standard_cost=20 WHERE id=?').run(item);
    await purchaseStock(item, warehouse, 5, 10, cookie);
    await purchaseStock(item, warehouse, 5, 20, cookie, '2026-09-02');
    const before = net('1200');
    const id = await count([[item, 2]]);
    expect((await post(`/api/inventory/physical-counts/${id}/correct`, { corrections: [{ item_id: item, counted_quantity: 11 }] })).status).toBe(200);
    expect(net('1200') - before).toBe(2000);
    expect(db.prepare("SELECT unit_cost FROM stock_batches WHERE item_id=? AND source_type='ADJUSTMENT'").get(item)).toEqual({ unit_cost: 20 });
  });
});
