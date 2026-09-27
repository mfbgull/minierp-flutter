import db from '../config/database';
import ledgerUtils from '../utils/ledgerUtils';
import {
  getAuthCookie,
  createCustomer,
  createItem,
  purchaseStock,
} from './helpers/invoiceReturnSpec';
import { InvoiceCreationService } from '../services/InvoiceCreationService';
import type { InvoiceCreationInput } from '../services/invoiceCreationTypes';

describe('InvoiceCreationService', () => {
  let authCookie = '';
  let customerId = 0;
  let itemId = 0;
  let warehouseId = 0;
  let userId = 0;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = await createCustomer('Invoice Creation Service Customer', authCookie);
    itemId = await createItem('Invoice Creation Service Item', authCookie);
    await purchaseStock(itemId, warehouseId, 10, 20, authCookie);

    const user = db.prepare('SELECT id FROM users WHERE username = ?').get('admin') as { id: number };
    userId = user.id;
  });

  function input(overrides: Partial<InvoiceCreationInput> = {}): InvoiceCreationInput {
    return {
      source: 'DIRECT',
      userId,
      customerId,
      invoiceDate: '2026-09-25',
      dueDate: '2026-10-10',
      items: [{ item_id: itemId, quantity: 2, unit_price: 50, tax_rate: 0 }],
      ...overrides,
    };
  }

  it('creates the invoice, stock movements, ledger, and GL in one transaction', () => {
    const service = new InvoiceCreationService(db);

    const result = service.create(input());

    expect(result.replayed).toBe(false);
    expect(result.totalAmount).toBe(100);
    expect(result.paidAmount).toBe(0);
    expect(result.balanceAmount).toBe(100);

    const invoice = db.prepare('SELECT total_amount, paid_amount, balance_amount, source_type FROM invoices WHERE id = ?')
      .get(result.invoiceId) as { total_amount: number; paid_amount: number; balance_amount: number; source_type: string };
    expect(Number(invoice.total_amount)).toBe(100);
    expect(Number(invoice.paid_amount)).toBe(0);
    expect(Number(invoice.balance_amount)).toBe(100);
    expect(invoice.source_type).toBe('DIRECT');

    const item = db.prepare('SELECT quantity, unit_price, amount FROM invoice_items WHERE invoice_id = ?')
      .get(result.invoiceId) as { quantity: number; unit_price: number; amount: number };
    expect(Number(item.quantity)).toBe(2);
    expect(Number(item.amount)).toBe(100);

    const stock = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(itemId, warehouseId) as { quantity: number };
    expect(Number(stock.quantity)).toBe(8);

    const ledger = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
      FROM customer_ledger
      WHERE customer_id = ? AND transaction_type = 'INVOICE' AND voided = 0
    `).get(customerId) as { debit: number; credit: number };
    expect(Number(ledger.debit)).toBe(100);
    expect(Number(ledger.credit)).toBe(0);

    const gl = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) AS debit, COALESCE(SUM(credit), 0) AS credit
      FROM journal_lines
      WHERE reference_type = 'INVOICE' AND reference_id = ? AND voided = 0
    `).get(result.invoiceId) as { debit: number; credit: number };
    expect(Number(gl.debit)).toBe(Number(gl.credit));
    expect(Number(gl.debit)).toBeGreaterThan(0);
  });

  it('replays the same idempotent request without creating a second invoice', () => {
    const service = new InvoiceCreationService(db);
    const requestInput = input({
      idempotency: { scope: 'invoice_create_test', key: 'service-test-key-001', hash: 'hash-001' },
    });

    const first = service.create(requestInput);
    const second = service.create(requestInput);

    expect(second.replayed).toBe(true);
    expect(second.invoiceId).toBe(first.invoiceId);
    expect(Number((db.prepare('SELECT COUNT(*) AS count FROM invoices WHERE customer_id = ?').get(customerId) as { count: number }).count)).toBe(2);
  });

  it('rejects a client total that disagrees with server line totals', () => {
    const service = new InvoiceCreationService(db);

    expect(() => service.create(input({ totalAmount: 101 }))).toThrow('total_amount disagrees');
  });

  it('re-foots the customer ledger chain when an invoice is backdated', async () => {
    const service = new InvoiceCreationService(db);
    const backdatedCustomerId = await createCustomer('Backdated Ledger Customer', authCookie);

    service.create(input({
      customerId: backdatedCustomerId,
      invoiceDate: '2026-09-20',
      items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0 }],
      recordPayment: true,
      payment: { amount: 100, payment_method: 'Cash', payment_date: '2026-09-20' },
    }));
    service.create(input({
      customerId: backdatedCustomerId,
      invoiceDate: '2026-09-10',
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
    }));

    const rows = db.prepare(`
      SELECT debit, credit, balance FROM customer_ledger
      WHERE customer_id = ? AND voided = 0
      ORDER BY transaction_date ASC, id ASC
    `).all(backdatedCustomerId) as Array<{ debit: number; credit: number; balance: number }>;
    expect(rows).toHaveLength(3);

    let running = 0;
    for (const row of rows) {
      running += Number(row.debit) - Number(row.credit);
      expect(Number(row.balance)).toBeCloseTo(running, 2);
    }
    expect(ledgerUtils.recalcCustomerBalanceFromLedger(backdatedCustomerId)).toBeCloseTo(running, 2);
  });
});
