import Database from 'better-sqlite3';
import { getCompanyStock, getCompanyPeriod } from '../models/CompanyReport';
import request from 'supertest';
import app from '../app';
import appDb from '../config/database';

describe('company current stock', () => {
  it('isolates companies, uses batch cost, keeps totals before paging and units separate', () => {
    const db = new Database(':memory:');
    try {
      db.exec(`
        CREATE TABLE items (id INTEGER PRIMARY KEY, item_code TEXT, item_name TEXT, unit_of_measure TEXT, company_id INTEGER);
        CREATE TABLE stock_batches (item_id INTEGER, quantity_remaining REAL, unit_cost REAL);
        INSERT INTO items VALUES (1, 'A', 'Apple', 'Kg', 1), (2, 'B', 'Bottle', 'Nos', 1), (3, 'C', 'Other', 'Kg', 2), (4, 'D', 'Sold Out', 'Nos', 1);
        INSERT INTO stock_batches VALUES (1, 2, 10), (1, 3, 20), (1, 0, 900), (2, 4, 5), (3, 100, 100);
      `);
      const report = getCompanyStock(1, 1, 1, db);
      expect(report.rows).toEqual([{ item_id: 1, item_code: 'A', item_name: 'Apple', unit_of_measure: 'Kg', quantity: 5, stock_value: 80 }]);
      expect(report.totals.stock_value).toBe(100);
      expect(report.totals.quantities_by_uom).toEqual({ Kg: 5, Nos: 4 });
      expect(report.pagination.total).toBe(3);
      expect(getCompanyStock(1, 1, 10, db).rows).toContainEqual({
        item_id: 4, item_code: 'D', item_name: 'Sold Out', unit_of_measure: 'Nos', quantity: 0, stock_value: 0,
      });
      expect(getCompanyStock(9, 1, 10, db).rows).toEqual([]);
    } finally { db.close(); }
  });

  it('matches valuation buckets for expired, halted, reserved and damaged stock', () => {
    const db = new Database(':memory:');
    try {
      db.exec(`
        CREATE TABLE items (id INTEGER PRIMARY KEY, item_code TEXT, item_name TEXT, unit_of_measure TEXT, company_id INTEGER);
        CREATE TABLE warehouses (id INTEGER PRIMARY KEY, warehouse_code TEXT, is_active INTEGER);
        CREATE TABLE stock_batches (id INTEGER PRIMARY KEY, item_id INTEGER, warehouse_id INTEGER,
          quantity_remaining REAL, unit_cost REAL, expiry_date TEXT, halted INTEGER);
        CREATE TABLE stock_reservations (batch_id INTEGER, quantity_reserved REAL, status TEXT);
        CREATE TABLE settings (key TEXT, value TEXT);
        CREATE TABLE batch_stock_by_location (batch_id INTEGER, quantity_physical REAL, status_override TEXT);
        INSERT INTO items VALUES (1, 'A', 'Apple', 'Kg', 1);
        INSERT INTO warehouses VALUES (1, 'MAIN', 1), (2, 'EXPIRED', 1);
        INSERT INTO stock_batches VALUES
          (1, 1, 1, 10, 2, '2099-01-01', 0),
          (2, 1, 1, 5, 3, '2020-01-01', 0),
          (3, 1, 1, 4, 4, NULL, 1),
          (4, 1, 2, 3, 5, NULL, 0);
        INSERT INTO stock_reservations VALUES (1, 2, 'ACTIVE'), (1, 1, 'RELEASED');
        INSERT INTO settings VALUES ('feature_batch_locations', '1');
        INSERT INTO batch_stock_by_location VALUES (1, 1, 'DAMAGED');
      `);
      const report = getCompanyStock(1, 1, 10, db);
      // sellable 10 x 2; reservation 2; expired warehouse 3 x 5; damaged 1 x 2.
      expect(report.rows[0]).toMatchObject({ quantity: 12, stock_value: 33 });
      expect(report.totals.stock_value).toBe(33);
    } finally { db.close(); }
  });
});

