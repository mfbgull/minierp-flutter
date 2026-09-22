/**
 * C3 + ACC-16: purchase-order goods receipts are the sole poster.
 *
 * Model (gl-posting-matrix ACC-16 + reversal-rules C3):
 *   - PO submission posts NOTHING — no GL entry, no supplier-ledger
 *     debit. A submitted PO is a commitment, not a liability.
 *   - Goods receipt posts Dr 1200 Inventory / Cr 2000 AP for the value
 *     that actually arrived, keyed to the receipt.
 *   - Cancelling a PO never touches any ledger: nothing was posted at
 *     submission, so there is nothing to reverse. Received goods keep
 *     their receipt-time AP; the unreceived remainder was never a
 *     liability.
 *
 * Identities asserted throughout:
 *   GL Inventory (1200) == Σ batch cost layers (+ legacy item fallback)
 *   GL AP (2000)        == Σ supplier ledger positions
 * (the old "less open PO commitments" term is gone — submission no
 * longer writes the supplier ledger, so the two ledgers agree at every
 * instant, not only when goods land)
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

const INVENTORY_CODE = '1200';
const AP_CODE = '2000';

let authCookie = '';
let supplierId = 0;
let itemId = 0;
let warehouseId = 0;
let poCounter = 0;

async function login(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD! });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

/**
 * Operational inventory value: FIFO batch cost layers plus the legacy
 * per-item fallback for items without batch rows. Mirrors
 * Reports.getGLReconciliation's inventory pairing.
 */
function batchValue(): number {
  const batchRow = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS v
    FROM stock_batches WHERE quantity_remaining > 0
  `).get() as { v: number };
  const legacyRow = db.prepare(`
    SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) AS v
    FROM items i
    WHERE i.is_active = 1 AND i.current_stock > 0
      AND NOT EXISTS (SELECT 1 FROM stock_batches sb
                      WHERE sb.item_id = i.id AND sb.quantity_remaining > 0)
  `).get() as { v: number };
  return Number(batchRow.v) + Number(legacyRow.v);
}

/**
 * Σ(debit − credit) over every non-voided supplier ledger row. The
 * per-row `balance` running total is maintained by
 * SupplierLedgerModel.rebuildBalances and can drift when an entry's
 * transaction_date falls out of id order; the debit/credit columns
 * are the source of truth. Under ACC-16 the GL tracks this same value
 * exactly: receipts credit AP, payments debit it, nothing else writes
 * either side.
 */
function supplierBalanceTotal(): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(debit - credit), 0) AS total
    FROM supplier_ledger WHERE voided = 0
  `).get() as { total: number };
  // Positive = we owe the supplier (debit-normal ledger), matching the
  // GL AP accountBalance() convention (a credit-normal account reads
  // positive when credits exceed debits).
  return Number(row.total);
}

/** Signed GL balance of one account, voided lines excluded. */
function accountBalance(code: string): number {
  const row = db.prepare(`
    SELECT a.normal_balance,
           COALESCE(SUM(jl.debit - jl.credit), 0) AS signed
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE jl.voided = 0 AND a.code = ?
    GROUP BY a.id, a.normal_balance
  `).get(code) as { normal_balance: 'debit' | 'credit'; signed: number } | undefined;
  if (!row) return 0;
  // Credit-normal accounts (liabilities) read positive when credits
  // exceed debits; debit-normal accounts (assets) read positive the
  // other way.
  return row.normal_balance === 'debit'
    ? Number(row.signed)
    : -Number(row.signed);
}

function assertInvariants(): void {
  const glInv = accountBalance(INVENTORY_CODE);
  const opInv = batchValue();
  expect(glInv).toBeCloseTo(opInv, 2);
  const glAp = accountBalance(AP_CODE);
  const supBal = supplierBalanceTotal();
  expect(glAp).toBeCloseTo(supBal, 2);
}

interface Fixture { poId: number; poNo: string; poItemId: number }
async function createSubmittedPo(quantity: number, unitPrice: number): Promise<Fixture> {
  poCounter += 1;
  void poCounter;
  const create = await request(app)
    .post('/api/purchase-orders')
    .set('Cookie', authCookie)
    .send({
      supplier_id: supplierId,
      po_date: '2026-09-15',
      items: [{ item_id: itemId, quantity, unit_price: unitPrice }],
    });
  expect(create.status).toBe(201);
  const poId = create.body.id as number;

  const submit = await request(app)
    .post(`/api/purchase-orders/${poId}/status`)
    .set('Cookie', authCookie)
    .send({ status: 'Submitted' });
  expect(submit.status).toBe(200);

  const poNo = (db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(poId) as { po_no: string }).po_no;
  const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };
  return { poId, poNo, poItemId: poItem.id };
}

