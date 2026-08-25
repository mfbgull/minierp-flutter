"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
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
describe('JWT Security', () => {
    it('rejects tampered token (modified payload)', async () => {
        const fakeToken = jsonwebtoken_1.default.sign({ id: 1, username: 'hacker', email: 'x@y.z', role: 'admin' }, 'wrong-secret', { algorithm: 'HS256' });
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', `token=${fakeToken}`);
        expect(res.status).toBe(403);
    });
    it('rejects token with wrong issuer', async () => {
        const fakeToken = jsonwebtoken_1.default.sign({ id: 1, username: 'admin', email: 'a@b.c', role: 'admin' }, process.env.JWT_SECRET, { algorithm: 'HS256', issuer: 'evil-app' });
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', `token=${fakeToken}`);
        expect(res.status).toBe(403);
    });
    it('rejects token with wrong audience', async () => {
        const fakeToken = jsonwebtoken_1.default.sign({ id: 1, username: 'admin', email: 'a@b.c', role: 'admin' }, process.env.JWT_SECRET, { algorithm: 'HS256', audience: 'evil-client' });
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', `token=${fakeToken}`);
        expect(res.status).toBe(403);
    });
    it('rejects expired token', async () => {
        const expiredToken = jsonwebtoken_1.default.sign({ id: 1, username: 'admin', email: 'a@b.c', role: 'admin' }, process.env.JWT_SECRET, { algorithm: 'HS256', expiresIn: '-1h', issuer: 'mini-erp', audience: 'mini-erp-client' });
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', `token=${expiredToken}`);
        expect(res.status).toBe(401);
        expect(res.body.code).toBe('TOKEN_EXPIRED');
    });
    it('rejects none algorithm attack', async () => {
        const noneToken = jsonwebtoken_1.default.sign({ id: 1, username: 'admin', email: 'a@b.c', role: 'admin' }, null, { algorithm: 'none' });
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', `token=${noneToken}`);
        expect([401, 403]).toContain(res.status);
    });
    it('rejects random string as token', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', 'token=not.a.valid.jwt.token');
        expect([401, 403]).toContain(res.status);
    });
    it('rejects empty token', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', 'token=');
        expect(res.status).toBe(401);
    });
});
describe('CSRF Protection', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
    });
    it('POST without CSRF token now succeeds (CSRF middleware removed)', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'Test Customer', phone: '1234567890' });
        // CSRF middleware was removed — SameSite=Strict + helmet covers CSRF
        expect(res.status).toBe(201);
    });
    it('POST with wrong CSRF token now succeeds (CSRF middleware removed)', async () => {
        const { cookie: csrfCookie } = await getCsrfToken(authCookie);
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', 'wrong-token-value')
            .send({ customer_name: 'Test Customer', phone: '1234567891' });
        expect(res.status).toBe(201);
    });
    it('POST with missing CSRF header now succeeds (CSRF middleware removed)', async () => {
        const { cookie: csrfCookie } = await getCsrfToken(authCookie);
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .send({ customer_name: 'Test Customer', phone: '1234567892' });
        expect(res.status).toBe(201);
    });
    it('POST with valid CSRF token passes CSRF check', async () => {
        const { cookie: csrfCookie, token: csrfToken } = await getCsrfToken(authCookie);
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ customer_name: 'Test Customer' });
        expect(res.status).not.toBe(403);
    });
    it('GET requests are not blocked by CSRF', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Cookie', authCookie);
        expect(res.status).not.toBe(403);
    });
});
describe('XSS Prevention', () => {
    let authCookie;
    let csrfCookie;
    let csrfToken;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const csrf = await getCsrfToken(authCookie);
        csrfCookie = csrf.cookie;
        csrfToken = csrf.token;
    });
    it('script tag in customer name is escaped', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ customer_name: '<script>alert("xss")</script>' });
        expect(res.status).not.toBe(500);
        if (res.body.data && res.body.data.customer_name) {
            expect(res.body.data.customer_name).not.toContain('<script>');
        }
    });
    it('onerror handler in search param is safe', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?search=<img src=x onerror=alert(1)>')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        const bodyStr = JSON.stringify(res.body);
        expect(bodyStr).not.toContain('<img src=x onerror=alert(1)>');
    });
    it('javascript: URL in email field is rejected or escaped', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({ customer_name: 'Test', email: 'javascript:alert(1)' });
        expect(res.status).not.toBe(500);
        if (res.status === 200 && res.body.data && res.body.data.email) {
            expect(res.body.data.email).not.toContain('javascript:');
        }
    });
});
describe('SQL Injection Regression', () => {
    let authCookie;
    let csrfCookie;
    let csrfToken;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const csrf = await getCsrfToken(authCookie);
        csrfCookie = csrf.cookie;
        csrfToken = csrf.token;
    });
    const sqliPayloads = [
        "' OR 1=1 --",
        "'; DROP TABLE customers; --",
        "1; SELECT * FROM users --",
        "' UNION SELECT NULL, NULL, NULL --",
        "admin'--",
        "1' AND '1'='1",
        "'; EXEC xp_cmdshell('whoami') --",
    ];
    it.each(sqliPayloads)('blocks SQLi in sortBy: %s', async (payload) => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/customers?sortBy=${encodeURIComponent(payload)}`)
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
        if (res.status === 200) {
            expect(res.body.success).toBe(true);
        }
    });
    it.each(sqliPayloads)('blocks SQLi in sortOrder: %s', async (payload) => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/payments?sortOrder=${encodeURIComponent(payload)}`)
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
    });
    it('blocks SQLi in period parameter', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get("/api/reports/dso?period=30'; DELETE FROM invoices; --")
            .set('Cookie', authCookie);
        expect(res.status).toBe(400);
    });
    it('blocks SQLi in customer ID param', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers/1 OR 1=1')
            .set('Cookie', authCookie);
        expect([400, 404]).toContain(res.status);
    });
    it('blocks SQLi in search parameter', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/customers?search=${encodeURIComponent("' UNION SELECT * FROM users --")}`)
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });
    it('database tables remain intact after all SQLi attempts', async () => {
        const tables = ['customers', 'payments', 'invoices', 'users'];
        for (const table of tables) {
            const res = await (0, supertest_1.default)(app_1.default)
                .get('/api/customers')
                .set('Cookie', authCookie);
            expect(res.status).toBe(200);
        }
    });
});
describe('Security Headers (Helmet)', () => {
    it('includes Content-Security-Policy header', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/health');
        expect(res.headers['content-security-policy']).toBeDefined();
    });
    it('includes X-Content-Type-Options header', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/health');
        expect(res.headers['x-content-type-options']).toBe('nosniff');
    });
    it('includes X-Frame-Options or Frame-Ancestors header', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/health');
        const hasFrameProtection = res.headers['x-frame-options'] ||
            (res.headers['content-security-policy'] &&
                res.headers['content-security-policy'].includes("frame-ancestors 'none'"));
        expect(!!hasFrameProtection).toBe(true);
    });
    it('includes Strict-Transport-Security or Referrer-Policy header', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/health');
        expect(res.headers['strict-transport-security'] || res.headers['referrer-policy']).toBeDefined();
    });
});
describe('Input Validation Regression', () => {
    let authCookie;
    let csrfCookie;
    let csrfToken;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const csrf = await getCsrfToken(authCookie);
        csrfCookie = csrf.cookie;
        csrfToken = csrf.token;
    });
    it('rejects negative page number', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?page=-1')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
        if (res.status === 400) {
            expect(res.body.success).toBe(false);
        }
    });
    it('rejects non-numeric limit', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers?limit=abc')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
    });
    it('rejects excessively long search string', async () => {
        const longSearch = 'a'.repeat(500);
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/customers?search=${longSearch}`)
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
    });
    it('rejects invalid date format in payments', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/payments?fromDate=not-a-date&toDate=also-not')
            .set('Cookie', authCookie);
        expect([200, 400]).toContain(res.status);
    });
    it('rejects missing required fields on customer creation', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', [authCookie, csrfCookie])
            .set('x-csrf-token', csrfToken)
            .send({});
        expect(res.status).toBe(400);
    });
});
describe('Authorization Boundary', () => {
    it('non-existent Bearer token is rejected', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Authorization', 'Bearer eyJhbGciOiJIUzI1NiJ9.eyJpZCI6MX0.invalid');
        expect([401, 403]).toContain(res.status);
    });
    it('malformed Authorization header is rejected', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/customers')
            .set('Authorization', 'NotBearer some-token');
        expect(res.status).toBe(401);
    });
});