describe('company period arithmetic', () => {
  it('allocates mixed-company discounts before filtering and attributes returns to return dates', () => {
    const db = new Database(':memory:');
    try {
      db.exec(`
        CREATE TABLE items(id INTEGER,item_code TEXT,item_name TEXT,unit_of_measure TEXT,company_id INTEGER);
        CREATE TABLE invoices(id INTEGER,invoice_no TEXT,invoice_date TEXT,status TEXT,discount_scope TEXT,discount_type TEXT,discount_value REAL);
        CREATE TABLE invoice_items(id INTEGER,invoice_id INTEGER,item_id INTEGER,quantity REAL,unit_price REAL,net_amount REAL,tax_amount REAL,tax_rate REAL,discount_type TEXT,discount_value REAL);
        CREATE TABLE invoice_returns(id INTEGER,return_no TEXT,return_date TEXT,status TEXT,voided_at TEXT);
        CREATE TABLE invoice_return_items(return_id INTEGER,item_id INTEGER,quantity REAL,line_amount REAL);
        INSERT INTO items VALUES(1,'A','A','Nos',1),(2,'B','B','Kg',2);
        INSERT INTO invoices VALUES(1,'INV-1','2026-01-01','Paid','invoice','flat',30),(2,'INV-2','2026-01-01','Cancelled','invoice','flat',0);
        INSERT INTO invoice_items VALUES(1,1,1,2,50,100,10,10,'percentage',0),(2,1,2,4,50,200,20,10,'percentage',0),(3,2,1,100,50,5000,0,0,'percentage',0);
        INSERT INTO invoice_returns VALUES(1,'RET-1','2026-02-01','Settled',NULL),(2,'RET-2','2026-02-01','Voided','2026-02-02');
        INSERT INTO invoice_return_items VALUES(1,1,1,50),(2,1,100,1000);
      `);
      const january = getCompanyPeriod(1,'sales','2026-01-01','2026-01-31',1,1,db);
      expect(january.totals.gross_value).toBe(100);
      expect(january.rows[0].gross_quantity).toBe(2);
      const february = getCompanyPeriod(1,'sales','2026-02-01','2026-02-28',1,1,db);
      expect(february.totals).toMatchObject({gross_value:0,return_value:50,net_value:-50});
    } finally { db.close(); }
  });

  it('counts direct purchases and actual receipt lines once with recoverable tax and returns', () => {
    const db = new Database(':memory:');
    try {
      db.exec(`
        CREATE TABLE items(id INTEGER,item_code TEXT,item_name TEXT,unit_of_measure TEXT,company_id INTEGER);
        CREATE TABLE purchases(id INTEGER,purchase_no TEXT,item_id INTEGER,purchase_date TEXT,quantity REAL,total_cost REAL,input_tax_amount REAL,supplier_id INTEGER,voided_at TEXT);
        CREATE TABLE purchase_orders(id INTEGER,supplier_id INTEGER);
        CREATE TABLE purchase_order_items(id INTEGER,unit_price REAL);
        CREATE TABLE goods_receipts(id INTEGER,po_id INTEGER,receipt_no TEXT,receipt_date TEXT,voided_at TEXT);
        CREATE TABLE goods_receipt_items(receipt_id INTEGER,po_item_id INTEGER,item_id INTEGER,received_quantity REAL,input_tax_amount REAL);
        CREATE TABLE purchase_returns(id INTEGER,return_no TEXT,return_date TEXT,status TEXT,voided_at TEXT);
        CREATE TABLE purchase_return_items(purchase_return_id INTEGER,item_id INTEGER,quantity REAL,amount REAL,input_tax_amount REAL);
        INSERT INTO items VALUES(1,'A','A','Nos',1);
        INSERT INTO purchases VALUES(1,'P1',1,'2026-01-01',2,100,10,1,NULL),(2,'P2',1,'2026-01-01',99,999,99,1,'2026-01-02');
        INSERT INTO purchase_orders VALUES(1,2);
        INSERT INTO purchase_order_items VALUES(1,20);
        INSERT INTO goods_receipts VALUES(1,1,'GR1','2026-01-02',NULL),(2,1,'GR2','2026-01-02','2026-01-03');
        INSERT INTO goods_receipt_items VALUES(1,1,1,3,6),(2,1,1,100,200);
        INSERT INTO purchase_returns VALUES(1,'PR1','2026-01-03','POSTED',NULL);
        INSERT INTO purchase_return_items VALUES(1,1,1,50,5);
      `);
      const report = getCompanyPeriod(1,'purchases','2026-01-01','2026-01-31',1,10,db);
      expect(report.totals).toMatchObject({gross_value:176,return_value:55,net_value:121});
      expect(report.rows[0]).toMatchObject({gross_quantity:5,return_quantity:1,net_quantity:4});
      expect(report.rows[0].transactions).toHaveLength(3);
    } finally { db.close(); }
  });
});

describe('mounted company report routes', () => {
  let cookie: string;
  let companyId: number;
  beforeAll(async () => {
    const response = await request(app).post('/api/auth/login').send({username:'admin',password:process.env.TEST_ADMIN_PASSWORD});
    expect(response.status).toBe(200);
    const cookies = response.headers['set-cookie'];
    cookie = (Array.isArray(cookies) ? cookies : [cookies]).find((value:string) => value.startsWith('token='))!.split(';')[0];
    companyId = Number(appDb.prepare("INSERT INTO item_companies(company_name,is_active) VALUES('Company report route fixture',0)").run().lastInsertRowid);
  });
  it.each(['stock','sales','purchases'])('serves archived company %s with full schema and rejects invalid requests', async view => {
    const path = `/api/reports/company/${view}`;
    const query = {company_id:companyId,startDate:'2026-01-01',endDate:'2026-01-31'};
    const response = await request(app).get(path).set('Cookie',cookie).query(query);
    expect(response.status).toBe(200);
    expect(response.body.data.rows).toEqual([]);
    expect((await request(app).get(path).query(query)).status).toBe(401);
    expect((await request(app).get(path).set('Cookie',cookie).query({...query,company_id:'bad'})).status).toBe(400);
    expect((await request(app).get(path).set('Cookie',cookie).query({...query,company_id:99999999})).status).toBe(404);
    if (view !== 'stock') expect((await request(app).get(path).set('Cookie',cookie).query({...query,startDate:'2026-02-30'})).status).toBe(400);
  });
});

