import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, purchaseStock, FUTURE_DUE_DATE } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;
let customerId: number;

beforeAll(async () => {
  token = await getAuthCookie();

  const cust = db.prepare(`
    INSERT INTO customers (customer_code, customer_name, phone)
    VALUES (?, 'Split Status Customer', '555-9999')
  `).run(`SPLIT-C-${Date.now()}`);
  customerId = Number(cust.lastInsertRowid);
});

async function createInvoiceWithPayment(
  authCookie: string,
  opts: {
    total_amount: number;
    paid_amount?: number;
    items: Array<{ item_id: number; quantity: number; unit_price: number }>;
  },
): Promise<{ id: number; body: Record<string, unknown> }> {
  const invNo = `INV-SPLIT-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
  const res = await request(app).post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      invoice_no: invNo,
      customer_id: customerId,
      invoice_date: '2026-09-15',
      due_date: FUTURE_DUE_DATE,
      total_amount: opts.total_amount,
      record_payment: (opts.paid_amount ?? 0) > 0,
      payment: (opts.paid_amount ?? 0) > 0
        ? { amount: opts.paid_amount, payment_method: 'Cash', payment_date: '2026-09-15' }
        : undefined,
      items: opts.items,
    });
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`createInvoice failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
  return { id: res.body.id, body: res.body };
}

function getInvoice(id: number) {
  return db.prepare('SELECT payment_status, return_status, status, paid_amount, returned_amount, balance_amount FROM invoices WHERE id = ?').get(id) as {
    payment_status: string; return_status: string; status: string;
    paid_amount: number; returned_amount: number; balance_amount: number;
  };
}

describe('P23: Invoice split payment_status / return_status', () => {
  let itemId: number;

  beforeAll(async () => {
    const authCookie = token;
    const iw = await purchaseStock(0, 1, 100, 10, authCookie).catch(() => null);
    const itemRes = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `SPLIT-ITEM-${Date.now()}`, item_name: 'Split Status Item' });
    itemId = itemRes.body.id;
    await purchaseStock(itemId, 1, 50, 10, authCookie);
  });

  it('unpaid invoice has payment_status=Unpaid, return_status=None', async () => {
    const { id } = await createInvoiceWithPayment(token, {
      total_amount: 100,
      items: [{ item_id: itemId, quantity: 2, unit_price: 50 }],
    });
    const inv = getInvoice(id);
    expect(inv.payment_status).toBe('Unpaid');
    expect(inv.return_status).toBe('None');
    expect(inv.status).toBe('Unpaid');
  });

  it('paid-in-full invoice has payment_status=Paid, return_status=None', async () => {
    const { id } = await createInvoiceWithPayment(token, {
      total_amount: 200,
      paid_amount: 200,
      items: [{ item_id: itemId, quantity: 2, unit_price: 100 }],
    });
    const inv = getInvoice(id);
    expect(inv.payment_status).toBe('Paid');
    expect(inv.return_status).toBe('None');
    expect(inv.status).toBe('Paid');
  });

  it('partially paid invoice has payment_status=Partially Paid, return_status=None', async () => {
    const { id } = await createInvoiceWithPayment(token, {
      total_amount: 300,
      paid_amount: 100,
      items: [{ item_id: itemId, quantity: 3, unit_price: 100 }],
    });
    const inv = getInvoice(id);
    expect(inv.payment_status).toBe('Partially Paid');
    expect(inv.return_status).toBe('None');
    expect(inv.status).toBe('Partially Paid');
  });

  it('invoice with payment then return updates return_status but keeps payment_status', async () => {
    const authCookie = token;
    const { id } = await createInvoiceWithPayment(authCookie, {
      total_amount: 500,
      paid_amount: 500,
      items: [{ item_id: itemId, quantity: 5, unit_price: 100 }],
    });

    const invBefore = getInvoice(id);
    expect(invBefore.payment_status).toBe('Paid');
    expect(invBefore.return_status).toBe('None');

    const returnRes = await request(app).post(`/api/invoices/${id}/return`)
      .set('Cookie', authCookie)
      .send({
        return_date: '2026-09-20',
        items: [{ invoice_item_id: (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(id) as { id: number }).id, return_quantity: 2 }],
        fee_type: 'percentage',
        fee_value: 0,
        settlements: [{ type: 'refund', amount: 200, method: 'Cash', payment_date: '2026-09-20' }],
      });

    if (returnRes.status !== 201 && returnRes.status !== 200) {
      throw new Error(`return failed: ${returnRes.status} ${JSON.stringify(returnRes.body)}`);
    }

    const invAfter = getInvoice(id);
    expect(invAfter.return_status).toBe('Partially Returned');
    expect(Number(invAfter.returned_amount)).toBeGreaterThan(0);
  });

  it('cancelled invoice has payment_status=Unpaid, return_status=None', async () => {
    const { id } = await createInvoiceWithPayment(token, {
      total_amount: 100,
      items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
    });
    const cancelRes = await request(app).put(`/api/invoices/${id}/cancel`)
      .set('Cookie', token)
      .send({ reason: 'test cancel' });

    if (cancelRes.status !== 200) {
      throw new Error(`cancel failed: ${cancelRes.status} ${JSON.stringify(cancelRes.body)}`);
    }

    const inv = getInvoice(id);
    expect(inv.status).toBe('Cancelled');
    expect(inv.payment_status).toBe('Unpaid');
    expect(inv.return_status).toBe('None');
  });
});
