/**
 * C2 REGRESSION: Every sales return must restock its own quantity.
 *
 * Root cause: reverseStockForItems() subtracted already-returned quantity
 * from the current return quantity before computing the batch-restore ratio.
 * On a second partial return of 3 items (after a first return of 2), only
 * 1 item was restocked instead of 3. The GL posted correctly for the full
 * 3, so stock and GL drifted apart.
 *
 * The fix uses totalToReturn directly for the RETURN path, because the
 * caller passes this return's quantity only and tracks accumulation itself.
 *
 * This suite covers:
 *   1. 2 + 2 (two equal partial returns)
 *   2. 1 + 3 (unequal partial returns)
 *   3. 5 + 5 (two full returns on separate items)
 *   4. 3 + 3 + 3 (triple partial return)
 *   5. Attempted over-return (must be rejected)
 *   6. Multi-line invoice (returns across lines)
 *   7. Partial return followed by another partial return (sequential)
 *
 * For each scenario: stock quantity, batch quantity, inventory value,
 * GL inventory, GL COGS, return accounting, invoice entitlement.
 */

import request from 'supertest';
import app from '../app';
import db from '../config/database';

// ── helpers ──────────────────────────────────────────────────────────

let authCookie: string;
let warehouseId: number;
let customerId: number;
let seq = 0;

function uid(): number { return ++seq; }

/** Assert value is within ±tolerance of expected. */
function expectClose(actual: number, expected: number, tolerance = 0.01): void {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance);
}

async function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: Record<string, unknown>) {
  let r = request(app)[method](url);
  if (authCookie) r = r.set('Cookie', authCookie);
  if (body !== undefined) r = r.send(body);
  return r;
}

function stockOf(itemId: number): number {
  return Number(
    (db.prepare('SELECT COALESCE(SUM(quantity),0) q FROM stock_balances WHERE item_id = ?')
      .get(itemId) as { q: number }).q
  );
}

function batchQtyRemaining(itemId: number): number {
  return Number(
    (db.prepare(`
      SELECT COALESCE(SUM(sb.quantity_remaining), 0) AS q
      FROM stock_batches sb
      WHERE sb.item_id = ?
    `).get(itemId) as { q: number }).q
  );
}

function glNetByAccount(code: string): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE coa.code = ? AND jl.voided = 0
  `).get(code) as { net: number };
  return Number(row.net);
}

function glNetForReturn(code: string, returnId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE coa.code = ? AND jl.voided = 0
      AND jl.reference_type = 'INVOICE_RETURN'
      AND jl.reference_id = ?
  `).get(code, returnId) as { net: number };
  return Number(row.net);
}

function glNetForCogsReversal(returnId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE coa.code = '1200' AND jl.voided = 0
      AND jl.reference_type = 'INVOICE_RETURN'
      AND jl.reference_id = ?
  `).get(returnId) as { net: number };
  return Number(row.net);
}

function cogsReversalForReturn(returnId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(jl.credit), 0) AS credit
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE coa.code = '5000' AND jl.voided = 0
      AND jl.reference_type = 'INVOICE_RETURN'
      AND jl.reference_id = ?
  `).get(returnId) as { credit: number };
  return Number(row.credit);
}

function returnedQty(invoiceItemId: number): number {
  const row = db.prepare('SELECT returned_qty FROM invoice_items WHERE id = ?')
    .get(invoiceItemId) as { returned_qty: number | null };
  return Number(row?.returned_qty ?? 0);
}

async function createItem(name: string): Promise<number> {
  const res = await api('post', '/api/inventory/items', {
    item_code: `C2-${Date.now()}-${uid()}`,
    item_name: name,
    unit_of_measure: 'pcs',
    standard_cost: 100,
    standard_selling_price: 200,
    current_stock: 0,
  });
  return res.body.id;
}

