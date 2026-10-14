/**
 * Audit regression tests, round 2 — findings from the purchases / returns /
 * purchase-order / supplier-ledger pass. Each test encodes CORRECT behaviour
 * and is expected to FAIL on commit 87f1265b until the finding is fixed.
 *
 *   ACCT-005  cash purchases (no supplier) must respect the cash-funds guard
 *   ACCT-012  supplier balance must stay correct after a backdated purchase + payment
 *   PO-001    goods receipt must reject a non-numeric quantity and leave the PO line intact
 *   PRET-001  purchase-return amounts must be rounded to currency precision everywhere
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { getAuthCookie, createItem, purchaseStock, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';

let cookie: string;
let warehouseId: number;
const post = (url: string, body: unknown) => request(app).post(url).set('Cookie', cookie).send(body as object);
const r2 = (v: number): number => Math.round(v * 100) / 100;
const idOf = (res: request.Response): number => (res.body?.data?.id ?? res.body?.id) as number;

const glBalance = (code: string, side: 'debit' | 'credit'): number => r2(Number((db.prepare(`
  SELECT COALESCE(SUM(${side === 'debit' ? 'jl.debit - jl.credit' : 'jl.credit - jl.debit'}), 0) AS v
  FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
  WHERE jl.voided = 0 AND a.code = ?
`).get(code) as { v: number }).v));

const fundBank = (amount: number): void => {
  const bank = AccountingService.getAccountByCode(db, '1010')!;
  const equity = AccountingService.getAccountByCode(db, '3000')!;
  db.transaction(() => AccountingService.postEntry(db, {
    entry_date: '2026-09-01', description: 'regression funding', reference_type: 'OWNER_CAPITAL', reference_id: 0,
    lines: [{ account_id: bank.id, debit: amount }, { account_id: equity.id, credit: amount }],
  }))();
};

beforeAll(async () => {
  cookie = await getAuthCookie();
  warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
});

describe('ACCT-005: cash purchase must not overdraw the cash account', () => {
  it('rejects a supplier-less (cash) purchase larger than cash on hand', async () => {
    const itemId = await createItem('ACCT-005 item', cookie);
    const res = await post('/api/purchases', {
      item_id: itemId, warehouse_id: warehouseId, quantity: 1, unit_cost: 50000, purchase_date: '2026-09-02',
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(glBalance('1000', 'debit')).toBeGreaterThanOrEqual(0);
  });
});

describe('ACCT-012: supplier balance after a backdated purchase and a payment', () => {
  it('header balance, ledger total and GL AP all agree', async () => {
    const sup = await post('/api/suppliers', { supplier_code: 'REG-SUP', supplier_name: 'Regression Supplier' });
    const supplierId = idOf(sup);
    const itemId = await createItem('ACCT-012 item', cookie);
    const buy = async (date: string, cost: number): Promise<number> =>
      idOf(await post('/api/purchases', {
        item_id: itemId, warehouse_id: warehouseId, quantity: 1, unit_cost: cost, purchase_date: date, supplier_id: supplierId,
      }));
    const a = await buy('2026-09-20', 1000);
    await buy('2026-09-10', 500); // backdated: inserted later, dated earlier
    fundBank(100000);
    const pay = await post('/api/payments', {
      supplier_id: supplierId, payment_date: '2026-09-21', amount: 200, payment_method: 'bank',
      purchase_allocations: [{ purchase_id: a, amount: 200 }],
    });
    expect(pay.status).toBe(201);

    const header = r2((db.prepare('SELECT current_balance AS b FROM suppliers WHERE id = ?').get(supplierId) as { b: number }).b);
    const ledger = r2((db.prepare('SELECT COALESCE(SUM(debit - credit), 0) AS b FROM supplier_ledger WHERE supplier_id = ? AND voided = 0').get(supplierId) as { b: number }).b);
    expect(ledger).toBe(1300);
    expect(header).toBe(ledger);
    expect(glBalance('2000', 'credit')).toBe(ledger);
  });

  it('control: the customer side stays consistent for the same backdating pattern', async () => {
    const customerId = await createCustomer('ACCT-012 customer', cookie);
    const itemId = await createItem('ACCT-012 cust item', cookie);
    await purchaseStock(itemId, warehouseId, 20, 5, cookie);
    const late = await createInvoice({ customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], invoiceDate: '2026-09-20' }, cookie);
    await createInvoice({ customerId, itemId, lines: [{ quantity: 1, unitPrice: 50 }], invoiceDate: '2026-09-10' }, cookie);
    const pay = await post('/api/payments', {
      customer_id: customerId, payment_date: '2026-09-21', amount: 25, payment_method: 'cash',
      invoice_allocations: [{ invoice_id: late.invoiceId, amount: 25 }],
    });
    expect(pay.status).toBe(201);
    const header = r2((db.prepare('SELECT current_balance AS b FROM customers WHERE id = ?').get(customerId) as { b: number }).b);
    const ledger = r2((db.prepare('SELECT COALESCE(SUM(debit - credit), 0) AS b FROM customer_ledger WHERE customer_id = ? AND voided = 0').get(customerId) as { b: number }).b);
    expect(header).toBe(125);
    expect(header).toBe(ledger);
  });
});

describe('PO-001: goods receipt quantity validation', () => {
  it('rejects a non-numeric received_quantity and leaves the PO line untouched', async () => {
    const supplierId = (db.prepare(`SELECT id FROM suppliers WHERE supplier_code = 'RET-FIX-SUPPLIER'`).get() as { id: number }).id;
    const itemId = await createItem('PO-001 item', cookie);
    const po = await post('/api/purchase-orders', {
      supplier_id: supplierId, po_date: '2026-09-12', items: [{ item_id: itemId, quantity: 10, unit_price: 5 }],
    });
    const poId = idOf(po);
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(poId) as { id: number };
    await post(`/api/purchase-orders/${poId}/status`, { status: 'Submitted' });

    const res = await post(`/api/purchase-orders/${poId}/receipts`, {
      receipt_date: '2026-09-13', warehouse_id: warehouseId,
      items: [{ po_item_id: poItem.id, received_quantity: 'abc' }],
    });
    expect(res.status).toBeGreaterThanOrEqual(400);

    const line = db.prepare('SELECT received_quantity AS q FROM purchase_order_items WHERE id = ?').get(poItem.id) as { q: number | null };
    expect(line.q).toBe(0);
    const receipts = (db.prepare('SELECT COUNT(*) AS n FROM goods_receipts WHERE po_id = ?').get(poId) as { n: number }).n;
    expect(receipts).toBe(0);
  });
});

describe('PRET-001: purchase-return amounts are rounded to currency precision', () => {
  it('header, credit note, supplier ledger and GL carry the same 2dp amount', async () => {
    const supplierId = (db.prepare(`SELECT id FROM suppliers WHERE supplier_code = 'RET-FIX-SUPPLIER'`).get() as { id: number }).id;
    const itemId = await createItem('PRET-001 item', cookie);
    const purchaseId = idOf(await post('/api/purchases', {
      item_id: itemId, warehouse_id: warehouseId, quantity: 10, unit_cost: 10.55, purchase_date: '2026-09-02', supplier_id: supplierId,
    }));
    const ret = await post('/api/purchase-returns', {
      return_date: '2026-09-05', source_type: 'PURCHASE', source_id: purchaseId, warehouse_id: warehouseId,
      reason: 'regression', items: [{ source_item_id: purchaseId, quantity: 0.333 }],
    });
    expect(ret.status).toBe(201);
    const returnId = idOf(ret);

    const header = (db.prepare('SELECT total_amount AS v FROM purchase_returns WHERE id = ?').get(returnId) as { v: number }).v;
    const note = (db.prepare(`SELECT amount AS v FROM credit_notes WHERE source_type = 'PURCHASE_RETURN' AND source_id = ?`).get(returnId) as { v: number }).v;
    const ledger = (db.prepare(`SELECT credit AS v FROM supplier_ledger WHERE transaction_type = 'CREDIT_NOTE' ORDER BY id DESC LIMIT 1`).get() as { v: number }).v;
    const gl = (db.prepare(`SELECT COALESCE(SUM(credit), 0) AS v FROM journal_lines WHERE reference_type = 'PURCHASE_RETURN' AND reference_id = ? AND voided = 0`).get(returnId) as { v: number }).v;

    expect(gl).toBe(3.51);
    expect(header).toBe(3.51);
    expect(note).toBe(3.51);
    expect(ledger).toBe(3.51);
  });
});
