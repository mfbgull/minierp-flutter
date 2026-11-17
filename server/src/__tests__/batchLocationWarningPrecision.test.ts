/**
 * GLM cross-review of the R1/R2 warning path (0fc5d41a). Each test is a
 * targeted reproduction of one finding. A finding that does NOT reproduce is
 * reported as unconfirmed with the observed behaviour, not "fixed".
 *
 * Findings under test:
 *   F1  flag-ON DAMAGED warning keys on the CANDIDATE list, not actual takes.
 *   F2  same flaw on the legacy (flag-OFF) path.
 *   F3  R2 under-coverage is masked by a NON-SELLABLE bin's availability.
 *   F4  the pre-receipt (backdated) fallback returns warnings: [].
 *   F6  duplicate per-batch warnings (cosmetic).
 *
 * These drive the REAL routes: POST /api/invoices and POST /api/pos/sale.
 */
import { beforeAll, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { setFeatureEnabled } from '../utils/featureFlags';
import {
  createCustomer,
  createItem,
  getAuthCookie,
  nextIdemKey,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

const FLAG = 'feature_batch_locations';
const AS_OF = '2026-10-15';

let cookie = '';
let customerId = 0;
let warehouseA = 0;

beforeAll(async () => {
  cookie = await getAuthCookie();
  customerId = await createCustomer('Warning Precision Customer', cookie);
  warehouseA = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function secondLocation(wh: number, code: string): number {
  db.prepare(
    'INSERT OR IGNORE INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)',
  ).run(wh, code, code);
  return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
    .get(wh, code) as { id: number }).id;
}

function batchIdOf(itemId: number, wh: number): number {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id DESC LIMIT 1',
  ).get(itemId, wh) as { id: number }).id;
}

function upsertBin(
  batchId: number, locationId: number, physical: number, reserved: number, status: string | null,
): void {
  db.prepare(
    `INSERT INTO batch_stock_by_location
       (batch_id, location_id, quantity_physical, quantity_reserved, status_override)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(batch_id, location_id)
     DO UPDATE SET quantity_physical = excluded.quantity_physical,
                   quantity_reserved = excluded.quantity_reserved,
                   status_override = excluded.status_override`,
  ).run(batchId, locationId, physical, reserved, status);
}

function warningsOf(body: Record<string, unknown> | undefined): string[] {
  const w = (body?.warnings ?? (body?.data as Record<string, unknown> | undefined)?.warnings) as unknown;
  return Array.isArray(w) ? (w as string[]) : [];
}

async function sellInvoice(
  itemId: number, qty: number, tag: string, invoiceDate = AS_OF,
): Promise<{ status: number; warnings: string[] }> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`wp-${tag}`))
    .send({
      customer_id: customerId,
      invoice_date: invoiceDate,
      items: [{ item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
    });
  return { status: res.status, warnings: warningsOf(res.body) };
}

// ---------------------------------------------------------------------------
// F1 / F2 — the DAMAGED warning must follow the ACTUAL take, not the
// candidate list. An ACTIVE bin ordered first absorbs the whole take, so a
// DAMAGED bin that is never touched must not raise the warning.
// ---------------------------------------------------------------------------
for (const featureOn of [false, true]) {
  const label = featureOn ? 'flag ON' : 'flag OFF';
  describe(`F1/F2: DAMAGED warning follows the actual take (${label})`, () => {
    beforeAll(() => setFeatureEnabled(db, FLAG, featureOn));

    it(`F1: ACTIVE bin covers the take, DAMAGED bin untouched -> NO damaged warning (${label})`, async () => {
      const itemId = await createItem(`F1 ${label}`, cookie);
      await purchaseStock(itemId, warehouseA, 15, 40, cookie, AS_OF);
      const batchId = batchIdOf(itemId, warehouseA);
      const activeLoc = defaultLocation(warehouseA); // created FIRST -> ordered first
      const damagedLoc = secondLocation(warehouseA, `F1D-${itemId}`);
      upsertBin(batchId, activeLoc, 10, 0, 'ACTIVE');
      upsertBin(batchId, damagedLoc, 5, 0, 'DAMAGED');

      const { status, warnings } = await sellInvoice(itemId, 3, `f1-${featureOn}`);

      expect(status).toBe(201);
      // Every unit came from the ACTIVE bin; nothing damaged was sold.
      expect(JSON.stringify(warnings)).not.toMatch(/damag/i);
    });

    it(`F2: take spills INTO the DAMAGED bin -> damaged warning present (${label})`, async () => {
      const itemId = await createItem(`F2 ${label}`, cookie);
      await purchaseStock(itemId, warehouseA, 15, 40, cookie, AS_OF);
      const batchId = batchIdOf(itemId, warehouseA);
      const activeLoc = defaultLocation(warehouseA);
      const damagedLoc = secondLocation(warehouseA, `F2D-${itemId}`);
      upsertBin(batchId, activeLoc, 2, 0, 'ACTIVE');
      upsertBin(batchId, damagedLoc, 13, 0, 'DAMAGED');

      const { status, warnings } = await sellInvoice(itemId, 5, `f2-${featureOn}`);

      expect(status).toBe(201);
      // 2 from ACTIVE, 3 from DAMAGED -> the warning is genuine.
      expect(JSON.stringify(warnings)).toMatch(/damag/i);
    });
  });
}

// ---------------------------------------------------------------------------
// F3 — a NON-SELLABLE bin must not mask the R2 under-coverage warning.
// ---------------------------------------------------------------------------
describe('F3: R2 under-coverage is not masked by a non-sellable bin', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('F3: sellable available < take while a BLOCKED bin inflates the sum -> warn', async () => {
    const itemId = await createItem('F3 masked item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const activeLoc = defaultLocation(warehouseA);
    const blockedLoc = secondLocation(warehouseA, `F3B-${itemId}`);
    // Master 10. Sellable (ACTIVE) available = 2. BLOCKED available = 5.
    // Sell 3: the ACTIVE bin covers only 2 -> a 1-unit mirror shortfall.
    // A naive sum (2 + 5 = 7) is >= 3 and hides the shortfall.
    upsertBin(batchId, activeLoc, 2, 0, 'ACTIVE');
    upsertBin(batchId, blockedLoc, 5, 0, 'BLOCKED');

    const { status, warnings } = await sellInvoice(itemId, 3, 'f3');

    expect(status).toBe(201);
    expect(JSON.stringify(warnings)).toMatch(/available/i);
  });
});

// ---------------------------------------------------------------------------
// F4 — the backdated (pre-receipt) fallback must not sell damaged stock
// silently.
// ---------------------------------------------------------------------------
describe('F4: the pre-receipt fallback still carries the damaged warning', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('F4: a backdated sale that drains a DAMAGED bin warns (flag OFF)', async () => {
    const itemId = await createItem('F4 backdated item', cookie);
    // Stock received AFTER the sale date, so the as-of position is empty and
    // the fallback fires.
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, '2026-10-20');
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const { status, warnings } = await sellInvoice(itemId, 1, 'f4', '2026-10-15');

    expect(status).toBe(201);
    expect(JSON.stringify(warnings)).toMatch(/damag/i);
  });
});

