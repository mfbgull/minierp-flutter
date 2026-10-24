import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import RoleModel from '../models/Role';
import SupplierModel from '../models/Supplier';
import UserModel from '../models/User';
import accountingController from '../controllers/accountingController';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — role update, supplier ledger helpers,
 * toggle-user-status, accounting period open/close and supplier
 * bill/advance list handlers.
 */

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

function fakeRes(): { res: Response; status: jest.Mock; json: jest.Mock } {
  const status = jest.fn();
  const json = jest.fn();
  const res = { status, json } as unknown as Response;
  status.mockReturnValue(res);
  return { res, status, json };
}

describe('Role.update', () => {
  function seedRole(name: string, system = false): number {
    return Number(
      db
        .prepare(
          `INSERT INTO roles (role_name, description, is_system_role, is_active)
           VALUES (?, 'seed', ?, 1)`
        )
        .run(name, system ? 1 : 0).lastInsertRowid
    );
  }

  it('rejects unknown and system roles', () => {
    expect(() => RoleModel.update(db, 999999, { role_name: 'X' } as never)).toThrow('Role not found');
    const systemId = seedRole('System Admin', true);
    expect(() => RoleModel.update(db, systemId, { role_name: 'X' } as never)).toThrow(
      'Cannot modify system roles'
    );
  });

  it('rejects duplicate names and empty updates', () => {
    seedRole('Bookkeeper');
    const other = seedRole('Clerk');

    expect(() => RoleModel.update(db, other, { role_name: 'Bookkeeper' } as never)).toThrow(
      'Role name already exists'
    );
    expect(() => RoleModel.update(db, other, {} as never)).toThrow('No fields to update');
  });

  it('updates name, description and active flag', () => {
    const id = seedRole('Temp Role');

    const updatedRole = RoleModel.update(db, id, {
      role_name: 'Senior Clerk',
      description: 'promoted',
      is_active: 0,
    } as never);
    expect(updatedRole.role_name).toBe('Senior Clerk');

    const row = db
      .prepare('SELECT role_name, description, is_active FROM roles WHERE id = ?')
      .get(id);
    expect(row).toEqual({ role_name: 'Senior Clerk', description: 'promoted', is_active: 0 });
  });
});

describe('Supplier ledger', () => {
  it('sorts safely and applies date bounds and paging', () => {
    const supplier = db
      .prepare(`INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('LED-S', 'Ledger S')`)
      .run();
    const insert = db.prepare(
      `INSERT INTO supplier_ledger (
         supplier_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description, voided
       ) VALUES (?, ?, 'PURCHASE_ORDER', ?, ?, 0, ?, 'row', 0)`
    );
    insert.run(supplier.lastInsertRowid, '2026-01-05', 'PO-A', 100, 100);
    insert.run(supplier.lastInsertRowid, '2026-02-05', 'PO-B', 50, 150);

    const ranged = SupplierModel.getLedger(
      Number(supplier.lastInsertRowid),
      'transaction_date',
      'DESC',
      db,
      1,
      1,
      '2026-01-01',
      '2026-12-31'
    );
    expect(ranged.total).toBe(2);
    expect(ranged.rows).toHaveLength(1);
    expect(ranged.rows[0].reference_no).toBe('PO-B');

    const unsorted = SupplierModel.getLedger(
      Number(supplier.lastInsertRowid),
      'DROP TABLE suppliers',
      'SIDEWAYS',
      db
    );
    expect(unsorted.total).toBe(2);
    expect(unsorted.rows).toHaveLength(2);
  });
});

describe('toggle user status', () => {
  const toggle = (id: number | string, body: Record<string, unknown>) =>
    request(app).put(`/api/users/${id}/toggle-status`).set('Cookie', cookie).send(body);

  it('requires a boolean flag', async () => {
    const res = await toggle(5, { is_active: 'yes' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'is_active must be a boolean' });
  });

  it('returns 404 for an unknown user', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue(undefined);
    expect((await toggle(999999, { is_active: true })).status).toBe(404);
  });

  it('refuses to deactivate the caller', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: adminId,
      username: 'admin',
      role: 'admin',
      is_active: 1,
    } as unknown as ReturnType<typeof UserModel.getPublicById>);

    const res = await toggle(adminId, { is_active: false });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Cannot deactivate your own account' });
  });

  it('refuses to deactivate the last admin', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: 999,
      username: 'other-admin',
      role: 'admin',
      is_active: 1,
    } as unknown as ReturnType<typeof UserModel.getPublicById>);
    jest.spyOn(UserModel, 'getAdminCount').mockReturnValue(1);

    const res = await toggle(999, { is_active: false });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Cannot deactivate the last active admin user' });
  });

  it('updates a regular user', async () => {
    jest.spyOn(UserModel, 'getPublicById').mockReturnValue({
      id: 999,
      username: 'clerk',
      role: 'staff',
      is_active: 1,
    } as unknown as ReturnType<typeof UserModel.getPublicById>);
    const update = jest.spyOn(UserModel, 'update').mockImplementation(() => {});

    const res = await toggle(999, { is_active: false });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, message: 'User deactivated successfully' });
    expect(update).toHaveBeenCalledWith(expect.anything(), 999, { is_active: false });
  });

  it('returns a sanitized 500 when the toggle fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(UserModel, 'getPublicById').mockImplementation(() => {
      throw new Error('forced toggle failure');
    });

    const res = await toggle(999, { is_active: true });
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to update user status' });
  });
});

