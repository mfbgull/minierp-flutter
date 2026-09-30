/**
 * Activity-log money text must not claim USD (audit-3 task 02).
 *
 * The expense and payment log lines hardcoded `$${amount}` while the
 * ledger is denominated in the configured business currency. They now go
 * through `formatCurrency` / `getCurrencySymbol`, which read the
 * `currency_symbol` setting.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { formatCurrency, getCurrencySymbol } from '../utils/displayCurrency';
import { flushLogs } from '../services/activityLogger';
import {
  createCustomer,
  createInvoice,
  createItem,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

function descriptionsMatching(fragment: string): string[] {
  // The logger batches writes and flushes on an interval, so without this
  // the queue is still holding the rows the assertion is about to read.
  flushLogs();
  const rows = db.prepare(
    'SELECT description FROM activity_log WHERE description LIKE ? ORDER BY id DESC LIMIT 5',
  ).all(`%${fragment}%`) as Array<{ description: string }>;
  return rows.map((r) => r.description);
}

describe('activity-log currency text', () => {
  let authCookie: string;
  let itemId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Log Currency Item', authCookie);
    await purchaseStock(itemId, warehouseId, 50, 10, authCookie);
  });

  it('logs an expense amount with the configured currency, not a dollar sign', async () => {
    const res = await request(app).post('/api/expenses')
      .set('Cookie', authCookie)
      .send({
        expense_category: 'Utilities',
        amount: 1234.56,
        expense_date: '2026-09-20',
        payment_method: 'Cash',
      });
    expect([200, 201]).toContain(res.status);

    const symbol = getCurrencySymbol(db);
    const lines = descriptionsMatching('Created expense:');
    expect(lines.length).toBeGreaterThan(0);

    const line = lines[0];
    expect(line).not.toMatch(/\$\d/);
    expect(line).not.toContain('$$');
    expect(line).toContain(symbol);
    expect(line).toContain(formatCurrency(1234.56, symbol));
    expect(line).toContain('1,234.56');
  });

  it('logs a customer payment with the configured currency, not a dollar sign', async () => {
    const customerId = await createCustomer('Log Currency Customer', authCookie);
    const { invoiceId } = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 500 }], payment: null },
      authCookie,
    );

    const res = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        payment_date: '2026-09-20',
        amount: 500,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoiceId, amount: 500 }],
      });
    expect([200, 201]).toContain(res.status);

    const symbol = getCurrencySymbol(db);
    const lines = descriptionsMatching('Created payment -');
    expect(lines.length).toBeGreaterThan(0);

    const line = lines[0];
    expect(line).not.toMatch(/\$\d/);
    expect(line).not.toContain('$$');
    expect(line).toContain(symbol);
    expect(line).toContain('500.00');
  });

  it('never emits a bare dollar sign for a money amount in the log', async () => {
    flushLogs();
    const rows = db.prepare(
      "SELECT description FROM activity_log WHERE description LIKE '%$%'",
    ).all() as Array<{ description: string }>;

    const offenders = rows
      .map((r) => r.description)
      .filter((d) => /\$\s?\d|\$\$/.test(d));

    expect(offenders).toEqual([]);
  });

  it('defaults to the rupee symbol when no symbol is configured', () => {
    expect(formatCurrency(10, '')).toBe('Rs. 10.00');
    expect(formatCurrency(10, '   ')).toBe('Rs. 10.00');
  });
});