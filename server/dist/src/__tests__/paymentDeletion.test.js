"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * PAY-01 regression tests: payment deletion during invoice update requires
 * ownership (an allocation row joining the payment to THIS invoice) and
 * writes an activity_log audit row per removed payment.
 */
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
    throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}
async function getAuthCookie() {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username: 'admin', password: TEST_PASSWORD });
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return '';
    const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c) => c.startsWith('token='));
    return tokenCookie ? tokenCookie.split(';')[0] : '';
}
describe('Payment deletion safety on invoice update (PAY-01)', () => {
    let authCookie;
    let itemId;
    let customerId;
    let otherCustomerId;
    let warehouseId;
    let invoiceNoCounter = 7000;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        const wh = database_1.default.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get();
        warehouseId = wh.id;
        const item = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: `PAY01-${Date.now()}`, item_name: 'PAY-01 Test Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        // Stock for two invoices' worth of sales.
        await (0, supertest_1.default)(app_1.default)
            .post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 10,
            unit_cost: 20,
            purchase_date: '2026-08-01',
            supplier_name: 'PAY-01 Supplier',
        });
        const customer = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'PAY-01 Customer', phone: '555-0701' });
        expect(customer.status).toBe(201);
        customerId = customer.body.data.id;
        const customer2 = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'PAY-01 Other Customer', phone: '555-0702' });
        expect(customer2.status).toBe(201);
        otherCustomerId = customer2.body.data.id;
    });
    async function createInvoice(customerIdForInvoice) {
        invoiceNoCounter += 1;
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-PAY01-${invoiceNoCounter}`,
            customer_id: customerIdForInvoice,
            invoice_date: '2026-08-10',
            due_date: '2026-08-20',
            status: 'Unpaid',
            total_amount: 100,
            items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
        });
        expect(res.status).toBe(201);
        return { invoiceId: res.body.id, invoiceNo: res.body.invoice_no };
    }
    async function recordPayment(invoiceId, amount = 40) {
        const res = await (0, supertest_1.default)(app_1.default)
            .put(`/api/invoices/${invoiceId}`)
            .set('Cookie', authCookie)
            .send(fullUpdateBody(invoiceId, {
            record_payment: true,
            payment: { amount, payment_date: '2026-08-11', payment_method: 'Cash' },
        }));
        expect(res.status).toBe(200);
        const alloc = database_1.default.prepare('SELECT payment_id FROM payment_allocations WHERE invoice_id = ?').get(invoiceId);
        expect(alloc).toBeDefined();
        return alloc.payment_id;
    }
    // PUT /api/invoices/:id validates the full invoice body — build it from
    // the current row plus any overrides.
    function fullUpdateBody(invoiceId, extra = {}) {
        const inv = database_1.default.prepare('SELECT customer_id, invoice_date, due_date, total_amount FROM invoices WHERE id = ?').get(invoiceId);
        return {
            customer_id: inv.customer_id,
            invoice_date: inv.invoice_date.slice(0, 10),
            due_date: inv.due_date.slice(0, 10),
            total_amount: inv.total_amount,
            items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
            ...extra,
        };
    }
    async function updateWithDeletedPayments(targetInvoiceId, deletedPayments) {
        return (0, supertest_1.default)(app_1.default)
            .put(`/api/invoices/${targetInvoiceId}`)
            .set('Cookie', authCookie)
            .send(fullUpdateBody(targetInvoiceId, { deleted_payments: deletedPayments }));
    }
    it('rejects a crafted cross-invoice payment id with 400 and deletes nothing', async () => {
        const { invoiceId: invA } = await createInvoice(customerId);
        const { invoiceId: invB } = await createInvoice(otherCustomerId);
        const victimPaymentId = await recordPayment(invA); // allocated to invoice A
        // Try to remove it while updating invoice B.
        const res = await updateWithDeletedPayments(invB, [victimPaymentId]);
        expect(res.status).toBe(400);
        // Payment and its allocation must be untouched.
        const stillThere = database_1.default.prepare(`SELECT COUNT(*) AS c FROM payment_allocations WHERE payment_id = ? AND invoice_id = ?`).get(victimPaymentId, invA);
        expect(stillThere.c).toBe(1);
        const paymentRow = database_1.default.prepare('SELECT id FROM payments WHERE id = ?').get(victimPaymentId);
        expect(paymentRow).toBeDefined();
    });
    it('deletes an own-invoice payment inside the transaction and writes an audit row', async () => {
        const { invoiceId } = await createInvoice(customerId);
        const ownPaymentId = await recordPayment(invoiceId);
        const paymentBefore = database_1.default.prepare('SELECT payment_no, amount FROM payments WHERE id = ?').get(ownPaymentId);
        const res = await updateWithDeletedPayments(invoiceId, [ownPaymentId]);
        expect(res.status).toBe(200);
        // Payment gone inside transaction
        expect(database_1.default.prepare('SELECT id FROM payments WHERE id = ?').get(ownPaymentId)).toBeUndefined();
        expect(database_1.default.prepare('SELECT id FROM payment_allocations WHERE payment_id = ?').get(ownPaymentId)).toBeUndefined();
        // The activity logger batches writes on a 1s interval and exposes no
        // completion signal, so a real delay is required to cover the flush
        // window (no fake-timer seam exists for the module's setInterval).
        let flushDone;
        const flushed = new Promise((resolve) => { flushDone = resolve; });
        setTimeout(flushDone, 1500);
        await flushed;
        // Audit row exists recording who removed which payment
        const audit = database_1.default.prepare(`
      SELECT user_id, action, entity_type, entity_id, description, metadata
      FROM activity_log
      WHERE action = 'PAYMENT_DELETE' AND entity_id = ?
      ORDER BY id DESC
    `).get(ownPaymentId);
        expect(audit).toBeDefined();
        expect(audit.entity_type).toBe('Payment');
        const meta = JSON.parse(audit.metadata);
        expect(meta.payment_no).toBe(paymentBefore.payment_no);
        expect(Number(meta.amount)).toBeCloseTo(Number(paymentBefore.amount), 2);
        expect(meta.invoice_id).toBe(invoiceId);
        expect(meta.actor).toBe(audit.user_id);
    });
});
//# sourceMappingURL=paymentDeletion.test.js.map