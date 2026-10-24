import { afterEach, beforeAll, beforeEach, describe, expect, it, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import StockMovementModel from '../models/StockMovement';
import ReportsModel from '../models/Reports';
import CustomReportModel from '../models/CustomReport';
import customReportsController from '../controllers/customReportsController';
import reportsController from '../controllers/reportsController';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — stock balance listing, customer statements
 * and the custom-report template/update handlers.
 */

let cookie = '';
const config = { entity: 'invoices', columns: [{ field: 'total_amount' }] };

beforeAll(async () => {
  cookie = await getAuthCookie();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('StockMovement.getStockBalances', () => {
  const balancesFor: jest.Mock = jest.fn();
  let itemA = 0;
  let itemB = 0;
  let wh1 = 0;
  let wh2 = 0;

  beforeAll(() => {
    itemA = Number(
      db.prepare(`INSERT INTO items (item_code, item_name) VALUES ('SB-A', 'Alpha')`).run()
        .lastInsertRowid
    );
    itemB = Number(
      db.prepare(`INSERT INTO items (item_code, item_name) VALUES ('SB-B', 'Beta')`).run()
        .lastInsertRowid
    );
    wh1 = Number(
      db
        .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('SB-WH-1', 'Main Annex')`)
        .run().lastInsertRowid
    );
    wh2 = Number(
      db
        .prepare(`INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('SB-WH-2', 'Annex Two')`)
        .run().lastInsertRowid
    );
  });

  beforeEach(() => {
    db.prepare('DELETE FROM stock_balances').run();
    const insert = db.prepare(
      `INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)`
    );
    insert.run(itemA, wh1, 30);
    insert.run(itemA, wh2, 5);
    insert.run(itemB, wh2, 12);
    void balancesFor;
  });

  it('pages and filters by search, warehouse code and id', () => {
    const page = StockMovementModel.getStockBalances({ page: 2, limit: 2 }, db);
    expect(page.total).toBe(3);
    expect(page.rows).toHaveLength(1);
    expect(page).toMatchObject({ pageNum: 2, limitNum: 2 });

    expect(StockMovementModel.getStockBalances({ search: 'Beta' }, db).rows).toHaveLength(1);
    expect(StockMovementModel.getStockBalances({ search: 'Annex Two' }, db).rows).toHaveLength(2);
    expect(StockMovementModel.getStockBalances({ warehouse_code: 'SB-WH-1' }, db).rows).toHaveLength(1);
  });

  it('sorts by whitelisted columns and falls back on junk input', () => {
    const sorted = StockMovementModel.getStockBalances(
      { sortBy: 'quantity', sortOrder: 'DESC' },
      db
    );
    expect(sorted.rows.map(r => Number((r as unknown as { quantity: number }).quantity))).toEqual([
      30, 12, 5,
    ]);

    const fallback = StockMovementModel.getStockBalances(
      { sortBy: 'quantity; DROP TABLE items', sortOrder: 'SIDEWAYS' },
      db
    );
    expect(fallback.rows).toHaveLength(3);
  });
});

describe('customer statements', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM customer_ledger').run();
    db.prepare('DELETE FROM customers').run();
  });

  function seed(): void {
    const first = db
      .prepare(`INSERT INTO customers (customer_code, customer_name) VALUES ('RS-A', 'A Co')`)
      .run();
    db.prepare(`INSERT INTO customers (customer_code, customer_name) VALUES ('RS-B', 'B Co')`).run();
    const insert = db.prepare(
      `INSERT INTO customer_ledger (
         customer_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description, voided
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'row', 0)`
    );
    insert.run(first.lastInsertRowid, '2026-01-05', 'INVOICE', 'INV-OLD', 100, 0, 100);
    insert.run(first.lastInsertRowid, '2026-02-05', 'INVOICE', 'INV-NEW', 40, 0, 140);
    insert.run(first.lastInsertRowid, '2026-02-06', 'PAYMENT', 'PAY-1', 0, 60, 80);
  }

  it('totals opening, debits and credits per customer', () => {
    seed();

    const all = ReportsModel.getCustomerStatements(db, 0).statements;
    expect(all).toHaveLength(2);

    const ranged = ReportsModel.getCustomerStatements(db, 0, '2026-02-01', '2026-02-28')
      .statements;
    const first = ranged.find(r => r.customer_code === 'RS-A')!;
    expect(Number(first.opening_balance)).toBe(100);
    expect(Number(first.total_debits)).toBe(40);
    expect(Number(first.total_credits)).toBe(60);
    expect(Number(first.invoice_count)).toBe(1);
    expect(first.last_invoice_date).toBe('2026-02-05');

    const one = ReportsModel.getCustomerStatements(db, first.customer_id).statements;
    expect(one).toHaveLength(1);
    expect(Number(one[0].total_debits)).toBe(140);
  });

  it('passes camelCase or snake_case bounds through the route', async () => {
    const spy = jest
      .spyOn(ReportsModel, 'getCustomerStatements')
      .mockReturnValue([] as unknown as ReturnType<typeof ReportsModel.getCustomerStatements>);

    const camel = await request(app)
      .get('/api/reports/customer-statements')
      .set('Cookie', cookie)
      .query({ customerId: '4', startDate: '2026-01-01', endDate: '2026-01-31' });
    expect(camel.status).toBe(200);
    expect(spy).toHaveBeenLastCalledWith(expect.anything(), 4, '2026-01-01', '2026-01-31');

    await request(app)
      .get('/api/reports/customer-statements')
      .set('Cookie', cookie)
      .query({ fromDate: '2026-02-01', toDate: '2026-02-28' });
    expect(spy).toHaveBeenLastCalledWith(expect.anything(), 0, '2026-02-01', '2026-02-28');

    await request(app).get('/api/reports/customer-statements').set('Cookie', cookie);
    expect(spy).toHaveBeenLastCalledWith(expect.anything(), 0, undefined, undefined);
  });

  it('returns a sanitized 500 when the statement read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(ReportsModel, 'getCustomerStatements').mockImplementation(() => {
      throw new Error('forced statement failure');
    });

    const res = await request(app)
      .get('/api/reports/customer-statements')
      .set('Cookie', cookie);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to fetch customer statements' });
  });

  it('maps controller failures for the direct handler path', () => {
    jest.spyOn(ReportsModel, 'getCustomerStatements').mockImplementation(() => {
      throw new Error('forced statement failure');
    });
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    reportsController.getCustomerStatements({ query: {} } as unknown as Request, res);
    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({
      success: false,
      error: 'Failed to fetch customer statements',
    });
  });
});

describe('custom report templates and updates', () => {
  it('rejects non-admin template creation', () => {
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    customReportsController.createTemplate(
      { user: { role: 'staff' }, body: {} } as unknown as Request,
      res
    );
    expect(status).toHaveBeenCalledWith(403);
  });

  it('validates and creates a template', async () => {
    const missingName = await request(app)
      .post('/api/reports/custom/templates')
      .set('Cookie', cookie)
      .send({ config });
    expect(missingName.status).toBe(400);

    const longName = await request(app)
      .post('/api/reports/custom/templates')
      .set('Cookie', cookie)
      .send({ name: 'x'.repeat(101), config });
    expect(longName.status).toBe(400);

    const missingConfig = await request(app)
      .post('/api/reports/custom/templates')
      .set('Cookie', cookie)
      .send({ name: 'No config' });
    expect(missingConfig.status).toBe(400);

    const invalid = await request(app)
      .post('/api/reports/custom/templates')
      .set('Cookie', cookie)
      .send({
        name: 'Bad',
        config: {
          entity: 'invoices',
          columns: [{ field: 'total_amount' }, { field: 'calc' }],
          computedColumns: [{ name: 'calc', expression: '(SELECT password_hash FROM users)' }],
        },
      });
    expect(invalid.status).toBe(400);

    const created = await request(app)
      .post('/api/reports/custom/templates')
      .set('Cookie', cookie)
      .send({ name: `Template ${Date.now()}`, description: 'saved', config });
    expect(created.status).toBe(201);
    expect(created.body.success).toBe(true);
    expect(created.body.data.user_id).toBe(0);
  });

  it('maps template creation failures to 500', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(CustomReportModel, 'createTemplate').mockImplementation(() => {
      throw new Error('forced template failure');
    });
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    customReportsController.createTemplate(
      {
        user: { role: 'admin' },
        body: { name: 'Throws', config },
      } as unknown as Request,
      res
    );
    expect(status).toHaveBeenCalledWith(500);
  });

  it('validates and applies report updates', async () => {
    const userId = (
      db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
    ).id;
    const report = CustomReportModel.create({
      user_id: userId,
      name: 'Coverage report',
      config,
    } as never);

    const emptyName = await request(app)
      .put(`/api/reports/custom/${report.id}`)
      .set('Cookie', cookie)
      .send({ name: '   ' });
    expect(emptyName.status).toBe(400);

    const badConfig = await request(app)
      .put(`/api/reports/custom/${report.id}`)
      .set('Cookie', cookie)
      .send({ config: 'not-an-object' });
    expect(badConfig.status).toBe(400);

    const invalidConfig = await request(app)
      .put(`/api/reports/custom/${report.id}`)
      .set('Cookie', cookie)
      .send({
        config: {
          entity: 'invoices',
          columns: [{ field: 'total_amount' }, { field: 'calc' }],
          computedColumns: [{ name: 'calc', expression: '(SELECT password_hash FROM users)' }],
        },
      });
    expect(invalidConfig.status).toBe(400);

    const updated = await request(app)
      .put(`/api/reports/custom/${report.id}`)
      .set('Cookie', cookie)
      .send({ name: ' Renamed ', description: 'now', config });
    expect(updated.status).toBe(200);
    expect(updated.body.data.name).toBe('Renamed');
    expect(updated.body.data.config).toEqual(config);

    const missing = await request(app)
      .put('/api/reports/custom/999999')
      .set('Cookie', cookie)
      .send({ name: 'Nope' });
    expect(missing.status).toBe(404);
  });

  it('maps update failures to 500', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(CustomReportModel, 'update').mockImplementation(() => {
      throw new Error('forced update failure');
    });
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    customReportsController.updateReport(
      { user: { id: 1 }, params: { id: '1' }, body: { name: 'X' } } as unknown as Request,
      res
    );
    expect(status).toHaveBeenCalledWith(500);
  });
});
