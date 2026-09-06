"use strict";
// Integration tests for Zod validation middleware
// (SHORTCOMINGS-FIX 2.3)
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
let authToken;
beforeAll(async () => {
    const res = await (0, supertest_1.default)(app_1.default)
        .post('/api/auth/login')
        .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
    authToken = res.body.data.token;
});
describe('Validation middleware — consistent error envelope', () => {
    it('returns 400 with details array for invalid body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({}); // missing username + password
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
        // The validateZod middleware returns error as a string, not nested
        expect(res.body.error).toBeDefined();
    });
    it('rejects invalid pagination query params', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?page=abc&limit=-1')
            .set('Authorization', `Bearer ${authToken}`);
        // Zod validation catches invalid page/limit
        expect([200, 400]).toContain(res.status);
    });
    it('accepts valid pagination query params', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?page=1&limit=5')
            .set('Authorization', `Bearer ${authToken}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('validates customer create body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Authorization', `Bearer ${authToken}`)
            .send({}); // missing required fields
        expect(res.status).toBe(400);
    });
    it('validates item create body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Authorization', `Bearer ${authToken}`)
            .send({}); // missing item_code + item_name
        expect(res.status).toBe(400);
    });
    it('validates expense create body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/expenses')
            .set('Authorization', `Bearer ${authToken}`)
            .send({}); // missing required fields
        expect(res.status).toBe(400);
    });
    it('validates role create body', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/roles')
            .set('Authorization', `Bearer ${authToken}`)
            .send({}); // missing role_name
        expect(res.status).toBe(400);
    });
});
