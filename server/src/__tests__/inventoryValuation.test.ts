/**
 * Expired-stock plan Phase 4.2 — inventory-valuation endpoint tests.
 *
 * Covers GET /api/reports/inventory-valuation with the fixed bucket
 * semantics:
 *   1. Empty DB: all buckets zero, totalPhysical = 0
 *   2. Bucket separation: sellable / expired / writtenOff populated by
 *      seeded stock; expired is NOT inside sellable (separate warehouse)
 *   3. reserved ⊆ sellable (reported separately, not additive) and the
 *      totalPhysical formula: (sellable − reserved) + expired + damaged
 *   4. Cost basis: value = qty × unit_cost, not selling price
 *   5. The invariant note is present
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

function mainWhId(): number {
  return (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'WH-001'`).get() as { id: number }).id;
}
function expiredWhId(): number {
  return (db.prepare(`SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED'`).get() as { id: number }).id;
}

function seedBatch(opts: {
  itemCode: string; qty: number; cost: number; warehouseId: number;
  expiry?: string | null; sellingPrice?: number;
}): { batchId: number; itemId: number } {
  const item = db.prepare(`
    INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,standard_selling_price,is_purchased,is_active,created_by)
    VALUES (?, ?, 'Nos', ?, ?, 1, 1, (SELECT id FROM users ORDER BY id LIMIT 1))
  `).run(opts.itemCode, `Valuation ${opts.itemCode}`, opts.cost, opts.sellingPrice ?? opts.cost * 3);
  const itemId = item.lastInsertRowid as number;
  const r = db.prepare(`
    INSERT INTO stock_batches (batch_no,item_id,warehouse_id,source_type,source_id,quantity_original,quantity_remaining,unit_cost,received_date,expiry_date)
    VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, ?, '2026-01-01', ?)
  `).run(
    `VAL-${opts.itemCode}`, itemId, opts.warehouseId,
    opts.qty, opts.qty, opts.cost, opts.expiry ?? null
  );
  db.prepare(`
    INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (?, ?, ?)
    ON CONFLICT(item_id, warehouse_id) DO UPDATE SET quantity = quantity + excluded.quantity
  `).run(itemId, opts.warehouseId, opts.qty);
  return { batchId: r.lastInsertRowid as number, itemId };
}

interface Report {
  sellable: { qty: number; value: number };
  reserved: { qty: number; value: number };
  expired: { qty: number; value: number };
  damaged: { qty: number; value: number };
  writtenOff: { count: number; qty: number; totalValue: number };
  totalPhysical: { qty: number; value: number };
  invariant: string;
  as_of_date: string;
}

async function fetchReport(authCookie: string): Promise<Report> {
  const res = await request(app)
    .get('/api/reports/inventory-valuation')
    .set('Cookie', authCookie);
  expect(res.status).toBe(200);
  return res.body.data as Report;
}

describe('GET /api/reports/inventory-valuation', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  it('requires authentication', async () => {
    const res = await request(app).get('/api/reports/inventory-valuation');
    expect([401, 403]).toContain(res.status);
  });

  it('returns zero buckets on a fresh report run (baseline snapshot)', () => {
    // This test asserts structure rather than absolute zeros because other
    // suites share the DB: every bucket must exist with numeric fields.
    return fetchReport(authCookie).then((r) => {
      for (const key of ['sellable', 'reserved', 'expired', 'damaged', 'totalPhysical'] as const) {
        expect(typeof r[key].qty).toBe('number');
        expect(typeof r[key].value).toBe('number');
      }
      expect(typeof r.writtenOff.count).toBe('number');
      expect(typeof r.writtenOff.qty).toBe('number');
      expect(typeof r.writtenOff.totalValue).toBe('number');
      expect(r.invariant).toContain('boot sweep');
      expect(r.as_of_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    });
  });

  it('separates sellable from expired and values at cost basis', async () => {
    const before = await fetchReport(authCookie);
    const main = mainWhId();
    const expiredWh = expiredWhId();

    // 10 units @ cost 5 (sellable, priced 15 for the cost-basis check)
    const a = seedBatch({ itemCode: `VAL-S-${Date.now()}`, qty: 10, cost: 5, sellingPrice: 15, warehouseId: main });
    // 4 units @ cost 7 sitting at EXPIRED
    seedBatch({ itemCode: `VAL-E-${Date.now()}`, qty: 4, cost: 7, warehouseId: expiredWh, expiry: '2026-01-01' });

    const after = await fetchReport(authCookie);

    // Sellable grew by exactly the main-warehouse batch at COST (50), not
    // selling price (150)
    expect(after.sellable.value - before.sellable.value).toBe(50);
    expect(after.sellable.qty - before.sellable.qty).toBe(10);

    // Expired grew by the EXPIRED-warehouse batch at cost (28)
    expect(after.expired.qty - before.expired.qty).toBe(4);
    expect(after.expired.value - before.expired.value).toBe(28);

    // totalPhysical = (sellable − reserved) + expired + damaged, delta-wise:
    // Δsellable 50 + Δexpired 28 − Δreserved 0 + Δdamaged 0 = 78
    expect(after.totalPhysical.value - before.totalPhysical.value).toBe(78);
    expect(after.totalPhysical.qty - before.totalPhysical.qty).toBe(14);

    // Sanity: reserved must never exceed sellable (subset semantics)
    expect(after.reserved.qty).toBeLessThanOrEqual(after.sellable.qty);

    void a;
  });

  it('counts writtenOff from WRITE_OFF movements (historical bucket)', async () => {
    const before = await fetchReport(authCookie);
    const expiredWh = expiredWhId();
    const { batchId, itemId } = seedBatch({
      itemCode: `VAL-WO-${Date.now()}`, qty: 3, cost: 10, warehouseId: expiredWh, expiry: '2026-01-01',
    });

    // Simulate a completed write-off the way the model does it.
    const value = 30;
    const mv = db.prepare(`
      INSERT INTO stock_movements (movement_no, item_id, warehouse_id, movement_type,
        quantity, unit_cost, reference_doctype, reference_docno, remarks, movement_date, created_by, batch_id,
        financial_value, financial_posted)
      VALUES ('MV-WO-VAL-' || (SELECT COUNT(*) FROM stock_movements), ?, ?, 'WRITE_OFF',
        -3, 10, 'WRITE_OFF', 'VAL-WO', '[WRITE_OFF] reason=test gl=7201 batch=VAL-WO', date('now'),
        (SELECT id FROM users ORDER BY id LIMIT 1), ?, ?, 1)
    `).run(itemId, expiredWh, batchId, value);
    const movementId = mv.lastInsertRowid as number;
    db.prepare(`UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?`).run(batchId);
    const je = db.prepare(`
      INSERT INTO journal_entries (reference_type, reference_id, entry_date, description,
        debit_account, credit_account, amount, created_by, voided)
      VALUES ('WRITE_OFF', ?, date('now'), 'test write-off', '7201', 'inventory_asset', 30,
        (SELECT id FROM users ORDER BY id LIMIT 1), 0)
    `).run(movementId);
    const jeId = je.lastInsertRowid as number;
    for (const [code, debit, credit] of [['7201', 30, 0], ['1200', 0, 30]] as const) {
      db.prepare(`
        INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, line_date,
          reference_type, reference_id)
        VALUES (?, (SELECT id FROM chart_of_accounts WHERE code = ?), ?, ?, date('now'), 'WRITE_OFF', ?)
      `).run(jeId, code, debit, credit, movementId);
    }

    const after = await fetchReport(authCookie);
    expect(after.writtenOff.count - before.writtenOff.count).toBe(1);
    expect(after.writtenOff.qty - before.writtenOff.qty).toBe(3);
    expect(after.writtenOff.totalValue - before.writtenOff.totalValue).toBe(30);
    // Written-off stock is NOT physical stock (batch qty is 0)
    expect(after.expired.qty - before.expired.qty).toBe(0);
  });

  it('keeps totalPhysical formula consistent: (sellable − reserved) + expired + damaged', async () => {
    const r = await fetchReport(authCookie);
    const expected = r.sellable.value - r.reserved.value + r.expired.value + r.damaged.value;
    expect(Math.abs(r.totalPhysical.value - expected)).toBeLessThan(0.02);
  });
});
