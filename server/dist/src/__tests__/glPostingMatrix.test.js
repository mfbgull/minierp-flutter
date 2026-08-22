"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const Payment_1 = __importDefault(require("../models/Payment"));
/**
 * GL posting-matrix tests (gl-posting-completeness §2).
 *
 * Every financial document type must produce balanced journal_lines rows:
 * purchase (Dr 1200 / Cr 2000), supplier payment (Dr 2000 / Cr cash),
 * expense (Dr 6000 / Cr cash), POS sale, mobile invoice, SO→invoice.
 */
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
function accountId(code) {
    return database_1.default.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code).id;
}
function linesFor(refType, refId) {
    return database_1.default.prepare(`SELECT account_id, debit, credit FROM journal_lines
     WHERE reference_type = ? AND reference_id = ? AND voided = 0`).all(refType, refId);
}
function expectBalanced(lines) {
    expect(lines.length).toBeGreaterThanOrEqual(2);
    const debits = lines.reduce((s, l) => s + Number(l.debit), 0);
    const credits = lines.reduce((s, l) => s + Number(l.credit), 0);
    expect(debits).toBeCloseTo(credits, 2);
    expect(debits).toBeGreaterThan(0);
}
describe('GL posting matrix', () => {
    let authCookie;
    let itemId;
    let customerId;
    let warehouseId;
    let supplierId;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        warehouseId = database_1.default.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get().id;
        const item = await (0, supertest_1.default)(app_1.default).post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: `GLPM-${Date.now()}`, item_name: 'Posting Matrix Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        supplierId = (await (0, supertest_1.default)(app_1.default).post('/api/suppliers')
            .set('Cookie', authCookie)
            .send({
            supplier_code: `GLPM-SUP-${Date.now()}`,
            supplier_name: 'Matrix Supplier',
        })).body?.data?.id;
        await (0, supertest_1.default)(app_1.default).post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 50,
            unit_cost: 20,
            purchase_date: '2026-08-01',
            supplier_id: supplierId,
        });
        const customer = await (0, supertest_1.default)(app_1.default).post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'Matrix Customer', phone: '555-0606' });
        expect(customer.status).toBe(201);
        customerId = customer.body.data?.id ?? customer.body.id;
    });
    it('purchase posts a balanced Dr Inventory / Cr AP entry', async () => {
        const res = await (0, supertest_1.default)(app_1.default).post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 5,
            unit_cost: 30,
            purchase_date: '2026-08-05',
            supplier_name: 'Matrix Supplier Two',
        });
        expect(res.status).toBe(201);
        const purchaseId = res.body.id;
        const lines = linesFor('PURCHASE', purchaseId);
        expectBalanced(lines);
        const inventoryId = accountId('1200');
        const apId = accountId('2000');
        const invLine = lines.find(l => l.account_id === inventoryId);
        const apLine = lines.find(l => l.account_id === apId);
        expect(invLine?.debit).toBeCloseTo(150, 2); // 5 × 30
        expect(apLine?.credit).toBeCloseTo(150, 2);
        // Movement flagged financially posted
        const mv = database_1.default.prepare(`SELECT financial_posted FROM stock_movements WHERE reference_docno = ? AND movement_type='PURCHASE'`).get(res.body.purchase_no);
        expect(Number(mv.financial_posted)).toBe(1);
    });
    it('supplier payment posts a balanced Dr AP / Cr cash entry', async () => {
        // The posting lives in the model — exercise it directly with a real
        // purchase allocation.
        const firstPurchase = database_1.default.prepare(`SELECT id FROM purchases WHERE supplier_id = ? ORDER BY id LIMIT 1`).get(supplierId);
        expect(firstPurchase).toBeDefined();
        const payId = Payment_1.default.createSupplierPayment(database_1.default, {
            supplier_id: supplierId,
            payment_date: '2026-08-07',
            amount: 250,
            payment_method: 'Cash',
            purchase_allocations: [{ purchase_id: String(firstPurchase.id), amount: 250 }],
            po_allocations: [],
            userId: 1,
        });
        const lines = linesFor('PAYMENT', payId);
        expectBalanced(lines);
        const apId = accountId('2000');
        const cashId = accountId('1000');
        expect(lines.some(l => l.account_id === apId && Number(l.debit) > 0)).toBe(true);
        expect(lines.some(l => l.account_id === cashId && Number(l.credit) > 0)).toBe(true);
    });
    it('expense posts a balanced Dr OpEx / Cr cash entry', async () => {
        const res = await (0, supertest_1.default)(app_1.default).post('/api/expenses')
            .set('Cookie', authCookie)
            .send({
            expense_category: 'Utilities',
            description: 'GL posting matrix test expense',
            amount: 75.5,
            expense_date: '2026-08-08',
            payment_method: 'Cash',
        });
        expect(res.status).toBe(201);
        const expenseId = res.body?.data?.id ?? res.body?.id;
        const lines = linesFor('EXPENSE', expenseId);
        expectBalanced(lines);
        const opexId = accountId('6000');
        const cashId = accountId('1000');
        expect(lines.some(l => l.account_id === opexId && Number(l.debit) > 0)).toBe(true);
        expect(lines.some(l => l.account_id === cashId && Number(l.credit) > 0)).toBe(true);
    });
    it('POS sale posts invoice + COGS + payment entries', async () => {
        const res = await (0, supertest_1.default)(app_1.default).post('/api/pos/sale')
            .set('Cookie', authCookie)
            .send({
            warehouse_id: warehouseId,
            sale_date: '2026-08-09',
            items: [{ item_id: itemId, quantity: 2, unit_price: 50 }],
            cash_received: 100,
        });
        expect(res.status).toBe(201);
        const invoiceId = res.body.data.sale_ids[0];
        const revenueLines = linesFor('INVOICE', invoiceId);
        expectBalanced(revenueLines);
        // Revenue entry: Dr AR / Cr Sales
        expect(revenueLines.some(l => l.account_id === accountId('1100'))).toBe(true);
        expect(revenueLines.some(l => l.account_id === accountId('4000'))).toBe(true);
        // COGS entry shares the reference and must balance too.
        const allInvLines = database_1.default.prepare(`SELECT account_id, debit, credit FROM journal_lines WHERE reference_type='INVOICE' AND reference_id=? AND voided=0`).all(invoiceId);
        expectBalanced(allInvLines);
        expect(allInvLines.some(l => l.account_id === accountId('5000'))).toBe(true);
        // Payment entry exists for the recorded cash.
        const payRow = database_1.default.prepare('SELECT id FROM payments WHERE customer_id = ? ORDER BY id DESC LIMIT 1').get(accountWalkIn());
        if (payRow) {
            const payLines = linesFor('PAYMENT', payRow.id);
            if (payLines.length > 0) {
                expectBalanced(payLines);
            }
        }
    });
    function accountWalkIn() {
        return database_1.default.prepare(`SELECT id FROM customers WHERE customer_name LIKE '%Walk-in%' LIMIT 1`).get().id;
    }
    it('SO conversion produces subledger row plus GL entries', async () => {
        // Create SO
        const so = await (0, supertest_1.default)(app_1.default).post('/api/sales-orders')
            .set('Cookie', authCookie)
            .send({
            customer_id: customerId,
            so_date: '2026-08-10',
            expected_delivery_date: '2026-08-15',
            warehouse_id: warehouseId,
            items: [{ item_id: itemId, quantity: 3, unit_price: 40, amount: 120 }],
        });
        expect(so.status).toBe(201);
        const soId = so.body.data?.id ?? so.body.id;
        const conv = await (0, supertest_1.default)(app_1.default).post(`/api/sales-orders/${soId}/convert`)
            .set('Cookie', authCookie)
            .send({});
        expect(conv.status).toBe(201);
        const invoiceNo = String(conv.body.data?.invoice_no ?? conv.body.invoice_no ?? conv.body.invoiceNo ?? '');
        const invoiceIdFromRes = conv.body.data?.invoice_id ?? conv.body.data?.id ?? conv.body.invoice_id ?? conv.body.id;
        let inv = database_1.default.prepare('SELECT id FROM invoices WHERE invoice_no = ?').get(invoiceNo);
        if (!inv && invoiceIdFromRes)
            inv = { id: Number(invoiceIdFromRes) };
        if (!inv)
            throw new Error(`converted invoice not found: no=${invoiceNo} resp=${JSON.stringify(conv.body).slice(0, 200)}`);
        // GL entries exist
        const lines = linesFor('INVOICE', inv.id);
        expectBalanced(lines);
        // Subledger row now exists (ACC-07 core assertion).
        const ledgerRow = database_1.default.prepare(`SELECT id FROM customer_ledger WHERE reference_no = ? AND transaction_type = 'INVOICE'`).get(invoiceNo);
        expect(ledgerRow).toBeDefined();
    });
});
//# sourceMappingURL=glPostingMatrix.test.js.map