/**
 * Audit regression tests — ACCT-001..004 (P0/P1 accounting findings).
 *
 * Every test here encodes CORRECT behaviour and is expected to FAIL on
 * commit 87f1265b until the matching finding is fixed. Assertions are
 * deliberately fix-agnostic (they check observable accounting truth, not a
 * particular implementation), so any valid fix turns them green.
 *
 *   ACCT-004  new postings must never land in a closed accounting period
 *   ACCT-001  balance sheet must balance after a store-credit offset (acct 1110)
 *   ACCT-002  P&L net profit must equal balance-sheet net income (all revenue/expense accounts)
 *   ACCT-003  partial sales returns must restore exactly the returned quantity to batches
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import {
  getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice, processReturn,
} from './helpers/invoiceReturnSpec';

let cookie: string;
let warehouseId: number;

const post = (url: string, body: unknown) => request(app).post(url).set('Cookie', cookie).send(body as object);
const get = (url: string) => request(app).get(url).set('Cookie', cookie);
const r2 = (v: number): number => Math.round(v * 100) / 100;
// Stock quantities are DECIMAL(15,3): compare at 3dp or sub-cent errors (3.003 vs 3) are hidden.
const r3 = (v: number): number => Math.round(v * 1000) / 1000;

const line = (itemId: number, quantity: number, unitPrice: number) => ({
  item_id: itemId, quantity, unit_price: unitPrice, tax_rate: 0, discount_type: 'none', discount_value: 0,
});

beforeAll(async () => {
  cookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

// ───────────────────────────────────────────────────────────────────────────
// ACCT-004 — closed-period bypass on create
// A closed period whose name is NOT the calendar month ('YYYY-MM') used to be
// ignored by postEntry, which auto-created an overlapping OPEN month period.
// ───────────────────────────────────────────────────────────────────────────
describe('ACCT-004: no posting into a closed accounting period', () => {
  const CLOSED = 'FY-REGRESSION-JULY';
  const FROM = '2026-07-01';
  const TO = '2026-07-31';
  let itemId: number;
  let customerId: number;
  let supplierId: number;

  beforeAll(async () => {
    itemId = await createItem('ACCT-004 item', cookie);
    await purchaseStock(itemId, warehouseId, 50, 10, cookie);
    customerId = await createCustomer('ACCT-004 customer', cookie);
    supplierId = (db.prepare(`SELECT id FROM suppliers WHERE supplier_code = 'RET-FIX-SUPPLIER'`).get() as { id: number }).id;
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, ?, ?, 'closed')
    `).run(CLOSED, FROM, TO);
  });

  afterAll(() => {
    db.prepare(`DELETE FROM accounting_periods WHERE period_name = ?`).run(CLOSED);
  });

  const linesInClosedRange = (): number =>
    (db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines
      WHERE voided = 0 AND line_date BETWEEN ? AND ?
    `).get(FROM, TO) as { n: number }).n;

  const openPeriodsOverlappingClosed = (): number =>
    (db.prepare(`
      SELECT COUNT(*) AS n FROM accounting_periods
      WHERE status = 'open' AND NOT (end_date < ? OR start_date > ?)
    `).get(FROM, TO) as { n: number }).n;

  it('rejects an invoice dated inside the closed period and writes no GL lines', async () => {
    const before = linesInClosedRange();
    const res = await post('/api/invoices', {
      customer_id: customerId, invoice_date: '2026-07-15', due_date: '2027-01-01',
      items: [line(itemId, 1, 100)],
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(linesInClosedRange()).toBe(before);
    expect(openPeriodsOverlappingClosed()).toBe(0);
  });

  it('rejects a purchase dated inside the closed period and writes no GL lines', async () => {
    const before = linesInClosedRange();
    const res = await post('/api/purchases', {
      item_id: itemId, warehouse_id: warehouseId, quantity: 1, unit_cost: 10,
      purchase_date: '2026-07-20', supplier_id: supplierId,
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(linesInClosedRange()).toBe(before);
    expect(openPeriodsOverlappingClosed()).toBe(0);
  });

  it('AccountingService.postEntry itself refuses a date inside a closed period', () => {
    const cash = AccountingService.getAccountByCode(db, '1000')!;
    const equity = AccountingService.getAccountByCode(db, '3000')!;
    const attempt = db.transaction(() => AccountingService.postEntry(db, {
      entry_date: '2026-07-10',
      description: 'ACCT-004 direct post',
      reference_type: 'MANUAL_JOURNAL',
      reference_id: 0,
      lines: [
        { account_id: cash.id, debit: 1 },
        { account_id: equity.id, credit: 1 },
      ],
    }));
    expect(() => attempt()).toThrow(/closed|period/i);
    expect(openPeriodsOverlappingClosed()).toBe(0);
  });

  it('control: an invoice in an open period still succeeds', async () => {
    const res = await post('/api/invoices', {
      customer_id: customerId, invoice_date: '2026-09-15', due_date: '2027-01-01',
      items: [line(itemId, 1, 100)],
    });
    expect([200, 201]).toContain(res.status);
  });
});

// ───────────────────────────────────────────────────────────────────────────
// ACCT-003 — partial-return restock rounding
// restoreQty used roundQty(returned/sold) at 3dp before multiplying back, so
// batches gained 3.003 for a return of 3, nothing for 1-of-3000, etc.
// ───────────────────────────────────────────────────────────────────────────
describe('ACCT-003: a partial return restores exactly the returned quantity', () => {
  const batchQty = (itemId: number): number =>
    (db.prepare('SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches WHERE item_id = ?').get(itemId) as { q: number }).q;
  const balanceQty = (itemId: number): number =>
    (db.prepare('SELECT COALESCE(SUM(quantity), 0) AS q FROM stock_balances WHERE item_id = ?').get(itemId) as { q: number }).q;

  it.each([
    { sold: 7, returned: 3 },
    { sold: 3, returned: 1 },
    { sold: 1500, returned: 1 },
    { sold: 3000, returned: 1 },
    { sold: 1000, returned: 1 }, // control: ratio is exact at 3dp
  ])('sold $sold, return $returned', async ({ sold, returned }) => {
    const customerId = await createCustomer(`ACCT-003 cust ${sold}/${returned}`, cookie);
    const itemId = await createItem(`ACCT-003 item ${sold}/${returned}`, cookie);
    await purchaseStock(itemId, warehouseId, 5000, 10, cookie);
    const invoice = await createInvoice({
      customerId, itemId, lines: [{ quantity: sold, unitPrice: 20 }], invoiceDate: '2026-09-15',
    }, cookie);

    const before = batchQty(itemId);
    const ret = await processReturn(invoice.invoiceId, {
      invoiceItemIds: invoice.invoiceItemIds, quantities: [returned], warehouseId,
      returnDate: '2026-09-16', settlements: [],
    }, cookie);
    expect(ret.status).toBe(200);

    expect(r3(batchQty(itemId) - before)).toBe(returned);
    expect(r3(batchQty(itemId))).toBe(5000 - sold + returned);
    // batches and the stock summary must agree after the return
    expect(r3(batchQty(itemId))).toBe(r3(balanceQty(itemId)));
  });
});

// ───────────────────────────────────────────────────────────────────────────
// ACCT-001 — balance sheet must balance after a store-credit offset
// Account 1110 (Customer Credit) is credit-normal but only ever debited, and
// the balance sheet summed asset balances without respecting its sign.
// ───────────────────────────────────────────────────────────────────────────
describe('ACCT-001: balance sheet after a store-credit offset', () => {
  const AS_OF = '2026-12-31';

  const glSignedSum = (type: string): number =>
    r2((db.prepare(`
      SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS v
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE jl.voided = 0 AND a.type = ? AND jl.line_date <= ?
    `).get(type, AS_OF) as { v: number }).v);

  let customerId: number;

  beforeAll(async () => {
    customerId = await createCustomer('ACCT-001 customer', cookie);
    const itemId = await createItem('ACCT-001 item', cookie);
    await purchaseStock(itemId, warehouseId, 100, 50, cookie);

    const paid = await createInvoice({
      customerId, itemId, lines: [{ quantity: 3, unitPrice: 100 }], invoiceDate: '2026-09-15', payment: 'full',
    }, cookie);
    const ret = await processReturn(paid.invoiceId, {
      invoiceItemIds: paid.invoiceItemIds, quantities: [2], warehouseId, returnDate: '2026-09-16',
      settlements: [{ type: 'credit', amount: 200 }],
    }, cookie);
    expect(ret.status).toBe(200);

    const offset = await post('/api/invoices', {
      customer_id: customerId, invoice_date: '2026-09-17', due_date: '2027-01-01', credit_offset: 200,
      items: [line(itemId, 3, 100)],
    });
    expect([200, 201]).toContain(offset.status);
  });

  it('trial balance balances (control)', async () => {
    const tb = (await get(`/api/reports/trial-balance?asOfDate=${AS_OF}`)).body.data;
    expect(tb.balanced).toBe(true);
  });

  it('balance sheet reports balanced', async () => {
    const bs = (await get(`/api/reports/balance-sheet?asOfDate=${AS_OF}`)).body.data;
    expect(bs.totals.balanced).toBe(true);
    expect(r2(bs.totals.total_assets)).toBe(r2(bs.totals.total_liab_and_equity));
  });

  it('balance-sheet total assets equals the signed GL sum of asset accounts', async () => {
    const bs = (await get(`/api/reports/balance-sheet?asOfDate=${AS_OF}`)).body.data;
    expect(r2(bs.totals.total_assets)).toBe(glSignedSum('asset'));
  });

  it('accounting identity holds against the GL (assets = -(liabilities + equity + revenue + expense))', async () => {
    const bs = (await get(`/api/reports/balance-sheet?asOfDate=${AS_OF}`)).body.data;
    // Σ(debit-credit) over assets == -(Σ(debit-credit) over liab+equity+revenue+expense)
    const rest = ['liability', 'equity', 'revenue', 'expense'].reduce((s, t) => s + glSignedSum(t), 0);
    expect(r2(bs.totals.total_assets)).toBe(r2(-rest));
  });

  it('control: sign-aware GL receivable (1100 + 1110) equals the customer subledger total', () => {
    const gl = (code: string): number => Number((db.prepare(`
      SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS v
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE jl.voided = 0 AND a.code = ?
    `).get(code) as { v: number }).v);
    const row = db.prepare('SELECT COALESCE(SUM(current_balance), 0) AS cb, COALESCE(SUM(credit_balance), 0) AS cr FROM customers').get() as { cb: number; cr: number };
    // No abs(): the net receivable must agree in sign as well as magnitude.
    expect(r2(gl('1100') + gl('1110'))).toBe(r2(row.cb - row.cr));
  });
});

// ───────────────────────────────────────────────────────────────────────────
// ACCT-002 — P&L must cover every revenue/expense account
// P&L read only 4000/4100/5000/6000; restocking-fee income (4150), payroll
// (6100) and 7xxx accounts were invisible, so P&L != balance-sheet net income.
// ───────────────────────────────────────────────────────────────────────────
describe('ACCT-002: P&L net profit equals balance-sheet net income', () => {
  const FROM = '2026-01-01';
  const TO = '2026-12-31';

  const netIncomes = async (): Promise<{ pl: number; bs: number }> => {
    const pl = (await get(`/api/reports/profit-loss?fromDate=${FROM}&toDate=${TO}`)).body.data;
    const bs = (await get(`/api/reports/balance-sheet?asOfDate=${TO}`)).body.data;
    return { pl: r2(pl.netProfit), bs: r2(bs.equity.net_income_ytd) };
  };

  let customerId: number;
  let itemId: number;

  beforeAll(async () => {
    customerId = await createCustomer('ACCT-002 customer', cookie);
    itemId = await createItem('ACCT-002 item', cookie);
    await purchaseStock(itemId, warehouseId, 100, 50, cookie);
  });

  it('control: P&L matches the balance sheet for plain sales', async () => {
    await createInvoice({ customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], invoiceDate: '2026-09-15', payment: 'full' }, cookie);
    const { pl, bs } = await netIncomes();
    expect(pl).toBe(bs);
  });

  it('includes restocking-fee income (4150)', async () => {
    const invoice = await createInvoice({ customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], invoiceDate: '2026-09-16', payment: 'full' }, cookie);
    const ret = await processReturn(invoice.invoiceId, {
      invoiceItemIds: invoice.invoiceItemIds, quantities: [1], feeType: 'fixed', feeValue: 20,
      warehouseId, returnDate: '2026-09-17', settlements: [],
    }, cookie);
    expect(ret.status).toBe(200);
    const { pl, bs } = await netIncomes();
    expect(pl).toBe(bs);
  });

  it('includes payroll expense (6100)', async () => {
    db.transaction(() => AccountingService.postSalaryEntry(db, {
      salaryPaymentId: 987001, employeeName: 'Regression', employeeCode: 'REG1',
      amount: 500, paymentDate: '2026-09-20', paymentMethod: 'cash',
    }))();
    const { pl, bs } = await netIncomes();
    expect(pl).toBe(bs);
  });

  it('includes inventory shrinkage (7200)', async () => {
    const shrink = AccountingService.getAccountByCode(db, '7200')!;
    const inventory = AccountingService.getAccountByCode(db, '1200')!;
    db.transaction(() => AccountingService.postEntry(db, {
      entry_date: '2026-09-21', description: 'ACCT-002 shrinkage', reference_type: 'MANUAL_JOURNAL', reference_id: 0,
      lines: [{ account_id: shrink.id, debit: 30 }, { account_id: inventory.id, credit: 30 }],
    }))();
    const { pl, bs } = await netIncomes();
    expect(pl).toBe(bs);
  });
});
