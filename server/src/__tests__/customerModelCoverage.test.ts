import { afterEach, beforeEach, describe, expect, it } from '@jest/globals';
import Database from 'better-sqlite3';
import CustomerModel from '../models/Customer';

describe('Customer model coverage', () => {
  let db: Database.Database;
  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_code TEXT NOT NULL DEFAULT '',
        customer_name TEXT NOT NULL,
        contact_person TEXT, email TEXT, phone TEXT,
        billing_address TEXT, shipping_address TEXT, payment_terms TEXT,
        payment_terms_days INTEGER, credit_limit REAL,
        current_balance REAL DEFAULT 0, opening_balance REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1, created_at TEXT, updated_at TEXT,
        deleted_at TEXT
      );
      CREATE TABLE customer_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        transaction_date TEXT NOT NULL,
        transaction_type TEXT NOT NULL,
        reference_no TEXT,
        debit REAL DEFAULT 0,
        credit REAL DEFAULT 0,
        balance REAL DEFAULT 0,
        description TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        voided INTEGER DEFAULT 0,
        reversed_by INTEGER
      );
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER,
        payment_no TEXT, amount REAL, notes TEXT
      );
      CREATE TABLE payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT, payment_id INTEGER,
        invoice_id INTEGER, voided_at TEXT
      );
      CREATE TABLE invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT);
      CREATE TABLE invoice_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT, return_no TEXT,
        invoice_id INTEGER, voided_at TEXT
      );
    `);
  });
  afterEach(() => { db.close(); });

  it('creates a customer with every optional field and with defaults', () => {
    const fullId = CustomerModel.create({
      customer_name: 'Full Customer', contact_person: 'A', email: 'a@example.test',
      phone: '123', billing_address: 'B', shipping_address: 'S',
      payment_terms: 'Net 30', payment_terms_days: 30, credit_limit: 5000,
      opening_balance: 100,
    }, db);
    const emptyId = CustomerModel.create({ customer_name: 'Empty', phone: '0' }, db);

    expect(fullId).toBe(1);
    expect(emptyId).toBe(2);
    expect(db.prepare(`SELECT customer_name, contact_person, email, phone, billing_address,
      shipping_address, payment_terms, payment_terms_days, credit_limit, current_balance, opening_balance
      FROM customers ORDER BY id`).all()).toEqual([
      { customer_name: 'Full Customer', contact_person: 'A', email: 'a@example.test', phone: '123',
        billing_address: 'B', shipping_address: 'S', payment_terms: 'Net 30', payment_terms_days: 30,
        credit_limit: 5000, current_balance: 100, opening_balance: 100 },
      { customer_name: 'Empty', contact_person: '', email: '', phone: '0',
        billing_address: '', shipping_address: '', payment_terms: '', payment_terms_days: 14,
        credit_limit: 0, current_balance: 0, opening_balance: 0 },
    ]);
  });

  it('lists, paginates and date-bounds the customer ledger', () => {
    const insert = db.prepare(`INSERT INTO customer_ledger
      (customer_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
    insert.run(1, '2026-01-01', 'INVOICE', 'INV-1', 1000, 0, 1000, 'Sale');
    insert.run(1, '2026-01-02', 'PAYMENT', 'PAY-1', 0, 400, 600, 'Payment');
    insert.run(1, '2026-01-03', 'INVOICE', 'INV-2', 200, 0, 800, 'Sale');

    const all = CustomerModel.getLedger(1, 'transaction_date', 'ASC', db);
    expect(all.total).toBe(3);
    expect(all.rows.map(row => row.reference_no)).toEqual(['INV-1', 'PAY-1', 'INV-2']);

    const paged = CustomerModel.getLedger(1, 'transaction_date', 'ASC', db, 2, 1);
    expect(paged.total).toBe(3);
    expect(paged.rows).toHaveLength(1);
    expect(paged.rows[0].reference_no).toBe('PAY-1');

    const ranged = CustomerModel.getLedger(1, 'transaction_date', 'ASC', db, 1, 0, '2026-01-02', '2026-01-03');
    expect(ranged.total).toBe(2);
    expect(ranged.rows.map(row => row.reference_no)).toEqual(['PAY-1', 'INV-2']);
  });
});
