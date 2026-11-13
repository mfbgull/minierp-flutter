/**
 * Closed accounting period immutability regression (H6).
 *
 * Once a period is closed, no server-side operation may silently rewrite
 * accounting history (GL, customer ledger, supplier ledger, payments,
 * invoices, expenses, returns, purchases, or owner transactions) inside
 * that period. The server must enforce this; UI hiding is insufficient.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import InvoiceModel from '../models/Invoice';
import PurchaseModel from '../models/Purchase';
import { getAuthCookie, createItem, purchaseStock, purchaseWithNamedSupplier, createCustomer, createInvoice } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { SupplierPaymentService } from '../services/SupplierPaymentService';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}

let token: string;
let warehouseId: number;

beforeAll(async () => {
  token = await getAuthCookie();
  const wh = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
  warehouseId = wh.id;
});

// Every case runs inside a SAVEPOINT that afterEach rolls back. Two reasons:
// 1. Isolation — the legacy cases below raw-insert GL-less dummy rows (the
//    known "expense 500" noise); without rollback that noise breaks the
//    accounting invariants of every later case.
// 2. Red-phase safety — a case exercising an unguarded path cannot leak its
//    mutations into the next case.
beforeEach(() => {
  db.exec('SAVEPOINT closed_period_case');
});

afterEach(() => {
  db.exec('ROLLBACK TO closed_period_case; RELEASE closed_period_case');
});

function api(method: 'get' | 'post' | 'put' | 'delete', url: string, body?: Record<string, unknown>) {
  return request(app)[method](url)
    .set('Cookie', token)
    .set('Idempotency-Key', `cp-${Math.abs(hashCode(url + JSON.stringify(body ?? {})))}`)
    .send(body);
}

// Deterministic keys so each distinct request body keeps its own idempotency
// slot — the supplier-refund endpoints mandate the header (ACCT-008).
function hashCode(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = (hash * 31 + value.charCodeAt(i)) | 0;
  }
  return hash;
}

function closePeriodFor(date: string, name = '2026-09-closed-for-test') {
  const start = `${date.slice(0, 7)}-01`;
  const end = `${date.slice(0, 7)}-31`;
  db.prepare(`
    INSERT INTO accounting_periods (period_name, start_date, end_date, status)
    VALUES (?, ?, ?, 'open')
    ON CONFLICT(period_name) DO NOTHING
  `).run(name, start, end);
  db.prepare(`UPDATE accounting_periods SET status = 'closed' WHERE period_name = ?`).run(name);
}

describe('Closed accounting period immutability (H6)', () => {
  it('blocks payment void in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust', token);
    const item = await createItem('Closed Period Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const voidRes = await api('delete', `/api/payments/${paymentId}`);
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT voided_at FROM payments WHERE id = ?').get(paymentId) as { voided_at: string | null };
    expect(p.voided_at).toBeNull();
  });

  it('blocks payment date edit in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust2', token);
    const item = await createItem('Closed Period Item2', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/payments/${paymentId}`, {
      payment_date: '2026-09-15',
      reference_no: 'changed',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT payment_date, reference_no FROM payments WHERE id = ?').get(paymentId) as { payment_date: string; reference_no: string };
    expect(p.payment_date).toBe('2026-09-10');
    expect(p.reference_no).toBe('');
  });

  it('blocks payment method edit in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust3', token);
    const item = await createItem('Closed Period Item3', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-10',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/payments/${paymentId}`, {
      payment_method: 'Bank',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT payment_method FROM payments WHERE id = ?').get(paymentId) as { payment_method: string };
    expect(p.payment_method).toBe('Cash');
  });

  it('blocks invoice cancellation in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust4', token);
    const item = await createItem('Closed Period Item4', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const invoiceId = inv.invoiceId;

    closePeriodFor('2026-09-10');
    const cancelRes = await api('put', `/api/invoices/${invoiceId}/cancel`);
    expect(cancelRes.status).toBe(409);
    expect(JSON.stringify(cancelRes.body)).toMatch(/closed|period/i);

    const invRow = db.prepare('SELECT status FROM invoices WHERE id = ?').get(invoiceId) as { status: string };
    expect(invRow.status).not.toBe('Cancelled');
  });

  it('blocks expense edit in closed period', async () => {
    const expenseId = db.prepare(`
      INSERT INTO expenses (expense_no, expense_category, description, amount, expense_date, payment_method, status, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run('EXP-CLOSED-1', 'Utilities', 'Electricity', 500, '2026-09-10', 'Cash', 'Recorded', 1).lastInsertRowid as number;

    closePeriodFor('2026-09-10');
    const editRes = await api('put', `/api/expenses/${expenseId}`, {
      amount: 600,
      expense_date: '2026-09-10',
    });
    expect(editRes.status).toBe(409);
    expect(JSON.stringify(editRes.body)).toMatch(/closed|period/i);

    const e = db.prepare('SELECT amount FROM expenses WHERE id = ?').get(expenseId) as { amount: number };
    expect(e.amount).toBe(500);
  });

  it('blocks purchase void in closed period', async () => {
    const item = await createItem('Closed Period Item6', token);
    const purchaseId = db.prepare(`
      INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost, purchase_date, supplier_name, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run('PO-CLOSED-1', item, warehouseId, 10, 100, 1000, '2026-09-10', 'Test Supplier', 1).lastInsertRowid as number;

    closePeriodFor('2026-09-10');
    const voidRes = await api('post', `/api/purchases/${purchaseId}/void`, { reason: 'test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT voided_at FROM purchases WHERE id = ?').get(purchaseId) as { voided_at: string | null };
    expect(p.voided_at).toBeNull();
  });

  it('blocks sales return void in closed period', async () => {
    const customer = await createCustomer('Closed Period Cust5', token);
    const item = await createItem('Closed Period Item5', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const retRes = await api('post', `/api/invoices/${inv.invoiceId}/return`, {
      items: [{ invoice_item_id: inv.invoiceItemIds[0], return_quantity: 2 }],
      disposition: 'credit',
      return_date: '2026-09-10',
    });
    expect(retRes.status).toBe(200);
    const returnId = retRes.body.data.returnId;

    closePeriodFor('2026-09-10');
    const voidRes = await api('post', `/api/invoice-returns/${returnId}/void`, { reason: 'test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);
  });

  it('allows the same operations in an open period', async () => {
    const customer = await createCustomer('Open Period Cust', token);
    const item = await createItem('Open Period Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-20',
    }, token);

    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: '2026-09-20',
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    const paymentId = payRes.body.data.id;
    const voidRes = await api('delete', `/api/payments/${paymentId}`);
    expect(voidRes.status).toBe(200);

    const cancelRes = await api('put', `/api/invoices/${inv.invoiceId}/cancel`);
    expect(cancelRes.status).toBe(200);
  });
});

// ════════════════════════════════════════════════════════════════════════
// Period-protection primitive — Phase 0–3 (tasks.md done-when conditions)
//
// Each refusal case proves three things (task 4.2):
//   1. the refused status (409, or a direct-model throw),
//   2. that GL, ledger, and stock state are byte-identical to before, and
//   3. that the whole-DB accounting invariants still hold (task 4.3).
// ════════════════════════════════════════════════════════════════════════

/** Serialized totals: GL by account, ledgers, batches, movements. */
function financialTotalsSnapshot(): string {
  const gl = db.prepare(`
    SELECT c.text_code,
           ROUND(SUM(jl.debit), 2) AS debit_total,
           ROUND(SUM(jl.credit), 2) AS credit_total,
           COUNT(*) AS line_count,
           SUM(jl.voided) AS voided_lines
    FROM journal_lines jl
    JOIN chart_of_accounts c ON c.id = jl.account_id
    GROUP BY c.text_code
    ORDER BY c.text_code
  `).all();
  const customerLedger = db.prepare(`
    SELECT COUNT(*) AS rows_n, SUM(voided) AS voided_n,
           ROUND(SUM(debit), 2) AS debit_total, ROUND(SUM(credit), 2) AS credit_total
    FROM customer_ledger
  `).get();
  const supplierLedger = db.prepare(`
    SELECT COUNT(*) AS rows_n, SUM(voided) AS voided_n,
           ROUND(SUM(debit), 2) AS debit_total, ROUND(SUM(credit), 2) AS credit_total
    FROM supplier_ledger
  `).get();
  const batches = db.prepare(`
    SELECT COUNT(*) AS rows_n, SUM(quantity_remaining) AS remaining_qty,
           ROUND(SUM(quantity_remaining * unit_cost), 2) AS remaining_value
    FROM stock_batches
  `).get();
  const movements = db.prepare(`
    SELECT COUNT(*) AS rows_n, SUM(quantity) AS qty_total,
           ROUND(SUM(CASE WHEN quantity >= 0 THEN quantity * unit_cost ELSE 0 END), 2) AS inflow_value,
           ROUND(SUM(CASE WHEN quantity < 0 THEN quantity * unit_cost ELSE 0 END), 2) AS outflow_value
    FROM stock_movements
  `).get();
  const periods = db.prepare(`
    SELECT period_name, status FROM accounting_periods ORDER BY id
  `).all();
  return JSON.stringify({ gl, customerLedger, supplierLedger, batches, movements, periods });
}

