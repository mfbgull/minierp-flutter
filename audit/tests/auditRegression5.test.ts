/**
 * Audit regression tests, round 5 — expired-stock write-off.
 * Each test encodes CORRECT behaviour and is expected to FAIL on commit
 * 87f1265b until the finding is fixed (assertions are fix-agnostic).
 *
 *   WO-001  loss value must equal qty x exact batch unit cost at currency precision (2dp)
 *   WO-003  a write-off must not post into a closed accounting period
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

let cookie: string;
let seq = 0;
const r2 = (v: number): number => Math.round(v * 100) / 100;
const warehouseId = (code: string): number =>
  (db.prepare('SELECT id FROM warehouses WHERE warehouse_code = ?').get(code) as { id: number }).id;

/** Seed an expired batch at the EXPIRED warehouse (same approach as writeOff.test.ts). */
function seedExpiredBatch(qty: number, unitCost: number): { batchId: number; batchNo: string } {
  seq += 1;
  const batchNo = `AUDIT-WO-${Date.now()}-${seq}`;
  const itemId = db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active, created_by)
    VALUES (?, 'Audit write-off item', 'Nos', ?, 1, 1, (SELECT id FROM users ORDER BY id LIMIT 1))
  `).run(batchNo, unitCost).lastInsertRowid as number;
  const wh = warehouseId('EXPIRED');
  const batchId = db.prepare(`
    INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date, expiry_date)
    VALUES (?, ?, ?, 'PURCHASE', 1, ?, ?, ?, '2026-01-01', '2026-01-01')
  `).run(batchNo, itemId, wh, qty, qty, unitCost).lastInsertRowid as number;
  db.prepare('INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (?, ?, ?)').run(itemId, wh, qty);
  return { batchId, batchNo };
}

const writeOff = (batchId: number) =>
  request(app).post('/api/inventory/expired/write-off').set('Cookie', cookie)
    .send({ batchIds: [batchId], reason: 'audit regression', glAccount: '7201' });

const entryLines = (batchNo: string) => db.prepare(`
  SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
  FROM stock_movements m
  JOIN journal_lines jl ON jl.journal_entry_id = m.journal_entry_id
  JOIN chart_of_accounts a ON a.id = jl.account_id
  WHERE m.movement_type = 'WRITE_OFF' AND m.reference_docno = ? AND jl.voided = 0
`).all(batchNo) as Array<{ code: string; debit: number; credit: number }>;

beforeAll(async () => {
  cookie = await getAuthCookie();
});

describe('WO-001: write-off value precision', () => {
  it('control: a round-number batch writes off at qty x cost (10 x 4 = 40)', async () => {
    const { batchId, batchNo } = seedExpiredBatch(10, 4);
    expect((await writeOff(batchId)).status).toBe(200);
    const lines = entryLines(batchNo);
    expect(lines.find((l) => l.code === '7201')?.debit).toBe(40);
    expect(lines.find((l) => l.code === '1200')?.credit).toBe(40);
  });

  it('1,000 units at 1.23456 write off at the exact batch value 1,234.56 (not 1,235.00)', async () => {
    const { batchId, batchNo } = seedExpiredBatch(1000, 1.23456);
    expect((await writeOff(batchId)).status).toBe(200);
    const lines = entryLines(batchNo);
    expect(lines.find((l) => l.code === '7201')?.debit).toBe(r2(1000 * 1.23456));
    expect(lines.find((l) => l.code === '1200')?.credit).toBe(r2(1000 * 1.23456));
  });

  it('journal amounts carry currency precision (2 decimals), not quantity precision', async () => {
    const { batchId, batchNo } = seedExpiredBatch(3, 0.3333);
    expect((await writeOff(batchId)).status).toBe(200);
    const lines = entryLines(batchNo);
    expect(lines).toHaveLength(2);
    for (const l of lines) {
      expect(r2(l.debit)).toBe(l.debit);
      expect(r2(l.credit)).toBe(l.credit);
    }
    expect(lines.find((l) => l.code === '7201')?.debit).toBe(r2(3 * 0.3333));
  });
});

describe('WO-003: closed periods', () => {
  it('rejects a write-off while today falls inside a closed, custom-named period', async () => {
    const { batchId, batchNo } = seedExpiredBatch(2, 5);
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('FY-WO-REGRESSION', '2026-01-01', '2099-12-31', 'closed')
    `).run();
    try {
      const res = await writeOff(batchId);
      expect(res.status).toBeGreaterThanOrEqual(400);
      expect(entryLines(batchNo)).toHaveLength(0);
      const batch = db.prepare('SELECT quantity_remaining AS q FROM stock_batches WHERE id = ?').get(batchId) as { q: number };
      expect(batch.q).toBe(2);
    } finally {
      db.prepare(`DELETE FROM accounting_periods WHERE period_name = 'FY-WO-REGRESSION'`).run();
    }
  });
});
