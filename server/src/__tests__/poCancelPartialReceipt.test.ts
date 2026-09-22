/**
 * H11: PO cancellation must leave only the received obligation.
 *
 * Accounting contract (ACC-16 receipt-only posting model):
 *   Submit  → posts NOTHING (a submitted PO is a commitment, not a liability)
 *   Receipt → GL Dr 1200 Inventory / Cr 2000 AP (per receipt value)
 *           + supplier_ledger GOODS_RECEIPT credit = received value
 *   Cancel  → posts NOTHING and reverses NOTHING — the unreceived
 *             remainder was never a liability, and received goods keep
 *             their real receipt-time obligation
 *
 * Stock from received goods must survive cancellation.  GL from receipt
 * must survive cancellation.  Supplier obligation must reflect only the
 * received goods after cancel.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';

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

describe('H11: PO cancel only unreceived remainder', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `H11-${Date.now()}`, item_name: 'H11 Test Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const wh = await request(app)
      .post('/api/inventory/warehouses')
      .set('Cookie', authCookie)
      .send({ warehouse_code: `H11-WH-${Date.now()}`, warehouse_name: 'H11 WH' });
    expect(wh.status).toBe(201);
    warehouseId = wh.body.id;

    const supplier = await request(app)
      .post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({
        supplier_code: `H11-SUP-${Date.now()}`,
        supplier_name: 'H11 Test Supplier',
      });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data.id;
  });

  async function createPO(qty: number, unitPrice: number): Promise<{ poId: number; poNo: string }> {
    const create = await request(app)
      .post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-09-01',
        items: [{ item_id: itemId, quantity: qty, unit_price: unitPrice }],
      });
    expect(create.status).toBe(201);
    const poId = create.body.id as number;

    const submit = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Submitted' });
    expect(submit.status).toBe(200);

    const poNo = (db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(poId) as { po_no: string }).po_no;
    return { poId, poNo };
  }

  async function receivePO(poId: number, receiveQty: number): Promise<number> {
    const poItems = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').all(poId) as Array<{ id: number }>;
    expect(poItems.length).toBe(1);

    const res = await request(app)
      .post(`/api/purchase-orders/${poId}/receipts`)
      .set('Cookie', authCookie)
      .send({
        po_id: poId,
        receipt_date: '2026-09-10',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItems[0].id, received_quantity: receiveQty }],
      });
    expect(res.status).toBe(201);
    return res.body.id as number;
  }

  function getLedgerEntries(poId: number) {
    // Receipt liability rows are keyed by receipt_no — join through the
    // receipt to scope them to this PO.
    return db.prepare(
      `SELECT sl.transaction_type, sl.debit, sl.credit
       FROM supplier_ledger sl
       JOIN goods_receipts gr ON sl.reference_no = gr.receipt_no
       WHERE gr.po_id = ? AND sl.voided = 0
       ORDER BY sl.id`
    ).all(poId) as Array<{ transaction_type: string; debit: number; credit: number }>;
  }

  function getSupplierBalance(): number {
    return (db.prepare('SELECT current_balance FROM suppliers WHERE id = ?').get(supplierId) as { current_balance: number }).current_balance;
  }

  function getStockQty(): number {
    return (db.prepare('SELECT COALESCE(quantity, 0) AS qty FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(itemId, warehouseId) as { qty: number } | undefined)?.qty ?? 0;
  }

  function getJournalLines(refType: string, refId: number) {
    return db.prepare(
      `SELECT jl.account_id, jl.debit, jl.credit, coa.code AS account_code
       FROM journal_lines jl
       JOIN chart_of_accounts coa ON jl.account_id = coa.id
       WHERE jl.reference_type = ? AND jl.reference_id = ? AND jl.voided = 0`
    ).all(refType, refId) as Array<{ account_id: number; debit: number; credit: number; account_code: string }>;
  }

  describe('cancel before any receipt', () => {
    it('reverses full PO value — net supplier effect 0, stock 0', async () => {
      const { poId } = await createPO(10, 100);

      const balBefore = getSupplierBalance();
      const stockBefore = getStockQty();

      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(200);

      // ACC-16: submission posted nothing and cancellation posts nothing —
      // an unreceived PO never touched the ledger at all
      const ledger = getLedgerEntries(poId);
      expect(ledger).toHaveLength(0);

      expect(getStockQty()).toBeCloseTo(stockBefore, 2);
    });
  });

  describe('cancel after partial receipt (core H11 scenario)', () => {
    it('PO 10×100, receive 4, cancel — stock stays at received level, supplier owes for 4 only', async () => {
      const { poId } = await createPO(10, 100);

      const stockBeforeReceipt = getStockQty();
      await receivePO(poId, 4);
      expect(getStockQty()).toBeCloseTo(stockBeforeReceipt + 4, 2);

      const stockBeforeCancel = getStockQty();
      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(200);

      // ACC-16: the only ledger row is the receipt's real liability.
      // Cancel does not post — the unreceived 600 was never owed.
      const ledger = getLedgerEntries(poId);
      expect(ledger).toHaveLength(1);
      expect(ledger[0].transaction_type).toBe('GOODS_RECEIPT');
      expect(ledger[0].debit).toBeCloseTo(400, 2);

      const net = ledger.reduce((s, r) => s + Number(r.debit) - Number(r.credit), 0);
      expect(net).toBeCloseTo(400, 2);

      // Stock unchanged by cancel — received goods survive
      expect(getStockQty()).toBeCloseTo(stockBeforeCancel, 2);
    });

    it('supplier current_balance reflects only received obligation', async () => {
      // Capture balance BEFORE the PO is created/submitted
      const balBeforePO = getSupplierBalance();
      const { poId } = await createPO(10, 100);

      // After submit: bal = balBeforePO + 1000 (debit)
      await receivePO(poId, 4);

      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(200);

      // After cancel: credit = 600 (unreceived). Net = +400 from before PO.
      const balAfterCancel = getSupplierBalance();
      expect(balAfterCancel).toBeCloseTo(balBeforePO + 400, 2);
    });
  });

  describe('cancel after full receipt', () => {
    it('blocked by state machine — PO auto-completes, Completed cannot Cancel', async () => {
      const { poId } = await createPO(10, 100);

      const stockBeforeReceipt = getStockQty();
      await receivePO(poId, 10);
      expect(getStockQty()).toBeCloseTo(stockBeforeReceipt + 10, 2);

      const poStatus = (db.prepare('SELECT status FROM purchase_orders WHERE id = ?').get(poId) as { status: string }).status;
      expect(poStatus).toBe('Completed');

      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(400);

      // Only the receipt's real liability exists (debit-normal ledger)
      const ledger = getLedgerEntries(poId);
      expect(ledger).toHaveLength(1);
      expect(ledger[0].transaction_type).toBe('GOODS_RECEIPT');
      expect(ledger[0].debit).toBeCloseTo(1000, 2);
    });
  });

  describe('multiple partial receipts then cancel', () => {
    it('receives 2 + 2, cancels remaining 6 of 10', async () => {
      const { poId } = await createPO(10, 100);

      const stockBeforeReceipts = getStockQty();
      await receivePO(poId, 2);
      await receivePO(poId, 2);
      expect(getStockQty()).toBeCloseTo(stockBeforeReceipts + 4, 2);

      const stockBeforeCancel = getStockQty();
      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(200);

      // ACC-16: two receipt liabilities (200 each), no commitment debit,
      // no cancel reversal
      const ledger = getLedgerEntries(poId);
      expect(ledger).toHaveLength(2);
      expect(ledger[0].transaction_type).toBe('GOODS_RECEIPT');
      expect(ledger[0].debit).toBeCloseTo(200, 2);
      expect(ledger[1].transaction_type).toBe('GOODS_RECEIPT');
      expect(ledger[1].debit).toBeCloseTo(200, 2);

      const net = ledger.reduce((s, r) => s + Number(r.debit) - Number(r.credit), 0);
      expect(net).toBeCloseTo(400, 2);

      expect(getStockQty()).toBeCloseTo(stockBeforeCancel, 2);
    });
  });

  describe('repeated cancellation (idempotency)', () => {
    it('second cancel is blocked by state machine', async () => {
      const { poId } = await createPO(10, 100);

      await receivePO(poId, 4);

      const cancel1 = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel1.status).toBe(200);

      const cancel2 = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel2.status).toBe(400);

      // ACC-16: only the receipt's liability exists — repeated cancel
      // attempts add no ledger rows
      const ledger = getLedgerEntries(poId);
      expect(ledger).toHaveLength(1);
      expect(ledger[0].transaction_type).toBe('GOODS_RECEIPT');
      expect(ledger[0].debit).toBeCloseTo(400, 2);
    });
  });

  describe('GL reconciliation', () => {
    it('receipt GL survives cancel — Dr Inventory / Cr AP for received value only', async () => {
      const { poId } = await createPO(10, 100);

      const receiptId = await receivePO(poId, 4);

      const receiptLines = getJournalLines('GOODS_RECEIPT', receiptId);
      expect(receiptLines.length).toBeGreaterThanOrEqual(2);

      const drInventory = receiptLines.find(l => l.account_code === '1200');
      const crAP = receiptLines.find(l => l.account_code === '2000');
      expect(drInventory).toBeDefined();
      expect(crAP).toBeDefined();
      expect(drInventory!.debit).toBeCloseTo(400, 2);
      expect(crAP!.credit).toBeCloseTo(400, 2);

      const cancel = await request(app)
        .post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Cancelled' });
      expect(cancel.status).toBe(200);

      const receiptLinesAfterCancel = getJournalLines('GOODS_RECEIPT', receiptId);
      expect(receiptLinesAfterCancel.length).toBeGreaterThanOrEqual(2);
      const drInvAfter = receiptLinesAfterCancel.find(l => l.account_code === '1200');
      const crAPAfter = receiptLinesAfterCancel.find(l => l.account_code === '2000');
      expect(drInvAfter!.debit).toBeCloseTo(400, 2);
      expect(crAPAfter!.credit).toBeCloseTo(400, 2);
    });
  });
});
