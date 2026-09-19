/**
 * Expired-stock plan Phase 3 — write-off endpoint integration tests.
 *
 * Covers POST /api/inventory/expired/write-off:
 *   1. Happy path (batch already at EXPIRED): 200, WRITE_OFF movement,
 *      batch zeroed, GL entry Dr 7201 / Cr 1200 at batch cost
 *   2. Auto-transfer path: expired batch still at MAIN is transferred to
 *      EXPIRED first (paired EXPIRY_TRANSFER legs), then written off
 *   3. Idempotency: re-writing off the same batch fails
 *   4. Validation: bad batchIds, empty/long reason, invalid glAccount,
 *      account outside the 7200 hierarchy, non-expired batch
 *   5. Partial success: one good + one bad batch → 200 with per-batch errors
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

function expiredWhId(): number {
  return (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
}

function seedExpiredBatch(opts: {
  batchNo: string; qty: number; cost: number; warehouseId?: number; expiry?: string;
}): number {
  const wh = opts.warehouseId ?? expiredWhId();
  // Dedicated item per batch (created_by references the admin user row).
  const item = db.prepare(`
    INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active,created_by)
    VALUES (?, 'Write-off Test Item', 'Nos', ?, 1, 1,
      (SELECT id FROM users ORDER BY id LIMIT 1))
  `).run(opts.batchNo, opts.cost);
  const r = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
    VALUES (?,?,?,'PURCHASE',1,?,?,?, '2026-01-01', ?)
  `).run(
    opts.batchNo,
    item.lastInsertRowid as number,
    wh, opts.qty, opts.qty, opts.cost, opts.expiry ?? '2026-01-01'
  );
  // Mirror the stock_balances row the transfer/GRN flow would have created
  // (INV-21 CHECK forbids negative balances, so the WRITE_OFF's negative
  // leg needs this positive row to draw down).
  db.prepare(`
    INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (?,?,?)
    ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = quantity + excluded.quantity
  `).run(item.lastInsertRowid as number, wh, opts.qty);
  return r.lastInsertRowid as number;
}

function lossBalance(code: string): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit),0) - COALESCE(SUM(jl.credit),0) AS bal
    FROM journal_lines jl
    JOIN chart_of_accounts c ON c.id = jl.account_id
    WHERE c.code = ? AND jl.reference_type = 'WRITE_OFF' AND jl.voided = 0
  `).get(code) as { bal: number };
  return row.bal;
}

describe('POST /api/inventory/expired/write-off', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  it('writes off a batch at EXPIRED: movement, zeroed batch, GL Dr 7201 / Cr 1200', async () => {
    const batchId = seedExpiredBatch({ batchNo: `WO-ATDEST-${Date.now()}`, qty: 10, cost: 4 });

    const res = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [batchId], reason: 'damaged past expiry', glAccount: '7201' });

    expect(res.status).toBe(200);
    expect(res.body.data[0].error).toBeUndefined();
    expect(res.body.data[0].value).toBe(40); // 10 × 4
    expect(res.body.data[0].transferred).toBe(false);

    // Batch zeroed; WRITE_OFF movement recorded with structured remarks
    const batch = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(batchId) as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBe(0);
    const mv = db.prepare(`
      SELECT movement_type, quantity, remarks, financial_posted, financial_value, journal_entry_id
      FROM stock_movements WHERE batch_id = ? AND movement_type = 'WRITE_OFF'
    `).get(batchId) as { quantity: number; remarks: string; financial_posted: number; financial_value: number; journal_entry_id: number };
    expect(mv.quantity).toBe(-10);
    expect(mv.remarks).toContain('[WRITE_OFF]');
    expect(mv.remarks).toContain('gl=7201');
    expect(mv.financial_posted).toBe(1);
    expect(mv.journal_entry_id).toBeGreaterThan(0);

    // GL: loss account 7201 debited 40, inventory asset 1200 credited 40
    const lines = db.prepare(`
      SELECT c.code, jl.debit, jl.credit FROM journal_lines jl
      JOIN chart_of_accounts c ON c.id = jl.account_id
      WHERE jl.journal_entry_id = ? ORDER BY jl.debit DESC
    `).all(mv.journal_entry_id) as Array<{ code: string; debit: number; credit: number }>;
    expect(lines).toHaveLength(2);
    expect(lines[0].code).toBe('7201');
    expect(lines[0].debit).toBe(40);
    expect(lines[1].code).toBe('1200');
    expect(lines[1].credit).toBe(40);
  });

  it('auto-transfers an expired batch still at MAIN before writing it off', async () => {
    const mainWh = (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'WH-001'`).get() as { id: number }).id;
    const batchId = seedExpiredBatch({ batchNo: `WO-TRANSFER-${Date.now()}`, qty: 5, cost: 6, warehouseId: mainWh });

    const res = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [batchId], reason: 'expired in main warehouse', glAccount: '7201' });

    expect(res.status).toBe(200);
    expect(res.body.data[0].transferred).toBe(true);

    // Source batch zeroed; WRITE_OFF landed on the mirrored batch at EXPIRED
    const src = db.prepare(`SELECT quantity_remaining FROM stock_batches WHERE id = ?`).get(batchId) as { quantity_remaining: number };
    expect(src.quantity_remaining).toBe(0);
    const expiredWh = expiredWhId();
    const mirror = db.prepare(
      `SELECT id, quantity_remaining FROM stock_batches WHERE source_type = 'TRANSFER' AND warehouse_id = ? ORDER BY id DESC LIMIT 1`
    ).get(expiredWh) as { id: number; quantity_remaining: number };
    const wo = db.prepare(`SELECT movement_type FROM stock_movements WHERE batch_id = ? AND movement_type = 'WRITE_OFF'`).get(mirror.id);
    expect(wo).toBeDefined();

    // Both movement types exist for this flow
    const legs = db.prepare(
      `SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type = 'EXPIRY_TRANSFER'`
    ).get() as { n: number };
    expect(legs.n).toBeGreaterThanOrEqual(2);
  });

  it('refuses to write off the same batch twice (idempotency)', async () => {
    const batchId = seedExpiredBatch({ batchNo: `WO-IDEmpotency-${Date.now()}`, qty: 3, cost: 2 });

    const first = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [batchId], reason: 'first', glAccount: '7201' });
    expect(first.status).toBe(200);

    const second = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [batchId], reason: 'second', glAccount: '7201' });
    expect(second.status).toBe(400); // all failed → 400 with per-batch errors
    expect(second.body.data[0].error).toContain('already written off');
  });

  it('validates body: batchIds, reason, glAccount hierarchy', async () => {
    const base = { batchIds: [1], reason: 'ok', glAccount: '7201' };

    // bad batchIds
    for (const batchIds of [[], [0], [-1], ['x'], 'nope']) {
      const res = await request(app)
        .post('/api/inventory/expired/write-off')
        .set('Cookie', authCookie)
        .send({ ...base, batchIds });
      expect(res.status).toBe(400);
    }

    // bad reason
    for (const reason of ['', '   ', 'x'.repeat(501), 42]) {
      const res = await request(app)
        .post('/api/inventory/expired/write-off')
        .set('Cookie', authCookie)
        .send({ ...base, reason });
      expect(res.status).toBe(400);
    }

    // bad glAccount: not in whitelist / not under 7200 / nonexistent
    for (const glAccount of ['5401', '1200', '9999', 7201]) {
      const res = await request(app)
        .post('/api/inventory/expired/write-off')
        .set('Cookie', authCookie)
        .send({ ...base, glAccount });
      expect(res.status).toBe(400);
    }
  });

  it('rejects a not-yet-expired batch with a per-batch error', async () => {
    const batchId = seedExpiredBatch({
      batchNo: `WO-FUTURE-${Date.now()}`, qty: 2, cost: 1, expiry: '2099-01-01',
    });

    const res = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [batchId], reason: 'not expired yet', glAccount: '7201' });

    expect(res.status).toBe(400);
    expect(res.body.data[0].error).toContain('not expired');
  });

  it('partial success: good batch written off, bad batch reported with error', async () => {
    const good = seedExpiredBatch({ batchNo: `WO-GOOD-${Date.now()}`, qty: 4, cost: 3 });
    const missing = 999999999;

    const res = await request(app)
      .post('/api/inventory/expired/write-off')
      .set('Cookie', authCookie)
      .send({ batchIds: [good, missing], reason: 'bulk cleanup', glAccount: '7202' });

    expect(res.status).toBe(200);
    expect(res.body.message).toContain('1 of 2');
    const byId = new Map<number, { batchId: number; movementNo?: string; error?: string }>(
      (res.body.data as Array<{ batchId: number; movementNo?: string; error?: string }>).map(d => [d.batchId, d])
    );
    expect(byId.get(good)?.movementNo).toBeDefined();
    expect(byId.get(missing)?.error).toContain('not found');
    // GL posted under 7202 (damaged goods)
    const bal = lossBalance('7202');
    expect(bal).toBeGreaterThan(0);
  });
});
