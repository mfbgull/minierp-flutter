"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
    throw new Error('TEST_ADMIN_PASSWORD environment variable must be set for integration tests.');
}
// Helper: authenticate and return cookie jar
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
describe('Health Endpoint', () => {
    it('GET /health returns status ok', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/health');
        expect(res.status).toBe(200);
        expect(res.body.status).toBe('ok');
        expect(res.body).toHaveProperty('timestamp');
        expect(res.body).toHaveProperty('uptime');
    });
});
describe('Auth Endpoints', () => {
    let token;
    it('POST /api/auth/login - rejects missing credentials', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({});
        expect(res.status).toBe(400);
    });
    it('POST /api/auth/login - rejects invalid credentials', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'admin', password: 'wrongpassword' });
        expect(res.status).toBe(401);
    });
    it('POST /api/auth/login - accepts valid credentials', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'admin', password: TEST_PASSWORD });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.user).toHaveProperty('username', 'admin');
        // Extract token from cookie
        const cookies = res.headers['set-cookie'];
        if (cookies) {
            const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
                .find((c) => c.startsWith('token='));
            if (tokenCookie) {
                token = tokenCookie.split(';')[0].split('=')[1];
            }
        }
        expect(token).toBeTruthy();
    });
    it('GET /api/auth/me - rejects unauthenticated requests', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/auth/me');
        expect(res.status).toBe(401);
    });
    it('GET /api/auth/me - returns current user with token', async () => {
        expect(token).toBeTruthy();
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/auth/me')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.data).toHaveProperty('username', 'admin');
    });
});
describe('Customers Endpoints', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
    });
    it('GET /api/customers - returns paginated customers list', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body).toHaveProperty('data');
        expect(res.body).toHaveProperty('pagination');
        expect(Array.isArray(res.body.data)).toBe(true);
    });
    it('GET /api/customers - supports search parameter', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?search=test')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('GET /api/customers - supports sorting', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?sortBy=customer_name&sortOrder=DESC')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('GET /api/customers - rejects invalid sort column (SQL injection)', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?sortBy=id;DROP%20TABLE%20customers;--')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
        if (res.status === 200) {
            expect(res.body.success).toBe(true);
        }
    });
    it('GET /api/customers/:id - returns 404 for non-existent customer', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers/99999')
            .set('Cookie', authCookie);
        expect(res.status).toBe(404);
    });
});
describe('Payments Endpoints', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
    });
    it('GET /api/payments - returns paginated payments list', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body).toHaveProperty('data');
        expect(res.body).toHaveProperty('pagination');
    });
    it('GET /api/payments - supports date range filtering', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments?fromDate=2025-01-01&toDate=2026-12-31')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('GET /api/payments/:id - returns 404 for non-existent payment', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments/99999')
            .set('Cookie', authCookie);
        expect(res.status).toBe(404);
    });
});
describe('Reports Endpoints', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
    });
    it('GET /api/reports/ar-aging - returns AR aging report', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/ar-aging')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('GET /api/reports/dso - returns DSO metric', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/dso')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('GET /api/reports/dso - rejects invalid period', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/dso?period=abc')
            .set('Cookie', authCookie);
        expect(res.status).toBe(400);
    });
    it('GET /api/reports/sales-summary - returns sales summary', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/sales-summary')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('GET /api/reports/stock-level - returns stock level report', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/stock-level')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
    it('GET /api/reports/low-stock - returns low stock report', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/reports/low-stock')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
    });
});
describe('Inventory Endpoints', () => {
    let token;
    beforeAll(async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'admin', password: TEST_PASSWORD });
        const cookies = res.headers['set-cookie'];
        if (cookies) {
            const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
                .find((c) => c.startsWith('token='));
            if (tokenCookie) {
                token = tokenCookie.split(';')[0].split('=')[1];
            }
        }
        expect(token).toBeTruthy();
    });
    it('GET /api/inventory/items - rejects unauthenticated requests', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/inventory/items');
        expect(res.status).toBe(401);
    });
    it('GET /api/inventory/items - returns inventory items with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/items')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
    });
    it('GET /api/inventory/items-categories - returns categories with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/items-categories')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
    });
    it('GET /api/inventory/warehouses - returns warehouses with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/warehouses')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
    });
});
describe('Security Tests', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
    });
    it('SQL injection via sortBy parameter is blocked', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?sortBy=id;DROP TABLE customers;--')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
        const check = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', authCookie);
        expect(check.status).toBe(200);
        expect(check.body.success).toBe(true);
    });
    it('SQL injection via sortOrder parameter is blocked', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments?sortOrder=DESC;DELETE FROM payments;--')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
        const check = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments')
            .set('Cookie', authCookie);
        expect(check.status).toBe(200);
    });
    it('SQL injection via period parameter is blocked', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get("/api/reports/dso?period=30';DELETE FROM invoices;--")
            .set('Cookie', authCookie);
        expect(res.status).toBe(400);
    });
});
//# sourceMappingURL=api.integration.test.js.map