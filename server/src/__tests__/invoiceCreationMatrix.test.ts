import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createCustomer, createItem, purchaseStock } from './helpers/invoiceReturnSpec';

type InvoiceRow = { id: number; invoice_no: string; total_amount: number; source_type: string };

describe('invoice creation endpoint matrix', () => {
  let authCookie = '';
  let customerId = 0;
  let itemId = 0;
  let warehouseId = 0;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = await createCustomer('Invoice Matrix Customer', authCookie);
    itemId = await createItem('Invoice Matrix Item', authCookie);
    await purchaseStock(itemId, warehouseId, 10, 20, authCookie);
  });

  function latestInvoice(sourceType: string): InvoiceRow {
    const row = db.prepare('SELECT id, invoice_no, total_amount, source_type FROM invoices WHERE source_type = ? ORDER BY id DESC LIMIT 1').get(sourceType) as InvoiceRow | undefined;
    if (!row) throw new Error(`No ${sourceType} invoice was created`);
    return row;
  }

  function expectSharedAccountingSemantics(invoice: InvoiceRow): void {
    expect(Number(invoice.total_amount)).toBe(100);

    const item = db.prepare('SELECT quantity, amount FROM invoice_items WHERE invoice_id = ?').get(invoice.id) as { quantity: number; amount: number };
    expect(Number(item.quantity)).toBe(1);
    expect(Number(item.amount)).toBe(100);

    const gl = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
      FROM journal_lines
      WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0
    `).get(invoice.id) as { debit: number; credit: number };
    expect(Number(gl.debit)).toBe(Number(gl.credit));
    expect(Number(gl.debit)).toBeGreaterThan(0);

    const ledger = db.prepare(`
      SELECT COUNT(*) AS count
      FROM customer_ledger
      WHERE reference_no = ? AND transaction_type = 'INVOICE' AND voided = 0
    `).get(invoice.invoice_no) as { count: number };
    expect(ledger.count).toBe(1);

    const movements = db.prepare(`
      SELECT COUNT(*) AS count
      FROM stock_movements
      WHERE reference_docno = ? AND movement_type = 'SALE'
    `).get(invoice.invoice_no) as { count: number };
    expect(movements.count).toBeGreaterThan(0);
  }

  it('routes standard, mobile, POS, and sales-order writes through shared accounting semantics', async () => {
    const standard = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-25',
        due_date: '2026-10-10',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0 }],
      });
    expect(standard.status).toBe(201);

    const mobile = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-09-25',
        due_date: '2026-10-10',
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0 }],
      });
    expect(mobile.status).toBe(201);

    const pos = await request(app)
      .post('/api/pos/sale')
      .set('Cookie', authCookie)
      .send({
        warehouse_id: warehouseId,
        sale_date: '2026-09-25',
        cash_received: 100,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
      });
    expect(pos.status).toBe(201);

    const salesOrder = await request(app)
      .post('/api/sales-orders')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        so_date: '2026-09-25',
        expected_delivery_date: '2026-09-30',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, amount: 100 }],
      });
    expect(salesOrder.status).toBe(201);
    const salesOrderId = salesOrder.body.data?.id ?? salesOrder.body.id;
    const converted = await request(app)
      .post(`/api/sales-orders/${salesOrderId}/convert`)
      .set('Cookie', authCookie)
      .send({});
    expect(converted.status).toBe(201);

    for (const sourceType of ['DIRECT', 'MOBILE', 'POS', 'SALES_ORDER']) {
      expectSharedAccountingSemantics(latestInvoice(sourceType));
    }
  });
});
