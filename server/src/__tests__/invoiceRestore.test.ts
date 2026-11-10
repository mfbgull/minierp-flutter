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
 * Fallow health remediation — `invoiceController.restoreInvoice` (CRAP 42).
 * The stock/GL/ledger collaborators are mocked so every restore branch is
 * exercised deterministically; the invoice + customer rows are real.
 */

type ReversedItem = { item_id: number; quantity: number };

let cookie = '';
let customerId = 0;
let invoiceSeq = 0;

function insertInvoice(opts: {
  deleted: boolean;
  total?: number;
  deletedFrom?: {
    status: string | null;
    paymentStatus: string | null;
    returnStatus: string | null;
  };
}): { id: number; invoice_no: string } {
  invoiceSeq += 1;
  const invoiceNo = `INV-RESTORE-${invoiceSeq}`;
  const deleted = opts.deleted ? '2026-01-02T00:00:00.000Z' : null;
  const info = db
    .prepare(
      `INSERT INTO invoices (
         invoice_no, customer_id, invoice_date, status, total_amount,
         deleted_at, deleted_by, deleted_from_status,
         deleted_from_payment_status, deleted_from_return_status
       ) VALUES (?, ?, '2026-01-01', ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      invoiceNo,
      customerId,
      opts.deleted ? 'Deleted' : 'Unpaid',
      opts.total ?? 50,
      deleted,
      opts.deleted ? 1 : null,
      opts.deletedFrom?.status ?? null,
      opts.deletedFrom?.paymentStatus ?? null,
      opts.deletedFrom?.returnStatus ?? null
    );
  return { id: Number(info.lastInsertRowid), invoice_no: invoiceNo };
}

function mockRestoreCollaborators(opts: {
  items?: ReversedItem[];
  restored?: Record<string, unknown> | undefined;
} = {}): {
  reconsume: jest.SpiedFunction<typeof InvoiceModel.reconsumeRestoredInvoiceItems>;
} {
  jest
    .spyOn(InvoiceModel, 'getItemsForStockReverse')
    .mockReturnValue((opts.items ?? [{ item_id: 1, quantity: 3 }]) as ReturnType<
      typeof InvoiceModel.getItemsForStockReverse
    >);
  // BUG-010: restore is now batch-faithful — the controller delegates the
  // whole stock re-consume to InvoiceModel.reconsumeRestoredInvoiceItems
  // (the model test covers its real behaviour).
  const reconsume = jest
    .spyOn(InvoiceModel, 'reconsumeRestoredInvoiceItems')
    .mockImplementation(() => {});
  jest.spyOn(AccountingService, 'restoreJournalLinesByReference').mockReturnValue(0);
  jest.spyOn(ledgerUtils, 'rebuildLedgerBalances').mockImplementation(() => {});
  jest.spyOn(ledgerUtils, 'recalcCustomerBalanceFromLedger').mockReturnValue(0);
  if ('restored' in opts) {
    jest
      .spyOn(InvoiceModel, 'getById')
      .mockReturnValue(opts.restored as ReturnType<typeof InvoiceModel.getById>);
  }
  return { reconsume };
}

describe('invoice restore controller', () => {
  beforeAll(async () => {
    cookie = await getAuthCookie();
    customerId = Number(
      db
        .prepare(
          `INSERT INTO customers (customer_code, customer_name)
           VALUES ('CUST-RESTORE', 'Restore Customer')`
        )
        .run().lastInsertRowid
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const restore = (id: number | string) =>
    request(app).post(`/api/invoices/${id}/restore`).set('Cookie', cookie);

  it('returns 404 for an unknown invoice', async () => {
    expect((await restore(999999)).status).toBe(404);
  });

  it('returns 400 when the invoice is not deleted', async () => {
    const { id } = insertInvoice({ deleted: false });
    const res = await restore(id);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Invoice is not deleted' });
  });

  it('re-consumes stock and restores the stored statuses', async () => {
    const warehouse = db
      .prepare(
        `INSERT INTO warehouses (warehouse_code, warehouse_name)
         VALUES ('WH-RESTORE', 'Restore WH')`
      )
      .run();
    const item = db
      .prepare(`INSERT INTO items (item_code, item_name) VALUES ('IT-RESTORE', 'Item')`)
      .run();
    const invoice = insertInvoice({
      deleted: true,
      deletedFrom: { status: 'Paid', paymentStatus: 'Paid', returnStatus: 'None' },
    });
    db.prepare(
      `INSERT INTO stock_movements (
         movement_no, item_id, warehouse_id, movement_type, quantity,
         reference_doctype, reference_docno, movement_date
       ) VALUES ('MV-RESTORE-1', ?, ?, 'SALE', -1, 'INVOICE', ?, '2026-01-01')`
    ).run(item.lastInsertRowid, warehouse.lastInsertRowid, invoice.invoice_no);
    const reversal = db
      .prepare(
        `INSERT INTO customer_ledger (
           customer_id, transaction_date, transaction_type, reference_no,
           debit, credit, balance, description, voided
         ) VALUES (?, '2026-01-01', 'REVERSAL:INVOICE', ?, 0, 50, 0, 'delete reversal', 0)`
      )
      .run(customerId, invoice.invoice_no);
    db.prepare(
      `INSERT INTO customer_ledger (
         customer_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description, voided
       ) VALUES (?, '2026-01-01', 'INVOICE', ?, 50, 0, 50, 'invoice', 1)`
    ).run(customerId, invoice.invoice_no);

    const { reconsume } = mockRestoreCollaborators({
      restored: { ...invoice, deleted_at: null },
    });

    const res = await restore(invoice.id);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(reconsume).toHaveBeenCalledWith(
      db,
      invoice.id,
      invoice.invoice_no,
      '2026-01-01',
      1
    );

    const row = db
      .prepare(
        `SELECT status, payment_status, return_status, deleted_at
         FROM invoices WHERE id = ?`
      )
      .get(invoice.id) as {
      status: string;
      payment_status: string;
      return_status: string;
      deleted_at: string | null;
    };
    expect(row).toEqual({
      status: 'Paid',
      payment_status: 'Paid',
      return_status: 'None',
      deleted_at: null,
    });

    expect(
      db.prepare('SELECT 1 FROM customer_ledger WHERE id = ?').get(reversal.lastInsertRowid)
    ).toBeUndefined();
    const original = db
      .prepare(
        `SELECT voided FROM customer_ledger
         WHERE customer_id = ? AND reference_no = ? AND transaction_type = 'INVOICE'`
      )
      .get(customerId, invoice.invoice_no) as { voided: number };
    expect(original.voided).toBe(0);
  });

  it('derives Unpaid when deleted_from_status is absent and returns the raw invoice if the read-back misses', async () => {
    const invoice = insertInvoice({ deleted: true, total: 50 });
    mockRestoreCollaborators({
      items: [{ item_id: 9, quantity: 2 }],
      restored: undefined,
    });

    const res = await restore(invoice.id);

    expect(res.status).toBe(200);
    expect(res.body.data.invoice_no).toBe(invoice.invoice_no);
    const row = db
      .prepare('SELECT status, payment_status, return_status FROM invoices WHERE id = ?')
      .get(invoice.id) as { status: string; payment_status: string; return_status: string };
    expect(row).toEqual({
      status: 'Unpaid',
      payment_status: 'Unpaid',
      return_status: 'None',
    });
  });

  it('derives Draft for a zero-value invoice with no stored status', async () => {
    const invoice = insertInvoice({ deleted: true, total: 0 });
    mockRestoreCollaborators({ items: [], restored: undefined });

    expect((await restore(invoice.id)).status).toBe(200);

    const row = db
      .prepare('SELECT status FROM invoices WHERE id = ?')
      .get(invoice.id) as { status: string };
    expect(row.status).toBe('Draft');
  });

  it('returns a sanitized 500 when the restore transaction fails', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    const invoice = insertInvoice({ deleted: true });
    mockRestoreCollaborators();
    jest.spyOn(InvoiceModel, 'reconsumeRestoredInvoiceItems').mockImplementation(() => {
      throw new Error('forced consume failure');
    });

    const res = await restore(invoice.id);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to restore invoice' });
  });
});
