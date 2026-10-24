import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import request from 'supertest';
import app from '../app';
import { updateBatchStatus } from '../controllers/inventoryController';
import posController from '../controllers/posController';
import db from '../config/database';
import EmployeeModel from '../models/Employee';
import MobileInvoiceModel from '../models/MobileInvoice';
import SettingsModel from '../models/Settings';
import UserModel from '../models/User';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — employee delete/salary detail, batch status,
 * mobile draft, POS transactions, settings update and user delete handlers.
 */

type EmployeeRecord = ReturnType<typeof EmployeeModel.getById>;
type DraftRecord = NonNullable<ReturnType<typeof MobileInvoiceModel.getDraftById>>;

let cookie = '';
let adminId = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  adminId = (
    db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
  ).id;
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('employees', () => {
  it('returns 404 when deleting an unknown employee', async () => {
    jest.spyOn(EmployeeModel, 'getById').mockReturnValue(undefined);

    const res = await request(app).delete('/api/employees/999999').set('Cookie', cookie);
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ success: false, error: 'Employee not found' });
  });

  it('deletes an existing employee and answers 204', async () => {
    jest.spyOn(EmployeeModel, 'getById').mockReturnValue({
      id: 5,
      employee_code: 'EMP-1',
      first_name: 'Ali',
      last_name: 'Khan',
    } as unknown as EmployeeRecord);
    const remove = jest
      .spyOn(EmployeeModel, 'delete')
      .mockReturnValue({ changes: 1, lastInsertRowid: 0 });

    const res = await request(app).delete('/api/employees/5').set('Cookie', cookie);

    expect(res.status).toBe(204);
    expect(remove).toHaveBeenCalledWith(5, expect.anything());
  });

  it('returns a sanitized 500 when the delete fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(EmployeeModel, 'getById').mockImplementation(() => {
      throw new Error('forced employee failure');
    });

    const res = await request(app).delete('/api/employees/5').set('Cookie', cookie);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to delete employee' });
  });

  it('returns the salary month detail for a known employee', async () => {
    jest.spyOn(EmployeeModel, 'getById').mockReturnValue({
      id: 5,
      employee_code: 'EMP-1',
    } as unknown as EmployeeRecord);
    const detail = { pay_period: '2026-09', net_salary: 5000 };
    const spy = jest
      .spyOn(EmployeeModel, 'getSalaryMonthDetail')
      .mockReturnValue(detail as unknown as ReturnType<
        typeof EmployeeModel.getSalaryMonthDetail
      >);

    const res = await request(app)
      .get('/api/employees/5/salary/month/2026-09')
      .set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, data: detail });
    expect(spy).toHaveBeenCalledWith(5, '2026-09', expect.anything());
  });

  it('returns 404 for an unknown employee salary month', async () => {
    jest.spyOn(EmployeeModel, 'getById').mockReturnValue(undefined);

    const res = await request(app)
      .get('/api/employees/999999/salary/month/2026-09')
      .set('Cookie', cookie);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ success: false, error: 'Employee not found' });
  });

  it('returns a sanitized 500 when the salary detail read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(EmployeeModel, 'getById').mockReturnValue({
      id: 5,
      employee_code: 'EMP-1',
    } as unknown as EmployeeRecord);
    jest.spyOn(EmployeeModel, 'getSalaryMonthDetail').mockImplementation(() => {
      throw new Error('forced salary failure');
    });

    const res = await request(app)
      .get('/api/employees/5/salary/month/2026-09')
      .set('Cookie', cookie);

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ success: false, error: 'Failed to fetch salary month detail' });
  });
});

