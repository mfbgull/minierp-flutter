/**
 * Reversal-rules Phase 1 regression tests — C2 (production deletion
 * must void the legacy journal_entries GL row).
 *
 * Audit case covered:
 *   8. DELETE /api/productions/:id → journal_entries.voided = 1 for the
 *      linked row, raw batch restored, output movement reversed.
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

describe('Production deletion GL void (C2)', () => {
  let authCookie: string;
  let rawItemId: number;
  let outputItemId: number;
  let warehouseId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;

    const raw = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `C2-RAW-${Date.now()}`, item_name: 'C2 Raw Material' });
    expect(raw.status).toBe(201);
    rawItemId = raw.body.id;

    const output = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `C2-FG-${Date.now()}`, item_name: 'C2 Finished Good' });
    expect(output.status).toBe(201);
    outputItemId = output.body.id;

    // Stock the raw material so a production can consume it.
    await request(app)
      .post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: rawItemId,
        warehouse_id: warehouseId,
        quantity: 20,
        unit_cost: 5,
        purchase_date: '2026-08-01',
        supplier_name: 'C2 Stock Supplier',
      });
  });

  async function createProduction(): Promise<{ productionId: number; productionNo: string; movementId: number; journalEntryId: number }> {
    const res = await request(app)
      .post('/api/productions')
      .set('Cookie', authCookie)
      .send({
        output_item_id: outputItemId,
        output_quantity: 4,
        warehouse_id: warehouseId,
        production_date: '2026-08-10',
        input_items: [{ item_id: rawItemId, quantity: 8 }],
        overhead_cost: 10,
      });
    expect(res.status).toBe(201);
    const productionId = res.body.data?.id ?? res.body.id;
    expect(productionId).toBeDefined();

    const productionNo = (db.prepare('SELECT production_no FROM productions WHERE id = ?').get(productionId) as { production_no: string }).production_no;
    const movement = db.prepare(
      `SELECT id, journal_entry_id FROM stock_movements WHERE reference_docno = ? AND movement_type = 'PRODUCTION' AND quantity > 0`
    ).get(productionNo) as { id: number; journal_entry_id: number | null };
    expect(movement?.journal_entry_id).toBeTruthy();
    return { productionId, productionNo, movementId: movement.id, journalEntryId: movement.journal_entry_id as number };
  }

  it('case 8: deleting a production voids the linked canonical GL lines and restores stock', async () => {
    const { productionId, productionNo, movementId, journalEntryId } = await createProduction();

    // GL row active before deletion
    const jeBefore = db.prepare(
      'SELECT voided, amount FROM journal_entries WHERE id = ?'
    ).get(journalEntryId) as { voided: number; amount: number };
    expect(Number(jeBefore.voided)).toBe(0);
    expect(Number(jeBefore.amount)).toBeCloseTo(50, 2); // 8×5 + 10 overhead

    const rawStockBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(rawItemId, warehouseId) as { quantity: number }).quantity;
    const fgStockBefore = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(outputItemId, warehouseId) as { quantity: number }).quantity;

    const res = await request(app)
      .delete(`/api/productions/${productionId}`)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);

    // Legacy GL header voided, canonical lines voided — neither deleted
    const jeAfter = db.prepare(
      'SELECT voided FROM journal_entries WHERE id = ?'
    ).get(journalEntryId) as { voided: number };
    expect(Number(jeAfter.voided)).toBe(1);
    const activeLines = db.prepare(
      'SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0'
    ).get('production', movementId) as { c: number };
    expect(activeLines.c).toBe(0);

    // Raw material restored (+8), finished good reversed (−4)
    const rawStockAfter = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(rawItemId, warehouseId) as { quantity: number }).quantity;
    const fgStockAfter = (db.prepare(
      'SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?'
    ).get(outputItemId, warehouseId) as { quantity: number }).quantity;
    expect(rawStockAfter - rawStockBefore).toBeCloseTo(8, 2);
    expect(fgStockAfter - fgStockBefore).toBeCloseTo(-4, 2);

    // Raw batch quantity restored
    const prodRows = db.prepare(
      'SELECT COUNT(*) AS c FROM stock_movements WHERE reference_docno = ? AND reference_doctype = ?'
    ).all(productionNo, 'PRODUCTION_DELETE') as Array<{ c: number }>;
    expect(prodRows.reduce((s, r) => s + r.c, 0)).toBeGreaterThan(0);
  });
});
