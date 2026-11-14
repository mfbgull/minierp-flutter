/**
 * BUG-010 REGRESSION: invoice restore must re-consume the SAME batches and
 * unit costs the invoice's original SALE movements used.
 *
 * Root cause: restoreInvoice re-ran generic FIFO (consumeFromOldestBatches)
 * while un-voiding the ORIGINAL COGS journal lines. If another sale consumed
 * the returned stock between delete and restore, restore took a later,
 * differently-costed layer and the stock ledger disagreed with the GL.
 *
 * Fix: delete records per-batch restorations (reverseStockForItems credits
 * the original sale batch back); restore replays those exact batches at
 * their original unit cost (InvoiceModel.reconsumeRestoredInvoiceItems).
 *
 * This suite covers:
 *   1. batch-faithful restore: stock ledger cost equals the un-voided COGS
 *   2. restore refused (no silent corruption) when the returned stock was
 *      consumed by another sale in the delete→restore window
 */

import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';

let authCookie: string;
let warehouseId: number;
let customerId: number;
let seq = 0;

function uid(): number { return ++seq; }

async function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: Record<string, unknown>) {
  let r = request(app)[method](url);
  // ACCT-008 / D19: mandated financial writes reject a keyless request.
  if (method === 'post') r = r.set('Idempotency-Key', `api-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  if (authCookie) r = r.set('Cookie', authCookie);
  if (body !== undefined) r = r.send(body);
  return r;
}

function stockOf(itemId: number): number {
  return Number(
    (db.prepare('SELECT COALESCE(SUM(quantity),0) q FROM stock_balances WHERE item_id = ?')
      .get(itemId) as { q: number }).q
  );
}

/** Net value of the un-voided COGS (5000) lines for this invoice. */
function cogsForInvoice(invoiceNo: string): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE coa.code = '5000' AND jl.voided = 0
      AND je.reference_type = 'INVOICE'
      AND je.reference_id = (SELECT id FROM invoices WHERE invoice_no = ?)
  `).get(invoiceNo) as { net: number };
  return Number(row.net);
}

/** Sum of the RESTORED SALE movement value (the movements the restore wrote). */
function restoredSaleValue(invoiceNo: string): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(ABS(quantity) * unit_cost), 0) AS v
    FROM stock_movements
    WHERE reference_docno = ? AND movement_type = 'SALE'
      AND quantity < 0 AND remarks LIKE '%(restored)%'
  `).get(invoiceNo) as { v: number };
  return Number(row.v);
}

async function createItem(name: string): Promise<number> {
  const res = await api('post', '/api/inventory/items', {
    item_code: `B10-${Date.now()}-${uid()}`,
    item_name: name,
    unit_of_measure: 'pcs',
    standard_cost: 0,
    standard_selling_price: 200,
    current_stock: 0,
  });
  return res.body.id;
}

async function purchaseStock(itemId: number, qty: number, cost: number, date = '2026-09-10'): Promise<void> {
  const supplierId = await resolveSupplierByName('BUG-010 Supplier', authCookie);
  const res = await api('post', '/api/purchases', {
    warehouse_id: warehouseId,
    purchase_date: date,
    supplier_id: supplierId,
    items: [{ item_id: itemId, quantity: qty, unit_cost: cost }],
  });
  if (res.status !== 201) throw new Error(`purchaseStock failed: ${res.status} ${JSON.stringify(res.body)}`);
}

async function sell(itemId: number, qty: number, price = 200): Promise<{ id: number; invoice_no: string }> {
  const res = await api('post', '/api/invoices', {
    customer_id: customerId,
    invoice_date: '2026-09-15',
    warehouse_id: warehouseId,
    items: [{ item_id: itemId, quantity: qty, unit_price: price }],
  });
  if (res.status !== 201) throw new Error(`sell failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { id: res.body.id, invoice_no: res.body.invoice_no };
}

beforeAll(async () => {
  const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD as string;
  const login = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = login.headers['set-cookie'] ?? [];
  const list = Array.isArray(cookies) ? cookies : [cookies];
  const tokenCookie = list.find((c: string) => c.startsWith('token='));
  if (!tokenCookie) throw new Error('Login failed: no token cookie');
  authCookie = tokenCookie.split(';')[0];

  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id ASC LIMIT 1').get() as { id: number }).id;
  customerId = (db.prepare(
    `INSERT INTO customers (customer_name, customer_code, phone)
     VALUES (?, ?, ?) RETURNING id`
  ).get('BUG-010 Customer', 'B10-CUST', '0300-1010') as { id: number }).id;
});

describe('BUG-010: restore is batch-faithful', () => {
  it('re-consumes the original batch and cost; stock value equals the un-voided COGS', async () => {
    const item = await createItem('B10 Faithful');
    // Batch A: received 2026-09-10, cost 100.
    await purchaseStock(item, 10, 100, '2026-09-10');

    const inv = await sell(item, 10);
    // COGS = 10 × 100 = 1000 on batch A.
    expect(cogsForInvoice(inv.invoice_no)).toBeCloseTo(1000, 2);

    expect((await api('delete', `/api/invoices/${inv.id}`)).status).toBe(200);

    // A CHEAPER batch B arrives while the invoice is deleted, with an
    // EARLIER received_date, so generic FIFO at restore time would select
    // it (batch B @50) instead of the original batch A @100.
    await purchaseStock(item, 10, 50, '2026-09-01');

    const res = await api('post', `/api/invoices/${inv.id}/restore`);
    expect(res.status).toBe(200);

    // The restored SALE must carry the ORIGINAL cost (10 × 100), so the
    // stock value re-consumed equals the COGS the restore un-voided (a
    // generic FIFO restore would have taken batch B at 50 = 500).
    expect(restoredSaleValue(inv.invoice_no)).toBeCloseTo(1000, 2);
    // The GL was un-voided, not re-posted: COGS stays 1000, not 2000.
    expect(cogsForInvoice(inv.invoice_no)).toBeCloseTo(1000, 2);
    // Batch A is spent again (10 sold, 10 restored then re-sold); batch B
    // is untouched (10 @ 50 still on hand).
    expect(stockOf(item)).toBeCloseTo(10, 3);
  });

  it('refuses restore instead of corrupting stock when the returned stock was sold in the window', async () => {
    const item = await createItem('B10 Consumed');
    await purchaseStock(item, 10, 100);

    const inv = await sell(item, 10);
    expect((await api('delete', `/api/invoices/${inv.id}`)).status).toBe(200);

    // Another invoice consumes the batch A stock the delete returned.
    await sell(item, 10);

    // A cheaper batch arrives too — the exact BUG-010 trap.
    await purchaseStock(item, 10, 50);

    const res = await api('post', `/api/invoices/${inv.id}/restore`);
    // Restore must NOT silently succeed by consuming batch B while
    // un-voiding the 1000 COGS. It fails; the invoice stays deleted.
    expect(res.status).toBeGreaterThanOrEqual(400);

    const row = db.prepare('SELECT deleted_at FROM invoices WHERE id = ?').get(inv.id) as { deleted_at: string | null };
    expect(row.deleted_at).not.toBeNull();
  });
});
