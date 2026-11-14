// ACCT-006 (D19) — backdated sales are accepted with a warning.
//
// A sale dated before the item's first purchase receipt used to die with
// SellableStockUnavailableError even though current stock covered it (goods
// arrive on the 10th, paperwork says the 5th). D19: accept, warn, flag the
// invoice, and list it in a Backdated sales exception report. The allocator's
// refusal to oversell CURRENT sellable stock stays; costing stays actual batch
// cost (D12 option b) — the later receipt's batch is consumed at its recorded
// cost so GL inventory keeps reconciling with batch values (invariant H).
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import { createItem, getAuthCookie, purchaseWithNamedSupplier } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

let cookie = '';
let seq = 0;

const RECEIPT_DATE = '2026-09-10';
const BEFORE_RECEIPT = '2026-09-05';
const AFTER_RECEIPT = '2026-09-11';

async function login(): Promise<void> {
  cookie = await getAuthCookie();
}

function firstWarehouseId(): number {
  return (db.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get() as { id: number }).id;
}

/** Item + a future-dated purchase receipt through the real API. */
async function seedItemWithFutureReceipt(opts: {
  qty: number; cost?: number; received?: string; expiry?: string | null; hasExpiry?: number;
} = { qty: 10 }): Promise<{ itemId: number; warehouseId: number; customerId: number; batchId: number }> {
  seq += 1;
  const warehouseId = firstWarehouseId();
  const itemId = await createItem(`BD item ${seq}`, cookie);
  db.prepare(`UPDATE items SET has_expiry = ?, standard_cost = ? WHERE id = ?`)
    .run(opts.hasExpiry ?? 0, opts.cost ?? 10, itemId);

  const purchase = await purchaseWithNamedSupplier(`BD supplier ${seq}`, {
    item_id: itemId, warehouse_id: warehouseId, quantity: opts.qty,
    unit_cost: opts.cost ?? 10, purchase_date: opts.received ?? RECEIPT_DATE,
  }, cookie);
  expect(purchase.status).toBe(201);
  const purchaseId = purchase.body.data?.id ?? purchase.body.id;
  const batch = db.prepare(
    `SELECT id, unit_cost, received_date FROM stock_batches WHERE source_type = 'PURCHASE' AND source_id = ? ORDER BY id DESC LIMIT 1`
  ).get(purchaseId) as { id: number; unit_cost: number; received_date: string };
  if (opts.expiry !== undefined) {
    db.prepare(`UPDATE stock_batches SET expiry_date = ? WHERE id = ?`).run(opts.expiry, batch.id);
  }

  const customer = db.prepare(
    `INSERT INTO customers (customer_code, customer_name, phone, created_at, updated_at)
     VALUES (?, ?, '0300-0000000', datetime('now'), datetime('now'))`
  ).run(`BD-C-${seq}`, `BD Cust ${seq}`) as { lastInsertRowid?: number };

  return { itemId, warehouseId, customerId: Number(customer.lastInsertRowid), batchId: batch.id };
}