describe('inventory batch status', () => {
  const put = (body: Record<string, unknown>) =>
    request(app).put('/api/inventory/batches/1/status').set('Cookie', cookie).send(body);

  it('requires both a location and a status', async () => {
    expect((await put({ status_override: 'ACTIVE' })).status).toBe(400);
    expect((await put({ location_id: 3 })).status).toBe(400);
  });

  it('rejects an unknown status', async () => {
    const res = await put({ location_id: 3, status_override: 'MELTED' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Invalid status_override' });
  });

  it('stores the override on the batch location row', async () => {
    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('BATCH-IT', 'Batch Item')`)
      .run();
    const warehouse = db
      .prepare(
        `INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES ('BATCH-WH', 'Batch WH')`
      )
      .run();
    const batch = db
      .prepare(
        `INSERT INTO stock_batches
           (batch_no, item_id, warehouse_id, source_type, source_id,
            quantity_original, quantity_remaining, unit_cost, received_date)
         VALUES ('BATCH-1', ?, ?, 'PURCHASE', 1, 5, 5, 2, '2026-01-01')`
      )
      .run(item.lastInsertRowid, warehouse.lastInsertRowid);
    const location = db
      .prepare(
        `INSERT INTO locations (warehouse_id, location_code, location_name)
         VALUES (?, 'BATCH-LOC', 'Batch Location')`
      )
      .run(warehouse.lastInsertRowid);
    db.prepare(
      `INSERT INTO batch_stock_by_location
         (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
       VALUES (?, ?, 5, 0, 5)`
    ).run(batch.lastInsertRowid, location.lastInsertRowid);

    const res = await request(app)
      .put(`/api/inventory/batches/${batch.lastInsertRowid}/status`)
      .set('Cookie', cookie)
      .send({ location_id: location.lastInsertRowid, status_override: 'BLOCKED' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      batch_id: Number(batch.lastInsertRowid),
      location_id: Number(location.lastInsertRowid),
      status_override: 'BLOCKED',
    });
    const row = db
      .prepare(
        `SELECT status_override FROM batch_stock_by_location
         WHERE batch_id = ? AND location_id = ?`
      )
      .get(batch.lastInsertRowid, location.lastInsertRowid) as { status_override: string };
    expect(row.status_override).toBe('BLOCKED');
  });

  it('returns a sanitized 500 when the update fails', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(db, 'prepare').mockImplementation(() => {
      throw new Error('forced batch failure');
    });
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    updateBatchStatus(
      { params: { id: '1' }, body: { location_id: 3, status_override: 'ACTIVE' } } as unknown as Request,
      res
    );

    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({ error: 'forced batch failure' });
  });
});

describe('mobile invoice draft', () => {
  const draft = {
    id: 4,
    session_id: 's-1',
    customer_id: null,
    invoice_date: null,
    due_date: null,
    terms: null,
    notes: null,
    items_data: JSON.stringify([{ item_id: 1, quantity: 2 }]),
    status: 'draft',
    expires_at: '2099-01-01T00:00:00.000Z',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  } as unknown as DraftRecord;

  it('returns 404 for an unknown draft', async () => {
    jest.spyOn(MobileInvoiceModel, 'getDraftById').mockReturnValue(undefined);
    expect((await request(app).get('/api/mobile-invoices/draft/4').set('Cookie', cookie)).status).toBe(
      404
    );
  });

  it('returns 410 for an expired draft', async () => {
    jest.spyOn(MobileInvoiceModel, 'getDraftById').mockReturnValue({
      ...draft,
      expires_at: '2000-01-01T00:00:00.000Z',
    });
    const res = await request(app).get('/api/mobile-invoices/draft/4').set('Cookie', cookie);
    expect(res.status).toBe(410);
    expect(res.body).toEqual({ error: 'Draft has expired' });
  });

  it('parses items_data for a live draft', async () => {
    jest.spyOn(MobileInvoiceModel, 'getDraftById').mockReturnValue(draft);

    const res = await request(app).get('/api/mobile-invoices/draft/4').set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.items_data).toEqual([{ item_id: 1, quantity: 2 }]);
  });

  it('returns a sanitized 500 when items_data is corrupt', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(MobileInvoiceModel, 'getDraftById').mockReturnValue({
      ...draft,
      items_data: '{not json',
    });

    const res = await request(app).get('/api/mobile-invoices/draft/4').set('Cookie', cookie);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to get draft' });
  });
});

describe('POS transactions', () => {
  it('returns an empty list on a fresh database', async () => {
    const res = await request(app).get('/api/pos/transactions').set('Cookie', cookie);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, data: [] });
  });

  it('maps POS invoices and honours the date filters', async () => {
    const customer = db
      .prepare(
        `INSERT INTO customers (customer_code, customer_name) VALUES ('POS-CUST', 'Walk-in')`
      )
      .run();
    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('POS-ITEM', 'POS Item')`)
      .run();
    const invoice = db
      .prepare(
        `INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount, source_type)
         VALUES ('POS-INV-1', ?, '2026-09-15', 'Paid', 40, 'POS')`
      )
      .run(customer.lastInsertRowid);
    db.prepare(
      `INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
       VALUES (?, ?, 2, 20, 40)`
    ).run(invoice.lastInsertRowid, item.lastInsertRowid);

    const all = await request(app)
      .get('/api/pos/transactions')
      .set('Cookie', cookie)
      .query({ limit: '10' });
    expect(all.status).toBe(200);
    expect(all.body.data).toHaveLength(1);
    expect(all.body.data[0]).toMatchObject({
      transaction_no: 'POS-INV-1',
      customer_name: 'Walk-in',
      items_count: 1,
      total: 40,
    });

    const ranged = await request(app)
      .get('/api/pos/transactions')
      .set('Cookie', cookie)
      .query({ start_date: '2026-09-01', end_date: '2026-09-30' });
    expect(ranged.body.data).toHaveLength(1);

    const excluded = await request(app)
      .get('/api/pos/transactions')
      .set('Cookie', cookie)
      .query({ start_date: '2026-10-01' });
    expect(excluded.body.data).toHaveLength(0);
  });

  it('returns a sanitized 500 when the query fails', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(db, 'prepare').mockImplementation(() => {
      throw new Error('forced pos failure');
    });
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);

    posController.getPOSTransactions({ query: {} } as unknown as Request, res);

    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({ error: 'Failed to fetch POS transactions' });
  });
});

