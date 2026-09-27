import request from 'supertest';
import app from '../app';
import db from '../config/database';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import ledgerUtils from '../utils/ledgerUtils';
import {
  getAuthCookie,
  createCustomer,
  createItem,
  purchaseStock,
  createInvoice,
  processReturn,
  settleReturn,
} from './helpers/invoiceReturnSpec';

type LedgerRow = { transaction_date: string; debit: number; credit: number; balance: number };
type GlRow = { code: string; debit: number; credit: number };

function paymentIdForInvoice(invoiceId: number): number {
  const row = db.prepare(`
    SELECT payment_id FROM payment_allocations
    WHERE invoice_id = ? AND voided_at IS NULL ORDER BY id DESC LIMIT 1
  `).get(invoiceId) as { payment_id: number } | undefined;
  if (!row) throw new Error(`No live payment allocation for invoice ${invoiceId}`);
  return row.payment_id;
}

function allocatedForInvoice(invoiceId: number): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations
    WHERE invoice_id = ? AND voided_at IS NULL
  `).get(invoiceId) as { total: number };
  return Number(row.total);
}

function glFor(referenceType: string, referenceId: number): GlRow[] {
  return db.prepare(`
    SELECT c.code, jl.debit, jl.credit
    FROM journal_lines jl JOIN chart_of_accounts c ON c.id = jl.account_id
    WHERE jl.reference_type = ? AND jl.reference_id = ? AND jl.voided = 0
  `).all(referenceType, referenceId) as GlRow[];
}

function glTotal(referenceType: string, referenceId: number): { debit: number; credit: number } {
  const rows = glFor(referenceType, referenceId);
  return {
    debit: rows.reduce((sum, r) => sum + Number(r.debit), 0),
    credit: rows.reduce((sum, r) => sum + Number(r.credit), 0),
  };
}

function expectCashInGl(referenceType: string, referenceId: number, amount: number): void {
  const totals = glTotal(referenceType, referenceId);
  expect(totals.debit).toBeCloseTo(amount, 2);
  expect(totals.credit).toBeCloseTo(amount, 2);
}

function ledgerRows(customerId: number): LedgerRow[] {
  return db.prepare(`
    SELECT transaction_date, debit, credit, balance FROM customer_ledger
    WHERE customer_id = ? AND voided = 0
    ORDER BY transaction_date ASC, id ASC
  `).all(customerId) as LedgerRow[];
}

function expectChainFooted(customerId: number): void {
  let running = 0;
  for (const row of ledgerRows(customerId)) {
    running += Number(row.debit) - Number(row.credit);
    expect(Number(row.balance)).toBeCloseTo(running, 2);
  }
}

function closePeriod(periodName: string, startDate: string, endDate: string): void {
  db.prepare('DELETE FROM accounting_periods WHERE period_name = ?').run(periodName);
  db.prepare(`
    INSERT INTO accounting_periods (period_name, start_date, end_date, status)
    VALUES (?, ?, ?, 'closed')
  `).run(periodName, startDate, endDate);
}

function reopenPeriod(periodName: string): void {
  db.prepare('DELETE FROM accounting_periods WHERE period_name = ?').run(periodName);
}

describe('payment recording matrix', () => {
  let authCookie = '';
  let customerId = 0;
  let itemId = 0;
  let warehouseId = 0;
  let closedPeriod = '';

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    customerId = await createCustomer('Payment Matrix Customer', authCookie);
    itemId = await createItem('Payment Matrix Item', authCookie);
    await purchaseStock(itemId, warehouseId, 60, 20, authCookie);
    closedPeriod = '2026-03-closed-for-payment-matrix';
  });

  afterEach(() => {
    reopenPeriod(closedPeriod);
  });

  async function payInvoice(invoiceId: number, paymentDate: string, amount = 100): Promise<number> {
    const res = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        payment_date: paymentDate,
        amount,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoiceId, amount }],
      });
    expect([200, 201]).toContain(res.status);
    return paymentIdForInvoice(invoiceId);
  }

  function expectFullyPaidAccounting(invoiceId: number, amount: number): void {
    const invoice = db.prepare('SELECT balance_amount, status FROM invoices WHERE id = ?')
      .get(invoiceId) as { balance_amount: number; status: string };
    expect(Number(invoice.balance_amount)).toBeCloseTo(0, 2);
    expect(invoice.status).toBe('Paid');
    expect(allocatedForInvoice(invoiceId)).toBeCloseTo(amount, 2);
    expectCashInGl('PAYMENT', paymentIdForInvoice(invoiceId), amount);
  }

  it('gives a payment recorded after invoicing and one recorded at invoice time identical accounting', async () => {
    const paidLater = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }] },
      authCookie,
    );
    await payInvoice(paidLater.invoiceId, '2026-09-20');

    const paidAtCreation = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], payment: 'full', invoiceDate: '2026-09-15' },
      authCookie,
    );

    expectFullyPaidAccounting(paidLater.invoiceId, 100);
    expectFullyPaidAccounting(paidAtCreation.invoiceId, 100);
    expectChainFooted(customerId);
  });

  it('converges the allocate-later path onto the same accounting as an up-front allocation', async () => {
    const invoice = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }] },
      authCookie,
    );
    const paymentId = await payInvoice(invoice.invoiceId, '2026-09-20');

    db.prepare('UPDATE payment_allocations SET voided_at = ? WHERE payment_id = ? AND invoice_id = ?')
      .run('2026-09-20 00:00:00', paymentId, invoice.invoiceId);
    ledgerUtils.calculateInvoiceBalance(invoice.invoiceId);

    const allocated = await request(app).post(`/api/payments/${paymentId}/allocate`)
      .set('Cookie', authCookie)
      .send({ allocations: [{ invoice_id: invoice.invoiceId, amount: 100 }] });
    expect([200, 201]).toContain(allocated.status);

    expectFullyPaidAccounting(invoice.invoiceId, 100);
    expectChainFooted(customerId);
  });

  it('posts a CREDIT_OFFSET journal entry when a return credit is applied to another invoice', async () => {
    const source = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 2, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );
    const target = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }] },
      authCookie,
    );

    const returned = await processReturn(source.invoiceId, {
      invoiceItemIds: source.invoiceItemIds,
      quantities: [1],
    }, authCookie);
    expect([200, 201]).toContain(returned.status);
    expect(returned.returnId).toBeGreaterThan(0);

    const settled = await settleReturn(returned.returnId as number, [
      { type: 'adjust', amount: 100, target_invoice_id: target.invoiceId },
    ], authCookie);
    expect([200, 201]).toContain(settled.status);

    const totals = glTotal('CREDIT_OFFSET', target.invoiceId);
    expect(totals.debit).toBeCloseTo(100, 2);
    expect(totals.credit).toBeCloseTo(100, 2);

    const applied = db.prepare('SELECT balance_amount, status FROM invoices WHERE id = ?')
      .get(target.invoiceId) as { balance_amount: number; status: string };
    expect(Number(applied.balance_amount)).toBeCloseTo(0, 2);
    expect(applied.status).toBe('Paid');
  });

  it('records a return refund as a negative payment with a REFUND ledger row and refund journal entry', async () => {
    const invoice = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], payment: 'full' },
      authCookie,
    );

    const returned = await processReturn(invoice.invoiceId, {
      invoiceItemIds: invoice.invoiceItemIds,
      quantities: [1],
    }, authCookie);
    expect([200, 201]).toContain(returned.status);

    const settled = await settleReturn(returned.returnId as number, [
      { type: 'refund', amount: 100, method: 'Bank' },
    ], authCookie);
    expect([200, 201]).toContain(settled.status);

    const refund = db.prepare(`
      SELECT id, amount FROM payments
      WHERE customer_id = ? AND amount < 0 ORDER BY id DESC LIMIT 1
    `).get(customerId) as { id: number; amount: number };
    expect(Number(refund.amount)).toBeCloseTo(-100, 2);
    expectCashInGl('PAYMENT', refund.id, 100);

    const refundRow = db.prepare(`
      SELECT COUNT(*) AS count FROM customer_ledger
      WHERE customer_id = ? AND transaction_type = 'REFUND' AND voided = 0
    `).get(customerId) as { count: number };
    expect(refundRow.count).toBe(1);
    expectChainFooted(customerId);
  });

  it('re-foots the customer ledger chain when a payment is dated before its invoice', async () => {
    const backdatedCustomerId = await createCustomer('Payment Matrix Backdated', authCookie);
    const invoice = await createInvoice(
      { customerId: backdatedCustomerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }], invoiceDate: '2026-09-20' },
      authCookie,
    );

    const res = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: backdatedCustomerId,
        payment_date: '2026-09-10',
        amount: 100,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoice.invoiceId, amount: 100 }],
      });
    expect([200, 201]).toContain(res.status);

    expectChainFooted(backdatedCustomerId);
  });

  it('rejects a payment dated inside a closed accounting period and writes nothing', async () => {
    const invoice = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: 100 }] },
      authCookie,
    );
    closePeriod(closedPeriod, '2026-03-01', '2026-03-31');

    const before = db.prepare('SELECT COUNT(*) AS count FROM payments').get() as { count: number };

    const rejected = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        payment_date: '2026-03-15',
        amount: 100,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoice.invoiceId, amount: 100 }],
      });
    expect(rejected.status).toBe(409);
    expect(JSON.stringify(rejected.body)).toMatch(/closed|period/i);

    const invoiceTime = await request(app).post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customerId,
        invoice_date: '2026-03-15',
        due_date: '2026-03-30',
        warehouse_id: warehouseId,
        items: [{ item_id: itemId, quantity: 1, unit_price: 100, tax_rate: 0 }],
        record_payment: true,
        payment: { payment_date: '2026-03-15', amount: 100, payment_method: 'Cash' },
      });
    expect(invoiceTime.status).toBe(409);
    expect(JSON.stringify(invoiceTime.body)).toMatch(/closed|period/i);

    const after = db.prepare('SELECT COUNT(*) AS count FROM payments').get() as { count: number };
    expect(Number(after.count)).toBe(Number(before.count));
  });

  it('records a supplier payment against AP with a cash funds guard', async () => {
    const supplier = await request(app).post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({ supplier_code: `PM-SUP-${Date.now()}`, supplier_name: 'Payment Matrix Supplier' });
    const supplierId = supplier.body.data?.id ?? supplier.body.id;
    expect(supplierId).toBeGreaterThan(0);

    OwnerCapitalModel.create(db, {
      capital_no: generateCapitalNo(db, '2026-02-01'),
      capital_date: '2026-02-01',
      amount: 1_000_000,
      payment_method: 'Cash',
      created_by: 1,
    });

    const purchaseNo = `PM-PUR-${Date.now()}`;
    db.prepare(`
      INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
                             purchase_date, supplier_id, created_by)
      VALUES (?, ?, ?, 1, 40, 40, '2026-09-01', ?, 1)
    `).run(purchaseNo, itemId, warehouseId, supplierId);
    const purchaseId = (db.prepare('SELECT id FROM purchases WHERE purchase_no = ?').get(purchaseNo) as { id: number }).id;

    const paid = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        payment_date: '2026-09-10',
        amount: 40,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: purchaseId, amount: 40 }],
      });
    expect([200, 201]).toContain(paid.status);

    const paymentId = (paid.body.data?.id ?? paid.body.id) as number;
    const totals = glTotal('PAYMENT', paymentId);
    expect(totals.debit).toBeCloseTo(40, 2);
    expect(totals.credit).toBeCloseTo(40, 2);

    const supplierLedger = db.prepare(`
      SELECT COALESCE(SUM(credit), 0) AS credit FROM supplier_ledger
      WHERE supplier_id = ? AND transaction_type = 'PAYMENT'
    `).get(supplierId) as { credit: number };
    expect(Number(supplierLedger.credit)).toBeCloseTo(40, 2);

    const bigPurchaseNo = `PM-BIG-PUR-${Date.now()}`;
    db.prepare(`
      INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
                             purchase_date, supplier_id, created_by)
      VALUES (?, ?, ?, 1, 5000000, 5000000, '2026-09-01', ?, 1)
    `).run(bigPurchaseNo, itemId, warehouseId, supplierId);
    const bigPurchaseId = (db.prepare('SELECT id FROM purchases WHERE purchase_no = ?').get(bigPurchaseNo) as { id: number }).id;

    const before = db.prepare('SELECT COUNT(*) AS count FROM payments').get() as { count: number };

    const cashOut = await request(app).post('/api/payments')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        payment_date: '2026-09-10',
        amount: 1_500_000,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: bigPurchaseId, amount: 1_500_000 }],
      });
    expect(cashOut.status).toBe(400);
    expect(JSON.stringify(cashOut.body)).toMatch(/insufficient funds/i);

    const after = db.prepare('SELECT COUNT(*) AS count FROM payments').get() as { count: number };
    expect(Number(after.count)).toBe(Number(before.count));
  });
});