async function purchaseStock(itemId: number, qty: number, cost: number): Promise<void> {
  const res = await api('post', '/api/purchases', {
    warehouse_id: warehouseId,
    purchase_date: '2026-09-10',
    items: [{ item_id: itemId, quantity: qty, unit_cost: cost }],
  });
  if (res.status !== 201) throw new Error(`purchaseStock failed: ${res.status} ${JSON.stringify(res.body)}`);
}

async function sellAndReturn(
  itemId: number,
  sellQty: number,
  sellPrice: number,
  returns: number[],
): Promise<{ invoiceId: number; invoiceItemIds: number[]; returnIds: number[] }> {
  const inv = await api('post', '/api/invoices', {
    customer_id: customerId,
    invoice_date: '2026-09-15',
    warehouse_id: warehouseId,
    items: [{ item_id: itemId, quantity: sellQty, unit_price: sellPrice }],
  });
  if (inv.status !== 201) throw new Error(`createInvoice failed: ${inv.status} ${JSON.stringify(inv.body)}`);
  const invoiceId = inv.body.id;
  const invoiceItemIds: number[] = (inv.body.items ?? []).map((i: { id: number }) => i.id);
  if (invoiceItemIds.length === 0) {
    const row = db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId) as { id: number };
    invoiceItemIds.push(row.id);
  }

  const returnIds: number[] = [];
  for (const returnQty of returns) {
    const r = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemIds[0], return_quantity: returnQty }],
      disposition: 'credit',
    });
    if (r.status !== 200) throw new Error(`return failed (qty=${returnQty}): ${r.status} ${JSON.stringify(r.body)}`);
    returnIds.push(r.body.data?.returnId ?? r.body.data?.id);
  }

  return { invoiceId, invoiceItemIds, returnIds };
}

// ── setup ────────────────────────────────────────────────────────────

beforeAll(async () => {
  const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD as string;
  const login = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = login.headers['set-cookie'] ?? [];
  const list = Array.isArray(cookies) ? cookies : [cookies];
  const tokenCookie = list.find((c: string) => c.startsWith('token='));
  if (!tokenCookie) throw new Error('Login failed: no token cookie');
  authCookie = tokenCookie.split(';')[0];

  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  customerId = (db.prepare(
    `INSERT INTO customers (customer_name, customer_code, phone)
     VALUES (?, ?, ?) RETURNING id`
  ).get('C2 Test Customer', 'C2-CUST', '0300-9999') as { id: number }).id;
});

// ── Scenario 1: 2 + 2 ───────────────────────────────────────────────

describe('C2 scenario 1: 2 + 2 (two equal partial returns)', () => {
  it('each return restocks exactly its own quantity; stock, batch, GL, entitlement all correct', async () => {
    const item = await createItem('C2-S1 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const { invoiceId, invoiceItemIds, returnIds } = await sellAndReturn(item, sellQty, sellPrice, [2, 2]);
    const [retId1, retId2] = returnIds;

    // Stock: sold 10, returned 2+2 = 4 → stock = beforeStock - 10 + 4
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 4, 5);

    const batchQty = batchQtyRemaining(item);
    expectClose(batchQty, 4, 0.02);

    // Invoice entitlement: returned_qty = 4
    expect(returnedQty(invoiceItemIds[0])).toBeCloseTo(4, 4);

    // Return 1 accounting
    const inv1 = glNetForReturn('1200', retId1);  // Inventory asset (debit from COGS reversal)
    const cogs1 = cogsReversalForReturn(retId1);
    expect(inv1).toBeCloseTo(2 * cost, 1);        // 2 units × 100 cost = 200
    expect(cogs1).toBeCloseTo(2 * cost, 1);

    // Return 2 accounting
    const inv2 = glNetForReturn('1200', retId2);
    const cogs2 = cogsReversalForReturn(retId2);
    expect(inv2).toBeCloseTo(2 * cost, 1);
    expect(cogs2).toBeCloseTo(2 * cost, 1);

    // Cumulative GL inventory: 200 + 200 = 400
    // Each return posts its own COGS reversal entry, so we check per-return.
  });
});