describe('settings update', () => {
  const put = (key: string, body: Record<string, unknown>) =>
    request(app).put(`/api/settings/${key}`).set('Cookie', cookie).send(body);

  it('rejects a falsy value', async () => {
    const res = await put('theme', { value: 0 });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Value is required' });
  });

  it('upserts the setting and returns the row', async () => {
    const res = await put('coverage_test_key', { value: 'dark', description: 'theme' });

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ key: 'coverage_test_key', value: 'dark', description: 'theme' });
  });

  it('returns a sanitized 500 when the upsert fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(SettingsModel, 'upsert').mockImplementation(() => {
      throw new Error('forced settings failure');
    });

    const res = await put('theme', { value: 'dark' });
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to update setting' });
  });
});

describe('user delete', () => {
  const del = (id: number | string) =>
    request(app).delete(`/api/users/${id}`).set('Cookie', cookie);

  it('returns 404 for an unknown user', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue(undefined);
    expect((await del(999999)).status).toBe(404);
  });

  it('refuses to delete the caller account', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: adminId,
      username: 'admin',
      role: 'admin',
    } as unknown as ReturnType<typeof UserModel.getPublicById>);

    const res = await del(adminId);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Cannot delete your own account' });
  });

  it('refuses to delete the last active admin', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: 999,
      username: 'other-admin',
      role: 'admin',
    } as unknown as ReturnType<typeof UserModel.getPublicById>);
    jest.spyOn(UserModel, 'getAdminCount').mockReturnValue(1);

    const res = await del(999);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Cannot delete the last active admin user' });
  });

  it('soft-deletes another user', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: 999,
      username: 'clerk',
      role: 'staff',
    } as unknown as ReturnType<typeof UserModel.getPublicById>);
    const softDelete = jest
      .spyOn(UserModel, 'softDelete')
      .mockImplementation(() => {});

    const res = await del(999);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, message: 'User deleted successfully' });
    expect(softDelete).toHaveBeenCalledWith(expect.anything(), 999);
  });

  it('returns a sanitized 500 when the delete fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(UserModel, 'getPublicById').mockImplementation(() => {
      throw new Error('forced user failure');
    });

    const res = await del(999);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to delete user' });
  });
});
