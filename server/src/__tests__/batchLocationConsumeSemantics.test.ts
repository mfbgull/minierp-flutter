/**
 * BUG-013 R1 / R2 / R4: the LEGACY (flag-OFF) consume path must match the
 * flag-ON allocator on three points, per Gull's decisions (2026-11-16):
 *
 *   R1  Damaged stock may be sold (scrap / reduced price) WITH a warning.
 *       It must not be sold silently.
 *   R2  When the bin layer under-covers the master, WARN about the available
 *       quantity. Warn only: no overselling a true shortage, no accounting or
 *       closed-period bypass, no silent auto-reconcile.
 *   R4  The legacy path MUST respect reservations. Cap EACH take to the bin's
 *       AVAILABLE (physical - reserved), not merely filter available > 0 and
 *       then take the physical quantity.
 *
 * These are the ENFORCING regression assertions for the intended behaviour.
 * They are RED on 819034da by design (red-first): the legacy predicate reads
 * `quantity_physical > 0` with no status clause and no reservation netting.
 * The characterisation probe lives in batchLocationLegacyParityTriage.test.ts
 * and is NOT the regression gate.
 *
 * The spec drives the REAL invoice route on the real test database. It does
 * not call the model helper directly: a source-level assertion cannot tell
 * "the wrong bin moved" from "nothing moved".
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
  customerId = await createCustomer('Consume Semantics Customer', cookie);
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseA = wh.id;
});

function defaultLocation(wh: number): number {
  return (db.prepare(
    "SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT'",
  ).get(wh) as { id: number }).id;
}

function secondLocation(wh: number, code: string): number {
  db.prepare(
    `INSERT OR IGNORE INTO locations (warehouse_id, location_code, location_name) VALUES (?, ?, ?)`,
  ).run(wh, code, code);
  return (db.prepare('SELECT id FROM locations WHERE warehouse_id = ? AND location_code = ?')
    .get(wh, code) as { id: number }).id;
}

function batchIdOf(itemId: number, wh: number): number {
  return (db.prepare(
    'SELECT id FROM stock_batches WHERE item_id = ? AND warehouse_id = ? ORDER BY id DESC LIMIT 1',
  ).get(itemId, wh) as { id: number }).id;
}

function binRow(batchId: number, locationId: number): {
  physical: number; reserved: number; available: number;
} {
  const r = db.prepare(
    `SELECT quantity_physical as physical, quantity_reserved as reserved, quantity_available as available
     FROM batch_stock_by_location WHERE batch_id = ? AND location_id = ?`,
  ).get(batchId, locationId) as { physical: number; reserved: number; available: number } | undefined;
  return r ?? { physical: 0, reserved: 0, available: 0 };
}

function masterQty(itemId: number, wh: number): number {
  const r = db.prepare(
    'SELECT COALESCE(SUM(quantity_remaining), 0) as q FROM stock_batches WHERE item_id = ? AND warehouse_id = ?',
  ).get(itemId, wh) as { q: number };
  return r.q;
}

async function sell(itemId: number, qty: number, tag: string): Promise<number> {
  return (await sellFull(itemId, qty, tag)).status;
}

async function sellFull(
  itemId: number, qty: number, tag: string,
): Promise<{ status: number; warnings: unknown }> {
  const res = await request(app)
    .post('/api/invoices')
    .set('Cookie', cookie)
    .set('Idempotency-Key', nextIdemKey(`cs-${tag}`))
    .send({
      customer_id: customerId,
      invoice_date: AS_OF,
      items: [{ item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0 }],
      warehouse_id: warehouseA,
    });
  return { status: res.status, warnings: res.body?.warnings ?? [] };
}

/** Seed a bin row directly. `quantity_available` is NEVER written here: the
 *  real schema derives it by trigger (`MAX(0, physical - reserved)`), so a
 *  hand-passed value would model a state the product cannot produce. The
 *  fixture must fail for a wrong PREDICATE, never for a wrong setup. */