describe('accounting periods', () => {
  const open = (body: Record<string, unknown>) =>
    request(app).post('/api/accounting/periods').set('Cookie', cookie).send(body);

  it('opens a period and rejects overlaps and duplicate names', async () => {
    const created = await open({
      period_name: 'COV-2026-01',
      start_date: '2026-01-01',
      end_date: '2026-01-31',
    });
    expect(created.status).toBe(201);

    const overlap = await open({
      period_name: 'COV-2026-01B',
      start_date: '2026-01-15',
      end_date: '2026-02-15',
    });
    expect(overlap.status).toBe(409);

    const duplicate = await open({
      period_name: 'COV-2026-01',
      start_date: '2027-01-01',
      end_date: '2027-01-31',
    });
    expect(duplicate.status).toBe(409);
  });

  it('validates the open-period payload when called directly', async () => {
    const nonAdmin = fakeRes();
    accountingController.openPeriod(
      { user: { role: 'staff' }, body: {} } as unknown as Request,
      nonAdmin.res
    );
    expect(nonAdmin.status).toHaveBeenCalledWith(403);

    const cases: Array<[Record<string, unknown>, string]> = [
      [{ period_name: '  ' }, 'period_name is required'],
      [
        { period_name: 'P', start_date: 'nope', end_date: '2026-01-31' },
        'start_date must be a valid YYYY-MM-DD date',
      ],
      [
        { period_name: 'P', start_date: '2026-01-01', end_date: 'nope' },
        'end_date must be a valid YYYY-MM-DD date',
      ],
      [
        { period_name: 'P', start_date: '2026-02-01', end_date: '2026-01-31' },
        'start_date must be on or before end_date',
      ],
    ];
    for (const [body, message] of cases) {
      const { res, status, json } = fakeRes();
      accountingController.openPeriod({ user: { role: 'admin' }, body } as unknown as Request, res);
      expect(status).toHaveBeenCalledWith(400);
      const errorBody = (json.mock.calls[0] as unknown[])[0] as { error: { message: string } };
      expect(errorBody.error.message).toBe(message);
    }
  });

  it('returns a sanitized 500 when the open throws unexpectedly', () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(db, 'prepare').mockImplementation(() => {
      throw new Error('forced open failure');
    });
    const { res, status } = fakeRes();

    accountingController.openPeriod(
      {
        user: { role: 'admin' },
        body: { period_name: 'X', start_date: '2026-05-01', end_date: '2026-05-31' },
      } as unknown as Request,
      res
    );
    expect(status).toHaveBeenCalledWith(500);
  });

  it('closes a period idempotently and validates the id', async () => {
    const created = await open({
      period_name: 'COV-2026-03',
      start_date: '2026-03-01',
      end_date: '2026-03-31',
    });
    const id = created.body.data.id;

    const invalid = await request(app)
      .post('/api/accounting/periods/abc/close')
      .set('Cookie', cookie);
    expect(invalid.status).toBe(400);

    expect(
      (await request(app).post('/api/accounting/periods/999999/close').set('Cookie', cookie))
        .status
    ).toBe(404);

    const closed = await request(app)
      .post(`/api/accounting/periods/${id}/close`)
      .set('Cookie', cookie);
    expect(closed.status).toBe(200);

    const again = await request(app)
      .post(`/api/accounting/periods/${id}/close`)
      .set('Cookie', cookie);
    expect(again.status).toBe(200);
    expect(again.body.data.alreadyClosed).toBe(true);
  });

  it('forbids non-admins from closing and maps failures', () => {
    const forbidden = fakeRes();
    accountingController.closePeriod(
      { user: { role: 'staff' }, params: { id: '1' } } as unknown as Request,
      forbidden.res
    );
    expect(forbidden.status).toHaveBeenCalledWith(403);

    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(db, 'prepare').mockImplementation(() => {
      throw new Error('forced close failure');
    });
    const failing = fakeRes();
    accountingController.closePeriod({ user: { role: 'admin' }, params: { id: '1' } } as unknown as Request, failing.res);
    expect(failing.status).toHaveBeenCalledWith(500);
  });
});

describe('supplier document lists', () => {
  it('validates and pages supplier bills', async () => {
    const missing = await request(app).get('/api/supplier-bills').set('Cookie', cookie);
    expect(missing.status).toBe(400);

    const badPage = await request(app)
      .get('/api/supplier-bills')
      .set('Cookie', cookie)
      .query({ supplier_id: '1', limit: '500' });
    expect(badPage.status).toBe(400);

    const ok = await request(app)
      .get('/api/supplier-bills')
      .set('Cookie', cookie)
      .query({ supplier_id: '1', page: '2', limit: '10' });
    expect(ok.status).toBe(200);
    expect(ok.body).toEqual({
      success: true,
      data: [],
      pagination: {
        currentPage: 2,
        totalPages: 1,
        totalItems: 0,
        hasNext: false,
        hasPrev: true,
      },
    });
  });

  it('validates and pages supplier advances', async () => {
    expect(
      (await request(app).get('/api/supplier-prepayments').set('Cookie', cookie)).status
    ).toBe(400);

    const ok = await request(app)
      .get('/api/supplier-prepayments')
      .set('Cookie', cookie)
      .query({ supplier_id: '1' });
    expect(ok.status).toBe(200);
    expect(ok.body.data).toEqual([]);
    expect(ok.body.pagination.currentPage).toBe(1);
    expect(ok.body.pagination.hasPrev).toBe(false);
  });
});
