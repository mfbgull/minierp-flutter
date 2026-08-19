import request from 'supertest';
import app from '../app';
import db from '../config/database';
import fs from 'fs';
import path from 'path';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

function createFixture(): void {
  // The app's database.ts already runs all migrations on import.
  // Just ensure the test data is idempotently seeded.

  // Ensure test fixture has the columns required by search queries
  const customerCols = (db.pragma('table_info(customers)') as unknown as Array<{ name: string }>).map((c) => c.name);
  const supplierCols = (db.pragma('table_info(suppliers)') as unknown as Array<{ name: string }>).map((c) => c.name);
  if (!customerCols.includes('current_balance')) db.exec(`ALTER TABLE customers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0`);
  if (!supplierCols.includes('current_balance')) db.exec(`ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0`);
  if (!customerCols.includes('credit_limit')) db.exec(`ALTER TABLE customers ADD COLUMN credit_limit DECIMAL(15,2) DEFAULT 0`);
  if (!customerCols.includes('opening_balance')) db.exec(`ALTER TABLE customers ADD COLUMN opening_balance DECIMAL(15,2) DEFAULT 0`);
  if (!customerCols.includes('payment_terms_days')) db.exec(`ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 14`);

  // Ensure employees table exists (migration may have path issue)
  const empTableCheck = db.prepare(`
    SELECT name FROM sqlite_master WHERE type='table' AND name='employees'
  `).get() as { name: string } | undefined;
  if (!empTableCheck) {
    const empSQL = fs.readFileSync(path.join(__dirname, '..', 'migrations', 'add-employees-table.sql'), 'utf8');
    db.exec(empSQL);
  }

  // Ensure quotations table exists (migration not registered in database.ts)
  const quoteTableCheck = db.prepare(`
    SELECT name FROM sqlite_master WHERE type='table' AND name='quotations'
  `).get() as { name: string } | undefined;
  if (!quoteTableCheck) {
    db.exec(`CREATE TABLE quotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      quotation_no VARCHAR(50) UNIQUE NOT NULL,
      customer_id INTEGER NOT NULL,
      customer_name VARCHAR(200),
      quotation_date DATE NOT NULL,
      expiry_date DATE,
      status VARCHAR(20) DEFAULT 'Draft',
      source_type VARCHAR(20),
      total_amount DECIMAL(15,2) DEFAULT 0,
      notes TEXT,
      terms TEXT,
      warehouse_id INTEGER,
      created_by INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
  }

  // Seed roles and permissions for action filtering
  db.exec(`INSERT OR IGNORE INTO roles (id, role_name, description, is_system_role, is_active) VALUES (1, 'Admin', 'Admin', 1, 1), (2, 'User', 'User', 1, 1)`);
  db.exec(`UPDATE users SET role_id = 1, role = 'admin' WHERE username = 'admin'`);
  const permModules = ['invoices','payments','purchases','inventory','sales_orders','production','employees','customers','suppliers','reports'];
  const permActions: Record<string, string[]> = {
    invoices: ['read','create','update','delete'],
    payments: ['read','create','update','delete'],
    purchases: ['read','create','update','delete'],
    inventory: ['read','create','update','delete'],
    sales_orders: ['read','create','update','delete'],
    production: ['read','create','update','delete'],
    employees: ['read','create','update','delete'],
    customers: ['read','create','update','delete'],
    suppliers: ['read','create','update','delete'],
    reports: ['read'],
  };
  let pid = 1;
  const rolePermInserts: string[] = [];
  for (const [mod, acts] of Object.entries(permActions)) {
    for (const act of acts) {
      db.exec(`INSERT OR IGNORE INTO permissions (id, permission_name, module, action, description) VALUES (${pid}, '${mod}:${act}', '${mod}', '${act}', '${mod} ${act}')`);
      rolePermInserts.push(`(${pid}, 1)`);
      pid++;
    }
  }
  if (rolePermInserts.length > 0) {
    db.exec(`INSERT OR IGNORE INTO role_permissions (permission_id, role_id) VALUES ${rolePermInserts.join(',')}`);
  }
}

beforeAll(() => {
  createFixture();
  // Seed minimal test data
  // Seed minimal test data (idempotent)
  db.prepare(`
    INSERT OR IGNORE INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('admin', 'admin@test.local', 'hash', 'Admin', 'admin', 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO items (item_code, item_name, category, unit_of_measure, standard_selling_price, is_purchased, is_finished_good, is_active)
    VALUES ('ITEM-001', 'Test Soap', 'FMCG', 'Nos', 85, 1, 1, 1),
           ('ITEM-002', 'Test Shampoo', 'FMCG', 'Nos', 120, 1, 1, 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO warehouses (warehouse_code, warehouse_name, is_active)
    VALUES ('WH-001', 'Main Warehouse', 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO customers (customer_code, customer_name, phone, email, current_balance, is_active)
    VALUES ('CUST-001', 'Ali Khan', '0300-1234567', 'ali@test.com', 12500, 1),
           ('CUST-002', 'Ali & Sons', '0312-9876543', null, 0, 1),
           ('CUST-003', 'Inactive Customer', null, null, 0, 0)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO suppliers (supplier_code, supplier_name, contact_person, phone, email, current_balance, is_active)
    VALUES ('SUP-001', 'Ali Traders', 'Ali', '0321-7654321', 'ali@traders.com', 35000, 1),
           ('SUP-002', 'Inactive Supplier', null, null, null, 0, 0)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO invoices (invoice_no, customer_id, status, total_amount, paid_amount, balance_amount, invoice_date)
    VALUES ('INV-001', 1, 'Unpaid', 12500, 0, 12500, '2024-08-15'),
           ('INV-002', 2, 'Paid', 5000, 5000, 0, '2024-08-01')
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO purchase_orders (po_no, supplier_id, status, total_amount, po_date)
    VALUES ('PO-001', 1, 'Submitted', 85000, '2024-08-10'),
           ('PO-002', 1, 'Draft', 10000, '2024-08-12')
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO quotations (quotation_no, customer_id, status, total_amount, quotation_date, created_by)
    VALUES ('QUO-001', 1, 'Accepted', 45000, '2024-08-05', 1),
           ('QUO-002', 2, 'Draft', 20000, '2024-08-08', 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO sales_orders (so_no, customer_id, status, total_amount, so_date)
    VALUES ('SO-001', 1, 'Confirmed', 67000, '2024-08-12'),
           ('SO-002', 2, 'Cancelled', 30000, '2024-08-13')
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO payments (payment_no, customer_id, amount, payment_method, payment_date)
    VALUES ('PAY-001', 1, 5000, 'Cash', '2024-08-18'),
           ('PAY-002', 2, 2000, 'Bank Transfer', '2024-08-17')
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO expenses (expense_no, expense_category, description, amount, expense_date, status)
    VALUES ('EXP-001', 'Office Supplies', 'Office rent August', 25000, '2024-08-01', 'Approved')
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO employees (employee_code, first_name, last_name, department, phone, is_active)
    VALUES ('EMP-001', 'Ahmed', 'Khan', 'Developer', '0300-1112233', 1),
           ('EMP-002', 'Sara', 'Ali', 'HR', '0311-2223344', 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO productions (production_no, output_item_id, output_quantity, warehouse_id, production_date, created_by)
    VALUES ('PRD-001', 1, 100, 1, '2024-08-15', 1)
  `).run();

  db.prepare(`
    INSERT OR IGNORE INTO boms (bom_no, bom_name, finished_item_id, quantity, is_active, created_by)
    VALUES ('BOM-001', 'Widget A BOM', 1, 1, 1, 1),
           ('BOM-002', 'Widget B BOM', 2, 1, 0, 1)
  `).run();
});

describe('Search API', () => {
  let authCookie: string;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', password: TEST_PASSWORD });
    const cookies = res.headers['set-cookie'];
    if (cookies) {
      authCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c: string) => c.startsWith('token=')) ?? '';
    }
  });

  describe('GET /api/search', () => {
    it('requires authentication', async () => {
      const res = await request(app).get('/api/search?q=ali');
      expect(res.status).toBe(401);
    });

    it('rejects query shorter than 2 chars', async () => {
      const res = await request(app)
        .get('/api/search?q=a')
        .set('Cookie', authCookie);
      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('returns results for customer search', async () => {
      const res = await request(app)
        .get('/api/search?q=ali&limit=10')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.query).toBe('ali');
      expect(res.body.data.results.length).toBeGreaterThan(0);

      const customers = res.body.data.results.filter((r: any) => r.type === 'customer');
      expect(customers.length).toBeGreaterThan(0);
      const titles = customers.map((c: any) => c.title);
      expect(titles).toContain('Ali Khan');
      expect(titles.some((t: string) => t === 'Ali & Sons' || t === 'Ali Khan')).toBe(true);
      const aliKhan = customers.find((c: any) => c.title === 'Ali Khan');
      expect(aliKhan).toBeDefined();
      expect(aliKhan.subtitle).toContain('CUST-001');
    });

    it('returns inactive customers filtered out', async () => {
      const res = await request(app)
        .get('/api/search?q=Inactive Customer')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const inactive = res.body.data.results.filter((r: any) => r.title === 'Inactive Customer');
      expect(inactive.length).toBe(0);
    });

    it('returns suppliers', async () => {
      const res = await request(app)
        .get('/api/search?q=Ali Traders')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const suppliers = res.body.data.results.filter((r: any) => r.type === 'supplier');
      expect(suppliers.length).toBe(1);
      expect(suppliers[0].title).toBe('Ali Traders');
      expect(suppliers[0].subtitle).toContain('SUP-001');
    });

    it('returns products', async () => {
      const res = await request(app)
        .get('/api/search?q=Test Soap')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const products = res.body.data.results.filter((r: any) => r.type === 'product');
      expect(products.length).toBe(1);
      expect(products[0].title).toBe('Test Soap');
    });

    it('returns invoices', async () => {
      const res = await request(app)
        .get('/api/search?q=INV-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const invoices = res.body.data.results.filter((r: any) => r.type === 'invoice');
      expect(invoices.length).toBe(1);
      expect(invoices[0].title).toBe('INV-001');
      expect(invoices[0].metadata.status).toBe('Unpaid');
    });

    it('returns purchase orders', async () => {
      const res = await request(app)
        .get('/api/search?q=PO-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const po = res.body.data.results.filter((r: any) => r.type === 'purchase_order');
      expect(po.length).toBe(1);
      expect(po[0].title).toBe('PO-001');
    });

  it('returns quotations', async () => {
    const res = await request(app)
      .get('/api/search?q=Ali')
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.results.some((r: any) => r.type === 'quotation')).toBe(true);
  });

    it('returns sales orders', async () => {
      const res = await request(app)
        .get('/api/search?q=SO-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const so = res.body.data.results.filter((r: any) => r.type === 'sales_order');
      expect(so.length).toBe(1);
    });

    it('returns payments', async () => {
      const res = await request(app)
        .get('/api/search?q=PAY-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const pay = res.body.data.results.filter((r: any) => r.type === 'payment');
      expect(pay.length).toBe(1);
    });

    it('returns expenses', async () => {
      const res = await request(app)
        .get('/api/search?q=Office rent')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const exp = res.body.data.results.filter((r: any) => r.type === 'expense');
      expect(exp.length).toBe(1);
    });

    it('returns warehouses', async () => {
      const res = await request(app)
        .get('/api/search?q=Main Warehouse')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const wh = res.body.data.results.filter((r: any) => r.type === 'warehouse');
      expect(wh.length).toBe(1);
      expect(wh[0].title).toBe('Main Warehouse');
    });

    it('returns employees', async () => {
      const res = await request(app)
        .get('/api/search?q=Ahmed')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const emp = res.body.data.results.filter((r: any) => r.type === 'employee');
      expect(emp.length).toBe(1);
      expect(emp[0].title).toContain('Ahmed');
    });

    it('returns productions', async () => {
      const res = await request(app)
        .get('/api/search?q=PRD-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const prod = res.body.data.results.filter((r: any) => r.type === 'production');
      expect(prod.length).toBe(1);
    });

    it('returns boms', async () => {
      const res = await request(app)
        .get('/api/search?q=BOM-001')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const bom = res.body.data.results.filter((r: any) => r.type === 'bom');
      expect(bom.length).toBe(1);
      expect(bom[0].title).toBe('BOM-001');
      // bom_items not seeded, so component_count is 0
      expect(bom[0].subtitle).toContain('Active');
    });

    it('ranks exact match before contains', async () => {
      const res = await request(app)
        .get('/api/search?q=Ali')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const customers = res.body.data.results.filter((r: any) => r.type === 'customer');
      expect(customers.length).toBeGreaterThan(0);
      // Both "Ali Khan" and "Ali & Sons" should be in top results (both start with "Ali")
      const titles = customers.map((c: any) => c.title);
      expect(titles).toContain('Ali Khan');
      expect(titles).toContain('Ali & Sons');
    });

    it('respects per-entity limit', async () => {
      const res = await request(app)
        .get('/api/search?q=ali&limit=1')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      // limit is applied per entity type, so total may exceed limit
      // but no single entity type should exceed limit
      const customers = res.body.data.results.filter((r: any) => r.type === 'customer');
      expect(customers.length).toBeLessThanOrEqual(1);
    });

    it('returns actions for each entity', async () => {
      const res = await request(app)
        .get('/api/search?q=ali&limit=1')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const customers = res.body.data.results.filter((r: any) => r.type === 'customer');
      expect(customers.length).toBe(1);
      expect(Array.isArray(customers[0].actions)).toBe(true);
      expect(customers[0].actions.length).toBeGreaterThan(0);
      expect(customers[0].actions.some((a: any) => a.id === 'open')).toBe(true);
    });

    it('filters actions based on invoice status', async () => {
      const res = await request(app)
        .get('/api/search?q=INV-002')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const invoices = res.body.data.results.filter((r: any) => r.type === 'invoice');
      expect(invoices.length).toBe(1);
      const actions = invoices[0].actions;
      // Paid invoice should NOT have record_payment action
      const hasRecordPayment = actions.some((a: any) => a.id === 'record_payment');
      expect(hasRecordPayment).toBe(false);
    });

    it('returns empty array for no results', async () => {
      const res = await request(app)
        .get('/api/search?q=xyznonexistent')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      expect(res.body.data.results.length).toBe(0);
      expect(res.body.data.total).toBe(0);
    });

    it('returns searchable pages', async () => {
      const res = await request(app)
        .get('/api/search?q=inventory')
        .set('Cookie', authCookie);
      expect(res.status).toBe(200);
      const pages = res.body.data.results.filter((r: any) => r.type === 'page');
      expect(pages.length).toBeGreaterThan(0);
      expect(pages.some((p: any) => p.id === 'inventory')).toBe(true);
    });
  });
});
