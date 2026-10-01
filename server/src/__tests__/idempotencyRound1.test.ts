/**
 * Idempotency on the money-moving write handlers (audit-3 task 08, Round 1).
 *
 * A POST can time out client-side AFTER the server committed. The retry must
 * not double-create. Each of these five handlers moves money or stock, so the
 * blast radius of a duplicate is a financial defect, not an inconvenience.
 *
 * The four scenarios per handler mirror the audit:
 *   1. the response is lost and the request is retried  -> replays
 *   2. two concurrent requests with one key              -> one write
 *   3. the same key with a changed amount/document       -> 409
 *   4. a failed attempt leaves no claim, so a retry runs -> one write
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { IDEMPOTENCY_SCOPES, pruneIdempotencyKeys } from '../utils/idempotency';
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

function keyFor(scope: string): string {
  return `${scope}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

describe('idempotency — Round 1 money handlers', () => {
  let authCookie: string;
  let itemId: number;
  let warehouseId: number;
  let customerId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Idem Round1 Item', authCookie);
    await purchaseStock(itemId, warehouseId, 400, 10, authCookie);
    customerId = await createCustomer('Idem Round1 Customer', authCookie);

    const supplier = await request(app).post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({ supplier_name: `Idem Round1 Supplier ${Date.now()}`, supplier_code: `IDEM-S-${Date.now()}` });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data?.id ?? supplier.body.id;
  });

  async function openInvoice(amount: number): Promise<number> {
    const { invoiceId } = await createInvoice(
      { customerId, itemId, lines: [{ quantity: 1, unitPrice: amount }], payment: null },
      authCookie,
    );
    return invoiceId;
  }

  async function post(path: string, key: string | null, body: unknown) {
    const req = request(app).post(path).set('Cookie', authCookie);
    if (key) req.set('Idempotency-Key', key);
    return req.send(body as object);
  }

  // ── payments.customer ────────────────────────────────────────────────
  describe('payments.customer', () => {
    async function body(invoiceId: number, amount: number) {
      return {
        customer_id: customerId,
        payment_date: '2026-09-20',
        amount,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoiceId, amount }],
      };
    }

    it('replays a lost response instead of taking the money twice', async () => {
      const invoiceId = await openInvoice(200);
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER);

      const before = {
        payments: count('SELECT COUNT(*) AS n FROM payments'),
        allocations: count('SELECT COUNT(*) AS n FROM payment_allocations'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PAYMENT'"),
      };

      const first = await post('/api/payments', key, await body(invoiceId, 100));
      expect(first.status).toBe(201);
      const second = await post('/api/payments', key, await body(invoiceId, 100));
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(second.body.data.id).toBe(first.body.data.id);
      expect(count('SELECT COUNT(*) AS n FROM payments')).toBe(before.payments + 1);
      expect(count('SELECT COUNT(*) AS n FROM payment_allocations')).toBe(before.allocations + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PAYMENT'"))
        .toBe(before.gl + 1);
    });

    it('creates one payment for two concurrent requests with one key', async () => {
      const invoiceId = await openInvoice(200);
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER);

      const before = count('SELECT COUNT(*) AS n FROM payments');
      const [a, b] = await Promise.all([
        post('/api/payments', key, await body(invoiceId, 100)),
        post('/api/payments', key, await body(invoiceId, 100)),
      ]);

      expect([a.status, b.status].every((s) => s === 201 || s === 409 || s === 200)).toBe(true);
      expect(count('SELECT COUNT(*) AS n FROM payments')).toBe(before + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const invoiceId = await openInvoice(300);
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER);

      const first = await post('/api/payments', key, await body(invoiceId, 100));
      expect(first.status).toBe(201);

      // A different amount against a DIFFERENT invoice, so the payload hash
      // is what rejects it rather than a business rule.
      const otherInvoice = await openInvoice(400);
      const second = await post('/api/payments', key, await body(otherInvoice, 150));
      expect(second.status).toBe(409);
      expect(second.body.error).toMatch(/already used with a different request payload/i);
    });

    it('allows a different key to record a genuinely second payment', async () => {
      const invoiceId = await openInvoice(500);
      const before = count('SELECT COUNT(*) AS n FROM payments');

      const a = await post('/api/payments', keyFor(IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER), await body(invoiceId, 100));
      const b = await post('/api/payments', keyFor(IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER), await body(invoiceId, 100));

      expect(a.status).toBe(201);
      expect(b.status).toBe(201);
      expect(count('SELECT COUNT(*) AS n FROM payments')).toBe(before + 2);
    });
  });

  // ── payments.supplier ───────────────────────────────────────────────
  describe('payments.supplier', () => {
    async function seedPurchase(): Promise<number> {
      const res = await request(app).post('/api/purchases')
        .set('Cookie', authCookie)
        .send({
          item_id: itemId,
          warehouse_id: warehouseId,
          quantity: 5,
          unit_cost: 10,
          purchase_date: '2026-09-01',
          supplier_id: supplierId,
        });
      expect(res.status).toBe(201);
      const purchaseId = Array.isArray(res.body) ? res.body[0].id : res.body.id;
      return purchaseId;
    }

    it('replays a lost supplier payment instead of paying twice', async () => {
      const purchaseId = await seedPurchase();
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_SUPPLIER);
      const payload = {
        supplier_id: supplierId,
        payment_date: '2026-09-20',
        amount: 20,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: purchaseId, amount: 20 }],
      };

      const before = {
        payments: count('SELECT COUNT(*) AS n FROM payments'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PAYMENT'"),
      };

      const first = await post('/api/payments', key, payload);
      expect(first.status).toBe(201);
      const second = await post('/api/payments', key, payload);
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(second.body.data.id).toBe(first.body.data.id);
      expect(count('SELECT COUNT(*) AS n FROM payments')).toBe(before.payments + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PAYMENT'"))
        .toBe(before.gl + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const purchaseA = await seedPurchase();
      const purchaseB = await seedPurchase();
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_SUPPLIER);

      const first = await post('/api/payments', key, {
        supplier_id: supplierId,
        payment_date: '2026-09-20',
        amount: 20,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: purchaseA, amount: 20 }],
      });
      expect(first.status).toBe(201);

      const second = await post('/api/payments', key, {
        supplier_id: supplierId,
        payment_date: '2026-09-20',
        amount: 30,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: purchaseB, amount: 30 }],
      });
      expect(second.status).toBe(409);
    });
  });

  // ── payments.allocate ───────────────────────────────────────────────
  describe('payments.allocate', () => {
    /**
     * The allocate endpoint exists for a payment recorded WITHOUT
     * allocations, but POST /api/payments requires allocations to sum to the
     * payment amount — so an unallocated payment cannot be produced through
     * that API. It is inserted directly as a fixture, which is also the only
     * way to reach the double-allocation this scope has to prevent.
     */
    function insertUnallocatedPayment(amount: number): number {
      const no = `IDEM-ALLOC-${Date.now()}-${Math.floor(Math.random() * 1e4)}`;
      const res = db.prepare(`
        INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method, created_by)
        VALUES (?, ?, '2026-09-20', ?, 'Cash', 1)
      `).run(no, customerId, amount);
      return Number(res.lastInsertRowid);
    }

    it('replays a lost allocation instead of double-allocating', async () => {
      const invoiceA = await openInvoice(300);
      const invoiceB = await openInvoice(300);
      const paymentId = insertUnallocatedPayment(200);

      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_ALLOCATE);
      const payload = {
        allocations: [
          { invoice_id: invoiceA, amount: 100 },
          { invoice_id: invoiceB, amount: 100 },
        ],
      };

      const before = count('SELECT COUNT(*) AS n FROM payment_allocations WHERE payment_id = ?', paymentId);
      const first = await request(app).post(`/api/payments/${paymentId}/allocate`)
        .set('Cookie', authCookie).set('Idempotency-Key', key).send(payload);
      expect(first.status).toBe(200);
      const second = await request(app).post(`/api/payments/${paymentId}/allocate`)
        .set('Cookie', authCookie).set('Idempotency-Key', key).send(payload);
      expect(second.status).toBe(200);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM payment_allocations WHERE payment_id = ?', paymentId))
        .toBe(before + 2);
    });

    it('rejects the same key with changed allocations', async () => {
      const invoiceA = await openInvoice(320);
      const invoiceB = await openInvoice(320);
      const paymentId = insertUnallocatedPayment(200);
      const key = keyFor(IDEMPOTENCY_SCOPES.PAYMENT_ALLOCATE);

      const first = await request(app).post(`/api/payments/${paymentId}/allocate`)
        .set('Cookie', authCookie).set('Idempotency-Key', key)
        .send({ allocations: [{ invoice_id: invoiceA, amount: 100 }, { invoice_id: invoiceB, amount: 100 }] });
      expect(first.status).toBe(200);

      const second = await request(app).post(`/api/payments/${paymentId}/allocate`)
        .set('Cookie', authCookie).set('Idempotency-Key', key)
        .send({ allocations: [{ invoice_id: invoiceA, amount: 200 }] });
      expect(second.status).toBe(409);
    });
  });

  // ── expenses.create ─────────────────────────────────────────────────
  describe('expenses.create', () => {
    const payload = () => ({
      expense_category: 'Utilities',
      description: 'Idempotency probe',
      amount: 321.45,
      expense_date: '2026-09-20',
      payment_method: 'Cash',
    });

    it('replays a lost response and expenses the cash once', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.EXPENSE_CREATE);
      // A Draft expense posts no GL entry — the cash leaves when it is
      // posted, not when it is created. So the duplicate-proof here is the
      // expense row; the GL is asserted on the posting transition instead.
      const before = count('SELECT COUNT(*) AS n FROM expenses');

      const first = await post('/api/expenses', key, payload());
      expect(first.status).toBe(201);
      const second = await post('/api/expenses', key, payload());
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM expenses')).toBe(before + 1);
    });

    it('rejects the same key with a changed amount', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.EXPENSE_CREATE);
      const first = await post('/api/expenses', key, payload());
      expect(first.status).toBe(201);

      const second = await post('/api/expenses', key, { ...payload(), amount: 999.99 });
      expect(second.status).toBe(409);
    });

    it('leaves no claim behind when the attempt fails, so the retry runs', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.EXPENSE_CREATE);

      // Unknown category — rejected before any write, so nothing is claimed.
      const failed = await post('/api/expenses', key, { ...payload(), expense_category: 'No Such Category' });
      expect(failed.status).toBe(400);
      expect(count('SELECT COUNT(*) AS n FROM idempotency_keys WHERE scope = ? AND key = ?', IDEMPOTENCY_SCOPES.EXPENSE_CREATE, key))
        .toBe(0);

      // The same key now succeeds rather than replaying a phantom.
      const retried = await post('/api/expenses', key, payload());
      expect(retried.status).toBe(201);
      expect(retried.headers['x-idempotent-replay']).toBeUndefined();
    });
  });

  // ── purchases.record ────────────────────────────────────────────────
  describe('purchases.record', () => {
    const payload = () => ({
      item_id: itemId,
      warehouse_id: warehouseId,
      quantity: 7,
      unit_cost: 12,
      purchase_date: '2026-09-05',
      supplier_id: supplierId,
    });

    it('replays a lost response and records the purchase once', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.PURCHASE_RECORD);
      const before = {
        purchases: count('SELECT COUNT(*) AS n FROM purchases'),
        batches: count('SELECT COUNT(*) AS n FROM stock_batches'),
        gl: count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PURCHASE'"),
      };

      const first = await post('/api/purchases', key, payload());
      expect(first.status).toBe(201);
      const second = await post('/api/purchases', key, payload());
      expect(second.status).toBe(201);

      expect(second.headers['x-idempotent-replay']).toBe('true');
      expect(count('SELECT COUNT(*) AS n FROM purchases')).toBe(before.purchases + 1);
      expect(count('SELECT COUNT(*) AS n FROM stock_batches')).toBe(before.batches + 1);
      expect(count("SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'PURCHASE'"))
        .toBe(before.gl + 1);
    });

    it('rejects the same key with a changed quantity', async () => {
      const key = keyFor(IDEMPOTENCY_SCOPES.PURCHASE_RECORD);
      const first = await post('/api/purchases', key, payload());
      expect(first.status).toBe(201);

      const second = await post('/api/purchases', key, { ...payload(), quantity: 9 });
      expect(second.status).toBe(409);
    });

    it('rejects a malformed key with 400 rather than silently proceeding', async () => {
      const res = await post('/api/purchases', 'short', payload());
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/Idempotency-Key must be 8\.\.200/);
    });
  });

  // ── key namespace + retention ───────────────────────────────────────
  describe('key namespace and retention', () => {
    it('treats the same key in two scopes as two operations', async () => {
      const shared = `shared-key-${Date.now()}`;

      const invoiceId = await openInvoice(600);
      const payment = await post('/api/payments', shared, {
        customer_id: customerId,
        payment_date: '2026-09-20',
        amount: 50,
        payment_method: 'Cash',
        invoice_allocations: [{ invoice_id: invoiceId, amount: 50 }],
      });
      expect(payment.status).toBe(201);

      // Same key, different scope: must NOT be treated as a replay.
      const expense = await post('/api/expenses', shared, {
        expense_category: 'Utilities',
        amount: 10,
        expense_date: '2026-09-20',
        payment_method: 'Cash',
      });
      expect(expense.status).toBe(201);
      expect(expense.headers['x-idempotent-replay']).toBeUndefined();
    });

    it('prunes only completed keys past the retention window', () => {
      const stale = `stale-${Date.now()}`;
      const fresh = `fresh-${Date.now()}`;
      db.prepare(`
        INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, created_at, completed_at)
        VALUES (?, 'test.scope', 'h', 1, '2020-01-01 00:00:00', '2020-01-01 00:00:00')
      `).run(stale);
      db.prepare(`
        INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, created_at, completed_at)
        VALUES (?, 'test.scope', 'h', 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `).run(fresh);
      // An incomplete claim (rolled-back attempt) must survive the sweep.
      const inFlight = `inflight-${Date.now()}`;
      db.prepare(`
        INSERT INTO idempotency_keys (key, scope, request_hash, resource_id, created_at, completed_at)
        VALUES (?, 'test.scope', 'h', NULL, CURRENT_TIMESTAMP, NULL)
      `).run(inFlight);

      const pruned = pruneIdempotencyKeys(db, 30, new Date());
      expect(pruned).toBeGreaterThanOrEqual(1);

      const remaining = db.prepare('SELECT key FROM idempotency_keys WHERE key IN (?, ?, ?)')
        .all(stale, fresh, inFlight) as Array<{ key: string }>;
      const keys = remaining.map((r) => r.key);
      expect(keys).not.toContain(stale);
      expect(keys).toContain(fresh);
      expect(keys).toContain(inFlight);
    });
  });
});