// ── Scenario 2: 1 + 3 ───────────────────────────────────────────────

describe('C2 scenario 2: 1 + 3 (unequal partial returns)', () => {
  it('first return 1, second return 3; stock = original - sold + 4', async () => {
    const item = await createItem('C2-S2 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const { invoiceId, invoiceItemIds, returnIds } = await sellAndReturn(item, sellQty, sellPrice, [1, 3]);
    const [retId1, retId2] = returnIds;

    // Stock: -10 + 1 + 3 = -6 from original
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 4, 5);

    expectClose(batchQtyRemaining(item), 4, 0.02);

    // Entitlement: 4 returned of 10
    expect(returnedQty(invoiceItemIds[0])).toBeCloseTo(4, 4);

    // Return 1: 1 unit × 100 cost = 100
    expect(cogsReversalForReturn(retId1)).toBeCloseTo(1 * cost, 1);
    // Return 2: 3 units × 100 cost = 300
    expect(cogsReversalForReturn(retId2)).toBeCloseTo(3 * cost, 1);
  });
});

// ── Scenario 3: 5 + 5 ───────────────────────────────────────────────

describe('C2 scenario 3: 5 + 5 (two full-size partial returns)', () => {
  it('sell 10, return 5 then 5; stock fully restored to pre-sale level', async () => {
    const item = await createItem('C2-S3 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const { invoiceId, invoiceItemIds, returnIds } = await sellAndReturn(item, sellQty, sellPrice, [5, 5]);
    const [retId1, retId2] = returnIds;

    // Stock fully restored: original level
    expect(stockOf(item)).toBeCloseTo(beforeStock, 5);

    expectClose(batchQtyRemaining(item), 10, 0.02);

    // Entitlement: all 10 returned
    expect(returnedQty(invoiceItemIds[0])).toBeCloseTo(10, 4);

    // Each return: 5 units × 100 cost = 500
    expect(cogsReversalForReturn(retId1)).toBeCloseTo(5 * cost, 1);
    expect(cogsReversalForReturn(retId2)).toBeCloseTo(5 * cost, 1);
  });
});

// ── Scenario 4: 3 + 3 + 3 ───────────────────────────────────────────

describe('C2 scenario 4: 3 + 3 + 3 (triple partial return)', () => {
  it('sell 10, return 3 three times; stock = original - 10 + 9', async () => {
    const item = await createItem('C2-S4 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const { invoiceId, invoiceItemIds, returnIds } = await sellAndReturn(item, sellQty, sellPrice, [3, 3, 3]);
    const [retId1, retId2, retId3] = returnIds;

    // Stock: -10 + 9 = -1 from original
    expect(stockOf(item)).toBeCloseTo(beforeStock - 1, 5);

    expectClose(batchQtyRemaining(item), 9, 0.02);

    // Entitlement: 9 returned of 10 (1 remaining)
    expect(returnedQty(invoiceItemIds[0])).toBeCloseTo(9, 4);

    // Each return: 3 units × 100 cost = 300
    expect(cogsReversalForReturn(retId1)).toBeCloseTo(3 * cost, 1);
    expect(cogsReversalForReturn(retId2)).toBeCloseTo(3 * cost, 1);
    expect(cogsReversalForReturn(retId3)).toBeCloseTo(3 * cost, 1);

    // 4th return of 1 must succeed (1 remaining)
    const r4 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemIds[0], return_quantity: 1 }],
      disposition: 'credit',
    });
    expect(r4.status).toBe(200);
    expect(stockOf(item)).toBeCloseTo(beforeStock, 5);
    expect(returnedQty(invoiceItemIds[0])).toBeCloseTo(10, 4);
  });
});

// ── Scenario 5: attempted over-return ────────────────────────────────

