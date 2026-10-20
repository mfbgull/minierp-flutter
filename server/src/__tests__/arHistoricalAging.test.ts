import { afterEach, beforeAll, beforeEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import Reports from '../models/Reports';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

let cookie: string;
let customerId: number;
let sequence = 0;
beforeAll(async () => { cookie = await getAuthCookie(); });
beforeEach(() => {
  db.exec('SAVEPOINT historical_ar_case');
  customerId = Number(db.prepare(`INSERT INTO customers (customer_code, customer_name)
    VALUES ('HIST-AR', 'Historical AR')`).run().lastInsertRowid);
});
afterEach(() => { db.exec('ROLLBACK TO historical_ar_case; RELEASE historical_ar_case'); });

function invoice(date = '2026-09-01', total = 1000): number {
  return Number(db.prepare(`INSERT INTO invoices
    (invoice_no, customer_id, invoice_date, due_date, status, total_amount, balance_amount, created_by)
    VALUES (?, ?, ?, '2026-09-01', 'Unpaid', ?, ?, 1)`)
    .run(`HIST-${++sequence}`, customerId, date, total, total).lastInsertRowid);
}

function receipt(invoiceId: number, date: string, amount: number): void {
  const payment = db.prepare(`INSERT INTO payments
    (payment_no, customer_id, payment_date, amount, payment_method)
    VALUES (?, ?, ?, ?, 'Cash')`).run(`HIST-PAY-${++sequence}`, customerId, date, amount);
  db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)')
    .run(payment.lastInsertRowid, invoiceId, amount);
  db.prepare(`UPDATE invoices SET paid_amount = paid_amount + ?, balance_amount = balance_amount - ?,
    status = CASE WHEN balance_amount - ? = 0 THEN 'Paid' ELSE 'Partially Paid' END WHERE id = ?`)
    .run(amount, amount, amount, invoiceId);
}

function total(asOf: string): number {
  const result = Reports.getARAgingReport(asOf, db);
  const summary: unknown = result.summary;
  if (!summary || typeof summary !== 'object' || !('totalReceivables' in summary)) {
    throw new Error('Missing aging summary');
  }
  return Number(summary.totalReceivables ?? 0);
}

describe('ACCT-010: AR aging reconstructs the selected date', () => {
  it('excludes invoices dated after the report date through the mounted route', async () => {
    invoice('2026-09-20', 1000);

    const response = await request(app).get('/api/reports/ar-aging?asOfDate=2026-09-10').set('Cookie', cookie);

    expect(response.status).toBe(200);
    expect(Number(response.body.data.summary.totalReceivables ?? 0)).toBe(0);
    expect(response.body.data.agingBuckets).toEqual([]);
  });

  it('shows debt that was fully paid only after the report date', () => {
    const id = invoice();
    receipt(id, '2026-09-25', 1000);

    expect(total('2026-09-10')).toBe(1000);
    expect(total('2026-09-25')).toBe(0);
  });

  it('counts receipts on or before the selected date and excludes later receipts', () => {
    const id = invoice();
    receipt(id, '2026-09-05', 100);
    receipt(id, '2026-09-25', 200);

    expect(total('2026-09-05')).toBe(900);
    expect(total('2026-09-25')).toBe(700);
  });

  it('counts a return and its fee only from its return date', () => {
    const id = invoice();
    db.prepare(`INSERT INTO invoice_returns
      (return_no, invoice_id, customer_id, return_date, returned_amount, net_amount, fee_amount, created_by)
      VALUES ('HIST-RET', ?, ?, '2026-09-20', 200, 190, 10, 1)`).run(id, customerId);
    db.prepare(`UPDATE invoices SET returned_amount = 200, return_fee = 10,
      balance_amount = 810, status = 'Partially Returned' WHERE id = ?`).run(id);

    expect(total('2026-09-10')).toBe(1000);
    expect(total('2026-09-20')).toBe(810);
  });

  it('keeps undated maturities in the current bucket and totals equal to their buckets', () => {
    const id = invoice();
    db.prepare('UPDATE invoices SET due_date = NULL WHERE id = ?').run(id);
    receipt(id, '2026-09-25', 250);

    const result = Reports.getARAgingReport('2026-09-10', db);
    expect(result.agingBuckets).toEqual([expect.objectContaining({
      total_outstanding: 1000, current_amount: 1000,
      days_1_30: 0, days_31_60: 0, days_61_90: 0, days_over_90: 0,
    })]);
  });
});
