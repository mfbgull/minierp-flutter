import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import InvoiceModel from '../models/Invoice';
import AccountingService from '../services/accountingService';
import ledgerUtils from '../utils/ledgerUtils';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `invoiceController.deleteInvoice` transaction
 * (CRAP 156). Stock/GL/ledger collaborators are mocked; the invoice row and
 * the soft-delete UPDATE are real.
 */

type InvoiceRecord = NonNullable<ReturnType<typeof InvoiceModel.getById>>;

let cookie = '';
let customerId = 0;
let seq = 0;

function insertInvoice(opts: { status?: string; total?: number; paid?: number } = {}): number {
  seq += 1;
  return Number(
    db
      .prepare(
        `INSERT INTO invoices (
           invoice_no, customer_id, invoice_date, status, total_amount, paid_amount
         ) VALUES (?, ?, '2026-01-01', ?, ?, ?)`
      )
      .run(
        `DEL-INV-${seq}`,
        customerId,
        opts.status ?? 'Draft',
        opts.total ?? 50,
        opts.paid ?? 0
      ).lastInsertRowid
  );
}

function invoiceRecord(id: number, opts: { total?: number; paid?: number; status?: string } = {}): InvoiceRecord {
  return {
    id,
    invoice_no: `DEL-INV-${seq}`,
    customer_id: customerId,
    invoice_date: '2026-01-01',
    status: opts.status ?? 'Draft',
    payment_status: 'Unpaid',
    return_status: 'None',
    total_amount: opts.total ?? 50,
    paid_amount: opts.paid ?? 0,
    returned_amount: 0,
  } as unknown as InvoiceRecord;
}

describe('invoice delete transaction', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = Number(
      db
        .prepare(
          `INSERT INTO customers (customer_code, customer_name) VALUES ('DEL-CUST', 'Delete Co')`
        )
        .run().lastInsertRowid
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const del = (id: number) => request(app).delete(`/api/invoices/${id}`).set('Cookie', cookie);

  function mockDeletePath(opts: { voided?: number; returnVoided?: number } = {}): void {
    const record = invoiceRecord(0);
    jest.spyOn(InvoiceModel, 'getById').mockReturnValue(record);
    jest.spyOn(InvoiceModel, 'getItemsForStockReverse').mockReturnValue([]);
    jest.spyOn(InvoiceModel, 'reverseStockForItems').mockReturnValue([]);
    jest.spyOn(InvoiceModel, 'voidOwnReturnJournalLines').mockReturnValue(opts.returnVoided ?? 0);
    jest.spyOn(InvoiceModel, 'deleteLedgerEntryByReference').mockImplementation(() => {});
    jest
      .spyOn(AccountingService, 'voidJournalLinesByReference')
      .mockReturnValue(opts.voided ?? 1);
    jest.spyOn(AccountingService, 'assertPeriodNotClosed').mockImplementation(() => {});
    jest.spyOn(ledgerUtils, 'rebuildLedgerBalances').mockImplementation(() => {});
    jest.spyOn(ledgerUtils, 'recalcCustomerBalanceFromLedger').mockReturnValue(0);
  }

  it('returns 404 for an unknown invoice', async () => {
    jest.spyOn(InvoiceModel, 'getById').mockReturnValue(undefined);
    expect((await del(999999)).status).toBe(404);
  });

  it('refuses to delete a paid or returned invoice', async () => {
    const id = insertInvoice({ status: 'Paid', total: 50, paid: 50 });
    jest.spyOn(InvoiceModel, 'getById').mockReturnValue(invoiceRecord(id, { status: 'Paid', paid: 50 }));

    const res = await del(id);
    expect(res.status).toBe(400);
    expect(res.body.error).toContain('Cannot delete this invoice');
  });

  it('soft-deletes a draft invoice and preserves the pre-delete status', async () => {
    const id = insertInvoice({ status: 'Draft', total: 50 });
    mockDeletePath();

    const res = await del(id);

    expect(res.status).toBe(200);
    const row = db
      .prepare(
        `SELECT status, deleted_at, deleted_from_status FROM invoices WHERE id = ?`
      )
      .get(id) as { status: string; deleted_at: string | null; deleted_from_status: string | null };
    expect(row.status).toBe('Deleted');
    expect(row.deleted_at).toBeTruthy();
    expect(row.deleted_from_status).toBe('Draft');
  });

  it('refuses to delete when no journal lines were voided', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    const id = insertInvoice({ status: 'Unpaid', total: 80 });
    mockDeletePath({ voided: 0, returnVoided: 0 });

    const res = await del(id);

    expect(res.status).toBe(500);
    expect(res.body.error).toBe('Failed to delete invoice');
    const row = db
      .prepare('SELECT deleted_at FROM invoices WHERE id = ?')
      .get(id) as { deleted_at: string | null };
    expect(row.deleted_at).toBeNull();
  });
});
