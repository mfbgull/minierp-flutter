/**
 * Idempotency on the remaining money-moving write handlers
 * (audit-3 task 08, Round 2).
 *
 * Same contract as Round 1: a request whose response is lost must replay on
 * retry, a changed payload under the same key must be refused, and a failed
 * attempt must leave no claim behind.
 *
 * Unlike Round 1, most of these have no read-by-id that returns the same
 * shape the create call returns, so a replay answers with the recorded
 * resource id and an `idempotentReplay` marker rather than the full record.
 * The guarantee that matters — no duplicate money, stock or GL — is asserted
 * directly against the tables.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { IDEMPOTENCY_SCOPES } from '../utils/idempotency';
import { createCustomer, createItem, createInvoice, purchaseStock } from './helpers/invoiceReturnSpec';

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

function count(sql: string, ...params: unknown[]): number {
  return Number((db.prepare(sql).get(...(params as [])) as { n: number }).n);
}

/**
 * Cash debited by supplier refunds so far. The account is picked from
 * `payment_method` (1000 Cash, 1010 Bank, 1020-1040 wallets), so this sums
 * the family instead of assuming one code.
 */
function refundCashDebit(): number {
  return Number((db.prepare(`
    SELECT COALESCE(SUM(jl.debit), 0) AS total
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE coa.code IN ('1000','1010','1020','1030','1040')
      AND je.reference_type = 'SUPPLIER_REFUND'
      AND je.voided = 0 AND jl.voided = 0
  `).get() as { total: number }).total);
}