async function receive(fixture: Fixture, qty: number): Promise<number> {
  const res = await request(app)
    .post(`/api/purchase-orders/${fixture.poId}/receipts`)
    .set('Cookie', authCookie)
    .send({
      receipt_date: '2026-09-16',
      warehouse_id: warehouseId,
      items: [{ po_item_id: fixture.poItemId, received_quantity: qty }],
    });
  expect([200, 201]).toContain(res.status);
  // The controller returns the bare receipt object at the root.
  return res.body.id as number;
}

/**
 * Pay the supplier against the given PO. Supplier payments require a
 * po_allocations entry; the payment path posts Dr 2000 AP / Cr cash.
 */
async function paySupplier(poId: number, amount: number): Promise<void> {
  const res = await request(app)
    .post('/api/payments')
    .set('Cookie', authCookie)
    .send({
      supplier_id: supplierId,
      payment_date: '2026-09-17',
      amount,
      payment_method: 'cash',
      reference_no: `POGL-PAY-${Date.now()}`,
      notes: 'C3 receipt GL test payment',
      po_allocations: [{ po_id: poId, amount }],
    });

  expect([200, 201]).toContain(res.status);
}

/**
 * Sell units off the shelf on an isolated item. The invoice path posts
 * COGS at actual FIFO cost, which relieves inventory value in lockstep
 * with the batch quantity consumed.
 */
async function sell(saleItemId: number, qty: number): Promise<void> {
  // The invoice FIFO guard refuses an oversell, and the seeded customer
  // set can be empty, so mint a customer per sale and keep the
  // quantity within what this scenario's receipt actually stocked.
  const customer = await request(app)
    .post('/api/customers')
    .set('Cookie', authCookie)
    .send({
      customer_name: `C3GL-CUST-${saleItemId}-${Date.now()}`,
      phone: '0000000',
    });
  expect([200, 201]).toContain(customer.status);
  const customerId = (customer.body.data?.id ?? customer.body.id) as number;

  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', authCookie)
    .send({
      customer_id: customerId,
      invoice_date: '2026-09-18',
      payment_method: 'cash',
      items: [{ item_id: saleItemId, quantity: qty, unit_price: 150 }],
    });
  expect([200, 201]).toContain(res.status);
}

beforeAll(async () => {
  authCookie = await login();
  expect(authCookie).not.toBe('');

  const item = await request(app)
    .post('/api/inventory/items')
    .set('Cookie', authCookie)
    .send({ item_code: `C3GL-${Date.now()}`, item_name: 'C3 GL Test Item' });
  expect(item.status).toBe(201);
  itemId = item.body.id as number;

  // The reconciliation's inventory pairing falls back to
  // current_stock * standard_cost for items with no batch rows. Seed
  // stock would show up on the operational side with no GL
  // counterpart, so pin both to zero — every unit in these scenarios
  // arrives through a posted receipt and nothing else.
  db.prepare(`UPDATE items SET current_stock = 0, standard_cost = 0 WHERE id = ?`).run(itemId);

  const supplier = await request(app)
    .post('/api/suppliers')
    .set('Cookie', authCookie)
    .send({
      supplier_code: `C3GL-SUP-${Date.now()}`,
      supplier_name: 'C3 GL Test Supplier',
    });
  expect(supplier.status).toBe(201);
  supplierId = supplier.body.data.id as number;

  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseId = wh.id;

  // Fund the cash account. Supplier payments debit a real cash/bank
  // account and the model refuses the withdrawal when the balance is
  // insufficient, so an unfunded ledger makes every payment fail with
  // a 400. One capital injection covers every payment in the suite.
  const capital = await request(app)
    .post('/api/owner-equity/capital')
    .set('Cookie', authCookie)
    .send({ capital_date: '2026-09-01', amount: 100000 });
  expect([200, 201]).toContain(capital.status);
});