function upsertBin(
  batchId: number, locationId: number,
  physical: number, reserved: number, status: string | null,
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

// ---------------------------------------------------------------------------
// R1 — damaged stock: sellable WITH a warning, but NOT silently. Gull chose
// option B: this applies in BOTH flag states. EXPIRED stays refused.
// ---------------------------------------------------------------------------
for (const featureOn of [false, true]) {
  const label = featureOn ? 'flag ON' : 'flag OFF';

  describe(`BUG-013 R1: damaged stock sells with a warning (${label})`, () => {
    beforeAll(() => setFeatureEnabled(db, FLAG, featureOn));

    it(`R1-a: a DAMAGED bin still sells, and the response carries a warning (${label})`, async () => {
      const itemId = await createItem(`R1 damaged ${label}`, cookie);
      await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
      const batchId = batchIdOf(itemId, warehouseA);
      upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'DAMAGED');

      const res = await request(app)
        .post('/api/invoices')
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`r1a-${featureOn}`))
        .send({
          customer_id: customerId,
          invoice_date: AS_OF,
          items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
          warehouse_id: warehouseA,
        });

      // Gull: damaged stock may be sold. The sale must NOT be refused.
      expect(res.status).toBe(201);
      // Gull: "but with warning or notification". A silent sale is the defect.
      const warnings = res.body?.warnings ?? [];
      expect(JSON.stringify(warnings)).toMatch(/damag/i);
      // The bin drains by the sold unit.
      expect(binRow(batchId, defaultLocation(warehouseA)).physical).toBe(4);
    });

    it(`R1-c: an EXPIRED bin is still refused (${label})`, async () => {
      const itemId = await createItem(`R1 expired ${label}`, cookie);
      await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
      const batchId = batchIdOf(itemId, warehouseA);
      upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'EXPIRED');

      const res = await request(app)
        .post('/api/invoices')
        .set('Cookie', cookie)
        .set('Idempotency-Key', nextIdemKey(`r1c-${featureOn}`))
        .send({
          customer_id: customerId,
          invoice_date: AS_OF,
          items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
          warehouse_id: warehouseA,
        });

      // Expired stock must stay unsellable; only DAMAGED was authorised.
      expect([400, 409]).toContain(res.status);
    });
  });
}