function keyFor(scope: string): string {
  return `${scope}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

describe('idempotency — Round 2 money handlers', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  let customerId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Idem Round2 Item', authCookie);
    await purchaseStock(itemId, warehouseId, 400, 10, authCookie);
    customerId = await createCustomer('Idem Round2 Customer', authCookie);
  });

  /**
   * A refund or a salary payment draws on the cash account, so the till needs
   * funds first. Without this the settlement is refused with "Insufficient
   * funds in Cash" before idempotency is ever reached.
   */
  async function fundCash(): Promise<void> {
    await request(app).post('/api/owner-equity/capital')
      .set('Cookie', authCookie)
      .send({ capital_date: '2026-09-01', amount: 500000, payment_method: 'Cash' });
  }

  function post(path: string, key: string | null, body: unknown) {
    const req = request(app).post(path).set('Cookie', authCookie);
    if (key) req.set('Idempotency-Key', key);
    return req.send(body as object);
  }

  // ── purchase-orders.receipt ──────────────────────────────────────────
  describe('purchase-orders.receipt', () => {
    async function openPo(): Promise<{ poId: number; poItemId: number }> {
      // supplier_id is required by the schema — a bare supplier_name is not
      // enough to open a PO.
      const supplier = await request(app).post('/api/suppliers')
        .set('Cookie', authCookie)
        .send({
          supplier_name: `Idem Round2 Supplier ${Date.now()}`,
          supplier_code: `R2-PO-${Date.now()}`,
        });
      expect(supplier.status).toBe(201);
      const supplierId = supplier.body.data?.id ?? supplier.body.id;

      const po = await request(app).post('/api/purchase-orders')
        .set('Cookie', authCookie)
        .send({
          supplier_id: supplierId,
          po_date: '2026-09-02',
          warehouse_id: warehouseId,
          items: [{ item_id: itemId, quantity: 40, unit_price: 10 }],
        });
      expect([200, 201]).toContain(po.status);
      const poId = po.body.data?.id ?? po.body.id;

      // A PO must be submitted before it can be received against.
      const submitted = await request(app).post(`/api/purchase-orders/${poId}/status`)
        .set('Cookie', authCookie)
        .send({ status: 'Submitted' });
      expect([200, 201]).toContain(submitted.status);

      // The receipt addresses the PO's own line, so read its id back.
      const poLines = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?')
        .all(poId) as Array<{ id: number }>;
      expect(poLines.length).toBeGreaterThan(0);
      return { poId, poItemId: poLines[0].id };
    }

    it('replays a lost receipt instead of receiving the goods twice', async () => {
      const { poId, poItemId } = await openPo();
      const payload = {
        receipt_date: '2026-09-10',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItemId, received_quantity: 10 }],
      };
      const key = keyFor(IDEMPOTENCY_SCOPES.PURCHASE_ORDER_RECEIPT);

      const before = {
        receipts: count('SELECT COUNT(*) AS n FROM goods_receipts WHERE po_id = ?', poId),
        movements: count(
          "SELECT COUNT(*) AS n FROM stock_movements WHERE reference_doctype = 'GOODS_RECEIPT'",
        ),
      };

      const first = await post(`/api/purchase-orders/${poId}/receipts`, key, payload);
      expect(first.status).toBe(201);
      const second = await post(`/api/purchase-orders/${poId}/receipts`, key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM goods_receipts WHERE po_id = ?', poId))
        .toBe(before.receipts + 1);
      expect(count("SELECT COUNT(*) AS n FROM stock_movements WHERE reference_doctype = 'GOODS_RECEIPT'"))
        .toBe(before.movements + 1);
    });

    it('rejects the same key with a changed receipt quantity', async () => {
      const { poId, poItemId } = await openPo();
      const key = keyFor(IDEMPOTENCY_SCOPES.PURCHASE_ORDER_RECEIPT);
      const base = {
        receipt_date: '2026-09-10',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItemId, received_quantity: 5 }],
      };

      const first = await post(`/api/purchase-orders/${poId}/receipts`, key, base);
      expect(first.status).toBe(201);

      const second = await post(`/api/purchase-orders/${poId}/receipts`, key, {
        ...base,
        items: [{ po_item_id: poItemId, received_quantity: 6 }],
      });
      expect(second.status).toBe(409);
    });
  });

  // ── invoices.return ──────────────────────────────────────────────────
  describe('invoices.return', () => {
    async function soldInvoice(quantity: number): Promise<{ invoiceId: number; itemId: number }> {
      const { invoiceId, invoiceItemIds } = await createInvoice(
        { customerId, itemId, lines: [{ quantity, unitPrice: 100 }], payment: null },
        authCookie,
      );
      return { invoiceId, itemId: invoiceItemIds[0] };
    }

    it('replays a lost return instead of restocking twice', async () => {
      const { invoiceId, itemId: invoiceItemId } = await soldInvoice(4);
      const payload = {
        reason: 'idempotency probe',
        disposition: 'refund',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
      };
      const key = keyFor(IDEMPOTENCY_SCOPES.INVOICE_RETURN);

      const before = {
        returns: count('SELECT COUNT(*) AS n FROM invoice_returns'),
        items: count('SELECT COUNT(*) AS n FROM invoice_return_items'),
      };

      const first = await post(`/api/invoices/${invoiceId}/return`, key, payload);
      expect(first.status).toBe(200);
      const second = await post(`/api/invoices/${invoiceId}/return`, key, payload);
      expect(second.status).toBe(200);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM invoice_returns')).toBe(before.returns + 1);
      expect(count('SELECT COUNT(*) AS n FROM invoice_return_items')).toBe(before.items + 1);
    });

    it('rejects the same key with a changed return quantity', async () => {
      const a = await soldInvoice(4);
      const b = await soldInvoice(4);
      const key = keyFor(IDEMPOTENCY_SCOPES.INVOICE_RETURN);

      const first = await post(`/api/invoices/${a.invoiceId}/return`, key, {
        reason: 'first',
        disposition: 'refund',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: a.itemId, return_quantity: 1 }],
      });
      expect(first.status).toBe(200);

      const second = await post(`/api/invoices/${b.invoiceId}/return`, key, {
        reason: 'second',
        disposition: 'refund',
        warehouse_id: warehouseId,
        items: [{ invoice_item_id: b.itemId, return_quantity: 3 }],
      });
      expect(second.status).toBe(409);
    });
  });

  // ── owner-equity.capital ─────────────────────────────────────────────
  describe('owner-equity.capital', () => {
    it('replays a lost capital contribution instead of capitalising twice', async () => {
      const payload = { capital_date: '2026-09-12', amount: 1500, payment_method: 'Cash' };
      const key = keyFor(IDEMPOTENCY_SCOPES.OWNER_CAPITAL);

      const before = {
        rows: count('SELECT COUNT(*) AS n FROM owner_capital'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'OWNER_CAPITAL'"),
      };

      const first = await post('/api/owner-equity/capital', key, payload);
      expect(first.status).toBe(201);
      const second = await post('/api/owner-equity/capital', key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM owner_capital')).toBe(before.rows + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'OWNER_CAPITAL'"))
        .toBe(before.gl + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.OWNER_CAPITAL);
      const first = await post('/api/owner-equity/capital', key, {
        capital_date: '2026-09-12', amount: 100, payment_method: 'Cash',
      });
      expect(first.status).toBe(201);

      const second = await post('/api/owner-equity/capital', key, {
        capital_date: '2026-09-12', amount: 250, payment_method: 'Cash',
      });
      expect(second.status).toBe(409);
    });
  });

  // ── owner-equity.withdrawal ──────────────────────────────────────────
  describe('owner-equity.withdrawal', () => {
    it('replays a lost cash withdrawal instead of paying out twice', async () => {
      const payload = {
        withdrawal_date: '2026-09-14',
        kind: 'cash',
        amount: 400,
        payment_method: 'Cash',
      };
      const key = keyFor(IDEMPOTENCY_SCOPES.OWNER_WITHDRAWAL);

      const before = {
        rows: count('SELECT COUNT(*) AS n FROM owner_withdrawals'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'OWNER_WITHDRAWAL'"),
      };

      const first = await post('/api/owner-equity/withdrawals', key, payload);
      expect(first.status).toBe(201);
      const second = await post('/api/owner-equity/withdrawals', key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM owner_withdrawals')).toBe(before.rows + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'OWNER_WITHDRAWAL'"))
        .toBe(before.gl + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.OWNER_WITHDRAWAL);
      const base = { withdrawal_date: '2026-09-14', kind: 'cash', payment_method: 'Cash' };

      const first = await post('/api/owner-equity/withdrawals', key, { ...base, amount: 50 });
      expect(first.status).toBe(201);

      const second = await post('/api/owner-equity/withdrawals', key, { ...base, amount: 75 });
      expect(second.status).toBe(409);
    });
  });

  // ── employees.salary.pay ─────────────────────────────────────────────
  describe('employees.salary.pay', () => {
    async function makeEmployee(): Promise<number> {
      const res = await request(app).post('/api/employees')
        .set('Cookie', authCookie)
        .send({
          first_name: 'Idem', last_name: 'Salary', employee_code: `IDEM-SAL-${Date.now()}`,
          email: `idem-sal-${Date.now()}@example.com`, department_id: 1, position: 'Clerk',
          hire_date: '2026-01-01', basic_salary: 50000,
        });
      expect([200, 201]).toContain(res.status);
      return res.body.data?.id ?? res.body.id;
    }

    it('replays a lost salary payment instead of paying twice', async () => {
      await fundCash();
      const employeeId = await makeEmployee();
      const payload = { amount: 50000, payment_date: '2026-09-15', payment_method: 'Cash' };
      const key = keyFor(IDEMPOTENCY_SCOPES.EMPLOYEE_SALARY_PAY);

      const before = {
        rows: count('SELECT COUNT(*) AS n FROM salary_payments WHERE employee_id = ?', employeeId),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'SALARY_PAYMENT'"),
      };

      const first = await post(`/api/employees/${employeeId}/salary/pay`, key, payload);
      if (first.status !== 201) console.log('SALARY_ERR', first.status, JSON.stringify(first.body));
      expect(first.status).toBe(201);
      const second = await post(`/api/employees/${employeeId}/salary/pay`, key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM salary_payments WHERE employee_id = ?', employeeId))
        .toBe(before.rows + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'SALARY_PAYMENT'"))
        .toBe(before.gl + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const employeeId = await makeEmployee();
      const key = keyFor(IDEMPOTENCY_SCOPES.EMPLOYEE_SALARY_PAY);

      const first = await post(`/api/employees/${employeeId}/salary/pay`, key, {
        amount: 1000, payment_date: '2026-09-15', payment_method: 'Cash',
      });
      expect(first.status).toBe(201);

      const second = await post(`/api/employees/${employeeId}/salary/pay`, key, {
        amount: 2000, payment_date: '2026-09-15', payment_method: 'Cash',
      });
      expect(second.status).toBe(409);
    });
  });

  // ── invoice-returns.settle ───────────────────────────────────────────
  describe('invoice-returns.settle', () => {
    it('replays a lost settlement instead of settling the return twice', async () => {
      await fundCash();
      // The refund entitlement is what the invoice actually collected, so a
      // settleable return needs a PAID invoice — on an unpaid one the
      // entitlement is 0 and settlement is refused before any claim.
      // `disposition` is deliberately omitted: that legacy shim settles the
      // return inline (status Settled), leaving a nil remainder to settle.
      const { invoiceId, invoiceItemIds } = await createInvoice(
        { customerId, itemId, lines: [{ quantity: 4, unitPrice: 100 }], payment: 'full' },
        authCookie,
      );
      const created = await request(app).post(`/api/invoices/${invoiceId}/return`)
        .set('Cookie', authCookie)
        .send({
          reason: 'settle probe',
          warehouse_id: warehouseId,
          items: [{ invoice_item_id: invoiceItemIds[0], return_quantity: 4 }],
        });
      expect(created.status).toBe(200);
      const returnId = created.body.data?.returnId ?? created.body.data?.return_id;
      expect(returnId).toBeDefined();

      const payload = { allocations: [{ type: 'refund', amount: 400, method: 'Cash' }] };
      const key = keyFor(IDEMPOTENCY_SCOPES.INVOICE_RETURN_SETTLE);
      const before = count(
        'SELECT COUNT(*) AS n FROM return_settlements WHERE return_id = ?', returnId,
      );

      const first = await post(`/api/invoice-returns/${returnId}/settle`, key, payload);
      expect({ status: first.status, body: first.body }).toMatchObject({ status: 200 });
      const second = await post(`/api/invoice-returns/${returnId}/settle`, key, payload);
      expect(second.status).toBe(200);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM return_settlements WHERE return_id = ?', returnId))
        .toBe(before + 1);
    });

    it('rejects the same key with a changed allocation amount', async () => {
      await fundCash();
      const { invoiceId, invoiceItemIds } = await createInvoice(
        { customerId, itemId, lines: [{ quantity: 4, unitPrice: 100 }], payment: 'full' },
        authCookie,
      );
      const created = await request(app).post(`/api/invoices/${invoiceId}/return`)
        .set('Cookie', authCookie)
        .send({
          reason: 'settle conflict probe',
          warehouse_id: warehouseId,
          items: [{ invoice_item_id: invoiceItemIds[0], return_quantity: 4 }],
        });
      const returnId = created.body.data?.returnId ?? created.body.data?.return_id;
      const key = keyFor(IDEMPOTENCY_SCOPES.INVOICE_RETURN_SETTLE);

      const first = await post(`/api/invoice-returns/${returnId}/settle`, key, {
        allocations: [{ type: 'refund', amount: 200, method: 'Cash' }],
      });
      expect(first.status).toBe(200);

      const second = await post(`/api/invoice-returns/${returnId}/settle`, key, {
        allocations: [{ type: 'refund', amount: 300, method: 'Cash' }],
      });
      expect(second.status).toBe(409);
    });
  });

  // ── supplier-refunds.create ──────────────────────────────────────────
  describe('supplier-refunds.create', () => {
    /**
     * A supplier refund needs a real POSTED supplier credit note, which only
     * a purchase return with `credit_on_account` disposition produces. The
     * chain is purchase -> purchase return (credit on account) -> credit note
     * -> refund, because a refund pays real cash out against that note.
     */
    async function postableCreditNote(): Promise<number> {
      const supplier = await request(app).post('/api/suppliers')
        .set('Cookie', authCookie)
        .send({
          supplier_name: `Idem Refund Supplier ${Date.now()}`,
          supplier_code: `R2-REF-${Date.now()}`,
        });
      expect(supplier.status).toBe(201);
      const supplierId = supplier.body.data?.id ?? supplier.body.id;

      const purchase = await request(app).post('/api/purchases')
        .set('Cookie', authCookie)
        .send({
          item_id: itemId,
          warehouse_id: warehouseId,
          quantity: 20,
          unit_cost: 10,
          purchase_date: '2026-09-03',
          supplier_id: supplierId,
        });
      expect(purchase.status).toBe(201);
      const purchaseId = Array.isArray(purchase.body) ? purchase.body[0].id : purchase.body.id;

      const returned = await request(app).post('/api/purchase-returns')
        .set('Cookie', authCookie)
        .send({
          return_date: '2026-09-16',
          source_type: 'PURCHASE',
          source_id: purchaseId,
          warehouse_id: warehouseId,
          disposition: 'credit_on_account',
          reason: 'idempotency refund probe',
          items: [{ source_item_id: purchaseId, quantity: 2, unit_cost: 10 }],
        });
      expect(returned.status).toBe(201);
      const returnId = returned.body.data?.id ?? returned.body.data?.return_id;

      const note = db.prepare(
        "SELECT id FROM credit_notes WHERE source_type = 'PURCHASE_RETURN' AND source_id = ? AND status = 'POSTED'",
      ).get(returnId) as { id: number } | undefined;
      expect(note).toBeDefined();
      expect(Number(note!.id)).toBeGreaterThan(0);
      return note!.id;
    }

    it('rejects a malformed key with 400', async () => {
      const res = await post('/api/supplier-refunds', 'short', {
        refund_date: '2026-09-16', credit_note_id: 1, amount: 10, payment_method: 'Cash',
      });
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/Idempotency-Key must be 8\.\.200/);
    });

    it('replays a lost refund instead of paying the supplier twice', async () => {
      await fundCash();
      const creditNoteId = await postableCreditNote();
      const payload = {
        refund_date: '2026-09-17',
        credit_note_id: creditNoteId,
        amount: 20,
        payment_method: 'Cash',
      };
      const key = keyFor(IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE);

      // A supplier refund writes supplier_refunds + a GL entry; it does NOT
      // create a payments row, so that is not one of the things to count.
      const before = {
        refunds: count('SELECT COUNT(*) AS n FROM supplier_refunds'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'SUPPLIER_REFUND'"),
        cashDr: refundCashDebit(),
      };

      const first = await post('/api/supplier-refunds', key, payload);
      expect(first.status).toBe(201);
      const second = await post('/api/supplier-refunds', key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      // The defect this prevents: cash out to the supplier a second time.
      expect(count('SELECT COUNT(*) AS n FROM supplier_refunds')).toBe(before.refunds + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'SUPPLIER_REFUND'"))
        .toBe(before.gl + 1);
      expect(refundCashDebit() - before.cashDr).toBeCloseTo(20, 2);
    });

    it('rejects the same key with a changed amount', async () => {
      await fundCash();
      const first = await postableCreditNote();
      const second = await postableCreditNote();
      const key = keyFor(IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE);

      const created = await post('/api/supplier-refunds', key, {
        refund_date: '2026-09-17', credit_note_id: first, amount: 20, payment_method: 'Cash',
      });
      expect(created.status).toBe(201);

      const changed = await post('/api/supplier-refunds', key, {
        refund_date: '2026-09-17', credit_note_id: second, amount: 30, payment_method: 'Cash',
      });
      expect(changed.status).toBe(409);
    });

    it('claims nothing when the credit note is invalid, so the key stays reusable', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE);
      const before = count('SELECT COUNT(*) AS n FROM supplier_refunds');
      const res = await post('/api/supplier-refunds', key, {
        refund_date: '2026-09-16', credit_note_id: 999999, amount: 10, payment_method: 'Cash',
      });
      expect(res.status).toBe(400);
      expect(count('SELECT COUNT(*) AS n FROM supplier_refunds')).toBe(before);
      expect(count(
        'SELECT COUNT(*) AS n FROM idempotency_keys WHERE scope = ? AND key = ?',
        IDEMPOTENCY_SCOPES.SUPPLIER_REFUND_CREATE, key,
      )).toBe(0);
    });
  });
});
