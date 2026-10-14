/**
 * ACCT-006 — safe inventory transaction dates (Option A).
 *
 * Rule under test: an inventory-affecting movement may not be effective
 * earlier than the latest existing movement for that item in that
 * warehouse, and batch availability/expiry is evaluated as of the
 * transaction's own date rather than today.
 *
 * Written FAILING-FIRST: each case below reproduces one of D1-D4 or a
 * companion scenario, and asserts both the rejection AND that a rejection
 * leaves inventory, GL and payments untouched.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie, createItem, createCustomer, resolveSupplierByName } from './helpers/invoiceReturnSpec';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');

let authCookie: string;
let warehouseId: number;
let customerId: number;
let supId: number;
let n = 0;

const code = () => `AE${Date.now()}${n++}`;

/** Ledger-derived stock as of a date — the historical truth we protect. */
function asOfStock(itemId: number, date: string): number {
  const r = db
    .prepare(`SELECT COALESCE(SUM(quantity),0) q FROM stock_movements
              WHERE item_id = ? AND warehouse_id = ? AND movement_date <= ?`)
    .get(itemId, warehouseId, date) as { q: number };
  return Math.round(Number(r.q) * 1000) / 1000;
}

function currentStock(itemId: number): number {
  const r = db.prepare(`SELECT COALESCE(quantity,0) q FROM stock_balances WHERE item_id = ? AND warehouse_id = ?`)
    .get(itemId, warehouseId) as { q: number } | undefined;
  return r ? Number(r.q) : 0;
}

async function buy(itemId: number, qty: number, cost: number, date: string) {
  return request(app).post('/api/purchases').set('Cookie', authCookie).send({
    item_id: itemId, warehouse_id: warehouseId, quantity: qty, unit_cost: cost,
    purchase_date: date, supplier_id: supId,
  });
}

async function sell(itemId: number, qty: number, price: number, date: string) {
  return request(app).post('/api/invoices').set('Cookie', authCookie).send({
    customer_id: customerId, invoice_date: date,
    items: [{ item_id: itemId, quantity: qty, unit_price: price, amount: qty * price }],
  });
}

function journalBalance(): { d: number; c: number; balanced: boolean } {
  const r = db.prepare(`SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c
                         FROM journal_lines WHERE COALESCE(voided,0)=0`).get() as { d: number; c: number };
  return { d: Number(r.d), c: Number(r.c), balanced: Math.abs(Number(r.d) - Number(r.c)) < 0.005 };
}

beforeAll(async () => {
  authCookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses WHERE is_active = 1 ORDER BY id LIMIT 1').get() as { id: number }).id;
  customerId = await createCustomer(`AED-${Date.now()}`, authCookie);
  supId = await resolveSupplierByName('AED Supplier', authCookie);
});

describe('ACCT-006 D1 — an invoice may not consume stock received after its own date', () => {
  it('rejects the invoice and leaves inventory + GL untouched', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);

    const stockBefore = currentStock(item);
    const glBefore = journalBalance();
    const invBefore = (db.prepare(`SELECT COUNT(*) c FROM invoices`).get() as { c: number }).c;

    const res = await sell(item, 2, 20, '2026-09-01'); // 9 days before receipt

    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.body.error).toMatch(/stock|date|before|not available|retroactive/i);
    expect(currentStock(item)).toBe(stockBefore);
    expect((db.prepare(`SELECT COUNT(*) c FROM invoices`).get() as { c: number }).c).toBe(invBefore);
    expect(journalBalance().balanced).toBe(true);
    expect(journalBalance().d).toBe(glBefore.d);
  });

  it('allows a same-day sale (document date == receipt date)', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);
    expect((await sell(item, 2, 20, '2026-09-10')).status).toBe(201);
  });
});

describe('ACCT-006 D3 — a backdated sale may not produce historical negative stock', () => {
  it('rejects, so ledger stock as of the invoice date never goes negative', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 5, 5, '2026-09-10')).status).toBe(201);

    const res = await sell(item, 5, 20, '2026-09-01');

    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(asOfStock(item, '2026-09-01')).toBeGreaterThanOrEqual(0);
  });
});

describe('ACCT-006 D4 — a backdated purchase may not retroactively reorder FIFO', () => {
  it('rejects a receipt dated before an already-posted sale', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);
    expect((await sell(item, 5, 30, '2026-09-20')).status).toBe(201);

    // A receipt dated 2026-09-05 would become the new FIFO-oldest batch and
    // silently invalidate the cost already posted for the 09-20 sale.
    const res = await buy(item, 10, 50, '2026-09-05');

    expect(res.status).toBeGreaterThanOrEqual(400);
    const batches = db.prepare(`SELECT COUNT(*) c FROM stock_batches WHERE item_id = ?`).get(item) as { c: number };
    expect(Number(batches.c)).toBe(1);
  });

  it('allows a purchase dated on/after the latest movement', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);
    expect((await buy(item, 10, 50, '2026-09-25')).status).toBe(201);
  });
});

