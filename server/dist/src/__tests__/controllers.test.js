"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
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
    if (!tokenCookie)
        return '';
    return tokenCookie.split(';')[0];
}
async function getCsrfToken(authCookie) {
    const res = await (0, supertest_1.default)(app_1.default)
        .get('/api/customers')
        .set('Cookie', authCookie);
    const cookies = res.headers['set-cookie'];
    if (!cookies)
        return { cookie: '', token: '' };
    const csrfCookie = (Array.isArray(cookies) ? cookies : [cookies])
        .find((c) => c.startsWith('csrf-token='));
    if (!csrfCookie)
        return { cookie: '', token: '' };
    const token = csrfCookie.split(';')[0].split('=')[1];
    return { cookie: csrfCookie.split(';')[0], token };
}
describe('Auth Controller', () => {
    it('login returns user without password_hash', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'admin', password: TEST_PASSWORD });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.user).not.toHaveProperty('password_hash');
        expect(res.body.data.user).toHaveProperty('username', 'admin');
    });
    it('login sets httpOnly cookie', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'admin', password: TEST_PASSWORD });
        const cookies = res.headers['set-cookie'];
        expect(cookies).toBeDefined();
        const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
            .find((c) => c.startsWith('token='));
        expect(tokenCookie).toBeDefined();
    });
    it('logout clears token cookie', async () => {
        const authCookie = await getAuthCookie();
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/logout')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        const cookies = res.headers['set-cookie'];
        const clearCookie = (Array.isArray(cookies) ? cookies : [cookies])
            .find((c) => c.includes('token=') && c.includes('Expires'));
        expect(clearCookie).toBeDefined();
    });
    it('getCurrentUser returns full user profile', async () => {
        const authCookie = await getAuthCookie();
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/auth/me')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.data).toHaveProperty('id');
        expect(res.body.data).toHaveProperty('username');
        expect(res.body.data).toHaveProperty('email');
        expect(res.body.data).toHaveProperty('full_name');
        expect(res.body.data).toHaveProperty('role');
    });
    it('changePassword rejects short password', async () => {
        const authCookie = await getAuthCookie();
        const { cookie: csrfCookie, token: csrfToken } = await getCsrfToken(authCookie);
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/change-password')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ currentPassword: TEST_PASSWORD, newPassword: 'short' });
        expect(res.status).toBe(400);
    });
    it('changePassword rejects wrong current password', async () => {
        const authCookie = await getAuthCookie();
        const { cookie: csrfCookie, token: csrfToken } = await getCsrfToken(authCookie);
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/change-password')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ currentPassword: 'wrong-password', newPassword: 'newpass123' });
        expect(res.status).toBe(401);
    });
});
describe('Inventory Controller', () => {
    let authCookie;
    let csrfCookie;
    let csrfToken;
    let createdItemId;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const csrf = await getCsrfToken(authCookie);
        csrfCookie = csrf.cookie;
        csrfToken = csrf.token;
    });
    it('createItem returns 201 with new item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({
            item_code: `TEST-${Date.now()}`,
            item_name: 'Test Controller Item',
            category: 'Test',
            unit_price: 10.00,
            cost_price: 5.00,
            reorder_level: 10
        });
        expect(res.status).toBe(201);
        expect(res.body).toHaveProperty('id');
        expect(res.body.item_code).toContain('TEST-');
        createdItemId = res.body.id;
    });
    it('createItem rejects duplicate item_code', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({
            item_code: 'DUPLICATE-CODE-TEST',
            item_name: 'First Item'
        });
        expect(res.status).toBe(201);
        const res2 = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({
            item_code: 'DUPLICATE-CODE-TEST',
            item_name: 'Second Item'
        });
        expect(res2.status).toBe(400);
        expect(res2.body.error).toContain('already exists');
    });
    it('getItem returns 404 for non-existent item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/items/999999')
            .set('Cookie', authCookie);
        expect(res.status).toBe(404);
    });
    it('getItem includes stock_by_warehouse', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/inventory/items/${createdItemId}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('stock_by_warehouse');
        expect(Array.isArray(res.body.stock_by_warehouse)).toBe(true);
    });
    it('updateItem returns updated item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put(`/api/inventory/items/${createdItemId}`)
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ item_name: 'Updated Test Item' });
        expect(res.status).toBe(200);
        expect(res.body.item_name).toBe('Updated Test Item');
    });
    it('updateItem returns 404 for non-existent item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .put('/api/inventory/items/999999')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ item_name: 'Should Fail' });
        expect(res.status).toBe(404);
    });
    it('deleteItem removes item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/inventory/items/${createdItemId}`)
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken);
        expect([200, 403]).toContain(res.status);
    });
    it('getWarehouses returns warehouse data', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/warehouses')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body).toBeDefined();
    });
    it('getStockSummary returns aggregated data', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/stock-summary')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
});
describe('Sales Controller', () => {
    let authCookie;
    let csrfCookie;
    let csrfToken;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const csrf = await getCsrfToken(authCookie);
        csrfCookie = csrf.cookie;
        csrfToken = csrf.token;
    });
    it('getSalesSummaryByDateRange returns data', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/sales/summary/daterange?start_date=2025-01-01&end_date=2026-12-31')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('getCustomers returns customer data', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('getSalesDashboard returns summary', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/dashboard')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('getSalesSummaryByItem handles invalid item id', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/sales/summary/item/abc')
            .set('Cookie', authCookie);
        expect([200, 400, 404]).toContain(res.status);
    });
    it('getCustomerBalance returns customer balance', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers/1/balance')
            .set('Cookie', authCookie);
        expect([200, 400, 404]).toContain(res.status);
    });
    it('getQuotations returns quotation list', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/quotations')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('createQuotation rejects missing customer', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/quotations')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({
            quotation_date: '2026-01-01',
            items: [{ item_id: 1, quantity: 1, unit_price: 10 }]
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toContain('Customer');
    });
    it('createQuotation rejects missing items', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/quotations')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ customer_id: 1, quotation_date: '2026-01-01' });
        expect(res.status).toBe(400);
        expect(res.body.error).toContain('item');
    });
    it('createQuotation rejects empty items array', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/quotations')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({
            customer_id: 1,
            quotation_date: '2026-01-01',
            items: []
        });
        expect(res.status).toBe(400);
    });
    it('getSalesOrders returns orders list', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/sales-orders')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
});
