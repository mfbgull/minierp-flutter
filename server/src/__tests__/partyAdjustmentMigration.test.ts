import { describe, expect, it } from '@jest/globals';
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const migration = fs.readFileSync(
  path.join(__dirname, '../migrations/125_party_adjustments.sql'),
  'utf8',
);

function legacyDatabase(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_name TEXT NOT NULL);
    CREATE TABLE suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_name TEXT NOT NULL);
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT, total_amount REAL NOT NULL,
      paid_amount REAL NOT NULL DEFAULT 0, balance_amount REAL, status TEXT
    );
    CREATE TABLE users (id INTEGER PRIMARY KEY);
    INSERT INTO users (id) VALUES (1);
    CREATE TABLE permissions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, permission_name TEXT UNIQUE,
      module TEXT, action TEXT, description TEXT
    );
    CREATE TABLE roles (id INTEGER PRIMARY KEY AUTOINCREMENT, role_name TEXT UNIQUE);
    INSERT INTO roles (id, role_name) VALUES (1, 'Admin');
    CREATE TABLE role_permissions (
      role_id INTEGER, permission_id INTEGER, PRIMARY KEY (role_id, permission_id)
    );
    CREATE TABLE purchases (id INTEGER PRIMARY KEY, total_cost REAL, input_tax_amount REAL DEFAULT 0);
    CREATE TABLE purchase_returns (
      id INTEGER PRIMARY KEY, source_type TEXT, source_id INTEGER,
      total_amount REAL, status TEXT
    );
    CREATE TABLE purchase_allocations (
      id INTEGER PRIMARY KEY, purchase_id INTEGER, amount REAL, voided_at TEXT
    );
    CREATE TABLE purchase_orders (id INTEGER PRIMARY KEY, total_amount REAL);
    CREATE TABLE po_allocations (
      id INTEGER PRIMARY KEY, po_id INTEGER, amount REAL, voided_at TEXT
    );
    CREATE TABLE supplier_bills (id INTEGER PRIMARY KEY);
    CREATE TABLE supplier_bill_allocations (
      id INTEGER PRIMARY KEY, bill_id INTEGER, amount REAL, voided_at TEXT, payment_id INTEGER
    );
    CREATE VIEW direct_purchase_payables AS
      SELECT p.id, ROUND(p.total_cost + p.input_tax_amount, 2) AS total_payable,
        COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
          WHERE r.source_type = 'PURCHASE' AND r.source_id = p.id AND r.status = 'POSTED'), 0) AS returned_amount,
        COALESCE((SELECT SUM(a.amount) FROM purchase_allocations a
          WHERE a.purchase_id = p.id AND a.voided_at IS NULL), 0) AS paid_amount
      FROM purchases p;
    CREATE VIEW purchase_order_payables AS
      SELECT po.id, po.total_amount AS total_payable,
        COALESCE((SELECT SUM(r.total_amount) FROM purchase_returns r
          WHERE r.source_type = 'PURCHASE_ORDER' AND r.source_id = po.id AND r.status = 'POSTED'), 0) AS returned_amount,
        COALESCE((SELECT SUM(a.amount) FROM po_allocations a
          WHERE a.po_id = po.id AND a.voided_at IS NULL), 0) AS paid_amount
      FROM purchase_orders po;
    INSERT INTO customers (id, customer_name) VALUES (1, 'Alpha'), (2, 'Beta');
    INSERT INTO suppliers (id, supplier_name) VALUES (1, 'Gamma'), (2, 'Delta');
    INSERT INTO invoices (id, total_amount, paid_amount, balance_amount, status)
      VALUES (1, 2000, 500, 1500, 'Partially Paid');
  `);
  return db;
}

describe('party adjustment migration', () => {
  it('creates one Party per existing profile without changing financial values', () => {
    const db = legacyDatabase();
    try {
      const before = db.prepare('SELECT total_amount, paid_amount, balance_amount FROM invoices WHERE id = 1').get();
      db.exec(migration);

      expect(db.prepare('SELECT id, party_id FROM customers ORDER BY id').all()).toEqual([
        { id: 1, party_id: 1 },
        { id: 2, party_id: 2 },
      ]);
      expect(db.prepare('SELECT id, party_id FROM suppliers ORDER BY id').all()).toEqual([
        { id: 1, party_id: 3 },
        { id: 2, party_id: 4 },
      ]);
      expect(db.prepare('SELECT COUNT(*) AS count, COUNT(DISTINCT display_name) AS names FROM parties').get())
        .toEqual({ count: 4, names: 4 });
      expect(db.prepare('SELECT adjusted_amount FROM invoices WHERE id = 1').get()).toEqual({ adjusted_amount: 0 });
      expect(db.prepare('SELECT total_amount, paid_amount, balance_amount FROM invoices WHERE id = 1').get()).toEqual(before);
    } finally { db.close(); }
  });

  it('recreates the payable views with adjustment columns', () => {
    const db = legacyDatabase();
    try {
      db.exec(migration);
      for (const view of ['direct_purchase_payables', 'purchase_order_payables']) {
        const columns = db.prepare(`PRAGMA table_info(${view})`).all() as Array<{ name: string }>;
        expect(columns.map(column => column.name)).toEqual(
          expect.arrayContaining(['adjusted_amount', 'settled_amount']),
        );
      }
    } finally { db.close(); }
  });

  it('gives a new profile its own Party and seeds Admin-only permissions', () => {
    const db = legacyDatabase();
    try {
      db.exec(migration);
      db.prepare('INSERT INTO customers (customer_name) VALUES (?)').run('Epsilon');
      expect(db.prepare('SELECT party_id FROM customers WHERE customer_name = ?').get('Epsilon'))
        .toEqual({ party_id: 5 });
      expect(db.prepare(`SELECT COUNT(*) AS count FROM permissions
        WHERE module IN ('parties', 'party_adjustments')`).get()).toEqual({ count: 5 });
      expect(db.prepare(`SELECT COUNT(*) AS count FROM party_identity_events`).get()).toEqual({ count: 0 });
      expect(db.prepare(`SELECT COUNT(*) AS count FROM role_permissions rp
        JOIN roles r ON r.id = rp.role_id JOIN permissions p ON p.id = rp.permission_id
        WHERE r.role_name = 'Admin' AND p.module IN ('parties', 'party_adjustments')`).get())
        .toEqual({ count: 5 });
    } finally { db.close(); }
  });
});
