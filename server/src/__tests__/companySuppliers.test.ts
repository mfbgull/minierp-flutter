import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

it('merges manual links with purchase history and preserves history after unlink', async () => {
  const cookie = await getAuthCookie();
  const company = db.prepare("INSERT INTO item_companies(company_name) VALUES ('Supplier company')").run().lastInsertRowid;
  const supplier = db.prepare("INSERT INTO suppliers(supplier_code,supplier_name,is_active) VALUES ('CS-S','Company supplier',1)").run().lastInsertRowid;
  const item = db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,company_id) VALUES ('CS-I','Company item','Nos',?)").run(company).lastInsertRowid;
  const warehouse = db.prepare("INSERT INTO warehouses(warehouse_code,warehouse_name) VALUES ('CS-W','Company warehouse')").run().lastInsertRowid;
  const admin = db.prepare("SELECT id FROM users WHERE username = 'admin'").get() as { id: number };
  const base = `/api/inventory/item-companies/${company}/suppliers`;
  expect((await request(app).post(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(200);
  expect((await request(app).post(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(200);
  let response = await request(app).get(base).set('Cookie', cookie);
  expect(response.status).toBe(200);
  expect(response.body.data).toHaveLength(1);
  expect(response.body.data[0]).toMatchObject({ linked: 1, purchased: 0, product_count: 0 });
  db.prepare(`INSERT INTO purchases(purchase_no,item_id,warehouse_id,quantity,unit_cost,total_cost,supplier_id,purchase_date,created_by)
    VALUES ('CS-P',?,?,1,10,10,?,'2026-10-01',?)`).run(item, warehouse, supplier, admin.id);
  response = await request(app).get(base).set('Cookie', cookie);
  expect(response.body.data[0]).toMatchObject({ linked: 1, purchased: 1, product_count: 1, last_purchase_date: '2026-10-01' });
  expect((await request(app).delete(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(200);
  response = await request(app).get(base).set('Cookie', cookie);
  expect(response.body.data).toHaveLength(1);
  expect(response.body.data[0]).toMatchObject({ linked: 0, purchased: 1 });
  const products = await request(app).get(`${base}/${supplier}/products`).set('Cookie', cookie);
  expect(products.body.data[0].id).toBe(Number(item));
  db.prepare("UPDATE purchases SET voided_at = CURRENT_TIMESTAMP WHERE purchase_no = 'CS-P'").run();
  expect((await request(app).get(base).set('Cookie', cookie)).body.data).toHaveLength(0);
  expect((await request(app).post(`${base}/invalid`).set('Cookie', cookie)).status).toBe(400);
  expect((await request(app).post(`${base}/${supplier}`)).status).toBe(401);
});

it('uses received purchase orders but excludes cancelled ones', async () => {
  const cookie = await getAuthCookie();
  const company = Number(db.prepare("INSERT INTO item_companies(company_name) VALUES ('Receipt company')").run().lastInsertRowid);
  const supplier = Number(db.prepare("INSERT INTO suppliers(supplier_code,supplier_name,is_active) VALUES ('CS-R','Receipt supplier',1)").run().lastInsertRowid);
  const item = Number(db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,company_id) VALUES ('CS-RI','Receipt item','Nos',?)").run(company).lastInsertRowid);
  const warehouse = Number(db.prepare("INSERT INTO warehouses(warehouse_code,warehouse_name) VALUES ('CS-RW','Receipt warehouse')").run().lastInsertRowid);
  const po = Number(db.prepare(`INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount, warehouse_id)
    VALUES ('CS-RPO',?,'2026-10-01','Completed',10,?)`).run(supplier, warehouse).lastInsertRowid);
  const poItem = Number(db.prepare(`INSERT INTO purchase_order_items (po_id,item_id,quantity,received_quantity,unit_price,amount)
    VALUES (?,?,1,1,10,10)`).run(po, item).lastInsertRowid);
  const receipt = Number(db.prepare(`INSERT INTO goods_receipts (receipt_no,po_id,receipt_date,warehouse_id)
    VALUES ('CS-RGR',?,'2026-10-02',?)`).run(po, warehouse).lastInsertRowid);
  db.prepare('INSERT INTO goods_receipt_items (receipt_id,po_item_id,item_id,received_quantity) VALUES (?,?,?,1)')
    .run(receipt, poItem, item);

  const base = `/api/inventory/item-companies/${company}/suppliers`;
  let response = await request(app).get(base).set('Cookie', cookie);
  expect(response.body.data).toHaveLength(1);
  expect(response.body.data[0]).toMatchObject({
    supplier_id: supplier,
    purchased: 1,
    product_count: 1,
    last_purchase_date: '2026-10-02',
  });

  db.prepare("UPDATE purchase_orders SET status = 'Cancelled' WHERE id = ?").run(po);
  response = await request(app).get(base).set('Cookie', cookie);
  expect(response.body.data).toHaveLength(0);
});

it('rejects inactive supplier links and archived companies while keeping archived history readable', async () => {
  const cookie = await getAuthCookie();
  const company = Number(db.prepare("INSERT INTO item_companies(company_name,is_active) VALUES ('Archived history company',0)").run().lastInsertRowid);
  const supplier = Number(db.prepare("INSERT INTO suppliers(supplier_code,supplier_name,is_active) VALUES ('CS-AL','Archived link supplier',1)").run().lastInsertRowid);
  const inactive = Number(db.prepare("INSERT INTO suppliers(supplier_code,supplier_name,is_active) VALUES ('CS-IL','Inactive link supplier',0)").run().lastInsertRowid);
  const item = Number(db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,company_id) VALUES ('CS-AH','Archived history item','Nos',?)").run(company).lastInsertRowid);
  const warehouse = Number(db.prepare("INSERT INTO warehouses(warehouse_code,warehouse_name) VALUES ('CS-AH','Archived history warehouse')").run().lastInsertRowid);
  const admin = db.prepare("SELECT id FROM users WHERE username = 'admin'").get() as { id: number };
  db.prepare(`INSERT INTO purchases(purchase_no,item_id,warehouse_id,quantity,unit_cost,total_cost,supplier_id,purchase_date,created_by)
    VALUES ('CS-AH',?,?,1,10,10,?,'2026-10-05',?)`).run(item, warehouse, supplier, admin.id);

  const base = `/api/inventory/item-companies/${company}/suppliers`;
  const read = await request(app).get(base).set('Cookie', cookie);
  expect(read.status).toBe(200);
  expect(read.body.data[0]).toMatchObject({ supplier_id: supplier, linked: 0, purchased: 1 });

  db.prepare('UPDATE item_companies SET is_active = 1 WHERE id = ?').run(company);
  expect((await request(app).post(`${base}/${inactive}`).set('Cookie', cookie)).status).toBe(409);
  expect((await request(app).post(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(200);

  db.prepare('UPDATE item_companies SET is_active = 0 WHERE id = ?').run(company);
  expect((await request(app).post(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(409);
  expect((await request(app).delete(`${base}/${supplier}`).set('Cookie', cookie)).status).toBe(200);
  expect((await request(app).get(base).set('Cookie', cookie)).body.data[0]).toMatchObject({ linked: 0, purchased: 1 });
});

it('keeps sold-out and fully returned purchases and deduplicates repeated receipt lines', async () => {
  const cookie = await getAuthCookie();
  const company = Number(db.prepare("INSERT INTO item_companies(company_name) VALUES ('Sold out company')").run().lastInsertRowid);
  const supplier = Number(db.prepare("INSERT INTO suppliers(supplier_code,supplier_name,is_active) VALUES ('CS-SO','Sold out supplier',1)").run().lastInsertRowid);
  const item = Number(db.prepare("INSERT INTO items(item_code,item_name,unit_of_measure,company_id) VALUES ('CS-SO','Sold out item','Nos',?)").run(company).lastInsertRowid);
  const warehouse = Number(db.prepare("INSERT INTO warehouses(warehouse_code,warehouse_name) VALUES ('CS-SO','Sold out warehouse')").run().lastInsertRowid);
  const admin = db.prepare("SELECT id FROM users WHERE username = 'admin'").get() as { id: number };

  db.prepare(`INSERT INTO purchases(purchase_no,item_id,warehouse_id,quantity,unit_cost,total_cost,supplier_id,purchase_date,created_by)
    VALUES ('CS-SO',?,?,1,10,10,?,'2026-10-03',?)`).run(item, warehouse, supplier, admin.id);
  const purchaseReturn = Number(db.prepare(`INSERT INTO purchase_returns
    (return_no,return_date,return_type,source_type,source_no,warehouse_id,total_qty,total_amount,status)
    VALUES ('CS-SO-PR','2026-10-04','PURCHASE_RETURN','PURCHASE','CS-SO',?,1,10,'POSTED')`).run(warehouse).lastInsertRowid);
  db.prepare(`INSERT INTO purchase_return_items(purchase_return_id,item_id,item_name,unit_cost,quantity,amount)
    VALUES (?,?,'Sold out item',10,1,10)`).run(purchaseReturn, item);

  const po = Number(db.prepare(`INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount, warehouse_id)
    VALUES ('CS-SO-PO',?,'2026-10-01','Completed',20,?)`).run(supplier, warehouse).lastInsertRowid);
  const poItemA = Number(db.prepare(`INSERT INTO purchase_order_items (po_id,item_id,quantity,received_quantity,unit_price,amount)
    VALUES (?,?,1,1,10,10)`).run(po, item).lastInsertRowid);
  const poItemB = Number(db.prepare(`INSERT INTO purchase_order_items (po_id,item_id,quantity,received_quantity,unit_price,amount)
    VALUES (?,?,1,1,10,10)`).run(po, item).lastInsertRowid);
  const receipt = Number(db.prepare(`INSERT INTO goods_receipts (receipt_no,po_id,receipt_date,warehouse_id)
    VALUES ('CS-SO-GR',?,'2026-10-06',?)`).run(po, warehouse).lastInsertRowid);
  db.prepare('INSERT INTO goods_receipt_items (receipt_id,po_item_id,item_id,received_quantity) VALUES (?,?,?,1)')
    .run(receipt, poItemA, item);
  db.prepare('INSERT INTO goods_receipt_items (receipt_id,po_item_id,item_id,received_quantity) VALUES (?,?,?,1)')
    .run(receipt, poItemB, item);

  const base = `/api/inventory/item-companies/${company}/suppliers`;
  const response = await request(app).get(base).set('Cookie', cookie);
  expect(response.status).toBe(200);
  expect(response.body.data).toHaveLength(1);
  expect(response.body.data[0]).toMatchObject({
    supplier_id: supplier,
    purchased: 1,
    product_count: 1,
    last_purchase_date: '2026-10-06',
  });
  const products = await request(app).get(`${base}/${supplier}/products`).set('Cookie', cookie);
  expect(products.body.data).toHaveLength(1);
  expect(products.body.data[0]).toMatchObject({ id: item, last_purchase_date: '2026-10-06' });
});
