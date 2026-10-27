import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';
import { setFeatureEnabled } from '../utils/featureFlags';

describe('reservation and journal audit invariants', () => {
  let cookie: string;
  let item: number;
  let warehouse: number;
  let batch: number;
  let location: number;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    item = await createItem('Reservation audit', cookie);
    await purchaseStock(item, warehouse, 10, 10, cookie);
    setFeatureEnabled(db, 'feature_batch_locations', true);
    db.prepare("INSERT OR IGNORE INTO locations(warehouse_id,location_code,location_name) VALUES(?,'DEFAULT','Audit bin')").run(warehouse);
    location = (db.prepare("SELECT id FROM locations WHERE warehouse_id=? AND location_code='DEFAULT'").get(warehouse) as { id: number }).id;
    batch = (db.prepare('SELECT id FROM stock_batches WHERE item_id=?').get(item) as { id: number }).id;
    db.prepare('INSERT INTO batch_stock_by_location(batch_id,location_id,quantity_physical,quantity_reserved,quantity_available) VALUES(?,?,10,0,10)').run(batch, location);
  });
  it.each([1, undefined])('F-071/F-072 reserve replay and release apply one location delta (line=%s)', async line => {
    const body = { item_id: item, warehouse_id: warehouse, batch_id: batch, location_id: location, quantity_reserved: 3,
      reference_doctype: 'SALES_ORDER', reference_docno: `AUDIT-${line ?? 'NULL'}`, reference_line_id: line };
    const post = () => request(app).post('/api/inventory/reservations').set('Cookie', cookie).send(body);
    const first = await post();
    expect(first.status).toBe(201);
    const replay = await post();
    expect(replay.status).toBe(201);
    expect(replay.body.id).toBe(first.body.id);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 3, quantity_available: 7 });
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(200);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 0, quantity_available: 10 });
    expect((await post()).body.id).toBe(first.body.id);
    const conflict = await request(app).post('/api/inventory/reservations').set('Cookie', cookie).send({ ...body, quantity_reserved: 4 });
    expect(conflict.status).toBe(409);
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(200);
    expect((await request(app).delete(`/api/inventory/reservations/${first.body.id}/release`).set('Cookie', cookie)).status).toBe(400);
    expect(db.prepare('SELECT quantity_reserved,quantity_available FROM batch_stock_by_location WHERE batch_id=? AND location_id=?').get(batch, location))
      .toEqual({ quantity_reserved: 0, quantity_available: 10 });
  });
});