// ---------------------------------------------------------------------------
// F5 — an idempotent replay must not silently drop the original warnings.
// ---------------------------------------------------------------------------
describe('F5: an idempotent replay preserves the warnings', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('F5: a retried POS sale with the same key still warns about damaged stock', async () => {
    const itemId = await createItem('F5 replay item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const key = nextIdemKey('f5-replay');
    const payload = {
      warehouse_id: warehouseA,
      sale_date: AS_OF,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
      cash_received: 1000,
    };
    const first = await request(app)
      .post('/api/pos/sale').set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(first.status).toBe(201);
    expect(JSON.stringify(warningsOf(first.body))).toMatch(/damag/i);

    const retry = await request(app)
      .post('/api/pos/sale').set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(retry.status).toBe(201);
    expect(JSON.stringify(warningsOf(retry.body))).toMatch(/damag/i);
  });

  it('F5: the CANONICAL invoice route also replays its warnings', async () => {
    const itemId = await createItem('F5 invoice replay item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const key = nextIdemKey('f5-invoice-replay');
    const payload = {
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
    };
    const first = await request(app)
      .post('/api/invoices').set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(first.status).toBe(201);
    expect(JSON.stringify(warningsOf(first.body))).toMatch(/damag/i);

    const retry = await request(app)
      .post('/api/invoices').set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(retry.status).toBe(201);
    expect(retry.headers['x-idempotent-replay']).toBe('true');
    expect(warningsOf(retry.body)).toEqual(warningsOf(first.body));
  });

  it('F5: a malformed stored value replays as an empty list, never a 500', async () => {
    const itemId = await createItem('F5 malformed item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    upsertBin(batchIdOf(itemId, warehouseA), defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const key = nextIdemKey('f5-malformed');
    const payload = {
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
    };
    await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key).send(payload);

    // A truncated/foreign value can never happen through claimIdempotencyKey,
    // but a legacy row or a hand-edited DB must degrade, not throw.
    db.prepare('UPDATE idempotency_keys SET response_warnings = ? WHERE key = ?')
      .run('{not json', key);

    const retry = await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(retry.status).toBe(201);
    expect(warningsOf(retry.body)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// F5 companion — rollback must leave NO false claim, and a replay must not
// re-consume stock or re-post cash.
// ---------------------------------------------------------------------------
describe('F5: rollback and replay side effects', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('a sale that FAILS on availability leaves no key, so the retry EXECUTES', async () => {
    const itemId = await createItem('F5 rollback item', cookie);
    await purchaseStock(itemId, warehouseA, 1, 40, cookie, AS_OF);

    const key = nextIdemKey('f5-rollback');
    const payload = {
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: 5, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
    };
    const failed = await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(failed.status).toBeGreaterThanOrEqual(400);

    // The claim lived inside the same transaction, so the rollback removed it.
    expect(
      db.prepare('SELECT COUNT(*) AS n FROM idempotency_keys WHERE key = ?').get(key),
    ).toEqual({ n: 0 });

    // A smaller retry with the SAME key must therefore execute, not replay.
    const ok = await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key)
      .send({ ...payload, items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }] });
    expect(ok.status).toBe(201);
    expect(ok.headers['x-idempotent-replay']).toBeUndefined();
  });

  it('a replay does NOT re-consume stock or re-post cash', async () => {
    const itemId = await createItem('F5 side-effect item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    upsertBin(batchIdOf(itemId, warehouseA), defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const key = nextIdemKey('f5-side-effects');
    const payload = {
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
      payments: [{ amount: 50, payment_method: 'Cash' }],
    };
    const moves = (): number =>
      (db.prepare('SELECT COUNT(*) AS n FROM stock_movements WHERE item_id = ?').get(itemId) as { n: number }).n;
    const balance = (): number =>
      (db.prepare('SELECT current_balance AS b FROM customers WHERE id = ?').get(customerId) as { b: number }).b;

    const first = await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(first.status).toBe(201);
    const movesAfterFirst = moves();
    const balanceAfterFirst = balance();

    const retry = await request(app).post('/api/invoices')
      .set('Cookie', cookie).set('Idempotency-Key', key).send(payload);
    expect(retry.status).toBe(201);
    expect(retry.headers['x-idempotent-replay']).toBe('true');

    // Delta 0 on both — a replay is a read, not a second write.
    expect(moves() - movesAfterFirst).toBe(0);
    expect(balance() - balanceAfterFirst).toBe(0);
    expect(warningsOf(retry.body)).toEqual(warningsOf(first.body));
  });
});

// ---------------------------------------------------------------------------
// F6 — duplicate warnings across batches (cosmetic, dedupe check).
// ---------------------------------------------------------------------------
describe('F6: duplicate per-batch warnings', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('F6: two DAMAGED batches in one sale produce one deduped warning', async () => {
    const itemId = await createItem('F6 dedupe item', cookie);
    await purchaseStock(itemId, warehouseA, 3, 40, cookie, AS_OF);
    await purchaseStock(itemId, warehouseA, 3, 40, cookie, AS_OF);
    const batches = db.prepare(
      'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id ASC',
    ).all(itemId, warehouseA) as Array<{ id: number }>;
    expect(batches.length).toBe(2);
    upsertBin(batches[0].id, defaultLocation(warehouseA), 3, 0, 'DAMAGED');
    upsertBin(batches[1].id, defaultLocation(warehouseA), 3, 0, 'DAMAGED');

    const { status, warnings } = await sellInvoice(itemId, 6, 'f6');

    expect(status).toBe(201);
    const damaged = warnings.filter((w) => /damag/i.test(w));
    expect(damaged.length).toBe(1);
  });
});