describe('C3: PO goods receipts post to the GL', () => {
  it('scenario 1: a submitted PO posts nothing — no GL, no supplier ledger (ACC-16)', async () => {
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);
    const supplierBefore = supplierBalanceTotal();
    const po = await createSubmittedPo(5, 20);

    // Submission must be invisible to both ledgers: nothing has
    // arrived, so there is no inventory and no liability to recognise.
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore, 2);
    expect(supplierBalanceTotal()).toBeCloseTo(supplierBefore, 2);

    // and no PURCHASE_ORDER commitment rows exist for this PO at all
    const commitment = db.prepare(`
      SELECT COUNT(*) AS n FROM supplier_ledger
      WHERE transaction_type = 'PURCHASE_ORDER' AND reference_no = ?
    `).get(po.poNo) as { n: number };
    expect(commitment.n).toBe(0);

    assertInvariants();
  });

  it('scenario 2: a full receipt posts Dr 1200 / Cr 2000 for the received value', async () => {
    const po = await createSubmittedPo(10, 100); // total 1000
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);

    const receiptId = await receive(po, 10);

    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 1000, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 1000, 2);

    const lines = db.prepare(`
      SELECT a.code AS account_code, jl.debit, jl.credit
      FROM journal_lines jl
      JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE jl.reference_type = 'GOODS_RECEIPT' AND jl.reference_id = ? AND jl.voided = 0
      ORDER BY jl.id
    `).all(receiptId) as Array<{ account_code: string; debit: number; credit: number }>;
    expect(lines).toHaveLength(2);
    expect(lines.find(l => l.account_code === INVENTORY_CODE)?.debit).toBeCloseTo(1000, 2);
    expect(lines.find(l => l.account_code === AP_CODE)?.credit).toBeCloseTo(1000, 2);

    // The receipt is the sole poster: GL AP and the supplier ledger
    // moved together.
    assertInvariants();
  });

  it('scenario 3: a partial receipt posts only the received value, not the PO total', async () => {
    const po = await createSubmittedPo(10, 100); // total 1000
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);

    await receive(po, 4); // 400 only

    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 400, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 400, 2);

    // The PO is partially received; the remaining 600 is still only a
    // commitment and must not appear in the GL — or anywhere else.
    const status = db.prepare('SELECT status FROM purchase_orders WHERE id = ?').get(po.poId) as { status: string };
    expect(status.status).toBe('Partially Received');

    assertInvariants();
  });

  it('scenario 4: repeated partial receipts are additive, never duplicative', async () => {
    const po = await createSubmittedPo(10, 100);
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);

    const r1 = await receive(po, 4);
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 400, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 400, 2);

    const r2 = await receive(po, 6);
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 1000, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 1000, 2);

    // Two distinct receipt groups, one per receipt — there is no shared
    // group a replay could double-post.
    const groups = db.prepare(`
      SELECT DISTINCT reference_id
      FROM journal_lines
      WHERE reference_type = 'GOODS_RECEIPT' AND voided = 0
        AND reference_id IN (?, ?)
    `).all(r1, r2) as Array<{ reference_id: number }>;
    expect(groups).toHaveLength(2);

    const over = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts`)
      .set('Cookie', authCookie)
      .send({
        receipt_date: '2026-09-16',
        warehouse_id: warehouseId,
        items: [{ po_item_id: po.poItemId, received_quantity: 1 }],
      });
    // Receiving beyond the ordered quantity is refused, so no further
    // receipt can inflate the GL past the PO value. The controller
    // surfaces the model's guard as a 500 rather than a 400, so accept
    // either rejection code — what matters is that no extra GL line was
    // posted.
    expect([400, 500]).toContain(over.status);
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 1000, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 1000, 2);

    assertInvariants();
  });

  it('scenario 5: receipt then payment settles AP to zero', async () => {
    const apBefore = accountBalance(AP_CODE);
    const supplierBefore = supplierBalanceTotal();
    const po = await createSubmittedPo(5, 100); // 500

    await receive(po, 5);
    await paySupplier(po.poId, 500);

    // The receipt credited both ledgers by 500; the payment's PAYMENT row
    // credits the ledger and debits GL AP by 500, so both return to their
    // pre-PO level and the PO closes.
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore, 2);
    expect(supplierBalanceTotal()).toBeCloseTo(supplierBefore, 2);

    const status = db.prepare('SELECT status FROM purchase_orders WHERE id = ?').get(po.poId) as { status: string };
    expect(['Closed', 'Completed']).toContain(status.status);

    assertInvariants();
  });

  it('scenario 6: receipt then sale keeps GL inventory == batch value', async () => {
    // Isolated item so the sale consumes only this PO's batch.
    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `C3GL-S6-${Date.now()}`, item_name: 'C3 GL S6 Item' });
    expect(item.status).toBe(201);
    const saleItemId = item.body.id as number;
    db.prepare(`UPDATE items SET current_stock = 0, standard_cost = 0 WHERE id = ?`).run(saleItemId);

    const create = await request(app)
      .post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-09-15',
        items: [{ item_id: saleItemId, quantity: 10, unit_price: 100 }],
      });
    expect(create.status).toBe(201);
    const poId = create.body.id as number;
    await request(app).post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie).send({ status: 'Submitted' });
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };

    const receipt = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send({
        receipt_date: '2026-09-16',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItem.id, received_quantity: 10 }],
      });
    expect([200, 201]).toContain(receipt.status);

    const invAfterReceipt = accountBalance(INVENTORY_CODE);
    const batchAfterReceipt = batchValue();

    await sell(saleItemId, 3);

    // Inventory dropped by the 300 of actual FIFO cost, and the GL still
    // equals the remaining batch value (700).
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invAfterReceipt - 300, 2);
    expect(batchValue()).toBeCloseTo(batchAfterReceipt - 300, 2);
    assertInvariants();
  });

  it('scenario 7: voiding a receipt reverses exactly that receipt GL group', async () => {
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);
    const po = await createSubmittedPo(10, 100);

    const receiptId = await receive(po, 10);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 1000, 2);

    const res = await request(app)
      .post(`/api/purchase-orders/${po.poId}/receipts/${receiptId}/void`)
      .set('Cookie', authCookie)
      .send({ reason: 'wrong delivery' });
    expect(res.status).toBe(200);

    // The receipt's group is voided (lines retained, voided = 1) and the
    // GL returns to its pre-receipt level.
    const active = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines
      WHERE reference_type = 'GOODS_RECEIPT' AND reference_id = ? AND voided = 0
    `).get(receiptId) as { n: number };
    expect(active.n).toBe(0);

    const voided = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines
      WHERE reference_type = 'GOODS_RECEIPT' AND reference_id = ? AND voided = 1
    `).get(receiptId) as { n: number };
    expect(voided.n).toBe(2);

    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore, 2);

    assertInvariants();
  });

  it('scenario 8: cancelling a partially received PO keeps the received goods on the books', async () => {
    const supplierBefore = supplierBalanceTotal();
    const invBefore = accountBalance(INVENTORY_CODE);
    const apBefore = accountBalance(AP_CODE);
    const po = await createSubmittedPo(10, 100); // total 1000
    await receive(po, 4); // 400 received, 600 still outstanding

    const cancel = await request(app)
      .post(`/api/purchase-orders/${po.poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Cancelled' });
    expect(cancel.status).toBe(200);

    // ACC-16: cancellation writes NO ledger rows at all. There was no
    // submission debit to reverse; the received 400 keeps its
    // receipt-time AP; the unreceived 600 was never a liability.
    const rows = db.prepare(`
      SELECT transaction_type, debit, credit
      FROM supplier_ledger
      WHERE reference_no = ? AND voided = 0
      ORDER BY id
    `).all(po.poNo) as Array<{ transaction_type: string; debit: number; credit: number }>;
    expect(rows).toHaveLength(0);

    // Supplier and GL both retain exactly the received 400.
    expect(supplierBalanceTotal()).toBeCloseTo(supplierBefore + 400, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore + 400, 2);
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(invBefore + 400, 2);

    assertInvariants();
  });

  it('scenario 9: cancelling a fully-unreceived PO moves no ledger at all', async () => {
    const supplierBefore = supplierBalanceTotal();
    const apBefore = accountBalance(AP_CODE);
    const po = await createSubmittedPo(8, 50); // total 400, nothing received

    const cancel = await request(app)
      .post(`/api/purchase-orders/${po.poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Cancelled' });
    expect(cancel.status).toBe(200);

    // Nothing was received and nothing was ever posted, so neither the
    // GL nor the supplier ledger moves.
    const rows = db.prepare(`
      SELECT transaction_type, debit, credit
      FROM supplier_ledger
      WHERE reference_no = ? AND voided = 0 ORDER BY id
    `).all(po.poNo) as Array<{ transaction_type: string; debit: number; credit: number }>;
    expect(rows).toHaveLength(0);

    expect(supplierBalanceTotal()).toBeCloseTo(supplierBefore, 2);
    expect(accountBalance(AP_CODE)).toBeCloseTo(apBefore, 2);
    assertInvariants();
  });

  it('invariant 10: GL inventory equals the value represented by batches', () => {
    expect(accountBalance(INVENTORY_CODE)).toBeCloseTo(batchValue(), 2);
  });

  it('invariant 10: GL AP equals the supplier ledger exactly (ACC-16)', () => {
    // With no commitment postings, the two ledgers agree at every
    // instant — not only when goods land. This is the identity the old
    // submission debit broke.
    expect(accountBalance(AP_CODE)).toBeCloseTo(supplierBalanceTotal(), 2);
  });
});

describe('C3: receipt GL posting is stamped on the stock movement', () => {
  it('marks the PURCHASE movement financial_posted with the posted value', async () => {
    const po = await createSubmittedPo(5, 40); // 200
    await receive(po, 5);

    const movements = db.prepare(`
      SELECT financial_posted, financial_value
      FROM stock_movements
      WHERE item_id = ? AND movement_type = 'PURCHASE'
      ORDER BY id
    `).all(itemId) as Array<{ financial_posted: number; financial_value: number | null }>;
    const last = movements[movements.length - 1];
    expect(last.financial_posted).toBe(1);
    expect(Number(last.financial_value)).toBeCloseTo(200, 2);
  });
});