describe('C2 scenario 5: attempted over-return', () => {
  it('return 2 then attempt 9 (total 11 > 10) must be rejected; stock unchanged by rejected attempt', async () => {
    const item = await createItem('C2-S5 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const inv = await api('post', '/api/invoices', {
      customer_id: customerId,
      invoice_date: '2026-09-20',
      warehouse_id: warehouseId,
      items: [{ item_id: item, quantity: sellQty, unit_price: sellPrice }],
    });
    expect(inv.status).toBe(201);
    const invoiceId = inv.body.id;
    const invoiceItemId = (inv.body.items ?? [])[0]?.id
      ?? (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId) as { id: number }).id;

    // First return: 2
    const r1 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
      disposition: 'credit',
    });
    expect(r1.status).toBe(200);
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 2, 5);
    expect(returnedQty(invoiceItemId)).toBeCloseTo(2, 4);

    // Attempted over-return: 9 (total would be 11 > 10)
    const r2 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 9 }],
      disposition: 'credit',
    });
    expect(r2.status).toBe(400);

    // Stock unchanged by rejected attempt
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 2, 5);
    expect(returnedQty(invoiceItemId)).toBeCloseTo(2, 4);

    // Attempted exact return of remaining 8 must succeed
    const r3 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 8 }],
      disposition: 'credit',
    });
    expect(r3.status).toBe(200);
    expect(stockOf(item)).toBeCloseTo(beforeStock, 5);
    expect(returnedQty(invoiceItemId)).toBeCloseTo(10, 4);
  });
});

// ── Scenario 6: multi-line invoice ───────────────────────────────────

describe('C2 scenario 6: multi-line invoice', () => {
  it('returns on separate lines each restock their own quantity independently', async () => {
    const itemA = await createItem('C2-S6 Widget A');
    const itemB = await createItem('C2-S6 Widget B');
    const cost = 100;
    const sellPrice = 200;

    await purchaseStock(itemA, 10, cost);
    await purchaseStock(itemB, 10, cost);

    const beforeA = stockOf(itemA);
    const beforeB = stockOf(itemB);

    // Invoice with 2 lines: 5×A + 5×B
    const inv = await api('post', '/api/invoices', {
      customer_id: customerId,
      invoice_date: '2026-09-21',
      warehouse_id: warehouseId,
      items: [
        { item_id: itemA, quantity: 5, unit_price: sellPrice },
        { item_id: itemB, quantity: 5, unit_price: sellPrice },
      ],
    });
    expect(inv.status).toBe(201);
    const invoiceId = inv.body.id;
    const items = db.prepare('SELECT id, item_id FROM invoice_items WHERE invoice_id = ? ORDER BY id')
      .all(invoiceId) as Array<{ id: number; item_id: number }>;
    expect(items).toHaveLength(2);

    const itemAId = items.find(i => i.item_id === itemA)!.id;
    const itemBId = items.find(i => i.item_id === itemB)!.id;

    // Stock after sale
    expect(stockOf(itemA)).toBeCloseTo(beforeA - 5, 5);
    expect(stockOf(itemB)).toBeCloseTo(beforeB - 5, 5);

    // Return 2 of item A
    const rA = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: itemAId, return_quantity: 2 }],
      disposition: 'credit',
    });
    expect(rA.status).toBe(200);
    const retIdA = rA.body.data?.returnId ?? rA.body.data?.id;

    // Only item A stock changed
    expect(stockOf(itemA)).toBeCloseTo(beforeA - 5 + 2, 5);
    expect(stockOf(itemB)).toBeCloseTo(beforeB - 5, 5);
    expect(returnedQty(itemAId)).toBeCloseTo(2, 4);
    expect(returnedQty(itemBId)).toBeCloseTo(0, 4);

    // Return 3 of item B
    const rB = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: itemBId, return_quantity: 3 }],
      disposition: 'credit',
    });
    expect(rB.status).toBe(200);
    const retIdB = rB.body.data?.returnId ?? rB.body.data?.id;

    // Both items now reflect their own returns
    expect(stockOf(itemA)).toBeCloseTo(beforeA - 5 + 2, 5);
    expect(stockOf(itemB)).toBeCloseTo(beforeB - 5 + 3, 5);
    expect(returnedQty(itemAId)).toBeCloseTo(2, 4);
    expect(returnedQty(itemBId)).toBeCloseTo(3, 4);

    // GL: each return has its own COGS reversal
    expect(cogsReversalForReturn(retIdA)).toBeCloseTo(2 * cost, 1);
    expect(cogsReversalForReturn(retIdB)).toBeCloseTo(3 * cost, 1);

    expectClose(batchQtyRemaining(itemA), 7, 0.02);
    expectClose(batchQtyRemaining(itemB), 8, 0.02);
  });
});

