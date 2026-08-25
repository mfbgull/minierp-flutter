/**
 * Supplier detail "Purchases" tab — `GET /purchases?supplier_id=<id>`
 * filter. The supplier detail page's Purchases tab pages the supplier's
 * direct purchases through `PurchaseModel.getAll` with `supplier_id`.
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import request from 'supertest';
import app from '../app';
import sharedDb from '../config/database';
import PurchaseModel from '../models/Purchase';

const MIGRATIONS = [
  'init.sql',
  'add-purchases-table.sql',
  'add-purchase-return-fields.sql',
  'add-batch-costing.sql',
  'add-stock-adjustment-financial.sql',
  'create-supplier-ledger.sql',
  'add-gl-foundation.sql',
  'create-customer-ledger.sql',
  'add-gl-void-attribution.sql',
  'add-purchase-returns-tables.sql',
  'create-payment-allocations.sql',
  'add-supplier-payment-support.sql',
  'add-purchase-supplier-payment.sql',
  'add-expenses-table.sql',
  'add-salary-payments.sql',
  'add-cash-accounts.sql',
  'add-opening-balances.sql',
  'add-purchase-void-columns.sql',
  'add-purchase-return-batches.sql',
];

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  for (const f of MIGRATIONS) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', f), 'utf8'));
  }

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
              VALUES ('S1','Acme',1)`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active)
              VALUES ('S2','Globex',1)`).run();
  db.prepare(`INSERT INTO warehouses (id, warehouse_code, warehouse_name, is_active)
              VALUES (1, 'W1', 'Main', 1)`).run();
  return db;
}

let counter = 0;
function seedPurchase(
  db: Database.Database,
  supplierId: number | null,
  supplierName: string | null,
): number {
  counter += 1;
  db.prepare(`INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
              VALUES (?, ?, ?, 'Nos', 10, 1, 1)`).run(counter, `IT-${counter}`, `Item ${counter}`);
  const result = db.prepare(`
    INSERT INTO purchases (
      purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
      supplier_id, supplier_name, purchase_date, created_by
    ) VALUES (?, ?, 1, 10, 10, 100, ?, ?, ?, 1)
  `).run(
    `PURCH-SF-${counter}`,
    counter,
    supplierId,
    supplierName,
    `2026-08-${String(counter).padStart(2, '0')}`,
  );
  return result.lastInsertRowid as number;
}

describe('purchases supplier_id filter', () => {
  it('returns only the given supplier\u2019s purchases', () => {
    const db = createFixture();
    seedPurchase(db, 1, 'Acme');
    seedPurchase(db, 1, 'Acme');
    seedPurchase(db, 2, 'Globex');
    seedPurchase(db, null, null);

    const acme = PurchaseModel.getAll({ supplier_id: 1 }, db);
    expect(acme.total).toBe(2);
    expect(acme.rows.every((r) => r.supplier_id === 1)).toBe(true);

    const globex = PurchaseModel.getAll({ supplier_id: 2 }, db);
    expect(globex.total).toBe(1);
    expect(globex.rows[0].supplier_name).toBe('Globex');
  });

  it('combines with the other filters and paging', () => {
    const db = createFixture();
    seedPurchase(db, 1, 'Acme');
    seedPurchase(db, 1, 'Acme');
    seedPurchase(db, 2, 'Globex');

    const page = PurchaseModel.getAll({ supplier_id: 1, page: 1, limit: 1 }, db);
    expect(page.total).toBe(2);
    expect(page.rows).toHaveLength(1);
    expect(page.limitNum).toBe(1);

    // supplier_name still works alongside / independently of supplier_id.
    const byName = PurchaseModel.getAll({ supplier_name: 'Globex' }, db);
    expect(byName.total).toBe(1);
  });
});

describe('GET /api/purchases?supplier_id (HTTP)', () => {
  async function getAuthCookie(): Promise<string> {
    const res = await request(app)
      .post('/api/auth/login')
      .send({
        username: 'admin',
        password: process.env.TEST_ADMIN_PASSWORD,
      });
    const cookies = res.headers['set-cookie'];
    if (!cookies) return '';
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
      .find((c: string) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
  }

  it('returns only the supplier\u2019s purchases with a pagination block', async () => {
    const tag = `SFHTTP${Date.now()}`;
    const db = sharedDb;

    const supA = db
      .prepare('INSERT INTO suppliers (supplier_code,supplier_name,is_active) VALUES (?,?,1)')
      .run(`${tag}-A`, `${tag} Acme`).lastInsertRowid as number;
    const supB = db
      .prepare('INSERT INTO suppliers (supplier_code,supplier_name,is_active) VALUES (?,?,1)')
      .run(`${tag}-B`, `${tag} Globex`).lastInsertRowid as number;

    const wh = db
      .prepare('INSERT INTO warehouses (warehouse_code,warehouse_name,is_active) VALUES (?,?,1)')
      .run(`${tag}-W`, `${tag} WH`).lastInsertRowid as number;

    const admin = db
      .prepare("SELECT id FROM users WHERE username = 'admin'")
      .get() as { id: number };

    let itemSeq = 0;
    const seed = (supplierId: number | null, supplierName: string | null): void => {
      itemSeq += 1;
      const item = db
        .prepare('INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active) VALUES (?,?,?,?,1,1)')
        .run(`${tag}-I${itemSeq}`, `${tag} Item ${itemSeq}`, 'Nos', 10).lastInsertRowid as number;
      db.prepare(`
        INSERT INTO purchases (
          purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
          supplier_id, supplier_name, purchase_date, created_by
        ) VALUES (?, ?, ?, 10, 10, 100, ?, ?, '2026-08-01', ?)
      `).run(`${tag}-P${itemSeq}`, item, wh, supplierId, supplierName, admin.id);
    };

    seed(supA, `${tag} Acme`);
    seed(supA, `${tag} Acme`);
    seed(supB, `${tag} Globex`);

    const cookie = await getAuthCookie();
    expect(cookie).toBeTruthy();

    const res = await request(app)
      .get('/api/purchases')
      .query({ page: 1, limit: 50, supplier_id: supA })
      .set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.pagination.totalItems).toBe(2);
    expect(res.body.data).toHaveLength(2);
    for (const row of res.body.data) {
      expect(row.supplier_id).toBe(supA);
    }
  });
});
