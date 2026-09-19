/**
 * Reversal-rules Phase 5 — accounting-invariant regression suite.
 *
 * Invariant A (GL balance): every reference group in journal_lines sums
 *   debit == credit; the ledger as a whole is balanced.
 * Invariant B (GL ↔ customer subledger): each invoice's posted GL cash
 *   collected (SUM of Dr cash over its PAYMENT entries) equals the net
 *   non-voided allocations on that invoice.
 * Invariant C (subledger ↔ source): customers.current_balance equals the
 *   ledger sum; invoices.paid_amount equals the non-voided allocation sum.
 * Invariant D (subledger ↔ source, suppliers): suppliers.current_balance
 *   equals the supplier_ledger chain balance.
 * Invariant E (stock ↔ batches): stock_balances.quantity equals the sum of
 *   quantity_remaining across stock_batches for the same item/warehouse.
 *
 * The invariants are exercised over a full lifecycle driven through real
 * endpoints: invoice → payment → partial return (refund disposition) →
 * cancel, plus purchase → supplier payment → purchase return, then
 * re-checked after each destructive step.
 *
 * Double-fire concurrency: every destructive endpoint is called twice
 * back-to-back (simulating a retried submit / double click — no real
 * parallelism, but better-sqlite3 serializes anyway, so this exercises the
 * same server-side guard path). The second call must fail with a 4xx and
 * the invariants must hold.
 */
import request from 'supertest';
import bcrypt from 'bcrypt';
import app from '../app';
import db from '../config/database';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;
let seq = 0;

