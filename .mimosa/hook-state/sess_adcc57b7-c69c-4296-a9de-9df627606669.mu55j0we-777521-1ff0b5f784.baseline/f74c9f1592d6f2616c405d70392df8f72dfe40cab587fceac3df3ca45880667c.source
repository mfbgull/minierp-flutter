/**
 * Reversal-rules Phase 4 regression tests — stock-transfer void primitive.
 *
 * Audit cases covered:
 *   1. Void restores source batch + source balance, drains destination
 *      mirrored batch + destination balance, and appends a TRANSFER_VOID
 *      reversal pair (append-only audit trail).
 *   2. Double void is rejected (idempotency guard).
 *   3. Voiding a transfer whose units were already consumed at the
 *      destination is refused (would drive stock negative).
 *   4. Voiding an unknown movement number is a 400, not a 500.
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

describe('Stock transfer void (Phase 4)', () => {
  let authCookie: string;
  let itemId: number;
  let fromWh: number;
  let toWh: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    fromWh = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    const whs = db.prepare('SELECT id FROM warehouses ORDER BY id').all() as Array<{ id: number }>;
    toWh = whs[1]?.id ?? fromWh;
    if (toWh === fromWh) {
      const created = await request(app)
        .post('/api/inventory/warehouses')
        .set('Cookie', authCookie)
        .send({ warehouse_code: `WH-TRFV-${Date.now()}`, warehouse_name: 'Transfer Void WH' });
      expect(created.status).toBe(201);
      toWh = created.body.data?.id ?? created.body.id;
    }

    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `TRFV-${Date.now()}`, item_name: 'Transfer Void Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    await request(app)
      .post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: fromWh,
        quantity: 20,
        unit_cost: 5,
        purchase_date: '2026-08-01',
        supplier_name: 'Transfer Void Supplier',
      });
  });

  async function createTransfer(quantity: number): Promise<string> {
    const res = await request(app)
      .post('/api/inventory/stock-transfers')
      .set('Cookie', authCookie)
      .send({ item_id: itemId, from_warehouse_id: fromWh, to_warehouse_id: toWh, quantity });
    expect(res.status).toBe(201);
    const outMovementNo = (db.prepare(`
      SELECT movement_no FROM stock_movements
      WHERE movement_type = 'TRANSFER' AND warehouse_id = ? AND item_id = ? AND quantity < 0
      ORDER BY id DESC LIMIT 1
    `).get(fromWh, itemId) as { movement_no: string }).movement_no;
    return outMovementNo;
  }

  function balances(): { src: number; dst: number } {
    const src = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, fromWh) as { quantity: number }).quantity;
    const dstRow = db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(itemId, toWh) as { quantity: number } | undefined;
    return { src, dst: dstRow?.quantity ?? 0 };
  }

  it('voids a transfer: restores source, drains destination, appends TRANSFER_VOID pair', async () => {
    const outMovementNo = await createTransfer(4);
    const afterTransfer = balances();
    expect(afterTransfer.src).toBe(16);
    expect(afterTransfer.dst).toBe(4);

    const res = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    // Balances back to pre-transfer state
    const afterVoid = balances();
    expect(afterVoid.src).toBe(20);
    expect(afterVoid.dst).toBe(0);

    // Batches: source layer restored, mirrored layer drained
    const coverage = (db.prepare(`
      SELECT
        (SELECT COALESCE(SUM(quantity_remaining), 0) FROM stock_batches WHERE item_id = ? AND warehouse_id = ?) AS src_cov,
        (SELECT COALESCE(SUM(quantity_remaining), 0) FROM stock_batches WHERE item_id = ? AND warehouse_id = ?) AS dst_cov
    `).get(itemId, fromWh, itemId, toWh) as { src_cov: number; dst_cov: number });
    expect(coverage.src_cov).toBeCloseTo(20, 3);
    expect(coverage.dst_cov).toBeCloseTo(0, 3);

    // Reversal pair exists, referencing the original movement (append-only)
    const reversals = db.prepare(`
      SELECT warehouse_id, quantity FROM stock_movements
      WHERE reference_doctype = 'TRANSFER_VOID' AND reference_docno = ?
      ORDER BY id
    `).all(outMovementNo) as Array<{ warehouse_id: number; quantity: number }>;
    expect(reversals.length).toBe(2);
    expect(reversals.find(r => r.warehouse_id === fromWh)?.quantity).toBe(4);
    expect(reversals.find(r => r.warehouse_id === toWh)?.quantity).toBe(-4);

    // Original movements retained (never deleted)
    const originalLegs = db.prepare(`
      SELECT COUNT(*) AS c FROM stock_movements
      WHERE movement_type = 'TRANSFER' AND (reference_docno = ? OR movement_no = ?)
    `).get(outMovementNo, outMovementNo) as { c: number };
    expect(originalLegs.c).toBe(2);
  });

  it('rejects a double void (idempotency guard)', async () => {
    const outMovementNo = await createTransfer(2);

    const first = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', authCookie);
    expect(first.status).toBe(200);

    const second = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', authCookie);
    expect(second.status).toBe(400);
    expect(second.body.error).toMatch(/already voided/i);

    // No extra reversal rows from the second attempt
    const reversals = db.prepare(`
      SELECT COUNT(*) AS c FROM stock_movements
      WHERE reference_doctype = 'TRANSFER_VOID' AND reference_docno = ?
    `).get(outMovementNo) as { c: number };
    expect(reversals.c).toBe(2);
  });

  it('refuses to void a transfer whose units were consumed at the destination', async () => {
    const outMovementNo = await createTransfer(5);

    // Sell the transferred units out of the destination warehouse via a
    // direct stock movement (SALE), draining the mirrored batch.
    const sale = await request(app)
      .post('/api/inventory/stock-movements')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: toWh,
        quantity: -5,
        movement_type: 'ADJUSTMENT',
        remarks: 'drain for void test',
      });
    expect(sale.status).toBe(201);

    const res = await request(app)
      .post(`/api/inventory/stock-transfers/${encodeURIComponent(outMovementNo)}/void`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/already consumed/i);

    // State untouched by the refused void
    const after = balances();
    expect(after.src).toBe(15);
    expect(after.dst).toBe(0);
  });

  it('returns 400 for an unknown movement number', async () => {
    const res = await request(app)
      .post('/api/inventory/stock-transfers/TRF-DOES-NOT-EXIST/void')
      .set('Cookie', authCookie);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/not found/i);
  });
});