// ── Scenario 7: partial return followed by another partial return ────

describe('C2 scenario 7: sequential partial returns', () => {
  it('return 2 then return 3 on same item; each return independently correct', async () => {
    const item = await createItem('C2-S7 Widget');
    const cost = 100;
    const sellPrice = 200;
    const sellQty = 10;
    await purchaseStock(item, sellQty, cost);
    const beforeStock = stockOf(item);

    const inv = await api('post', '/api/invoices', {
      customer_id: customerId,
      invoice_date: '2026-09-22',
      warehouse_id: warehouseId,
      items: [{ item_id: item, quantity: sellQty, unit_price: sellPrice }],
    });
    expect(inv.status).toBe(201);
    const invoiceId = inv.body.id;
    const invoiceItemId = (inv.body.items ?? [])[0]?.id
      ?? (db.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId) as { id: number }).id;

    // Return 1: 2 units
    const r1 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
      disposition: 'credit',
    });
    expect(r1.status).toBe(200);
    const retId1 = r1.body.data?.returnId ?? r1.body.data?.id;

    // After return 1: stock restored by 2
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 2, 5);
    expectClose(batchQtyRemaining(item), 2, 0.02);
    expect(returnedQty(invoiceItemId)).toBeCloseTo(2, 4);

    // GL inventory for return 1: 2 × 100 = 200
    expect(cogsReversalForReturn(retId1)).toBeCloseTo(2 * cost, 1);

    // Return 2: 3 units
    const r2 = await api('post', `/api/invoices/${invoiceId}/return`, {
      items: [{ invoice_item_id: invoiceItemId, return_quantity: 3 }],
      disposition: 'credit',
    });
    expect(r2.status).toBe(200);
    const retId2 = r2.body.data?.returnId ?? r2.body.data?.id;

    // After return 2: stock restored by 3 more (total 5)
    expect(stockOf(item)).toBeCloseTo(beforeStock - sellQty + 5, 5);
    expectClose(batchQtyRemaining(item), 5, 0.02);
    expect(returnedQty(invoiceItemId)).toBeCloseTo(5, 4);

    // GL inventory for return 2: 3 × 100 = 300
    expect(cogsReversalForReturn(retId2)).toBeCloseTo(3 * cost, 1);

    // Cumulative: 5 units returned, 5 remaining on invoice
    // Invoice entitlement: returned_qty = 5
    expect(returnedQty(invoiceItemId)).toBeCloseTo(5, 4);

    // Stock movement audit: exactly 2 ADJUSTMENT/RETURN movements
    const movements = db.prepare(`
      SELECT quantity FROM stock_movements
      WHERE item_id = ? AND reference_docno = ? AND movement_type = 'ADJUSTMENT'
        AND reference_doctype = 'RETURN'
      ORDER BY id
    `).all(item, inv.body.invoice_no) as Array<{ quantity: number }>;
    expect(movements).toHaveLength(2);
    expect(movements[0].quantity).toBeCloseTo(2, 4);
    expect(movements[1].quantity).toBeCloseTo(3, 4);
  });
});