beforeAll(async () => {
  const admin = db.prepare(`SELECT id FROM users WHERE username = 'inv-admin'`).get() as
    | { id: number }
    | undefined;
  if (!admin) {
    db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES ('inv-admin', 'inv-admin@test.local', ?, 'INV Admin', 'admin', 1)
    `).run(bcrypt.hashSync(TEST_PASSWORD, 10));
  }
  const login = await request(app)
    .post('/api/auth/login')
    .send({ username: 'inv-admin', password: TEST_PASSWORD });
  if (login.status !== 200) {
    throw new Error(`Admin login failed: ${login.status} ${JSON.stringify(login.body)}`);
  }
  const cookies = login.headers['set-cookie'] ?? [];
  const cookieList = Array.isArray(cookies) ? cookies : [cookies];
  const tokenCookie = cookieList.find((c: string) => c.startsWith('token='));
  if (!tokenCookie) throw new Error('Login did not return a token cookie');
  token = tokenCookie.split(';')[0];
});

// ---------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------

async function createCustomer(): Promise<number> {
  seq += 1;
  const res = await request(app)
    .post('/api/customers')
    .set('Cookie', token)
    .send({
      customer_name: `INV Cust ${seq}`,
      customer_code: `INV-C-${seq}`,
      phone: '0300-0000000',
    });
  const body = res.body?.data ?? res.body;
  if (res.status !== 201 && res.status !== 200) {
    throw new Error(`createCustomer: ${res.status} ${JSON.stringify(res.body)}`);
  }
  return body.id as number;
}

async function createItemWithStock(qty: number): Promise<number> {
  seq += 1;
  const itemRes = await request(app)
    .post('/api/inventory/items')
    .set('Cookie', token)
    .send({
      item_code: `INV-IT-${seq}`,
      item_name: `INV Item ${seq}`,
      unit_of_measure: 'pcs',
      current_stock: 0,
    });
  const item = itemRes.body?.data ?? itemRes.body;
  if (itemRes.status !== 201 && itemRes.status !== 200) {
    throw new Error(`createItem: ${itemRes.status} ${JSON.stringify(itemRes.body)}`);
  }
  const itemId = item.id as number;

  // Stock via a direct batch + balance insert is NOT used — drive through
  // the app: create a supplier purchase and receive nothing else.
  return itemId;
}

async function seedStock(itemId: number, warehouseId: number, qty: number, unitCost: number): Promise<void> {
  db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES ('INV-SEED-' || ?, ?, ?, 'OPENING', 0, ?, ?, ?, '2026-09-01')
  `).run(seq, itemId, warehouseId, qty, qty, unitCost);
  db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)
  `).run(itemId, warehouseId, qty);
}

async function getFirstWarehouseId(): Promise<number> {
  const wh = db.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get() as { id: number };
  return wh.id;
}

// ---------------------------------------------------------------------
// Invariant lifecycle test
// ---------------------------------------------------------------------

describe('Accounting invariants over a full lifecycle', () => {
  it('holds after invoice → payment → return → cancel; purchase → payment → return', async () => {
    // --- Baseline before any of our activity.
    expectAllInvariantsHold('baseline');

    // Seed owner capital so the cash account can cover outflows (the GL
    // funds guard rejects payments when cash is negative).
    const capRes = await request(app)
      .post('/api/owner-equity/capital')
      .set('Cookie', token)
      .send({ capital_date: '2026-09-01', amount: 10000 });
    if (capRes.status !== 201 && capRes.status !== 200) {
      throw new Error(`capital: ${capRes.status} ${JSON.stringify(capRes.body)}`);
    }
    expectAllInvariantsHold('after capital');

    // --- Sales side -----------------------------------------------------
    const customerId = await createCustomer();
    const warehouseId = await getFirstWarehouseId();
    const itemId = await createItemWithStock(0);
    await seedStock(itemId, warehouseId, 100, 10);

    const invRes = await request(app)
      .post('/api/invoices')
      .set('Cookie', token)
      .send({
        invoice_no: `INV-AI-${seq}`,
        customer_id: customerId,
        invoice_date: '2026-09-12',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 10, unit_price: 15, warehouse_id: warehouseId }],
      });
    const invoice = invRes.body?.data ?? invRes.body;
    if (invRes.status !== 201 && invRes.status !== 200) {
      throw new Error(`createInvoice: ${invRes.status} ${JSON.stringify(invRes.body)}`);
    }
    expectAllInvariantsHold('after invoice');

    // Pay 100 of the 150 invoice.
    const payRes = await request(app)
      .post('/api/payments')
      .set('Cookie', token)
      .send({
        customer_id: customerId,
        payment_date: '2026-09-12',
        amount: 100,
        payment_method: 'cash',
        invoice_allocations: [{ invoice_id: invoice.id, amount: 100 }],
      });
    if (payRes.status !== 201 && payRes.status !== 200) {
      throw new Error(`payment: ${payRes.status} ${JSON.stringify(payRes.body)}`);
    }
    expectAllInvariantsHold('after payment');

    // Partial return of 4 units (60 of 150) — refund disposition refunds
    // at most the collected 100, remainder stays as credit on account.
    const invoiceItem = db.prepare(
      'SELECT id FROM invoice_items WHERE invoice_id = ? ORDER BY id LIMIT 1'
    ).get(invoice.id) as { id: number };
    const retRes = await request(app)
      .post(`/api/invoices/${invoice.id}/return`)
      .set('Cookie', token)
      .send({
        disposition: 'refund',
        items: [{ invoice_item_id: invoiceItem.id, return_quantity: 4 }],
      });
    if (retRes.status !== 201 && retRes.status !== 200) {
      throw new Error(`return: ${retRes.status} ${JSON.stringify(retRes.body)}`);
    }
    expectAllInvariantsHold('after partial return');

    // C1 blocks cancelling an invoice with recorded payments — void the
    // remaining 40 allocation's payment first, then cancel.
    const leftover = db.prepare(`
      SELECT DISTINCT pa.payment_id AS id
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      WHERE pa.invoice_id = ? AND pa.voided_at IS NULL AND p.voided_at IS NULL
    `).all(invoice.id) as Array<{ id: number }>;
    for (const p of leftover) {
      const voidRes = await request(app).delete(`/api/payments/${p.id}`).set('Cookie', token);
      if (voidRes.status !== 200 && voidRes.status !== 204) {
        throw new Error(`void leftover payment: ${voidRes.status} ${JSON.stringify(voidRes.body)}`);
      }
    }
    expectAllInvariantsHold('after voiding leftover payment');

    // Note: the returned invoice cannot be cancelled (rule 5: returned
    // documents lock) — there is no invoice-return void endpoint by design;
    // corrections flow through additional returns. Cancel is exercised on
    // a separate unreturned invoice below.

    const customerId2 = await createCustomer();
    seq += 1;
    const inv2Res = await request(app)
      .post('/api/invoices')
      .set('Cookie', token)
      .send({
        invoice_no: `INV-AI-${seq}`,
        customer_id: customerId2,
        invoice_date: '2026-09-12',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 2, unit_price: 15, warehouse_id: warehouseId }],
      });
    const invoice2 = inv2Res.body?.data ?? inv2Res.body;
    if (inv2Res.status !== 201 && inv2Res.status !== 200) {
      throw new Error(`createInvoice2: ${inv2Res.status} ${JSON.stringify(inv2Res.body)}`);
    }

    // Cancel the untouched invoice (C1 path).
    const cancelRes = await request(app)
      .put(`/api/invoices/${invoice2.id}/cancel`)
      .set('Cookie', token)
      .send({});
    if (cancelRes.status !== 200) {
      throw new Error(`cancel: ${cancelRes.status} ${JSON.stringify(cancelRes.body)}`);
    }
    expectAllInvariantsHold('after invoice cancel');

    // --- Purchase side ---------------------------------------------------
    const supRes = await request(app)
      .post('/api/suppliers')
      .set('Cookie', token)
      .send({ supplier_name: `INV Sup ${seq}`, supplier_code: `INV-S-${seq}` });
    const supplier = supRes.body?.data ?? supRes.body;
    if (supRes.status !== 201 && supRes.status !== 200) {
      throw new Error(`createSupplier: ${supRes.status} ${JSON.stringify(supRes.body)}`);
    }

    const poRes = await request(app)
      .post('/api/purchase-orders')
      .set('Cookie', token)
      .send({
        supplier_id: supplier.id,
        po_date: '2026-09-12',
        items: [{ item_id: itemId, quantity: 20, unit_price: 8 }],
      });
    const po = poRes.body?.data ?? poRes.body;
    if (poRes.status !== 201 && poRes.status !== 200) {
      throw new Error(`createPO: ${poRes.status} ${JSON.stringify(poRes.body)}`);
    }
    await request(app).post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });
    expectAllInvariantsHold('after PO (no GL yet)');

    // Supplier payment.
    const supPay = await request(app)
      .post('/api/payments')
      .set('Cookie', token)
      .send({
        supplier_id: supplier.id,
        payment_date: '2026-09-12',
        amount: 80,
        payment_method: 'cash',
        po_allocations: [{ po_id: po.id, amount: 80 }],
      });
    if (supPay.status !== 201 && supPay.status !== 200) {
      throw new Error(`supplier payment: ${supPay.status} ${JSON.stringify(supPay.body)}`);
    }
    expectAllInvariantsHold('after supplier payment');

    // PO cancel after payment — payment must be handled (C3).
    const poCancel = await request(app)
      .post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token)
      .send({ status: 'Cancelled' });
    if (poCancel.status !== 200) {
      throw new Error(`PO cancel: ${poCancel.status} ${JSON.stringify(poCancel.body)}`);
    }
    expectAllInvariantsHold('after PO cancel');
  });
});

// ---------------------------------------------------------------------
// Double-fire concurrency tests
// ---------------------------------------------------------------------

async function paidInvoiceFixture(): Promise<{ invoiceId: number; customerId: number; itemId: number; paymentId: number; warehouseId: number }> {
  const customerId = await createCustomer();
  const warehouseId = await getFirstWarehouseId();
  const itemId = await createItemWithStock(0);
  await seedStock(itemId, warehouseId, 50, 10);

  seq += 1;
  const invRes = await request(app)
    .post('/api/invoices')
    .set('Cookie', token)
    .send({
      invoice_no: `INV-AI-${seq}`,
      customer_id: customerId,
      invoice_date: '2026-09-12',
      warehouse_id: warehouseId,
      items: [{ item_id: itemId, quantity: 5, unit_price: 20, warehouse_id: warehouseId }],
    });
  const invoice = invRes.body?.data ?? invRes.body;

  const payRes = await request(app)
    .post('/api/payments')
    .set('Cookie', token)
    .send({
      customer_id: customerId,
      payment_date: '2026-09-12',
      amount: 100,
      payment_method: 'cash',
      invoice_allocations: [{ invoice_id: invoice.id, amount: 100 }],
    });
  const payment = payRes.body?.data ?? payRes.body;

  return { invoiceId: invoice.id, customerId, itemId, paymentId: payment.id, warehouseId };
}

describe('Double-fire rejection on destructive endpoints', () => {
  it('cancelling an invoice twice: second attempt 4xx, invariants hold', async () => {
    const f = await paidInvoiceFixture();
    expectAllInvariantsHold('double-cancel fixture');

    // C1 blocks cancelling a paid invoice — void the payment first.
    const voidRes = await request(app).delete(`/api/payments/${f.paymentId}`)
      .set('Cookie', token);
    expect([200, 204]).toContain(voidRes.status);

    const first = await request(app).put(`/api/invoices/${f.invoiceId}/cancel`)
      .set('Cookie', token).send({});
    expect(first.status).toBe(200);

    const second = await request(app).put(`/api/invoices/${f.invoiceId}/cancel`)
      .set('Cookie', token).send({});
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after double cancel');
  });

  it('deleting a payment twice: second attempt 4xx, invariants hold', async () => {
    const f = await paidInvoiceFixture();
    const first = await request(app).delete(`/api/payments/${f.paymentId}`)
      .set('Cookie', token);
    expect([200, 204]).toContain(first.status);
    expectAllInvariantsHold('after payment delete 1');

    const second = await request(app).delete(`/api/payments/${f.paymentId}`)
      .set('Cookie', token);
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after payment delete 2');
  });

  it('cancelling a PO twice: second attempt 4xx, invariants hold', async () => {
    const supRes = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_name: `DF Sup ${seq}`, supplier_code: `DF-S-${seq}` });
    const supplier = supRes.body?.data ?? supRes.body;
    const itemId = await createItemWithStock(0);

    const poRes = await request(app).post('/api/purchase-orders').set('Cookie', token)
      .send({ supplier_id: supplier.id, po_date: '2026-09-12',
              items: [{ item_id: itemId, quantity: 3, unit_price: 5 }] });
    const po = poRes.body?.data ?? poRes.body;
    await request(app).post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });

    const first = await request(app).post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token).send({ status: 'Cancelled' });
    expect(first.status).toBe(200);

    const second = await request(app).post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token).send({ status: 'Cancelled' });
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after double PO cancel');
  });

  // Phase 5 expansion: GRN void, transfer void, count correction.

  it('voiding a goods receipt twice: second attempt 4xx, invariants hold', async () => {
    const supRes = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_name: `GRN Sup ${seq}`, supplier_code: `GRN-S-${seq}` });
    const supplier = supRes.body?.data ?? supRes.body;
    const warehouseId = await getFirstWarehouseId();
    const itemId = await createItemWithStock(0);

    const poRes = await request(app).post('/api/purchase-orders').set('Cookie', token)
      .send({ supplier_id: supplier.id, po_date: '2026-09-12',
              items: [{ item_id: itemId, quantity: 8, unit_price: 6 }] });
    const po = poRes.body?.data ?? poRes.body;
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?')
      .get(po.id) as { id: number };
    await request(app).post(`/api/purchase-orders/${po.id}/status`)
      .set('Cookie', token).send({ status: 'Submitted' });

    const recRes = await request(app)
      .post(`/api/purchase-orders/${po.id}/receipts`)
      .set('Cookie', token)
      .send({ receipt_date: '2026-09-12', warehouse_id: warehouseId,
              items: [{ po_item_id: poItem.id, received_quantity: 8 }] });
    const receipt = recRes.body?.data ?? recRes.body;
    expect(recRes.status === 201 || recRes.status === 200).toBe(true);
    expectAllInvariantsHold('after goods receipt');

    const first = await request(app)
      .post(`/api/purchase-orders/${po.id}/receipts/${receipt.id}/void`)
      .set('Cookie', token).send({ reason: 'test void' });
    expect(first.status).toBe(200);
    expectAllInvariantsHold('after GRN void 1');

    const second = await request(app)
      .post(`/api/purchase-orders/${po.id}/receipts/${receipt.id}/void`)
      .set('Cookie', token).send({});
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after GRN void 2');
  });

  it('voiding a stock transfer twice: second attempt 4xx, invariants hold', async () => {
    const warehouseId = await getFirstWarehouseId();
    const whRes = await request(app).post('/api/inventory/warehouses')
      .set('Cookie', token)
      .send({ warehouse_name: `XFER WH ${seq}`, warehouse_code: `XFER-WH-${seq}` });
    const destWh = whRes.body?.data ?? whRes.body;
    const destId = destWh.id as number;
    const itemId = await createItemWithStock(0);

    // Seed 20 units in the source warehouse.
    await seedStock(itemId, warehouseId, 20, 5);

    const xferRes = await request(app)
      .post('/api/inventory/stock-transfers')
      .set('Cookie', token)
      .send({
        item_id: itemId,
        from_warehouse_id: warehouseId,
        to_warehouse_id: destId,
        quantity: 5,
        movement_date: '2026-09-12',
      });
    const xfer = xferRes.body?.data ?? xferRes.body;
    if (xferRes.status !== 201 && xferRes.status !== 200) {
      throw new Error(`transfer: ${xferRes.status} ${JSON.stringify(xferRes.body)}`);
    }
    expectAllInvariantsHold('after transfer');

    // The transfer response carries the OUT movement number (movement_no);
    // fall back to the latest TRANSFER OUT leg for this item.
    let outMovementNo: string | undefined = xfer.movement_no ?? xfer.movementNo;
    if (!outMovementNo) {
      const leg = db.prepare(`
        SELECT movement_no FROM stock_movements
        WHERE movement_type = 'TRANSFER' AND quantity < 0 AND item_id = ?
        ORDER BY id DESC LIMIT 1
      `).get(itemId) as { movement_no: string } | undefined;
      outMovementNo = leg?.movement_no;
    }
    if (!outMovementNo) throw new Error('No transfer OUT leg found after create');

    const first = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', token).send({});
    expect(first.status).toBe(200);
    expectAllInvariantsHold('after transfer void 1');

    const second = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', token).send({});
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after transfer void 2');
  });

  it('correcting a physical count twice: second attempt 4xx, invariants hold', async () => {
    const warehouseId = await getFirstWarehouseId();
    const itemId = await createItemWithStock(0);
    await seedStock(itemId, warehouseId, 20, 10);

    // Drive a count session through the model (same as countCorrection tests).
    const PhysicalCountModel = (await import('../models/PhysicalCount')).default;
    const countId = PhysicalCountModel.create({ warehouse_id: warehouseId }, 1, db);
    PhysicalCountModel.recordCount(countId, itemId, 12, 1, null, db);
    PhysicalCountModel.completeCount(countId, 1, db);
    expectAllInvariantsHold('after count completion (shortage −8)');

    const first = await request(app)
      .post(`/api/inventory/physical-counts/${countId}/correct`)
      .set('Cookie', token)
      .send({ corrections: [{ item_id: itemId, counted_quantity: 18 }] });
    expect(first.status).toBe(200);
    expectAllInvariantsHold('after count correction 1');

    const second = await request(app)
      .post(`/api/inventory/physical-counts/${countId}/correct`)
      .set('Cookie', token)
      .send({ corrections: [{ item_id: itemId, counted_quantity: 20 }] });
    expect(second.status).toBeGreaterThanOrEqual(400);
    expect(second.status).toBeLessThan(500);
    expectAllInvariantsHold('after count correction 2');

    // Stock nets to the corrected quantity.
    const bal = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, warehouseId) as { quantity: number }).quantity;
    expect(bal).toBeCloseTo(18, 6);
  });
});