async function postInvoice(body: Record<string, unknown>): Promise<request.Response> {
  return request(app).post('/api/invoices')
      .set('Idempotency-Key', `patch-backdatedSaleWar-30-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
      .set('Cookie', cookie).send(body);
}

function invoiceRow(invoiceId: number): { backdated_before_receipt: number; invoice_no: string } {
  return db.prepare(`SELECT backdated_before_receipt, invoice_no FROM invoices WHERE id = ?`)
    .get(invoiceId) as { backdated_before_receipt: number; invoice_no: string };
}

beforeAll(async () => {
  await login();
});

afterEach(() => {
  setFeatureEnabled(db, 'feature_batch_locations', false);
});

describe('ACCT-006 — sale dated before the first purchase receipt', () => {
  it('is accepted with a warnings array, the backdated flag, and actual-batch-cost COGS', async () => {
    for (const flag of [false, true]) {
      setFeatureEnabled(db, 'feature_batch_locations', flag);
      const { itemId, warehouseId, customerId, batchId } = await seedItemWithFutureReceipt({ qty: 10, cost: 10 });

      const res = await postInvoice({
        customer_id: customerId,
        invoice_date: BEFORE_RECEIPT,
        total_amount: 80, // 4 × 20
        items: [{ item_id: itemId, quantity: 4, unit_price: 20, warehouse_id: warehouseId }],
      });
      expect(res.status).toBe(201);

      const body = res.body as { warnings?: string[]; id: number };
      expect(Array.isArray(body.warnings)).toBe(true);
      expect(body.warnings?.length).toBeGreaterThanOrEqual(1);
      expect(body.warnings?.join(' ')).toMatch(/2026-09-05/);
      expect(body.warnings?.join(' ')).toMatch(/2026-09-10|receipt/i);

      expect(invoiceRow(body.id).backdated_before_receipt).toBe(1);

      // Costing: actual batch cost, not standard-cost fabrication.
      const movement = db.prepare(
        `SELECT unit_cost, quantity FROM stock_movements
         WHERE reference_doctype IN ('INVOICE', 'POS') AND item_id = ? AND movement_type = 'SALE'
         ORDER BY id DESC LIMIT 1`
      ).get(itemId) as { unit_cost: number; quantity: number };
      expect(Number(movement.unit_cost)).toBeCloseTo(10, 4);
      expect(Number(movement.quantity)).toBe(-4);
      const remaining = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`)
        .get(batchId) as { quantity_remaining: number };
      expect(Number(remaining.quantity_remaining)).toBeCloseTo(6, 6);

      // GL inventory keeps reconciling with batch values (invariant H).
      expectAllInvariantsHold(`backdated sale accepted (flag ${flag ? 'ON' : 'OFF'})`, db);
    }
  });

  it('a sale on or after the receipt date carries no warning and no flag', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const { itemId, warehouseId, customerId } = await seedItemWithFutureReceipt({ qty: 10 });

    const res = await postInvoice({
      customer_id: customerId,
      invoice_date: AFTER_RECEIPT,
      total_amount: 40,
      items: [{ item_id: itemId, quantity: 2, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(res.status).toBe(201);
    const body = res.body as { warnings?: string[]; id: number };
    expect(body.warnings).toEqual([]);
    expect(invoiceRow(body.id).backdated_before_receipt).toBe(0);
    void itemId;
  });

  it('still refuses a backdated sale that would oversell current sellable stock', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const { itemId, warehouseId, customerId } = await seedItemWithFutureReceipt({ qty: 10 });

    const res = await postInvoice({
      customer_id: customerId,
      invoice_date: BEFORE_RECEIPT,
      total_amount: 400, // 20 × 20 > 10 on hand
      items: [{ item_id: itemId, quantity: 20, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(/sellable stock/i);
  });

  it('still refuses when the later batch was already expired on the sale date', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const { itemId, warehouseId, customerId } = await seedItemWithFutureReceipt({
      qty: 10, hasExpiry: 1, expiry: '2026-09-01',
    });

    const res = await postInvoice({
      customer_id: customerId,
      invoice_date: BEFORE_RECEIPT,
      total_amount: 80,
      items: [{ item_id: itemId, quantity: 4, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(/sellable stock/i);
  });

  it('still refuses when as-of stock exists but is not enough for the sale', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const { itemId, warehouseId, customerId } = await seedItemWithFutureReceipt({ qty: 10 });
    // An earlier receipt of 2 units gives the sale date *some* as-of stock.
    await purchaseWithNamedSupplier(`BD early supplier ${seq}`, {
      item_id: itemId, warehouse_id: warehouseId, quantity: 2,
      unit_cost: 12, purchase_date: '2026-09-01',
    }, cookie);
    // The earlier receipt must sit in an earlier FIFO layer.
    db.prepare(`UPDATE stock_batches SET received_date = '2026-09-01'
                WHERE item_id = ? AND warehouse_id = ? AND received_date > '2026-09-01' AND quantity_remaining = 2`)
      .run(itemId, warehouseId);

    const res = await postInvoice({
      customer_id: customerId,
      invoice_date: BEFORE_RECEIPT,
      total_amount: 100, // 5 × 20, only 2 units existed as of the sale date
      items: [{ item_id: itemId, quantity: 5, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(/sellable stock/i);
  });

  it('the Backdated sales exception report lists flagged invoices only', async () => {
    setFeatureEnabled(db, 'feature_batch_locations', true);
    const { itemId, warehouseId, customerId } = await seedItemWithFutureReceipt({ qty: 10 });

    const backdated = await postInvoice({
      customer_id: customerId,
      invoice_date: BEFORE_RECEIPT,
      total_amount: 20,
      items: [{ item_id: itemId, quantity: 1, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(backdated.status).toBe(201);
    const flaggedNo = invoiceRow((backdated.body as { id: number }).id).invoice_no;

    const clean = await postInvoice({
      customer_id: customerId,
      invoice_date: AFTER_RECEIPT,
      total_amount: 20,
      items: [{ item_id: itemId, quantity: 1, unit_price: 20, warehouse_id: warehouseId }],
    });
    expect(clean.status).toBe(201);
    const cleanNo = invoiceRow((clean.body as { id: number }).id).invoice_no;

    const report = await request(app).get('/api/invoices/backdated').set('Cookie', cookie);
    expect(report.status).toBe(200);
    const rows = (report.body.data ?? report.body) as Array<{ invoice_no: string; backdated_before_receipt: number }>;
    expect(Array.isArray(rows)).toBe(true);
    expect(rows.some((r) => r.invoice_no === flaggedNo && r.backdated_before_receipt === 1)).toBe(true);
    expect(rows.some((r) => r.invoice_no === cleanNo)).toBe(false);
  });
});
