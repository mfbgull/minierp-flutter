"use strict";
// Integration tests for customer/item soft-delete and restore
// (SHORTCOMINGS-FIX 4.2)
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
let authToken;
beforeAll(async () => {
    // Login as admin to get auth token
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
    authToken = res.body.data.token;
});
describe('Customer soft-delete and restore', () => {
    let customerId;
    it('creates a customer', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Authorization', `Bearer ${authToken}`)
            .send({ customer_name: 'Test Customer SD', phone: '555-0100' });
        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        customerId = res.body.data.id;
    });
    it('soft-deletes the customer', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/customers/${customerId}`)
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('deleted customer is hidden from list', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?search=Test+Customer+SD')
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        const names = res.body.data.map((c) => c.customer_name);
        expect(names).not.toContain('Test Customer SD');
    });
    it('restores the customer', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/customers/${customerId}/restore`)
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('restored customer appears in list again', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?search=Test+Customer+SD')
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        const names = res.body.data.map((c) => c.customer_name);
        expect(names).toContain('Test Customer SD');
    });
});
describe('Item soft-delete and restore', () => {
    let itemId;
    it('creates an item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Authorization', `Bearer ${authToken}`)
            .send({
            item_code: 'SD-TEST-001',
            item_name: 'Soft Delete Test Item',
            selling_price: 50,
        });
        expect(res.status).toBe(201);
        // Item create returns the raw item (no `success` wrapper) — same
        // contract the api.integration tests pin.
        itemId = res.body.id;
    });
    it('soft-deletes the item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .delete(`/api/inventory/items/${itemId}`)
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('restores the item', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/inventory/items/${itemId}/restore`)
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
});
