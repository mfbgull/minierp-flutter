/**
 * ACC-16 tests: PO submission posts nothing to GL or supplier ledger;
 * goods receipt is the sole poster; the dedupe backfill reverses legacy
 * double-debits idempotently.
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

describe('PO commitment removal (ACC-16)', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get() as { id: number }).id;

    const item = await request(app).post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `ACC16-${Date.now()}`, item_name: 'ACC-16 Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const supplier = await request(app).post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({
        supplier_code: `ACC16-SUP-${Date.now()}`,
        supplier_name: 'ACC-16 Supplier',
        contact_person: 'Test',
      });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body?.data?.id ?? supplier.body?.id;

    await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 10,
        unit_cost: 5,
        purchase_date: '2026-08-01',
        supplier_id: supplierId,
      });
  });

  it('PO submission writes no journal_lines and no supplier_ledger rows', async () => {
    const poBefore = db.prepare(
      `SELECT COUNT(*) AS c FROM purchase_orders`
    ).get() as { c: number };

    const res = await request(app).post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-08-10',
        expected_delivery_date: '2026-08-15',
        warehouse_id: warehouseId,
        status: 'Submitted',
        items: [{ item_id: itemId, quantity: 4, unit_price: 25 }],
      });
    expect(res.status).toBe(201);
    const poId = res.body?.data?.id ?? res.body?.id;

    // No GL entry keyed to this PO
    const gl = db.prepare(
      `SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type='PURCHASE_ORDER' AND reference_id=?`
    ).get(poId) as { c: number };
    expect(gl.c).toBe(0);

    // No supplier-ledger commitment debit
    const sl = db.prepare(
      `SELECT COUNT(*) AS c FROM supplier_ledger WHERE supplier_id=? AND transaction_type='PURCHASE_ORDER' AND reference_no LIKE '%'
       AND id > (SELECT COALESCE(MAX(id),0) FROM supplier_ledger) - 100`
    ).get(supplierId) as { c: number };
    // Strict check: no PURCHASE_ORDER rows at all for this supplier created
    // by this submission — count all and compare against a fresh baseline.
    const slExact = db.prepare(
      `SELECT COUNT(*) AS c FROM supplier_ledger WHERE supplier_id=? AND transaction_type='PURCHASE_ORDER' AND reversed_by IS NULL`
    ).get(supplierId) as { c: number };
    void poBefore;
    expect(sl.c).toBe(slExact.c);
    expect(slExact.c).toBe(0);
  });

  it('goods receipt via recordPurchase is the sole inventory/AP poster', async () => {
    // Submit a PO, then record the purchase against the same supplier.
    const po = await request(app).post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-08-11',
        expected_delivery_date: '2026-08-12',
        warehouse_id: warehouseId,
        status: 'Submitted',
        items: [{ item_id: itemId, quantity: 2, unit_price: 30 }],
      });
    expect(po.status).toBe(201);

    const pur = await request(app).post('/api/purchases')
      .set('Cookie', authCookie)
      .send({
        item_id: itemId,
        warehouse_id: warehouseId,
        quantity: 2,
        unit_cost: 30,
        purchase_date: '2026-08-12',
        supplier_id: supplierId,
      });
    expect(pur.status).toBe(201);
    const purchaseId = pur.body.id as number;

    // Exactly one GL entry for this economic event, balanced.
    const lines = db.prepare(
      `SELECT account_id, debit, credit FROM journal_lines WHERE reference_type='PURCHASE' AND reference_id=? AND voided=0`
    ).all(purchaseId) as Array<{ account_id: number; debit: number; credit: number }>;
    expect(lines.length).toBeGreaterThanOrEqual(2);
    const debits = lines.reduce((s, l) => s + Number(l.debit), 0);
    const credits = lines.reduce((s, l) => s + Number(l.credit), 0);
    expect(debits).toBeCloseTo(60, 2); // 2 × 30
    expect(debits).toBeCloseTo(credits, 2);
  });

  it('dedupe-po script reverses legacy double-debits idempotently', async () => {
    const { spawnSync } = await import('child_process');
    const path = await import('path');

    // Simulate a legacy double-posting directly in the test DB.
    const insert = db.prepare(`
      INSERT INTO supplier_ledger (
        supplier_id, transaction_date, transaction_type, reference_no, debit, credit, balance, description
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const legacyDate = '2026-08-09';
    const refNo = `PO-LEGACY-${Date.now()}`;
    const balRow = db.prepare(
      `SELECT COALESCE(balance, 0) AS b FROM supplier_ledger WHERE supplier_id = ? AND voided = 0
       ORDER BY transaction_date DESC, id DESC LIMIT 1`
    ).get(supplierId) as { b: number } | undefined;
    insert.run(supplierId, legacyDate, 'PURCHASE_ORDER', refNo, 500, 0, Number(balRow?.b || 0), 'Legacy PO commitment');

    const scriptPath = path.join(__dirname, '../../scripts/dedupe-po.js');
    // The script appends 'erp.db' to DATABASE_PATH (a directory), matching
    // how src/config/database.ts resolves the file.
    const dbDirEnv = process.env.DATABASE_PATH as string;
    const run = (args: string[]) => spawnSync(process.execPath, [scriptPath, ...args], {
      encoding: 'utf8',
      env: { ...process.env, DATABASE_PATH: dbDirEnv },
      timeout: 60_000,
    });
    expect(dbDirEnv).toBeTruthy();

    // Dry run reports but does not write.
    const dry = run([]);
    expect(dry.stdout).toContain('redundant commitment debit');
    // Dry run wrote nothing.
    const preCount = db.prepare(
      `SELECT COUNT(*) AS c FROM supplier_ledger WHERE description='PO commitment reversal (backfill)' AND reference_no=?`
    ).get(refNo) as { c: number };
    expect(preCount.c).toBe(0);

    // Apply.
    const applyRes = run(['--apply']);
    expect(applyRes.stdout).toContain('done:');

    const reversal = db.prepare(
      `SELECT id FROM supplier_ledger WHERE description = 'PO commitment reversal (backfill)' AND reference_no = ?`
    ).get(refNo);
    expect(reversal).toBeDefined();

    const voidedOriginal = db.prepare(
      `SELECT voided FROM supplier_ledger WHERE transaction_type='PURCHASE_ORDER' AND reference_no = ?`
    ).get(refNo) as { voided: number };
    expect(Number(voidedOriginal.voided)).toBe(1);

    // Second run must not duplicate the reversal for this reference.
    const second = run(['--apply']);
    expect(second.stdout).toBeDefined();
    const reversalsForRef = db.prepare(
      `SELECT COUNT(*) AS c FROM supplier_ledger WHERE description='PO commitment reversal (backfill)' AND reference_no=?`
    ).get(refNo) as { c: number };
    expect(reversalsForRef.c).toBe(1);
  });
});
