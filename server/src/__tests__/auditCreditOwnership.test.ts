import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createInvoice, createItem, getAuthCookie, processReturn, purchaseStock } from './helpers/invoiceReturnSpec';

describe('F-002 source credit cannot be regenerated after consumption', () => {
  let cookie: string;
  let item: number;
  let warehouse: number;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    warehouse = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    item = await createItem('Credit ownership', cookie);
    await purchaseStock(item, warehouse, 100, 10, cookie);
  });

  async function grant(customer: number) {
    const invoice = await createInvoice({ customerId: customer, itemId: item, lines: [{ quantity: 4, unitPrice: 15 }], payment: 'full' }, cookie);
    const ret = await processReturn(invoice.invoiceId, { invoiceItemIds: invoice.invoiceItemIds, quantities: [4], warehouseId: warehouse, settlements: [{ type: 'credit', amount: 60 }] }, cookie);
    expect(ret.status).toBe(200);
    const row = db.prepare('SELECT id FROM return_settlements WHERE return_id = ?').get(ret.returnId) as { id: number };
    return { returnId: ret.returnId!, settlementId: row.id };
  }

  function financialState() {
    return ['customers', 'invoices', 'invoice_returns', 'return_settlements', 'customer_ledger', 'journal_lines', 'stock_batches', 'stock_movements']
      .map(table => db.prepare(`SELECT * FROM ${table} ORDER BY id`).all());
  }

  it.each([
    { consumed: 30, draws: [{ quantity: 5, amount: 30 }] },
    { consumed: 60, draws: [{ quantity: 5, amount: 60 }] },
    { consumed: 60, draws: [{ quantity: 2, amount: 30 }, { quantity: 3, amount: 30 }] },
  ])('blocks consumed $consumed credit with $draws after replenishment', async ({ consumed, draws }) => {
    const customer = await createCustomer(`Ownership ${consumed}-${draws.length}`, cookie);
    const source = await grant(customer);
    for (const draw of draws) {
    const offset = await request(app).post('/api/invoices').set('Cookie', cookie).send({
      customer_id: customer, invoice_date: '2026-09-16',
      items: [{ item_id: item, quantity: draw.quantity, unit_price: 15 }], credit_offset: draw.amount,
    });
    expect(offset.status).toBe(201);
    }
    // Another source restores aggregate pool capacity, but cannot undo ownership.
    const unused = await grant(customer);
    const before = financialState();
    for (const url of [`/api/return-settlements/${source.settlementId}/void`, `/api/invoice-returns/${source.returnId}/void`]) {
      for (let retry = 0; retry < 2; retry++) {
        const res = await request(app).post(url).set('Cookie', cookie).send({ reason: 'Attempt reuse' });
        expect(res.status).toBe(409);
        expect(res.body.error).toMatch(/consum/i);
        expect(financialState()).toEqual(before);
      }
    }
    // Unconsumed source remains reversible; no blanket customer-wide lock.
    const reversed = await request(app).post(`/api/return-settlements/${unused.settlementId}/void`).set('Cookie', cookie);
    expect(reversed.status).toBe(200);
    const row = db.prepare('SELECT current_balance, credit_balance FROM customers WHERE id=?').get(customer) as { current_balance: number; credit_balance: number };
    // Net retained goods 75, collected cash 120: signed exposure -45.
    expect(Math.round((row.current_balance - row.credit_balance) * 100)).toBe(-4500);
    const gl = db.prepare(`SELECT SUM(j.debit-j.credit) AS net FROM journal_lines j JOIN chart_of_accounts a ON a.id=j.account_id
      WHERE a.code IN ('1100','1110') AND j.voided=0`).get() as { net: number };
    const sub = db.prepare('SELECT SUM(current_balance-credit_balance) AS net FROM customers').get() as { net: number };
    expect(Math.round(gl.net * 100)).toBe(Math.round(sub.net * 100));
    expect(db.prepare(`SELECT journal_entry_id FROM journal_lines WHERE voided=0 GROUP BY journal_entry_id
      HAVING ABS(SUM(debit-credit)) > 0.005`).all()).toEqual([]);
  });

  it('cannot settle or void an unsettled return after its ledger credit funded another invoice', async () => {
    const customer = await createCustomer('Legacy return ownership', cookie);
    const invoice = await createInvoice({ customerId: customer, itemId: item, lines: [{ quantity: 4, unitPrice: 15 }], payment: 'full' }, cookie);
    const ret = await processReturn(invoice.invoiceId, { invoiceItemIds: invoice.invoiceItemIds, quantities: [4], warehouseId: warehouse, returnDate: '2026-09-15' }, cookie);
    expect(ret.status).toBe(200);
    const applied = await request(app).post('/api/invoices').set('Cookie', cookie).send({
      customer_id: customer, invoice_date: '2026-09-16', items: [{ item_id: item, quantity: 5, unit_price: 15 }], credit_offset: 60,
    });
    expect(applied.status).toBe(201);
    const before = financialState();
    const settle = await request(app).post(`/api/invoice-returns/${ret.returnId}/settle`).set('Cookie', cookie)
      .send({ allocations: [{ type: 'credit', amount: 60 }] });
    expect(settle.status).toBe(400);
    expect((await request(app).post(`/api/invoice-returns/${ret.returnId}/void`).set('Cookie', cookie)).status).toBe(409);
    expect(financialState()).toEqual(before);
    expect(db.prepare('SELECT current_balance,credit_balance FROM customers WHERE id=?').get(customer)).toEqual({ current_balance: 15, credit_balance: 0 });
    expect(db.prepare('SELECT paid_amount,balance_amount FROM invoices WHERE id=?').get(applied.body.id)).toEqual({ paid_amount: 60, balance_amount: 15 });
    // Ledger credit was already present: recording ownership must add no second credit or cash.
    expect(db.prepare("SELECT id FROM customer_ledger WHERE customer_id=? AND transaction_type IN ('CREDIT','CREDIT_OFFSET') AND credit>0").all(customer)).toEqual([]);
  });
  it('locks another return that supports the same invoice credit entitlement', async () => {
    const customer = await createCustomer('Cumulative source credit', cookie);
    const invoice = await createInvoice({ customerId: customer, itemId: item, lines: [{ quantity: 10, unitPrice: 15 }], payment: { amount: 50 } }, cookie);
    const first = await processReturn(invoice.invoiceId, { invoiceItemIds: invoice.invoiceItemIds, quantities: [6], warehouseId: warehouse, returnDate: '2026-09-15' }, cookie);
    const second = await processReturn(invoice.invoiceId, { invoiceItemIds: invoice.invoiceItemIds, quantities: [4], warehouseId: warehouse, returnDate: '2026-09-15' }, cookie);
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    const applied = await request(app).post('/api/invoices').set('Cookie', cookie).send({ customer_id: customer,
      invoice_date: '2026-09-16', items: [{ item_id: item, quantity: 4, unit_price: 15 }], credit_offset: 50 });
    expect(applied.status).toBe(201);
    const before = financialState();
    expect((await request(app).post(`/api/invoice-returns/${second.returnId}/void`).set('Cookie', cookie)).status).toBe(409);
    expect(financialState()).toEqual(before);
  });
});