describe('Period-protection primitive phases', () => {
  /** Seed a paid, dated 2026-09-10 customer payment via fixed raw rows. */
  async function seedPaidInvoiceForPeriod(nameSuffix: string, invoiceDate = '2026-09-10') {
    const customer = await createCustomer(`Primitive Cust ${nameSuffix}`, token);
    const item = await createItem(`Primitive Item ${nameSuffix}`, token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate,
    }, token);
    const payRes = await api('post', '/api/payments', {
      customer_id: customer,
      amount: 200,
      payment_method: 'Cash',
      payment_date: invoiceDate,
      invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 200 }],
    });
    expect(payRes.status).toBe(201);
    return { invoiceId: inv.invoiceId, paymentId: payRes.body.data.id as number, customerId: customer };
  }

  // ── Phase 0.1: the primitive itself refuses closed-period voids ──
  it('voidJournalLinesByReference refuses a closed-period reference with no caller guard', async () => {
    const { invoiceId } = await seedPaidInvoiceForPeriod('0.1');

    closePeriodFor('2026-09-10');
    // Snapshot AFTER closing: the period row itself is test setup. The refusal
    // must leave everything — including the new period row — byte-identical.
    const before = financialTotalsSnapshot();

    expect(() =>
      AccountingService.voidJournalLinesByReference(db, 'INVOICE', invoiceId)
    ).toThrow(/inside closed accounting period/);

    expect(financialTotalsSnapshot()).toBe(before);
    expectAllInvariantsHold('after primitive refusal');
  });

  // ── Phase 0.3: model-layer guards without the controller ──
  it('Purchase.void throws at the model layer for a closed-period purchase', async () => {
    const supplierId = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_code: 'PRIM-VOID-SUP', supplier_name: 'Primitive Void Supplier' })
      .then(r => r.body?.data?.id as number);
    const res = await request(app).post('/api/purchases').set('Cookie', token)
      .send({
        item_id: await createItem('Primitive Purchase Item', token),
        warehouse_id: warehouseId,
        quantity: 10, unit_cost: 100,
        purchase_date: '2026-09-05',
        supplier_id: supplierId,
      });
    expect([200, 201]).toContain(res.status);
    const purchaseId = (db.prepare(
      `SELECT id FROM purchases WHERE supplier_id = ? ORDER BY id DESC LIMIT 1`
    ).get(supplierId) as { id: number }).id;

    closePeriodFor('2026-09-05');
    const before = financialTotalsSnapshot();

    expect(() =>
      PurchaseModel.void(purchaseId, 1, 'model-layer closed-period test', db)
    ).toThrow(/inside closed accounting period/);

    expect(financialTotalsSnapshot()).toBe(before);
    expectAllInvariantsHold('after purchase model refusal');
  });

  it('Invoice cancel throws at the model layer for a closed-period invoice', async () => {
    const customer = await createCustomer('Primitive Cancel Cust', token);
    const item = await createItem('Primitive Cancel Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);

    closePeriodFor('2026-09-10');
    const before = financialTotalsSnapshot();

    expect(() =>
      InvoiceModel.cancelInvoiceInternal(db, InvoiceModel.getById(inv.invoiceId, db)!, 1)
    ).toThrow(/inside closed accounting period/);

    expect(financialTotalsSnapshot()).toBe(before);
    expectAllInvariantsHold('after invoice model refusal');
  });

  // ── Phase 1.1: goods-receipt void (PUR-003) ──
  async function seedReceipt(receiptDate: string): Promise<{ poId: number; receiptId: number; poItemId: number; itemId: number }> {
    const itemId = await createItem(`Primitive PO Item ${receiptDate}`, token);
    const supplierId = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_code: `PRIM-PO-SUP-${receiptDate}`, supplier_name: `Primitive PO Supplier ${receiptDate}` })
      .then(r => r.body?.data?.id as number);
    const poRes = await request(app).post('/api/purchase-orders').set('Cookie', token)
      .send({
        supplier_id: supplierId,
        po_date: receiptDate,
        items: [{ item_id: itemId, quantity: 10, unit_price: 100 }],
      });
    expect(poRes.status).toBeLessThan(300);
    const poId = (poRes.body?.data?.id ?? poRes.body?.id) as number;
    const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ? ORDER BY id LIMIT 1').get(poId) as { id: number };
    const submit = await request(app).post(`/api/purchase-orders/${poId}/status`).set('Cookie', token)
      .send({ status: 'Submitted' });
    expect(submit.status).toBeLessThan(300);
    const receiptRes = await request(app).post(`/api/purchase-orders/${poId}/receipts`).set('Cookie', token)
      .send({
        receipt_date: receiptDate,
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItem.id, received_quantity: 10 }],
      });
    expect(receiptRes.status).toBeLessThan(300);
    const receiptId = (receiptRes.body?.data?.id ?? receiptRes.body?.id) as number;
    return { poId, receiptId, poItemId: poItem.id, itemId };
  }

  it('goods receipt void in a closed period returns 409 and changes nothing (PUR-003)', async () => {
    const { receiptId } = await seedReceipt('2026-03-05');

    closePeriodFor('2026-03-05');
    const before = financialTotalsSnapshot();

    const voidRes = await api('post', `/api/purchase-orders/1/receipts/${receiptId}/void`, { reason: 'closed-period test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    expect(financialTotalsSnapshot()).toBe(before);
    const receipt = db.prepare('SELECT voided_at FROM goods_receipts WHERE id = ?').get(receiptId) as { voided_at: string | null };
    expect(receipt.voided_at).toBeNull();
    expectAllInvariantsHold('after GRN void refusal');
  });

  // ── Phase 1.2: supplier-refund void honours the closed period (HTTP) ──
  it('supplier refund void in a closed period returns 409 and changes nothing', async () => {
    const itemId = await createItem('Primitive Refund Item', token);
    const purchaseRes = await purchaseWithNamedSupplier('Primitive Refund Supplier', {
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 1,
      unit_cost: 100,
      purchase_date: '2026-09-03',
    }, token);
    expect(purchaseRes.status).toBeLessThan(300);
    const purchaseId = (purchaseRes.body.data?.id ?? purchaseRes.body.id) as number;
    const supplierId = (db.prepare('SELECT supplier_id FROM purchases WHERE id = ?')
      .get(purchaseId) as { supplier_id: number }).supplier_id;

    // Opening cash so the supplier payment passes the cash-balance guard.
    const capRes = await api('post', '/api/owner-equity/capital', {
      amount: 1000, capital_date: '2026-09-01', payment_method: 'Cash',
    });
    expect(capRes.status).toBeLessThan(300);
    new SupplierPaymentService(db).recordSupplierPayment({
      supplierId,
      paymentDate: '2026-09-03',
      amount: 100,
      paymentMethod: 'Cash',
      allocations: [{ kind: 'purchase', id: purchaseId, amount: 100 }],
    });

    const returned = await api('post', '/api/purchase-returns', {
      return_date: '2026-09-04',
      source_type: 'PURCHASE',
      source_id: purchaseId,
      warehouse_id: warehouseId,
      disposition: 'credit_on_account',
      items: [{ source_item_id: purchaseId, quantity: 1 }],
    });
    expect(returned.status).toBeLessThan(300);
    const returnId = (returned.body.data?.id ?? returned.body.id) as number;
    const note = db.prepare('SELECT id FROM credit_notes WHERE source_id = ?')
      .get(returnId) as { id: number };

    const refundRes = await api('post', '/api/supplier-refunds', {
      refund_date: '2026-09-08',
      credit_note_id: note.id,
      amount: 100,
      payment_method: 'Cash',
    });
    expect(refundRes.status).toBe(201);
    const refundId = refundRes.body.data.id as number;

    closePeriodFor('2026-09-08');
    const before = financialTotalsSnapshot();

    const voidRes = await api('post', `/api/supplier-refunds/${refundId}/void`, { reason: 'closed-period test' });
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    expect(financialTotalsSnapshot()).toBe(before);
    const refund = db.prepare('SELECT status FROM supplier_refunds WHERE id = ?')
      .get(refundId) as { status: string };
    expect(refund.status).toBe('POSTED');
    expectAllInvariantsHold('after supplier refund void refusal');
  });

  // ── Phase 1.3: invoice restore honours the closed period ──
  it('invoice restore in a closed period returns 409 and changes nothing', async () => {
    const customer = await createCustomer('Primitive Restore Cust', token);
    const item = await createItem('Primitive Restore Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 10, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const delRes = await api('delete', `/api/invoices/${inv.invoiceId}`);
    expect(delRes.status).toBeLessThan(300);

    closePeriodFor('2026-09-10');
    const before = financialTotalsSnapshot();

    const restoreRes = await api('post', `/api/invoices/${inv.invoiceId}/restore`);
    expect(restoreRes.status).toBe(409);
    expect(JSON.stringify(restoreRes.body)).toMatch(/closed|period/i);

    expect(financialTotalsSnapshot()).toBe(before);
    const row = db.prepare('SELECT deleted_at FROM invoices WHERE id = ?').get(inv.invoiceId) as { deleted_at: string | null };
    expect(row.deleted_at).not.toBeNull();
    expectAllInvariantsHold('after restore refusal');
  });

  // ── Audit-driven control: the open-period twin still works end-to-end ──
  it('goods receipt void in an open period still succeeds', async () => {
    const { receiptId } = await seedReceipt('2026-09-09');
    const voidRes = await api('post', `/api/purchase-orders/1/receipts/${receiptId}/void`, { reason: 'open-period control' });
    expect(voidRes.status).toBeLessThan(300);
    expectAllInvariantsHold('after open-period GRN void');
  });

  // ── Phase 2.1: a document date never creates a future period ──
  const FUTURE_DATE = '2027-06-15';

  it('a future-dated purchase is refused and creates no period', async () => {
    const supplierId = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_code: 'PRIM-FUT-SUP', supplier_name: 'Primitive Future Supplier' })
      .then(r => r.body?.data?.id as number);
    const itemId = await createItem('Primitive Future Item', token);
    const before = financialTotalsSnapshot();

    const res = await request(app).post('/api/purchases').set('Cookie', token)
      .send({
        item_id: itemId, warehouse_id: warehouseId,
        quantity: 10, unit_cost: 100,
        purchase_date: FUTURE_DATE,
        supplier_id: supplierId,
      });
    expect(res.status).toBe(400);

    expect(financialTotalsSnapshot()).toBe(before);
    const futurePeriod = db.prepare(
      `SELECT id FROM accounting_periods WHERE period_name = '2027-06'`
    ).get();
    expect(futurePeriod).toBeUndefined();
    expectAllInvariantsHold('after future purchase refusal');
  });

  it('a future-dated invoice is refused and creates no period', async () => {
    const customer = await createCustomer('Primitive Future Cust', token);
    const item = await createItem('Primitive Future Sale Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    const before = financialTotalsSnapshot();

    const res = await request(app).post('/api/invoices').set('Cookie', token)
      .send({
        customer_id: customer,
        invoice_date: FUTURE_DATE,
        items: [{ item_id: item, quantity: 1, unit_price: 200 }],
      });
    expect(res.status).toBe(400);

    expect(financialTotalsSnapshot()).toBe(before);
    const futurePeriod = db.prepare(
      `SELECT id FROM accounting_periods WHERE period_name = '2027-06'`
    ).get();
    expect(futurePeriod).toBeUndefined();
    expectAllInvariantsHold('after future invoice refusal');
  });

  it('a future date on an invoice update is refused with 400, not 500', async () => {
    const customer = await createCustomer('Primitive Future Upd Cust', token);
    const item = await createItem('Primitive Future Upd Item', token);
    await purchaseStock(item, warehouseId, 10, 100, token);
    // The invoice itself exists at a valid past date; only the EDIT carries
    // a future date — the update path re-posts GL, so the same refusal
    // must hold and the client must see a 400, not a 500.
    const inv = await createInvoice({
      customerId: customer,
      itemId: item,
      lines: [{ quantity: 1, unitPrice: 200 }],
      invoiceDate: '2026-09-10',
    }, token);
    const before = financialTotalsSnapshot();

    const res = await request(app).put(`/api/invoices/${inv.invoiceId}`).set('Cookie', token)
      .send({
        customer_id: customer,
        invoice_date: FUTURE_DATE,
        due_date: '2030-01-01',
        items: [{ item_id: item, description: 'future-dated edit', quantity: 1, unit_price: 200, tax_rate: 0, discount_type: 'none', discount_value: 0 }],
        total_amount: 200,
      });
    expect(res.status).toBe(400);
    // The rejection must come from the future-date guard, not some other 400.
    expect(String(res.body?.error)).toMatch(/future/i);

    expect(financialTotalsSnapshot()).toBe(before);
    const futurePeriod = db.prepare(
      `SELECT id FROM accounting_periods WHERE period_name = '2027-06'`
    ).get();
    expect(futurePeriod).toBeUndefined();
    expectAllInvariantsHold('after future invoice update refusal');
  });


  it('a future-dated goods receipt is refused and creates no period', async () => {
    const itemId = await createItem('Primitive Future GRN Item', token);
    const supplierId = await request(app).post('/api/suppliers').set('Cookie', token)
      .send({ supplier_code: 'PRIM-FUT-GRN-SUP', supplier_name: 'Primitive Future GRN Supplier' })
      .then(r => r.body?.data?.id as number);
    const poRes = await request(app).post('/api/purchase-orders').set('Cookie', token)
      .send({
        supplier_id: supplierId,
        po_date: '2026-09-01',
        items: [{ item_id: itemId, quantity: 10, unit_price: 100 }],
      });
    expect(poRes.status).toBeLessThan(300);
    const poId = (poRes.body?.data?.id ?? poRes.body?.id) as number;
    const poItem = db.prepare(
      'SELECT id FROM purchase_order_items WHERE po_id = ? ORDER BY id LIMIT 1'
    ).get(poId) as { id: number };
    const submit = await request(app).post(`/api/purchase-orders/${poId}/status`).set('Cookie', token)
      .send({ status: 'Submitted' });
    expect(submit.status).toBeLessThan(300);
    const before = financialTotalsSnapshot();

    // The receipt endpoint refuses a future receipt_date before any write.
    const res = await request(app).post(`/api/purchase-orders/${poId}/receipts`).set('Cookie', token)
      .send({
        receipt_date: '2030-01-01',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItem.id, received_quantity: 1 }],
      });
    expect(res.status).toBe(400);

    expect(financialTotalsSnapshot()).toBe(before);
    const futurePeriod = db.prepare(
      `SELECT id FROM accounting_periods WHERE period_name = '2030-01'`
    ).get();
    expect(futurePeriod).toBeUndefined();
    expectAllInvariantsHold('after future receipt refusal');
  });

  it('a future-dated stock adjustment is refused and creates no period', async () => {
    const item = await createItem('Primitive Future Adj Item', token);
    const before = financialTotalsSnapshot();

    const res = await request(app).post('/api/inventory/stock-movements').set('Cookie', token)
      .send({
        item_id: item, warehouse_id: warehouseId,
        quantity: 5, movement_type: 'ADJUSTMENT',
        movement_date: FUTURE_DATE,
      });
    expect(res.status).toBe(400);

    expect(financialTotalsSnapshot()).toBe(before);
    const futurePeriod = db.prepare(
      `SELECT id FROM accounting_periods WHERE period_name = '2027-06'`
    ).get();
    expect(futurePeriod).toBeUndefined();
    expectAllInvariantsHold('after future adjustment refusal');
  });

  it('a closed-period stock adjustment returns 409 and GL receives no lines (ACCT-005)', async () => {
    const item = await createItem('Primitive Closed Adj Item', token);
    closePeriodFor('2026-01-15', '2026-01');
    const before = financialTotalsSnapshot();

    // unit_cost is required for the GL adjustment leg to fire at all —
    // a zero-value adjustment posts no journal entry, so the guard under
    // test (postLegacyStockEntry's closed-period assert) would never run.
    const res = await request(app).post('/api/inventory/stock-movements').set('Cookie', token)
      .send({
        item_id: item, warehouse_id: warehouseId,
        quantity: 5, movement_type: 'ADJUSTMENT',
        movement_date: '2026-01-15',
        unit_cost: 10,
      });
    expect(res.status).toBe(409);
    expect(String(res.body?.error)).toMatch(/inside closed accounting period/i);

    expect(financialTotalsSnapshot()).toBe(before);
    // GL 1200 / 7100 must receive no lines for the refused date.
    const glLines = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE je.entry_date = '2026-01-15'
    `).get() as { n: number };
    expect(glLines.n).toBe(0);
    expectAllInvariantsHold('after closed-period adjustment refusal');
  });

  // ── Phase 2.2: postEntry itself refuses to auto-create a future period ──
  it('postEntry with a future date throws instead of inserting an open period', () => {
    const before = financialTotalsSnapshot();
    const cash = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1000'`).get() as { id: number };
    const equity = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '3000'`).get() as { id: number };
    expect(() =>
      AccountingService.postEntry(db, {
        entry_date: FUTURE_DATE,
        description: 'future-dated direct posting',
        lines: [
          { account_id: cash.id, debit: 100, description: 'future' },
          { account_id: equity.id, credit: 100, description: 'future' },
        ],
      })
    ).toThrow(/future/i);

    expect(financialTotalsSnapshot()).toBe(before);
    expectAllInvariantsHold('after future postEntry refusal');
  });

  // ── Phase 2.3: explicit administrative opening stays available ──
  it('an explicitly opened future period accepts future-dated postings', async () => {
    const openRes = await api('post', '/api/accounting/periods', {
      period_name: '2027-06',
      start_date: '2027-06-01',
      end_date: '2027-06-30',
    });
    expect(openRes.status).toBeLessThan(300);

    // A real business flow dated inside the explicitly opened future period
    // must still post — the Phase 2.2 guard only refuses dates with no
    // covering period. Cash flows stay balanced, so no cleanup void is needed.
    const capRes = await api('post', '/api/owner-equity/capital', {
      amount: 100, capital_date: FUTURE_DATE, payment_method: 'Cash',
    });
    expect(capRes.status).toBeLessThan(300);

    expectAllInvariantsHold('after explicit future open');
  });

  // ── Phase 3.1: closure is status-based, not name-shape-based ──
  it('a period closed under a non-calendar name still refuses mutations', async () => {
    const { paymentId } = await seedPaidInvoiceForPeriod('3.1');

    closePeriodFor('2026-09-10', 'Q-custom-closed-for-test');
    const voidRes = await api('delete', `/api/payments/${paymentId}`);
    expect(voidRes.status).toBe(409);
    expect(JSON.stringify(voidRes.body)).toMatch(/closed|period/i);

    const p = db.prepare('SELECT voided_at FROM payments WHERE id = ?').get(paymentId) as { voided_at: string | null };
    expect(p.voided_at).toBeNull();
    expectAllInvariantsHold('after non-calendar-name refusal');
  });
});
