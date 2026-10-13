/**
 * Audit regression tests, round 4 — production / BOM pass.
 * Each test encodes CORRECT behaviour. On commit 87f1265b every test is
 * expected to FAIL except the one marked GUARD, which passes today but must
 * keep passing once ACCT-002 (P&L covers every expense account) is applied.
 *
 *   PROD-001  consuming raw materials must relieve inventory in the GL
 *   PROD-001G GUARD: P&L profit must stay correct if account 7000 is included in the P&L
 *   PROD-001O overhead design: overhead_cost is capitalized once against unpaid overhead payable,
 *             with no separate expense or cash posting (user-approved D6 correction)
 *   PROD-002  output batch value must equal the cost posted to the GL (no 3dp unit-cost drift)
 *   PROD-004  a negative overhead must be rejected (no negative unit cost)
 *   PROD-005  deleting a production must restore stock exactly once, and not after output was sold
 *   PROD-006  production must not post into a closed accounting period
 *   PROD-007  an item must not be produced from itself
 *
 * Every test works on its own items and compares before/after deltas, so a
 * red test cannot cascade into another.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';

let cookie: string;
let warehouseId: number;
const post = (url: string, body: unknown) => request(app).post(url).set('Cookie', cookie).send(body as object);
const get = (url: string) => request(app).get(url).set('Cookie', cookie);
const del = (url: string) => request(app).delete(url).set('Cookie', cookie).send({});
const r2 = (v: number): number => Math.round(v * 100) / 100;
const r3 = (v: number): number => Math.round(v * 1000) / 1000;
const idOf = (res: request.Response): number => (res.body?.data?.id ?? res.body?.id) as number;

const glNet = (code: string): number => r2(Number((db.prepare(`
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS v
  FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
  WHERE jl.voided = 0 AND a.code = ?
`).get(code) as { v: number }).v));
const batchValue = (): number => r2(Number((db.prepare('SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) AS v FROM stock_batches').get() as { v: number }).v));
const stock = (itemId: number) => ({
  batches: r3(Number((db.prepare('SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ?').get(itemId) as { q: number }).q)),
  balances: r3(Number((db.prepare('SELECT COALESCE(SUM(quantity), 0) AS q FROM stock_balances WHERE item_id = ?').get(itemId) as { q: number }).q)),
});
const produce = (body: Record<string, unknown>) => post('/api/productions', {
  warehouse_id: warehouseId, production_date: '2026-09-10', ...body,
});
const reports = async () => ({
  pl: r2((await get('/api/reports/profit-loss?fromDate=2026-01-01&toDate=2026-12-31')).body.data.netProfit),
  bs: r2((await get('/api/reports/balance-sheet?asOfDate=2026-12-31')).body.data.equity.net_income_ytd),
});

beforeAll(async () => {
  cookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

describe('PROD-001: raw-material consumption is relieved from inventory', () => {
  it('GL inventory moves by exactly the change in batch value (produce 10 from 100 raw + 50 overhead)', async () => {
    const raw = await createItem('PROD-001 raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-001 finished', cookie);
    const glBefore = glNet('1200');
    const valueBefore = batchValue();
    const res = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }], overhead_cost: 50,
    });
    expect(res.status).toBe(201);
    // batches: -1000 raw consumed, +1050 finished goods => +50
    expect(r2(batchValue() - valueBefore)).toBe(50);
    expect(r2(glNet('1200') - glBefore)).toBe(r2(batchValue() - valueBefore));
  });

  it('book profit rises by the true profit (2,000 sales - 1,000 materials = 1,000) once the goods are sold', async () => {
    const raw = await createItem('PROD-001b raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-001b finished', cookie);
    const customerId = await createCustomer('PROD-001b customer', cookie);
    const before = await reports();
    const glBefore = glNet('1200');
    const valueBefore = batchValue();
    const res = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }],
    });
    expect(res.status).toBe(201);
    await createInvoice({ customerId, itemId: finished, lines: [{ quantity: 10, unitPrice: 200 }], invoiceDate: '2026-09-15', payment: 'full' }, cookie);
    const after = await reports();
    // no phantom inventory left behind once everything is sold
    expect(r2(glNet('1200') - glBefore)).toBe(r2(batchValue() - valueBefore));
    // balance-sheet net income (all accounts) must equal the true profit
    expect(r2(after.bs - before.bs)).toBe(1000);
  });

  it('PROD-001O: overhead accrues once as unpaid overhead payable (profit 950)', async () => {
    const bank = AccountingService.getAccountByCode(db, '1010')!;
    const equity = AccountingService.getAccountByCode(db, '3000')!;
    db.transaction(() => AccountingService.postEntry(db, {
      entry_date: '2026-09-01', description: 'PROD-001O funding', reference_type: 'OWNER_CAPITAL', reference_id: 0,
      lines: [{ account_id: bank.id, debit: 100 }, { account_id: equity.id, credit: 100 }],
    }))();
    const raw = await createItem('PROD-001o raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-001o finished', cookie);
    const customerId = await createCustomer('PROD-001o customer', cookie);
    const before = await reports();
    const payableBefore = glNet('2200');
    const cashBefore = glNet('1000');
    const bankBefore = glNet('1010');
    const expensesBefore = glNet('6000');
    const clearingBefore = glNet('7000');
    const res = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }], overhead_cost: 50,
    });
    expect(res.status).toBe(201);
    expect(r2(glNet('2200') - payableBefore)).toBe(-50);
    expect(glNet('1000')).toBe(cashBefore);
    expect(glNet('1010')).toBe(bankBefore);
    expect(glNet('6000')).toBe(expensesBefore);
    expect(glNet('7000')).toBe(clearingBefore);
    expect(r2((await reports()).pl - before.pl)).toBe(0);
    await createInvoice({ customerId, itemId: finished, lines: [{ quantity: 10, unitPrice: 200 }], invoiceDate: '2026-09-15', payment: 'full' }, cookie);
    const after = await reports();
    expect(r2(after.bs - before.bs)).toBe(950);
    expect(r2(after.pl - before.pl)).toBe(950);
    expect(r2(glNet('2200') - payableBefore)).toBe(-50);
  });

  it('GUARD: P&L profit still rises by 1,000 for the same scenario (must hold after ACCT-002 is applied)', async () => {
    const raw = await createItem('PROD-001g raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-001g finished', cookie);
    const customerId = await createCustomer('PROD-001g customer', cookie);
    const before = await reports();
    const res = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }],
    });
    expect(res.status).toBe(201);
    await createInvoice({ customerId, itemId: finished, lines: [{ quantity: 10, unitPrice: 200 }], invoiceDate: '2026-09-15', payment: 'full' }, cookie);
    const after = await reports();
    expect(r2(after.pl - before.pl)).toBe(1000);
  });
});

describe('PROD-002: unit-cost rounding must not create GL/batch drift', () => {
  it('output batch value equals the amount debited to inventory (7,000 units from 100,000)', async () => {
    const raw = await createItem('PROD-002 raw', cookie);
    await purchaseStock(raw, warehouseId, 100000, 1, cookie);
    const finished = await createItem('PROD-002 finished', cookie);
    const res = await produce({
      output_item_id: finished, output_quantity: 7000, input_items: [{ item_id: raw, quantity: 100000 }],
    });
    expect(res.status).toBe(201);
    const batch = db.prepare('SELECT quantity_original AS q, unit_cost AS uc FROM stock_batches WHERE item_id = ?').get(finished) as { q: number; uc: number };
    const debitedToInventory = r2(Number((db.prepare(`
      SELECT COALESCE(SUM(jl.debit), 0) AS v
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE a.code = '1200' AND jl.voided = 0 AND jl.reference_type = 'production'
        AND jl.reference_id IN (SELECT id FROM stock_movements WHERE item_id = ? AND movement_type = 'PRODUCTION')
    `).get(finished) as { v: number }).v));
    // Either design is valid (carry more unit-cost precision, or post qty x rounded unit cost),
    // as long as the books and the batch agree.
    expect(debitedToInventory).toBeGreaterThan(0);
    expect(r2(batch.q * batch.uc)).toBe(debitedToInventory);
  });
});

describe('PROD-004 / PROD-007: input validation', () => {
  it('rejects a negative overhead and creates no negative-cost batch', async () => {
    const raw = await createItem('PROD-004 raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 2, cookie);
    const finished = await createItem('PROD-004 finished', cookie);
    const res = await produce({
      output_item_id: finished, output_quantity: 1, input_items: [{ item_id: raw, quantity: 10 }], overhead_cost: -500,
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    const negative = (db.prepare('SELECT COUNT(*) AS n FROM stock_batches WHERE item_id = ? AND unit_cost < 0').get(finished) as { n: number }).n;
    expect(negative).toBe(0);
    expect(stock(finished).batches).toBe(0);
  });

  it('rejects producing an item from itself', async () => {
    const raw = await createItem('PROD-007 raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 2, cookie);
    const res = await produce({
      output_item_id: raw, output_quantity: 1, input_items: [{ item_id: raw, quantity: 1 }],
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});

describe('PROD-005: deleting a production', () => {
  it('restores raw-material stock exactly once (batches == balances == original)', async () => {
    const raw = await createItem('PROD-005 raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-005 finished', cookie);
    const original = stock(raw);
    const created = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }], overhead_cost: 50,
    });
    expect(created.status).toBe(201);
    const removed = await del(`/api/productions/${idOf(created)}`);
    expect(removed.status).toBe(200);
    expect(stock(raw)).toEqual(original);
    expect(stock(finished)).toEqual({ batches: 0, balances: 0 });
  });

  it('leaves the GL inventory in step with batch value after deleting an unsold production', async () => {
    const raw = await createItem('PROD-005b raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-005b finished', cookie);
    const glBefore = glNet('1200');
    const clearingBefore = glNet('7000');
    const valueBefore = batchValue();
    const created = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }], overhead_cost: 50,
    });
    expect(created.status).toBe(201);
    const removed = await del(`/api/productions/${idOf(created)}`);
    expect(removed.status).toBe(200);
    expect(r2(batchValue() - valueBefore)).toBe(0);
    expect(r2(glNet('1200') - glBefore)).toBe(0);
    expect(r2(glNet('7000') - clearingBefore)).toBe(0);
  });

  it('refuses to delete a production whose output has been (partly) sold', async () => {
    const raw = await createItem('PROD-005c raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-005c finished', cookie);
    const customerId = await createCustomer('PROD-005c customer', cookie);
    const created = await produce({
      output_item_id: finished, output_quantity: 10, input_items: [{ item_id: raw, quantity: 100 }],
    });
    expect(created.status).toBe(201);
    await createInvoice({ customerId, itemId: finished, lines: [{ quantity: 4, unitPrice: 300 }], invoiceDate: '2026-09-13' }, cookie);
    const rawBefore = stock(raw);
    const finishedBefore = stock(finished);
    const removed = await del(`/api/productions/${idOf(created)}`);
    expect(removed.status).toBeGreaterThanOrEqual(400);
    expect(stock(raw)).toEqual(rawBefore);
    expect(stock(finished)).toEqual(finishedBefore);
  });
});

describe('PROD-006: closed periods', () => {
  it('rejects a production dated inside a closed, custom-named period and posts nothing there', async () => {
    const raw = await createItem('PROD-006 raw', cookie);
    await purchaseStock(raw, warehouseId, 100, 10, cookie);
    const finished = await createItem('PROD-006 finished', cookie);
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('FY-PROD-REGRESSION', '2026-05-01', '2026-05-31', 'closed')
    `).run();
    const linesBefore = (db.prepare(`SELECT COUNT(*) AS n FROM journal_lines WHERE voided = 0 AND line_date BETWEEN '2026-05-01' AND '2026-05-31'`).get() as { n: number }).n;
    const res = await produce({
      output_item_id: finished, output_quantity: 1, input_items: [{ item_id: raw, quantity: 10 }], production_date: '2026-05-15',
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    const linesAfter = (db.prepare(`SELECT COUNT(*) AS n FROM journal_lines WHERE voided = 0 AND line_date BETWEEN '2026-05-01' AND '2026-05-31'`).get() as { n: number }).n;
    expect(linesAfter).toBe(linesBefore);
    db.prepare(`DELETE FROM accounting_periods WHERE period_name = 'FY-PROD-REGRESSION'`).run();
  });
});
