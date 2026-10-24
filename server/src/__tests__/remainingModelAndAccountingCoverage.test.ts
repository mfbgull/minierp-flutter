import { afterAll, beforeEach, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import CustomerModel from '../models/Customer';
import SupplierModel from '../models/Supplier';
import ExpenseModel from '../models/Expense';
import RoleModel from '../models/Role';
import CustomReportModel from '../models/CustomReport';
import SettingsModel from '../models/Settings';
import AccountingService from '../services/accountingService';
import PeriodModel from '../models/Period';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — statement reads (Customer/Supplier), expense
 * category update, role create, custom report update, bulk settings and the
 * accounting balance/period handlers.
 */

const ORIGINAL_DB = db;

beforeEach(() => {
  db.prepare('DELETE FROM customer_ledger').run();
  db.prepare('DELETE FROM supplier_ledger').run();
  db.prepare('DELETE FROM customers').run();
  db.prepare('DELETE FROM suppliers').run();
  db.prepare('DELETE FROM expense_categories').run();
  db.prepare('DELETE FROM custom_reports').run();
});

describe('statement reads', () => {
  function seedCustomerLedger(): number {
    const customer = db
      .prepare(
        `INSERT INTO customers (customer_code, customer_name) VALUES ('ST-CUST', 'Statement Co')`
      )
      .run();
    const insert = db.prepare(
      `INSERT INTO customer_ledger (
         customer_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description, voided
       ) VALUES (?, ?, 'INVOICE', ?, ?, 0, ?, 'row', ?)`
    );
    insert.run(customer.lastInsertRowid, '2026-01-01', 'INV-1', 100, 100, 0);
    insert.run(customer.lastInsertRowid, '2026-02-01', 'INV-2', 50, 150, 0);
    insert.run(customer.lastInsertRowid, '2026-02-15', 'INV-VOID', 10, 160, 1);
    return Number(customer.lastInsertRowid);
  }

  it('returns full customer history from zero', () => {
    const id = seedCustomerLedger();

    const full = CustomerModel.getStatement(id, undefined, undefined, ORIGINAL_DB);

    expect(full.transactions).toHaveLength(2);
    expect(full.openingBalance).toBe(0);
  });

  it('uses the last balance before the range as the customer opening', () => {
    const id = seedCustomerLedger();

    const ranged = CustomerModel.getStatement(id, '2026-02-01', '2026-02-28', ORIGINAL_DB);

    expect(ranged.transactions).toHaveLength(1);
    expect(ranged.transactions[0].reference_no).toBe('INV-2');
    expect(ranged.openingBalance).toBe(100);
    expect(CustomerModel.getStatement(999999, undefined, undefined, ORIGINAL_DB)).toEqual({
      transactions: [],
      openingBalance: 0,
    });
  });

  it('returns supplier history and range opening', () => {
    const supplier = db
      .prepare(
        `INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('ST-SUP', 'Supplier Co')`
      )
      .run();
    const insert = db.prepare(
      `INSERT INTO supplier_ledger (
         supplier_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description, voided
       ) VALUES (?, ?, 'PURCHASE_ORDER', ?, ?, 0, ?, 'row', 0)`
    );
    insert.run(supplier.lastInsertRowid, '2026-01-10', 'PO-1', 200, 200);
    insert.run(supplier.lastInsertRowid, '2026-03-10', 'PO-2', 100, 300);

    const full = SupplierModel.getStatement(
      Number(supplier.lastInsertRowid),
      undefined,
      undefined,
      ORIGINAL_DB
    );
    const ranged = SupplierModel.getStatement(
      Number(supplier.lastInsertRowid),
      '2026-03-01',
      '2026-03-31',
      ORIGINAL_DB
    );

    expect(full.transactions).toHaveLength(2);
    expect(full.openingBalance).toBe(0);
    expect(ranged.transactions.map(t => t.reference_no)).toEqual(['PO-2']);
    expect(ranged.openingBalance).toBe(200);
  });
});

describe('expense category update', () => {
  function seedCategory(name: string): number {
    const created = ExpenseModel.createCategory(ORIGINAL_DB, {
      category_name: name,
      description: 'initial',
    });
    return Number(created);
  }

  it('rejects an unknown category', () => {
    expect(() =>
      ExpenseModel.updateCategory(ORIGINAL_DB, 999999, { category_name: 'X' })
    ).toThrow('Expense category not found');
  });

  it('rejects a duplicate name', () => {
    seedCategory('Rent');
    const other = seedCategory('Utilities');

    expect(() =>
      ExpenseModel.updateCategory(ORIGINAL_DB, other, { category_name: 'Rent' })
    ).toThrow('Expense category name already exists');
  });

  it('updates only the supplied fields', () => {
    const id = seedCategory('Supplies');

    ExpenseModel.updateCategory(ORIGINAL_DB, id, { category_name: 'Supplies', is_active: 0 });

    const row = db
      .prepare('SELECT category_name, description, is_active FROM expense_categories WHERE id = ?')
      .get(id) as { category_name: string; description: string; is_active: number };
    expect(row).toEqual({ category_name: 'Supplies', description: 'initial', is_active: 0 });
  });
});

describe('role create', () => {
  it('creates a role without permissions', () => {
    const role = RoleModel.create(ORIGINAL_DB, { role_name: 'Auditor' } as never, 1);

    expect(role.role_name).toBe('Auditor');
    expect(role.is_system_role).toBe(0);
  });

  it('creates a role with permissions', () => {
    const permission = db
      .prepare(
        `INSERT INTO permissions (permission_name, module, action) VALUES ('x:read', 'x', 'read')`
      )
      .run();
    const role = RoleModel.create(
      ORIGINAL_DB,
      {
        role_name: 'Reader',
        description: 'read-only',
        permissions: [Number(permission.lastInsertRowid)],
      } as never,
      1
    );

    const linked = db
      .prepare('SELECT COUNT(*) AS n FROM role_permissions WHERE role_id = ?')
      .get(role.id) as { n: number };
    expect(linked.n).toBe(1);
  });
});

describe('custom report update', () => {
  function seedReport(): { id: number; userId: number } {
    const userId = (
      db.prepare(`SELECT id FROM users WHERE username = 'admin'`).get() as { id: number }
    ).id;
    const report = CustomReportModel.create({
      user_id: userId,
      name: 'Sales by month',
      config: { entity: 'invoices', columns: [] },
    } as never);
    return { id: report.id, userId };
  }

  it('returns false when no field is supplied', () => {
    const { id, userId } = seedReport();
    expect(CustomReportModel.update(id, userId, {} as never)).toBe(false);
  });

  it('updates name, description and config', () => {
    const { id, userId } = seedReport();

    expect(
      CustomReportModel.update(id, userId, {
        name: 'Renamed',
        description: 'updated',
        config: { entity: 'expenses', columns: [] },
      } as never)
    ).toBe(true);

    const row = db.prepare('SELECT * FROM custom_reports WHERE id = ?').get(id) as {
      name: string;
      description: string;
      config: string;
    };
    expect(row.name).toBe('Renamed');
    expect(row.description).toBe('updated');
    expect(JSON.parse(row.config).entity).toBe('expenses');
  });

  it('returns false for another user', () => {
    const { id } = seedReport();
    expect(CustomReportModel.update(id, 999999, { name: 'Nope' } as never)).toBe(false);
  });
});

describe('bulk settings transaction', () => {
  it('upserts every entry and keeps an omitted description', () => {
    db.prepare(`INSERT INTO settings (key, value, description) VALUES ('bulk_keep', 'old', 'kept')`).run();

    SettingsModel.updateBulk(ORIGINAL_DB, {
      bulk_keep: { value: 'new' },
      bulk_new: { value: 'fresh', description: 'created' },
    } as never);

    const rows = db
      .prepare(`SELECT key, value, description FROM settings WHERE key LIKE 'bulk_%' ORDER BY key`)
      .all() as Array<{ key: string; value: string; description: string | null }>;
    expect(rows).toEqual([
      { key: 'bulk_keep', value: 'new', description: 'kept' },
      { key: 'bulk_new', value: 'fresh', description: 'created' },
    ]);
  });
});

describe('accounting balance and period handlers', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterAll(() => {
    jest.restoreAllMocks();
  });

  it('returns 404 for an unknown account', async () => {
    jest.spyOn(AccountingService, 'getAccountByCode').mockReturnValue(undefined);

    const res = await request(app)
      .get('/api/accounting/accounts/NOPE/balance')
      .set('Cookie', cookie);

    expect(res.status).toBe(404);
  });

  it('returns 400 for an invalid asOfDate', async () => {
    jest
      .spyOn(AccountingService, 'getAccountByCode')
      .mockReturnValue({ id: 1, code: '1200' } as unknown as ReturnType<
        typeof AccountingService.getAccountByCode
      >);

    const res = await request(app)
      .get('/api/accounting/accounts/1200/balance')
      .set('Cookie', cookie)
      .query({ asOfDate: 'not-a-date' });

    expect(res.status).toBe(400);
  });

  it('returns the account balance', async () => {
    jest
      .spyOn(AccountingService, 'getAccountByCode')
      .mockReturnValue({ id: 1, code: '1200' } as unknown as ReturnType<
        typeof AccountingService.getAccountByCode
      >);
    const spy = jest
      .spyOn(AccountingService, 'getAccountBalance')
      .mockReturnValue({ debit: 10, credit: 4, balance: 6 } as unknown as ReturnType<
        typeof AccountingService.getAccountBalance
      >);

    const res = await request(app)
      .get('/api/accounting/accounts/1200/balance')
      .set('Cookie', cookie)
      .query({ asOfDate: '2026-01-31' });

    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(expect.anything(), 1, '2026-01-31');
  });

  it('returns a sanitized 500 when the balance read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(AccountingService, 'getAccountByCode').mockImplementation(() => {
      throw new Error('forced balance failure');
    });

    const res = await request(app)
      .get('/api/accounting/accounts/1200/balance')
      .set('Cookie', cookie);
    expect(res.status).toBe(500);
  });

  it('validates the period id and maps lookups', async () => {
    expect(
      (await request(app).get('/api/accounting/periods/abc').set('Cookie', cookie)).status
    ).toBe(400);

    jest.spyOn(PeriodModel, 'getById').mockReturnValue(undefined);
    expect(
      (await request(app).get('/api/accounting/periods/999999').set('Cookie', cookie)).status
    ).toBe(404);

    jest
      .spyOn(PeriodModel, 'getById')
      .mockReturnValue({ id: 3, period_name: '2026-01' } as unknown as ReturnType<
        typeof PeriodModel.getById
      >);
    expect((await request(app).get('/api/accounting/periods/3').set('Cookie', cookie)).status).toBe(
      200
    );
  });

  it('returns a sanitized 500 when the period read fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(PeriodModel, 'getById').mockImplementation(() => {
      throw new Error('forced period failure');
    });

    const res = await request(app).get('/api/accounting/periods/3').set('Cookie', cookie);
    expect(res.status).toBe(500);
  });
});