describe('company report boundaries and stability', () => {
  function salesFixture(db: Database.Database): void {
    db.exec(`
      CREATE TABLE items(id INTEGER,item_code TEXT,item_name TEXT,unit_of_measure TEXT,company_id INTEGER);
      CREATE TABLE item_companies(id INTEGER,company_name TEXT);
      CREATE TABLE suppliers(id INTEGER,supplier_name TEXT);
      CREATE TABLE item_company_suppliers(company_id INTEGER,supplier_id INTEGER,PRIMARY KEY(company_id,supplier_id));
      CREATE TABLE invoices(id INTEGER,invoice_no TEXT,invoice_date TEXT,status TEXT,discount_scope TEXT,discount_type TEXT,discount_value REAL);
      CREATE TABLE invoice_items(id INTEGER,invoice_id INTEGER,item_id INTEGER,quantity REAL,unit_price REAL,net_amount REAL,tax_amount REAL,tax_rate REAL,discount_type TEXT,discount_value REAL);
      CREATE TABLE invoice_returns(id INTEGER,return_no TEXT,return_date TEXT,status TEXT,voided_at TEXT);
      CREATE TABLE invoice_return_items(return_id INTEGER,item_id INTEGER,quantity REAL,line_amount REAL);
      INSERT INTO items VALUES(1,'A','A','Nos',1);
      INSERT INTO item_companies VALUES(1,'Original name');
      INSERT INTO suppliers VALUES(1,'S1'),(2,'S2');
      INSERT INTO item_company_suppliers VALUES(1,1),(1,2);
      INSERT INTO invoices VALUES
        (1,'INV-A','2026-01-01','Paid','invoice','flat',0),
        (2,'INV-B','2026-01-31','Paid','invoice','flat',0),
        (3,'INV-C','2025-12-31','Paid','invoice','flat',0);
      INSERT INTO invoice_items VALUES
        (1,1,1,1,100,100,0,0,'percentage',0),
        (2,2,1,1,100,100,0,0,'percentage',0),
        (3,3,1,1,100,100,0,0,'percentage',0);
    `);
  }

  it('counts inclusive date boundaries once and stays stable after a rename or extra supplier links', () => {
    const db = new Database(':memory:');
    try {
      salesFixture(db);
      const january = getCompanyPeriod(1, 'sales', '2026-01-01', '2026-01-31', 1, 10, db);
      expect(january.totals).toMatchObject({ gross_value: 200, return_value: 0, net_value: 200 });
      expect(january.rows[0]).toMatchObject({ gross_quantity: 2, net_quantity: 2 });
      expect(january.rows[0].transactions).toHaveLength(2);

      db.prepare("UPDATE item_companies SET company_name = 'Renamed company' WHERE id = 1").run();
      db.prepare('INSERT INTO item_company_suppliers VALUES (1, 1) ON CONFLICT DO NOTHING').run();
      const renamed = getCompanyPeriod(1, 'sales', '2026-01-01', '2026-01-31', 1, 10, db);
      expect(renamed.totals).toEqual(january.totals);
      expect(renamed.rows).toEqual(january.rows);
    } finally { db.close(); }
  });

  it('reduces net values for partial and full returns to zero', () => {
    const db = new Database(':memory:');
    try {
      salesFixture(db);
      db.prepare('INSERT INTO invoices VALUES (4,\'INV-D\',\'2026-01-10\',\'Paid\',\'invoice\',\'flat\',0)').run();
      db.prepare('INSERT INTO invoice_items VALUES (4,4,1,10,10,100,0,0,\'percentage\',0)').run();
      db.prepare("INSERT INTO invoice_returns VALUES (1,'RET-A','2026-01-12','Settled',NULL)").run();
      db.prepare("INSERT INTO invoice_returns VALUES (2,'RET-B','2026-01-15','Settled',NULL)").run();
      db.prepare('INSERT INTO invoice_return_items VALUES (1,1,4,40),(2,1,6,60)').run();
      const report = getCompanyPeriod(1, 'sales', '2026-01-01', '2026-01-31', 1, 10, db);
      const invoiceLine = report.rows[0];
      expect(report.totals.gross_value).toBe(300);
      expect(report.totals.return_value).toBe(100);
      expect(report.totals.net_value).toBe(200);
      expect(invoiceLine.gross_quantity).toBe(12);
      expect(invoiceLine.return_quantity).toBe(10);
      expect(invoiceLine.net_quantity).toBe(2);
      expect(invoiceLine.net_value).toBe(200);
    } finally { db.close(); }
  });
});
