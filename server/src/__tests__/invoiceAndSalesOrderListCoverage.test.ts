import { beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import InvoiceModel from '../models/Invoice';
import SalesOrderModel from '../models/SalesOrder';

/**
 * Fallow health remediation — `Invoice.getAll` (CRAP 38.9) and
 * `SalesOrder.getAll` (CRAP 35.1) filter/sort/paging branches.
 */

let customerA = 0;
let customerB = 0;
let warehouseId = 0;
let soId = 0;
let caseSeq = 0;

beforeEach(() => {
  db.prepare('DELETE FROM invoice_items').run();
  db.prepare('DELETE FROM invoices').run();
  db.prepare('DELETE FROM sales_order_items').run();
  db.prepare('DELETE FROM sales_orders').run();
  db.prepare('DELETE FROM customers').run();
  db.prepare('DELETE FROM items').run();

  customerA = Number(
    db
      .prepare(`INSERT INTO customers (customer_code, customer_name) VALUES ('LS-A', 'Alpha Ltd')`)
      .run().lastInsertRowid
  );
  customerB = Number(
    db
      .prepare(`INSERT INTO customers (customer_code, customer_name) VALUES ('LS-B', 'Beta Ltd')`)
      .run().lastInsertRowid
  );
  caseSeq += 1;
  warehouseId = Number(
    db
      .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, 'List WH')`)
      .run(`LS-WH-${caseSeq}`).lastInsertRowid
  );
});

describe('Invoice.getAll', () => {
  function seedInvoices(): void {
    soId = Number(
      db
        .prepare(
          `INSERT INTO sales_orders (so_no, customer_id, so_date, status, total_amount)
           VALUES ('LS-SO-1', ?, '2026-01-01', 'Confirmed', 100)`
        )
        .run(customerA).lastInsertRowid
    );
    const insert = db.prepare(
      `INSERT INTO invoices (
         invoice_no, customer_id, invoice_date, status, total_amount,
         customer_name, source_type, so_id, deleted_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    insert.run('LS-INV-1', customerA, '2026-01-10', 'Unpaid', 100, 'Walk Alpha', 'POS', null, null);
    insert.run('LS-INV-2', customerB, '2026-02-10', 'Paid', 200, 'Walk Beta', 'DIRECT', null, null);
    insert.run('LS-INV-3', customerA, '2026-03-10', 'Draft', 300, 'Walk Gamma', 'DIRECT', soId, null);
    insert.run('LS-INV-4', customerB, '2026-01-15', 'Unpaid', 400, 'Walk Delta', 'SALES_ORDER', null, '2026-03-11');
  }

  it('excludes deleted invoices and pages the remainder', () => {
    seedInvoices();

    const page = InvoiceModel.getAll({ page: 2, limit: 2 }, db);

    expect(page.total).toBe(3);
    expect(page.rows).toHaveLength(1);
    expect(page.rows[0].invoice_no).toBe('LS-INV-1');
    expect(page).toMatchObject({ pageNum: 2, limitNum: 2 });
  });

  it('applies every filter branch', () => {
    seedInvoices();
    const ids = (filters: Parameters<typeof InvoiceModel.getAll>[0]) =>
      InvoiceModel.getAll(filters, db).rows.map(r => r.invoice_no).sort();

    expect(ids({ statuses: ['Unpaid', 'Paid'] })).toEqual(['LS-INV-1', 'LS-INV-2']);
    expect(ids({ customer_id: customerA })).toEqual(['LS-INV-1', 'LS-INV-3']);
    expect(ids({ customer_name: 'Walk Beta' })).toEqual(['LS-INV-2']);
    expect(ids({ search: 'INV-3' })).toEqual(['LS-INV-3']);
    expect(ids({ search: 'Alpha' })).toEqual(['LS-INV-1', 'LS-INV-3']);
    expect(ids({ start_date: '2026-02-01' })).toEqual(['LS-INV-2', 'LS-INV-3']);
    expect(ids({ end_date: '2026-01-31' })).toEqual(['LS-INV-1']);
    expect(ids({ source_type: 'DIRECT' })).toEqual(['LS-INV-2', 'LS-INV-3']);
    expect(ids({ so_id: soId })).toEqual(['LS-INV-3']);
  });

  it('sorts by whitelisted columns and falls back on junk', () => {
    seedInvoices();

    const ascending = InvoiceModel.getAll(
      { sortBy: 'invoice_no', sortOrder: 'ASC' },
      db
    ).rows.map(r => r.invoice_no);
    expect(ascending).toEqual(['LS-INV-1', 'LS-INV-2', 'LS-INV-3']);

    const fallback = InvoiceModel.getAll(
      { sortBy: 'invoice_no; DROP TABLE invoices', sortOrder: 'NOPE' },
      db
    );
    expect(fallback.rows.map(r => r.invoice_no)).toEqual(['LS-INV-3', 'LS-INV-2', 'LS-INV-1']);
  });
});

describe('SalesOrder.getAll', () => {
  function seedOrders(): void {
    const insert = db.prepare(
      `INSERT INTO sales_orders (
         so_no, customer_id, so_date, status, total_amount,
         warehouse_id, customer_name, source_type
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    );
    insert.run('LS-SO-1', customerA, '2026-01-05', 'Draft', 100, null, 'Alpha Ltd', 'DIRECT');
    insert.run('LS-SO-2', customerB, '2026-02-05', 'Confirmed', 200, warehouseId, 'Beta Ltd', 'QUOTATION');
    insert.run('LS-SO-3', customerA, '2026-03-05', 'Delivered', 300, warehouseId, 'Alpha Ltd', 'DIRECT');

    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('LS-IT', 'List Item')`)
      .run();
    db.prepare(
      `INSERT INTO sales_order_items (
         so_id, item_id, quantity, delivered_quantity, unit_price, amount
       ) VALUES (?, ?, 2, 1, 50, 100)`
    ).run(soIdOf('LS-SO-3'), item.lastInsertRowid);
  }

  function soIdOf(no: string): number {
    return (db.prepare('SELECT id FROM sales_orders WHERE so_no = ?').get(no) as { id: number }).id;
  }

  it('returns page rows with their items', () => {
    seedOrders();

    const page = SalesOrderModel.getAll({ page: 1, limit: 2 }, db);

    expect(page.total).toBe(3);
    expect(page.rows).toHaveLength(2);
    expect(page.rows[0].so_no).toBe('LS-SO-3');
    expect(page.rows[0].items).toHaveLength(1);
    expect(page.rows[0].items?.[0]).toMatchObject({ item_code: 'LS-IT', quantity: 2 });
  });

  it('applies every filter branch', () => {
    seedOrders();
    const ids = (filters: Parameters<typeof SalesOrderModel.getAll>[0]) =>
      SalesOrderModel.getAll(filters, db).rows.map(r => r.so_no).sort();

    expect(ids({ status: 'Draft' })).toEqual(['LS-SO-1']);
    expect(ids({ customer_id: customerA })).toEqual(['LS-SO-1', 'LS-SO-3']);
    expect(ids({ customer_name: 'Beta' })).toEqual(['LS-SO-2']);
    expect(ids({ search: 'SO-2' })).toEqual(['LS-SO-2']);
    expect(ids({ search: 'Alpha' })).toEqual(['LS-SO-1', 'LS-SO-3']);
    expect(ids({ start_date: '2026-02-01' })).toEqual(['LS-SO-2', 'LS-SO-3']);
    expect(ids({ end_date: '2026-01-31' })).toEqual(['LS-SO-1']);
    expect(ids({ warehouse_id: warehouseId })).toEqual(['LS-SO-2', 'LS-SO-3']);
    expect(ids({ source_type: 'QUOTATION' })).toEqual(['LS-SO-2']);
  });

  it('sorts by whitelisted columns and falls back on junk', () => {
    seedOrders();

    const ascending = SalesOrderModel.getAll({ sortBy: 'so_no', sortOrder: 'ASC' }, db).rows.map(
      r => r.so_no
    );
    expect(ascending).toEqual(['LS-SO-1', 'LS-SO-2', 'LS-SO-3']);

    const fallback = SalesOrderModel.getAll(
      { sortBy: 'so_no); --', sortOrder: 'UP' },
      db
    );
    expect(fallback.rows.map(r => r.so_no)).toEqual(['LS-SO-3', 'LS-SO-2', 'LS-SO-1']);
  });
});
