/**
 * TASK 15 — H9: customer store credit must be visible and usable.
 *
 * Lifecycle: sale → return settled as store credit → credit_balance is
 * the authoritative pool → exposed via the customer API → partially and
 * fully consumed by credit_offset on later invoices (pool decrements,
 * AR/ledger/GL stay consistent) → over-application rejected.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice,
  processReturn, customerLedgerNet, glTotalsFor, assertGlBalanced,
} from './helpers/invoiceReturnSpec';

interface CustomerRow {
  current_balance: number;
  credit_balance: number;
}

function customerRow(id: number): CustomerRow {
  return db.prepare(
    'SELECT current_balance, COALESCE(credit_balance, 0) as credit_balance FROM customers WHERE id = ?'
  ).get(id) as CustomerRow;
}

function invoiceRow(id: number) {
  return db.prepare(
    'SELECT status, total_amount, paid_amount, balance_amount, credit_offset FROM invoices WHERE id = ?'
  ).get(id) as {
    status: string; total_amount: number; paid_amount: number;
    balance_amount: number; credit_offset: number;
  };
}

async function invoiceWithOffset(
  authCookie: string, customerId: number, itemId: number,
  qty: number, creditOffset: number,
): Promise<{ status: number; body: { id?: number; error?: string } }> {
  return request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: customerId,
      invoice_date: '2026-09-12',
      due_date: '2026-09-26',
      items: [{
        item_id: itemId,
        description: 'Store Credit Item',
        quantity: qty,
        unit_price: 100,
        tax_rate: 0,
        discount_type: 'none',
        discount_value: 0,
      }],
      total_amount: qty * 100,
      credit_offset: creditOffset,
    }) as unknown as Promise<{ status: number; body: { id?: number; error?: string } }>;
}

describe('H9: store credit lifecycle', () => {
  let authCookie: string;
  let itemId: number;
  let customerId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    warehouseId = wh.id;
    itemId = await createItem('Widget SC (H9)', authCookie);
    await purchaseStock(itemId, warehouseId, 30, 10, authCookie);
    customerId = await createCustomer('Store Credit Customer H9', authCookie);
  });

  it('return settled as credit lands in the pool, not in negative AR', async () => {
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );
    const ret = await processReturn(
      inv.invoiceId,
      {
        invoiceItemIds: inv.invoiceItemIds, quantities: [2], warehouseId,
        settlements: [{ type: 'credit', amount: 200 }],
      },
      authCookie,
    );
    expect(ret.status).toBe(200);

    const row = customerRow(customerId);
    expect(row.credit_balance).toBeCloseTo(200, 2);
    // The pool half is NOT also carried as negative AR — applyCredit's
    // consuming debit row cleared the RETURN credit from the ledger.
    expect(row.current_balance).toBeCloseTo(0, 2);
  });

  it('customer API exposes the credit pool', async () => {
    const byId = await request(app).get(`/api/customers/${customerId}`).set('Cookie', authCookie);
    expect(byId.status).toBe(200);
    expect(Number(byId.body.data.credit_balance)).toBeCloseTo(200, 2);

    const list = await request(app)
      .get('/api/customers?search=Store+Credit+Customer+H9').set('Cookie', authCookie);
    expect(list.status).toBe(200);
    const listed = (list.body.data as Array<{ id: number; credit_balance: number }>)
      .find((c) => c.id === customerId);
    expect(Number(listed?.credit_balance)).toBeCloseTo(200, 2);

    const balance = await request(app).get(`/api/customers/${customerId}/balance`).set('Cookie', authCookie);
    expect(balance.status).toBe(200);
    expect(Number(balance.body.data.creditBalance)).toBeCloseTo(200, 2);
  });

  let inv2Id: number;
  it('applying part of the credit settles partially and drains the pool', async () => {
    const res = await invoiceWithOffset(authCookie, customerId, itemId, 3, 100);
    expect(res.status).toBe(201);
    inv2Id = res.body.id!;

    const inv = invoiceRow(inv2Id);
    expect(inv.status).toBe('Partially Paid');
    expect(inv.credit_offset).toBeCloseTo(100, 2);
    expect(inv.paid_amount).toBeCloseTo(100, 2);
    expect(inv.balance_amount).toBeCloseTo(200, 2);

    const cust = customerRow(customerId);
    expect(cust.credit_balance).toBeCloseTo(100, 2);
    // AR reflects only the unpaid remainder of INV2.
    expect(cust.current_balance).toBeCloseTo(200, 2);

    // GL: balanced Dr 1110 / Cr AR for the offset; ledger net agrees
    // with the stored balance.
    assertGlBalanced('CREDIT_OFFSET', inv2Id);
    expect(glTotalsFor('CREDIT_OFFSET', inv2Id).debit).toBeCloseTo(100, 2);
    expect(customerLedgerNet(customerId)).toBeCloseTo(cust.current_balance, 2);
  });

  it('applying the remaining credit fully settles the invoice', async () => {
    const res = await invoiceWithOffset(authCookie, customerId, itemId, 1, 100);
    expect(res.status).toBe(201);

    const inv = invoiceRow(res.body.id!);
    expect(inv.status).toBe('Paid');
    expect(inv.paid_amount).toBeCloseTo(100, 2);
    expect(inv.balance_amount).toBeCloseTo(0, 2);

    const cust = customerRow(customerId);
    expect(cust.credit_balance).toBeCloseTo(0, 2);
    expect(cust.current_balance).toBeCloseTo(200, 2);
    expect(customerLedgerNet(customerId)).toBeCloseTo(cust.current_balance, 2);
  });

  it('rejects applying credit the customer no longer has', async () => {
    const res = await invoiceWithOffset(authCookie, customerId, itemId, 1, 50);
    expect(res.status).toBe(400);
    expect(String(res.body.error)).toMatch(/credit/i);
    // Nothing was written.
    expect(customerRow(customerId).credit_balance).toBeCloseTo(0, 2);
  });

  it('rejects an offset beyond the invoice entitlement', async () => {
    // Re-seed a small pool (sell 1, pay, return as credit).
    const inv = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );
    const ret = await processReturn(
      inv.invoiceId,
      { invoiceItemIds: inv.invoiceItemIds, quantities: [1], warehouseId, settlements: [{ type: 'credit', amount: 100 }] },
      authCookie,
    );
    expect(ret.status).toBe(200);
    expect(customerRow(customerId).credit_balance).toBeCloseTo(100, 2);

    // Entitlement guard: payment 50 + offset 100 exceeds the 100 total.
    const res = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-12',
        due_date: '2026-09-26',
        items: [{
          item_id: itemId, description: 'Store Credit Item',
          quantity: 1, unit_price: 100, tax_rate: 0,
          discount_type: 'none', discount_value: 0,
        }],
        total_amount: 100,
        record_payment: true,
        payment: { payment_date: '2026-09-12', amount: 50, payment_method: 'Cash' },
        credit_offset: 100,
      });
    expect(res.status).toBe(400);
    expect(String(res.body.error)).toMatch(/exceeds invoice total/i);
    expect(customerRow(customerId).credit_balance).toBeCloseTo(100, 2);
  });
});
