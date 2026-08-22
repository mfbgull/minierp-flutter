"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * GL lifecycle consistency tests (gl-posting-completeness §1).
 *
 * ACC-08: invoice update must void + re-post its INVOICE/COGS lines.
 * ACC-09: payment delete/update must void PAYMENT lines.
 * ACC-21: deleteInvoice orphan-cleanup branch must actually run.
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
function activeLines(refType, refId) {
    return database_1.default.prepare(`SELECT account_id, debit, credit, voided FROM journal_lines
     WHERE reference_type = ? AND reference_id = ? AND voided = 0`).all(refType, refId);
}
function voidedAttribution(refType, refId) {
    return database_1.default.prepare(`SELECT voided_at, voided_by, void_reason FROM journal_lines
     WHERE reference_type = ? AND reference_id = ? AND voided = 1
     ORDER BY id DESC LIMIT 1`).get(refType, refId);
}
function arAccountId() {
    const row = database_1.default.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1100'`).get();
    return row.id;
}
describe('GL lifecycle: update/delete voiding', () => {
    let authCookie;
    let itemId;
    let customerId;
    let warehouseId;
    let invoiceNoCounter = 8000;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        const wh = database_1.default.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get();
        warehouseId = wh.id;
        const item = await (0, supertest_1.default)(app_1.default).post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: `GLLC-${Date.now()}`, item_name: 'GL Lifecycle Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        await (0, supertest_1.default)(app_1.default).post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 20,
            unit_cost: 10,
            purchase_date: '2026-08-01',
            supplier_name: 'GL Lifecycle Supplier',
        });
        const customer = await (0, supertest_1.default)(app_1.default).post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'GL Lifecycle Customer', phone: '555-0808' });
        expect(customer.status).toBe(201);
        customerId = customer.body.data?.id ?? customer.body.id;
    });
    async function createInvoice(totalAmount) {
        invoiceNoCounter += 1;
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-GLLC-${invoiceNoCounter}`,
            customer_id: customerId,
            invoice_date: '2026-08-10',
            due_date: '2026-08-20',
            status: 'Unpaid',
            total_amount: totalAmount,
            items: [{ item_id: itemId, quantity: totalAmount / 100, unit_price: 100, warehouse_id: warehouseId }],
        });
        expect(res.status).toBe(201);
        return { invoiceId: res.body.id, invoiceNo: res.body.invoice_no };
    }
    function fullUpdateBody(invoiceId, extra = {}) {
        const inv = database_1.default.prepare('SELECT customer_id, invoice_date, due_date FROM invoices WHERE id = ?').get(invoiceId);
        return {
            customer_id: inv.customer_id,
            invoice_date: inv.invoice_date.slice(0, 10),
            due_date: inv.due_date.slice(0, 10),
            items: [{ item_id: itemId, quantity: 2, unit_price: 100, warehouse_id: warehouseId }],
            ...extra,
        };
    }
    it('invoice update voids old lines with attribution and re-posts at the new amount', async () => {
        const { invoiceId } = await createInvoice(100);
        // Revenue leg only (AR account) — the COGS entry also references this
        // invoice and must not pollute the amount assertion.
        const arId = arAccountId();
        const beforeAr = database_1.default.prepare(`SELECT debit FROM journal_lines WHERE reference_type='INVOICE' AND reference_id=? AND voided=0 AND account_id=?`).all(invoiceId, arId);
        const beforeDebit = beforeAr.reduce((s, l) => s + Number(l.debit), 0);
        expect(beforeDebit).toBeCloseTo(100, 2);
        // Change the total to 200 (2 × 100).
        const put = await (0, supertest_1.default)(app_1.default).put(`/api/invoices/${invoiceId}`)
            .set('Cookie', authCookie)
            .send(fullUpdateBody(invoiceId, { total_amount: 200 }));
        expect(put.status).toBe(200);
        const afterAr = database_1.default.prepare(`SELECT debit FROM journal_lines WHERE reference_type='INVOICE' AND reference_id=? AND voided=0 AND account_id=?`).all(invoiceId, arId);
        const afterDebit = afterAr.reduce((s, l) => s + Number(l.debit), 0);
        expect(afterDebit).toBeCloseTo(200, 2);
        // Old lines survive as voided with attribution.
        const attr = voidedAttribution('INVOICE', invoiceId);
        expect(attr).toBeDefined();
        expect(attr.voided_at).toBeTruthy();
        expect(attr.void_reason).toContain('updated');
        // Active line count is the same shape (re-posted, not accumulated).
        expect(afterAr.length).toBe(beforeAr.length);
    });
    it('payment deletion leaves zero non-voided PAYMENT lines', async () => {
        const { invoiceId } = await createInvoice(100);
        // Record a payment via the invoice-update endpoint.
        const put = await (0, supertest_1.default)(app_1.default).put(`/api/invoices/${invoiceId}`)
            .set('Cookie', authCookie)
            .send(fullUpdateBody(invoiceId, {
            record_payment: true,
            payment: { amount: 40, payment_date: '2026-08-11', payment_method: 'Cash' },
        }));
        expect(put.status).toBe(200);
        const alloc = database_1.default.prepare('SELECT payment_id FROM payment_allocations WHERE invoice_id = ?').get(invoiceId);
        expect(alloc).toBeDefined();
        const beforeVoid = database_1.default.prepare(`SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type='PAYMENT' AND reference_id=? AND voided=0`).get(alloc.payment_id);
        expect(beforeVoid.c).toBeGreaterThan(0);
        // Delete the payment through the payments API.
        const del = await (0, supertest_1.default)(app_1.default).delete(`/api/payments/${alloc.payment_id}`)
            .set('Cookie', authCookie);
        if (![200, 204].includes(del.status)) {
            throw new Error(`payment delete returned ${del.status}: ${JSON.stringify(del.body)}`);
        }
        const afterVoid = database_1.default.prepare(`SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type='PAYMENT' AND reference_id=? AND voided=0`).get(alloc.payment_id);
        expect(afterVoid.c).toBe(0);
    });
    it('payment amount change voids the old entry and re-posts the new one', async () => {
        const { invoiceId } = await createInvoice(200);
        const put = await (0, supertest_1.default)(app_1.default).put(`/api/invoices/${invoiceId}`)
            .set('Cookie', authCookie)
            .send(fullUpdateBody(invoiceId, {
            record_payment: true,
            payment: { amount: 50, payment_date: '2026-08-11', payment_method: 'Cash' },
        }));
        expect(put.status).toBe(200);
        const alloc = database_1.default.prepare('SELECT payment_id FROM payment_allocations WHERE invoice_id = ?').get(invoiceId);
        // Edit the payment amount to 80.
        const upd = await (0, supertest_1.default)(app_1.default).put(`/api/payments/${alloc.payment_id}`)
            .set('Cookie', authCookie)
            .send({ amount: 80 });
        expect(upd.status).toBe(200);
        // Exactly one active debit leg remains, at the new amount.
        const active = database_1.default.prepare(`SELECT debit FROM journal_lines
       WHERE reference_type='PAYMENT' AND reference_id=? AND voided=0 AND debit > 0`).all(alloc.payment_id);
        const activeDebit = active.reduce((s, l) => s + Number(l.debit), 0);
        expect(activeDebit).toBeCloseTo(80, 2);
        // The 50-entry is gone into voided state.
        const attr = voidedAttribution('PAYMENT', alloc.payment_id);
        expect(attr).toBeDefined();
        expect(attr.voided_at).toBeTruthy();
    });
});
//# sourceMappingURL=glLifecycle.test.js.map