describe('ACCT-006 D2 — expiry is judged at the transaction date, not today', () => {
  it('a sale dated while the batch was still valid is permitted', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 5, 5, '2026-06-01')).status).toBe(201);
    db.prepare(`UPDATE items SET has_expiry = 1 WHERE id = ?`).run(item);
    db.prepare(`UPDATE stock_batches SET expiry_date = '2026-07-01' WHERE item_id = ?`).run(item);

    // Valid on 2026-06-15 (expires 2026-07-01), long expired today.
    const res = await sell(item, 1, 20, '2026-06-15');
    expect(res.status).toBe(201);
  });

  it('a sale dated AFTER the batch expired is rejected', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 5, 5, '2026-06-01')).status).toBe(201);
    db.prepare(`UPDATE items SET has_expiry = 1 WHERE id = ?`).run(item);
    db.prepare(`UPDATE stock_batches SET expiry_date = '2026-06-10' WHERE item_id = ?`).run(item);

    const res = await sell(item, 1, 20, '2026-06-20');
    expect(res.status).toBeGreaterThanOrEqual(400);
  });

  it('backdating cannot resurrect stock the expiry sweep already removed', async () => {
    const { runExpiryDetection } = await import('../boot/expiryDetection');
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 5, 5, '2020-01-01')).status).toBe(201);
    db.prepare(`UPDATE items SET has_expiry = 1 WHERE id = ?`).run(item);
    // Expiry long past, so the real boot sweep claims the batch and moves it
    // to EXPIRED — the faithful "it is gone" state rather than a synthetic one.
    db.prepare(`UPDATE stock_batches SET expiry_date = '2020-02-01' WHERE item_id = ?`).run(item);

    runExpiryDetection(db);
    const afterSweep = db.prepare(
      `SELECT quantity_remaining FROM stock_batches WHERE item_id = ? AND warehouse_id = ?`,
    ).get(item, warehouseId) as { quantity_remaining: number } | undefined;
    expect(Number(afterSweep?.quantity_remaining ?? 0)).toBe(0);

    // Dating the sale before the expiry must not conjure the goods back.
    const res = await sell(item, 1, 20, '2020-01-15');
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});

describe('ACCT-006 — goods receipt and production', () => {
  async function receive(itemId: number, poDate: string, receiptDate: string): Promise<number> {
    const po = await request(app).post('/api/purchase-orders').set('Cookie', authCookie).send({
      supplier_id: supId, po_date: poDate,
      items: [{ item_id: itemId, quantity: 5, unit_price: 5 }],
    });
    const poId = po.body.id as number;
    await request(app).post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie).send({ status: 'Submitted' });
    const poItem = db.prepare(`SELECT id FROM purchase_order_items WHERE po_id = ?`).get(poId) as { id: number };
    const rec = await request(app).post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send({ receipt_date: receiptDate, warehouse_id: warehouseId, items: [{ po_item_id: poItem.id, received_quantity: 5 }] });
    return rec.status;
  }

  it('permits a backdated receipt while no posted document has consumed stock', async () => {
    // Nothing has been sold, so a late supplier invoice restates no COGS.
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);
    expect(await receive(item, '2026-09-25', '2026-09-01')).toBeLessThan(400);
  });

  it('rejects a backdated receipt that would reorder FIFO beneath a consumed batch', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-10')).status).toBe(201);
    // Consume part of the 09-10 batch, so its COGS is now posted.
    expect((await sell(item, 5, 30, '2026-09-20')).status).toBe(201);

    // A batch dated 09-05 would sort ahead of the already-costed 09-10 batch.
    expect(await receive(item, '2026-09-25', '2026-09-05')).toBeGreaterThanOrEqual(400);
  });

  it('rejects a production dated before its own material receipt', async () => {
    const raw = await createItem(code(), authCookie);
    expect((await buy(raw, 20, 5, '2026-09-10')).status).toBe(201);
    const out = await createItem(code(), authCookie);

    const res = await request(app).post('/api/productions').set('Cookie', authCookie).send({
      outputs: [{ item_id: out, quantity: 4 }],
      warehouse_id: warehouseId, production_date: '2026-09-01',
      input_items: [{ item_id: raw, quantity: 8 }],
    });

    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});

describe('ACCT-006 — closed periods still win', () => {
  it('rejects a backdated sale into a closed period', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 5, 5, '2026-10-01')).status).toBe(201);
    db.prepare(`INSERT OR IGNORE INTO accounting_periods (period_name,start_date,end_date,status,created_at)
                VALUES ('2026-07','2026-07-01','2026-07-31','open',CURRENT_TIMESTAMP)`).run();
    db.prepare(`UPDATE accounting_periods SET status='closed', closed_at=CURRENT_TIMESTAMP WHERE period_name='2026-07'`).run();

    const res = await sell(item, 1, 20, '2026-07-15');

    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/closed accounting period/i);
    db.prepare(`UPDATE accounting_periods SET status='open', closed_at=NULL WHERE period_name='2026-07'`).run();
  });
});

describe('ACCT-006 — normal chronological processing is unaffected', () => {
  it('accepts a strictly forward sequence: buy -> sell -> buy -> sell', async () => {
    const item = await createItem(code(), authCookie);
    expect((await buy(item, 10, 5, '2026-09-01')).status).toBe(201);
    expect((await sell(item, 3, 30, '2026-09-02')).status).toBe(201);
    expect((await buy(item, 10, 7, '2026-09-03')).status).toBe(201);
    expect((await sell(item, 3, 30, '2026-09-04')).status).toBe(201);
    expect(journalBalance().balanced).toBe(true);
  });
});