// ---------------------------------------------------------------------------
// R2 — bin under-coverage: warn about the available quantity.
// ---------------------------------------------------------------------------
describe('BUG-013 R2: bin under-coverage warns about available quantity (flag OFF)', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('R2-a: an under-covered sale warns with the available quantity', async () => {
    const itemId = await createItem('R2 undercover item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    // Only 4 sit in a bin; the master holds 10.
    upsertBin(batchId, defaultLocation(warehouseA), 4, 0, 'ACTIVE');

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('r2a'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: itemId, quantity: 6, unit_price: 50, tax_rate: 0 }],
        warehouse_id: warehouseA,
      });

    // Gull: warn, do not refuse. The sale completes.
    expect(res.status).toBe(201);
    const warnings = JSON.stringify(res.body?.warnings ?? []);
    expect(warnings).toMatch(/available/i);
    // The bin drains fully and the master falls by the full sale.
    expect(binRow(batchId, defaultLocation(warehouseA)).physical).toBe(0);
    expect(masterQty(itemId, warehouseA)).toBe(4);
  });

  it('R2-b: a TRUE shortage is refused, not warned around', async () => {
    const itemId = await createItem('R2 shortage item', cookie);
    await purchaseStock(itemId, warehouseA, 4, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 4, 0, 'ACTIVE');

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('r2b'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: itemId, quantity: 6, unit_price: 50, tax_rate: 0 }],
        warehouse_id: warehouseA,
      });

    // No overselling a real shortage: the master cannot cover 6.
    expect([400, 409]).toContain(res.status);
    expect(masterQty(itemId, warehouseA)).toBe(4);
  });

  it('R2-c: hidden reservation in a SECOND bin is authoritative — refused', async () => {
    const itemId = await createItem('R2 hidden res item', cookie);
    await purchaseStock(itemId, warehouseA, 6, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R2C-${itemId}`);
    // Bin A: physical 1, reserved 1 -> available 0 (the only availability).
    // Bin B: physical 5, reserved 5 -> available 0 (a hidden reservation).
    // The master says 6, but the AUTHORITATIVE reservation total is 6, so
    // nothing is genuinely free. Sell 1 must be REFUSED: master quantity alone
    // is NOT free.
    upsertBin(batchId, locA, 1, 1, 'ACTIVE');
    upsertBin(batchId, locB, 5, 5, 'ACTIVE');

    const res = await request(app)
      .post('/api/invoices')
      .set('Cookie', cookie)
      .set('Idempotency-Key', nextIdemKey('r2c'))
      .send({
        customer_id: customerId,
        invoice_date: AS_OF,
        items: [{ item_id: itemId, quantity: 1, unit_price: 50, tax_rate: 0 }],
        warehouse_id: warehouseA,
      });

    expect([400, 409]).toContain(res.status);
    expect(binRow(batchId, locA).physical).toBe(1);
    expect(binRow(batchId, locB).physical).toBe(5);
    expect(masterQty(itemId, warehouseA)).toBe(6);
  });
});

// ---------------------------------------------------------------------------
// R4 — reservations: cap EACH take to the bin's available.
// ---------------------------------------------------------------------------
describe('BUG-013 R4: legacy consume respects reservations (flag OFF)', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  it('R4-a: a PARTIALLY reserved bin is capped to its available', async () => {
    const itemId = await createItem('R4 partial item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R4A-${itemId}`);
    // Bin A: physical 5, reserved 2 -> available 3. Bin B: available 5.
    upsertBin(batchId, locA, 5, 2, 'ACTIVE');
    upsertBin(batchId, locB, 5, 0, 'ACTIVE');

    const status = await sell(itemId, 4, 'r4a');

    expect(status).toBe(201);
    // Bin A must give at most its 3 available; the reserved 2 stay.
    expect(binRow(batchId, locA).reserved).toBe(2);
    expect(binRow(batchId, locA).physical).toBeGreaterThanOrEqual(2);
    expect(binRow(batchId, locA).physical - binRow(batchId, locA).reserved)
      .toBeGreaterThanOrEqual(0);
    // The remainder comes from bin B.
    expect(binRow(batchId, locB).physical).toBe(4);
  });

  it('R4-b: a FULLY reserved bin is untouched; the unit comes from elsewhere', async () => {
    const itemId = await createItem('R4 full item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R4B-${itemId}`);
    // Bin A: physical 5, reserved 5 -> available 0. Bin B: available 5.
    upsertBin(batchId, locA, 5, 5, 'ACTIVE');
    upsertBin(batchId, locB, 5, 0, 'ACTIVE');

    const status = await sell(itemId, 1, 'r4b');

    expect(status).toBe(201);
    // The reserved bin must NOT move.
    expect(binRow(batchId, locA).physical).toBe(5);
    expect(binRow(batchId, locA).reserved).toBe(5);
    // The unit comes from the free bin.
    expect(binRow(batchId, locB).physical).toBe(4);
  });

  it('R4-c: all stock reserved -> nothing is available, sale refused', async () => {
    const itemId = await createItem('R4 allreserved item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 5, 5, 'ACTIVE');

    const status = await sell(itemId, 1, 'r4c');

    expect([400, 409]).toContain(status);
    expect(binRow(batchId, defaultLocation(warehouseA)).physical).toBe(5);
  });

  it('R4-d: a batch with NO bin rows keeps the legacy shape (no reservation evidence)', async () => {
    const itemId = await createItem('R4 norecords item', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    db.prepare('DELETE FROM batch_stock_by_location WHERE batch_id = ?').run(batchId);

    const status = await sell(itemId, 1, 'r4d');

    // No bin rows means no reservation evidence: the legacy path sells.
    expect(status).toBe(201);
    expect(masterQty(itemId, warehouseA)).toBe(4);
  });

  it('R4-e: reservations are honoured THROUGH the fallback (bins under-cover)', async () => {
    const itemId = await createItem('R4 fallback item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const loc = defaultLocation(warehouseA);
    // Bin: physical 2, reserved 2 -> available 0. The master holds 10, so 8
    // units are unmirrored. Reservation evidence EXISTS for this batch, so the
    // unmirrored stock must NOT be handed out as if it were free.
    upsertBin(batchId, loc, 2, 2, 'ACTIVE');

    const { status, warnings } = await sellFull(itemId, 1, 'r4e');

    // Precise expected outcome. The master covers the unit, so the sale
    // SUCCEEDS; the reserved bin never drains. The unit comes from unmirrored
    // master stock only.
    expect(status).toBe(201);
    expect(binRow(batchId, loc).physical).toBe(2);
    expect(binRow(batchId, loc).reserved).toBe(2);
    expect(masterQty(itemId, warehouseA)).toBe(9);
    // Mirror shortfall is present (the bin under-covers), so the response must
    // warn about the available quantity — sell-with-warning, not silent.
    expect(JSON.stringify(warnings)).toMatch(/available/i);
  });

  it('R4-f: a BLOCKED bin with a reservation is not double-subtracted', async () => {
    const itemId = await createItem('R4 blocked mixed item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R4F-${itemId}`);
    // Bin A: BLOCKED, physical 5, reserved 3. Bin B: ACTIVE, physical 5 free.
    // Master 10. Reserved = 3. Unreserved blocked = 5 - 3 = 2. Free = 10-3-2 = 5.
    // A naive formula (10 - 3 - 5 = 2) would still allow 2 here, so sell 3 to
    // prove the disjoint accounting: 3 succeeds only if the blocked bin's
    // reserved 3 units are NOT counted twice.
    upsertBin(batchId, locA, 5, 3, 'BLOCKED');
    upsertBin(batchId, locB, 5, 0, 'ACTIVE');

    const status = await sell(itemId, 3, 'r4f');

    expect(status).toBe(201);
    // The blocked bin and its reservation never move.
    expect(binRow(batchId, locA).physical).toBe(5);
    expect(binRow(batchId, locA).reserved).toBe(3);
    // All 3 come out of the free ACTIVE bin.
    expect(binRow(batchId, locB).physical).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// ON controls: R4 uses the SAME bin-level allocator the R1 widening touches, so
// the reservation semantics must be confirmed on flag ON too (a control, not a
// new fix — the ON path already honours reservations).
// ---------------------------------------------------------------------------
describe('BUG-013 R4 control: flag-ON allocator honours reservations', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, true));

  it('R4-on-a: a PARTIALLY reserved bin is capped to its available (flag ON)', async () => {
    const itemId = await createItem('R4 on partial item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R4ONA-${itemId}`);
    upsertBin(batchId, locA, 5, 2, 'ACTIVE');
    upsertBin(batchId, locB, 5, 0, 'ACTIVE');

    const status = await sell(itemId, 4, 'r4ona');

    expect(status).toBe(201);
    expect(binRow(batchId, locA).reserved).toBe(2);
    expect(binRow(batchId, locA).physical).toBeGreaterThanOrEqual(2);
    expect(binRow(batchId, locB).physical).toBe(4);
  });

  it('R4-on-b: a FULLY reserved bin is untouched (flag ON)', async () => {
    const itemId = await createItem('R4 on full item', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    const locA = defaultLocation(warehouseA);
    const locB = secondLocation(warehouseA, `R4ONB-${itemId}`);
    upsertBin(batchId, locA, 5, 5, 'ACTIVE');
    upsertBin(batchId, locB, 5, 0, 'ACTIVE');

    const status = await sell(itemId, 1, 'r4onb');

    expect(status).toBe(201);
    expect(binRow(batchId, locA).physical).toBe(5);
    expect(binRow(batchId, locA).reserved).toBe(5);
    expect(binRow(batchId, locB).physical).toBe(4);
  });
});

// ---------------------------------------------------------------------------
// WIRE integration: the invoice response is not enough. A warning that the
// service builds but the POS handler drops never reaches a cashier. The POS
// handler rebuilds its body from the database, which stores no warnings, so
// `result.warnings` was silently discarded. These tests drive the REAL
// POST /api/pos/sale and assert the warning survives to the wire.
// ---------------------------------------------------------------------------
describe('BUG-013 wire: warnings survive the real sale responses', () => {
  beforeAll(() => setFeatureEnabled(db, FLAG, false));

  async function posSale(itemId: number, tag: string, qty = 1) {
    return request(app)
      .post('/api/pos/sale')
      .set('Cookie', cookie)
      .send({
        warehouse_id: warehouseA,
        sale_date: AS_OF,
        items: [{ item_id: itemId, quantity: qty, unit_price: 50, tax_rate: 0 }],
        cash_received: 1000,
      })
      .expect(201)
      .then((r) => {
        void tag;
        return r;
      });
  }

  it('W-1: a DAMAGED-bin POS sale carries the warning on the wire', async () => {
    const itemId = await createItem('POS wire A', cookie);
    await purchaseStock(itemId, warehouseA, 5, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    upsertBin(batchId, defaultLocation(warehouseA), 5, 0, 'DAMAGED');

    const res = await posSale(itemId, 'w1');

    // The POS body is `{ success, message, data }`; the warning must be
    // reachable in the real response, not only in the service out-param.
    // Assert on the WARNINGS COLLECTION, never a loose body match: the item
    // name would satisfy /damag/i and mask a dropped warning.
    const warnings = res.body?.warnings ?? res.body?.data?.warnings ?? [];
    expect(Array.isArray(warnings)).toBe(true);
    expect(warnings.length).toBeGreaterThan(0);
    expect(JSON.stringify(warnings)).toMatch(/damag/i);
  });

  it('W-2: an under-covered POS sale carries the available-quantity warning', async () => {
    const itemId = await createItem('POS wire B', cookie);
    await purchaseStock(itemId, warehouseA, 10, 40, cookie, AS_OF);
    const batchId = batchIdOf(itemId, warehouseA);
    // Bin physical 2 mirrors only part of the 10-unit master; sell 6 so the
    // take EXCEEDS the bin (6 > 2) and the under-coverage warning fires.
    upsertBin(batchId, defaultLocation(warehouseA), 2, 0, 'ACTIVE');

    const res = await posSale(itemId, 'w2', 6);

    const warnings = res.body?.warnings ?? res.body?.data?.warnings ?? [];
    expect(Array.isArray(warnings)).toBe(true);
    expect(warnings.length).toBeGreaterThan(0);
    expect(JSON.stringify(warnings)).toMatch(/available/i);
  });
});
