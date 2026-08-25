"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
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
    it('GET /api/inventory/stock-movements - returns paged stock movements with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/stock-movements')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        // Flat envelope matching customers/suppliers (data = list, pagination
        // as a sibling) — what the client's `getPaged` helper parses.
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/inventory/stock-movements/:id - returns the joined movement', async () => {
        // The fresh test DB has no items/warehouses/movements — create the
        // chain first.
        const item = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', `token=${token}`)
            .send({ item_code: 'IT-DETAIL', item_name: 'Detail Test Item' });
        expect(item.status).toBe(201);
        const warehouse = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/warehouses')
            .set('Cookie', `token=${token}`)
            .send({ warehouse_code: 'WH-DETAIL', warehouse_name: 'Detail Test WH' });
        expect(warehouse.status).toBe(201);
        const created = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/stock-movements')
            .set('Cookie', `token=${token}`)
            .send({
            item_id: item.body.id,
            warehouse_id: warehouse.body.id,
            quantity: 5,
            movement_type: 'ADJUSTMENT',
            remarks: 'detail test',
        });
        expect(created.status).toBe(201);
        const res = await (0, supertest_1.default)(app_1.default)
            .get(`/api/inventory/stock-movements/${created.body.id}`)
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.id).toBe(created.body.id);
        expect(res.body.movement_no).toBe(created.body.movement_no);
        expect(res.body.item_code).toBe('IT-DETAIL');
        expect(res.body.warehouse_code).toBe('WH-DETAIL');
    });
    it('GET /api/inventory/stock-movements/999999 - returns 404', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/inventory/stock-movements/999999')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(404);
    });
    it('GET /api/invoices - returns paged invoices with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/invoices')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        // Flat envelope matching customers/suppliers (data = list, pagination
        // as a sibling) — what the client's `getPaged` helper parses.
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/invoices/returns - returns paged invoice returns with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/invoices/returns')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/sales-orders - returns paged sales orders with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/sales-orders')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/quotations - returns paged quotations with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/quotations')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/purchase-orders - returns paged purchase orders with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/purchase-orders')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/purchases - returns paged purchases with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/purchases')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/purchase-returns - returns paged return headers with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/purchase-returns')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/purchase-returns - rejects unauthenticated requests', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/purchase-returns');
        expect(res.status).toBe(401);
    });
    it('GET /api/purchase-returns/:id - returns 404 for non-existent return', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/purchase-returns/999999')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(404);
    });
    it('GET /api/productions - returns paged productions with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/productions')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/boms - returns paged BOMs with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/boms')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/expenses - returns paged expenses with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/expenses')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
    });
    it('GET /api/forecasts/demand - returns paged demand forecasts with auth', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get('/api/forecasts/demand')
            .set('Cookie', `token=${token}`);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.pagination?.currentPage).toBe(1);
        expect(res.body.pagination?.totalPages).toBeGreaterThanOrEqual(0);
        expect(res.body.pagination?.totalItems).toBeGreaterThanOrEqual(0);
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
    // task 8.3 — batch: every new sortable endpoint must reject SQL injection
    // in sortBy/sortOrder; the whitelist falls back to the default column
    // and the table is never dropped.
    const batchSortEndpoints = [
        '/api/inventory/items',
        '/api/invoices',
        '/api/invoices/returns',
        '/api/sales-orders',
        '/api/quotations',
        '/api/purchase-orders',
        '/api/purchases',
        '/api/productions',
        '/api/boms',
        '/api/forecasts/demand',
    ];
    for (const ep of batchSortEndpoints) {
        it(`SQL injection via sortBy blocked on ${ep}`, async () => {
            const res = await (0, supertest_1.default)(app_1.default)
                .get(`${ep}?sortBy=id;DROP TABLE x;--`)
                .set('Cookie', authCookie);
            expect([200, 400]).toContain(res.status);
            // Verify data endpoint is still alive (no drop).
            const ok = await (0, supertest_1.default)(app_1.default).get(ep).set('Cookie', authCookie);
            expect(ok.status).toBe(200);
        });
        it(`SQL injection via sortOrder blocked on ${ep}`, async () => {
            const res = await (0, supertest_1.default)(app_1.default)
                .get(`${ep}?sortOrder=DESC;DROP TABLE x;--`)
                .set('Cookie', authCookie);
            expect([200, 400]).toContain(res.status);
            const ok = await (0, supertest_1.default)(app_1.default).get(ep).set('Cookie', authCookie);
            expect(ok.status).toBe(200);
        });
    }
    it('SQL injection via period parameter is blocked', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .get("/api/reports/dso?period=30';DELETE FROM invoices;--")
            .set('Cookie', authCookie);
        expect(res.status).toBe(400);
    });
});
describe('Purchase Returns Endpoints (full flow)', () => {
    let authCookie;
    let warehouseId;
    let itemId;
    let supplierId;
    let purchaseId;
    let purchaseNo;
    let returnId;
    let returnNo;
    // Seed the master data through the public API so the whole chain (item
    // → warehouse → supplier → purchase → return) runs against the real
    // controllers, prepared statements and permission middleware.
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const warehouse = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/warehouses')
            .set('Cookie', authCookie)
            .send({ warehouse_code: 'WH-RETURN', warehouse_name: 'Return Test WH' });
        expect(warehouse.status).toBe(201);
        warehouseId = warehouse.body.id;
        const item = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: 'RET-ITM', item_name: 'Return Test Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        const supplier = await (0, supertest_1.default)(app_1.default)
            .post('/api/suppliers')
            .set('Cookie', authCookie)
            .send({ supplier_code: 'RET-SUP', supplier_name: 'Return Test Supplier' });
        expect(supplier.status).toBe(201);
        supplierId = supplier.body.data.id;
        const purchase = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 10,
            unit_cost: 10,
            purchase_date: '2026-08-01',
            // PRET-03 (task 4.3): returns resolve the supplier by FK — the
            // purchase must carry supplier_id (the Flutter form sends it too).
            supplier_id: supplierId,
            supplier_name: 'Return Test Supplier',
        });
        expect(purchase.status).toBe(201);
        purchaseId = purchase.body.id;
        purchaseNo = purchase.body.purchase_no;
    });
    it('creates a return via the picker shape and posts stock, credit note, ledger + GL', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchase-returns')
            .set('Cookie', authCookie)
            .send({
            return_date: '2026-08-05',
            source_type: 'PURCHASE',
            source_id: purchaseId,
            warehouse_id: warehouseId,
            reason: 'Damaged on delivery',
            // The Flutter entry form's line shape (source_item_id = purchases.id).
            items: [{ source_item_id: purchaseId, quantity: 4 }],
        });
        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('POSTED');
        expect(res.body.data.return_no).toMatch(/^PR-\d{4}-\d{4}$/);
        expect(res.body.data.credit_no).toMatch(/^CN-\d{4}-\d{4}$/);
        expect(res.body.data.source_no).toBe(purchaseNo);
        expect(res.body.data.total_qty).toBe(4);
        expect(res.body.data.total_amount).toBe(40);
        returnId = res.body.data.id;
        returnNo = res.body.data.return_no;
        // Header + line persisted.
        const header = database_1.default.prepare('SELECT * FROM purchase_returns WHERE id = ?').get(returnId);
        expect(header.status).toBe('POSTED');
        expect(header.source_id).toBe(purchaseId);
        expect(header.warehouse_id).toBe(warehouseId);
        const line = database_1.default.prepare('SELECT * FROM purchase_return_items WHERE purchase_return_id = ?').get(returnId);
        expect(line.item_id).toBe(itemId);
        expect(line.quantity).toBe(4);
        expect(line.amount).toBe(40);
        // Stock reduced 10 → 6 and the negative movement is back-linked.
        const balance = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(itemId, warehouseId);
        expect(balance.quantity).toBe(6);
        const movement = database_1.default.prepare(`
      SELECT * FROM stock_movements WHERE purchase_return_id = ? AND quantity < 0
    `).get(returnId);
        expect(movement.quantity).toBe(-4);
        expect(movement.reference_docno).toBe(returnNo);
        // Source returned_quantity tracked.
        const purchase = database_1.default.prepare('SELECT returned_quantity FROM purchases WHERE id = ?').get(purchaseId);
        expect(purchase.returned_quantity).toBe(4);
        // Credit note resolved the supplier by name + posted the ledger entry.
        const creditNote = database_1.default.prepare(`
      SELECT * FROM credit_notes WHERE source_id = ? AND source_type = 'PURCHASE_RETURN'
    `).get(returnId);
        expect(creditNote.supplier_id).toBe(supplierId);
        expect(creditNote.amount).toBe(40);
        expect(creditNote.status).toBe('POSTED');
        const ledger = database_1.default.prepare(`
      SELECT * FROM supplier_ledger WHERE transaction_type = 'CREDIT_NOTE' AND reference_no = ?
    `).get(creditNote.credit_no);
        expect(ledger.supplier_id).toBe(supplierId);
        expect(ledger.credit).toBe(40);
        expect(ledger.debit).toBe(0);
        // GL reversal (Dr AP / Cr Inventory) keyed to the return header.
        const journal = database_1.default.prepare(`
      SELECT * FROM journal_lines WHERE reference_type = 'PURCHASE_RETURN' AND reference_id = ?
    `).all(returnId);
        expect(journal).toHaveLength(2);
        expect(journal.every((j) => j.voided === 0)).toBe(true);
    });
    it('rejects a return above the remaining returnable quantity (cap)', async () => {
        // 4 of 10 already returned — only 6 remain.
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchase-returns')
            .set('Cookie', authCookie)
            .send({
            return_date: '2026-08-06',
            source_type: 'PURCHASE',
            source_id: purchaseId,
            warehouse_id: warehouseId,
            items: [{ source_item_id: purchaseId, quantity: 7 }],
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/exceeds remaining available/);
    });
    it('voids the return — restores stock, GL, credit note + ledger, header VOIDED', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/purchase-returns/${returnId}/void`)
            .set('Cookie', authCookie)
            .send({ reason: 'Wrong stock' });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.status).toBe('VOIDED');
        expect(res.body.data.voided_reason).toBe('Wrong stock');
        const header = database_1.default.prepare('SELECT status FROM purchase_returns WHERE id = ?').get(returnId);
        expect(header.status).toBe('VOIDED');
        // Stock back to 10; source returned_quantity reset.
        const balance = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(itemId, warehouseId);
        expect(balance.quantity).toBe(10);
        const purchase = database_1.default.prepare('SELECT returned_quantity FROM purchases WHERE id = ?').get(purchaseId);
        expect(purchase.returned_quantity).toBe(0);
        // Credit note voided + reversing ledger entry (debit restores balance).
        const creditNote = database_1.default.prepare(`
      SELECT * FROM credit_notes WHERE source_id = ? AND source_type = 'PURCHASE_RETURN'
    `).get(returnId);
        expect(creditNote.status).toBe('VOIDED');
        const reversal = database_1.default.prepare(`
      SELECT * FROM supplier_ledger WHERE transaction_type = 'CREDIT_NOTE_VOID'
    `).get();
        expect(reversal.debit).toBe(40);
        expect(reversal.reference_no).toBe(creditNote.credit_no);
        // GL lines voided; positive reversal movement back-linked.
        const journal = database_1.default.prepare(`
      SELECT * FROM journal_lines WHERE reference_type = 'PURCHASE_RETURN' AND reference_id = ?
    `).all(returnId);
        expect(journal.every((j) => j.voided === 1)).toBe(true);
        const reversalMovement = database_1.default.prepare(`
      SELECT * FROM stock_movements WHERE purchase_return_id = ? AND quantity > 0
    `).get(returnId);
        expect(reversalMovement.quantity).toBe(4);
    });
    it('rejects voiding an already-voided return', async () => {
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/purchase-returns/${returnId}/void`)
            .set('Cookie', authCookie)
            .send({ reason: 'again' });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/Only POSTED returns can be voided/);
    });
    it('gates create/void behind the purchase_returns permission (User = read only)', async () => {
        // A User-role account: the seed grants the User role every `read`
        // permission (incl. purchase_returns) but not create/void.
        const role = database_1.default.prepare("SELECT id FROM roles WHERE role_name = 'User'").get();
        database_1.default.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active, role_id)
      VALUES ('retuser', 'retuser@x.io', ?, 'Ret User', 'user', 1, ?)
    `).run(bcrypt_1.default.hashSync('user-pass-2026', 10), role.id);
        const login = await (0, supertest_1.default)(app_1.default)
            .post('/api/auth/login')
            .send({ username: 'retuser', password: 'user-pass-2026' });
        expect(login.status).toBe(200);
        const cookieHeader = login.headers['set-cookie'];
        const cookieList = Array.isArray(cookieHeader) ? cookieHeader : [cookieHeader];
        const userCookie = cookieList
            .find((c) => c.startsWith('token='))
            .split(';')[0];
        // read is granted…
        const list = await (0, supertest_1.default)(app_1.default).get('/api/purchase-returns').set('Cookie', userCookie);
        expect(list.status).toBe(200);
        // …but create and void are denied.
        const create = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchase-returns')
            .set('Cookie', userCookie)
            .send({
            return_date: '2026-08-07',
            source_type: 'PURCHASE',
            source_id: purchaseId,
            warehouse_id: warehouseId,
            items: [{ source_item_id: purchaseId, quantity: 1 }],
        });
        expect(create.status).toBe(403);
        const voidRes = await (0, supertest_1.default)(app_1.default)
            .post(`/api/purchase-returns/${returnId}/void`)
            .set('Cookie', userCookie)
            .send({ reason: 'x' });
        expect(voidRes.status).toBe(403);
    });
});
describe('Invoice Returns Endpoints (restock warehouse)', () => {
    let authCookie;
    let itemId;
    let saleWarehouseId;
    let restockWarehouseId;
    let customerId;
    // Self-contained seeds: its own item, two warehouses (the sale origin
    // + the chosen restock target) and a customer, all through the API.
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        const saleWh = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/warehouses')
            .set('Cookie', authCookie)
            .send({ warehouse_code: 'WH-INVSALE', warehouse_name: 'Invoice Sale WH' });
        expect(saleWh.status).toBe(201);
        saleWarehouseId = saleWh.body.id;
        const restockWh = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/warehouses')
            .set('Cookie', authCookie)
            .send({ warehouse_code: 'WH-INVREST', warehouse_name: 'Invoice Restock WH' });
        expect(restockWh.status).toBe(201);
        restockWarehouseId = restockWh.body.id;
        const item = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: 'INV-RET', item_name: 'Invoice Return Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        const customer = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', authCookie)
            .send({
            customer_name: 'Invoice Return Customer',
            phone: '555-0901',
        });
        expect(customer.status).toBe(201);
        customerId = customer.body.data.id;
        // Stock the sale warehouse so the invoice can dispatch from it.
        const purchase = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: saleWarehouseId,
            quantity: 10,
            unit_cost: 20,
            purchase_date: '2026-08-01',
            supplier_name: 'Invoice Return Supplier',
        });
        expect(purchase.status).toBe(201);
    });
    // The web form generates the invoice_no client-side (the server has no
    // fallback sequence) — each call needs a unique one.
    let invoiceNoCounter = 9000;
    async function createInvoice(quantity) {
        invoiceNoCounter += 1;
        const invoice = await (0, supertest_1.default)(app_1.default)
            .post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-2026-${invoiceNoCounter}`,
            customer_id: customerId,
            invoice_date: '2026-08-10',
            due_date: '2026-08-20',
            status: 'Unpaid',
            total_amount: quantity * 100,
            // Ship from the sale warehouse (same shape the invoice form sends).
            items: [{
                    item_id: itemId,
                    quantity,
                    unit_price: 100,
                    warehouse_id: saleWarehouseId,
                }],
        });
        expect(invoice.status).toBe(201);
        const invoiceId = invoice.body.id;
        const invoiceNo = invoice.body.invoice_no;
        const invoiceItem = database_1.default.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId);
        return { invoiceId, invoiceNo, invoiceItemId: invoiceItem.id };
    }
    it('restocks the returned items into the explicit warehouse', async () => {
        const { invoiceId, invoiceNo, invoiceItemId } = await createInvoice(3);
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/invoices/${invoiceId}/return`)
            .set('Cookie', authCookie)
            .send({
            reason: 'Damaged goods',
            disposition: 'credit',
            warehouse_id: restockWarehouseId,
            items: [{ invoice_item_id: invoiceItemId, return_quantity: 2 }],
        });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.totalItems).toBe(1);
        expect(res.body.data.returnAmount).toBe(200);
        // The restock ADJUSTMENT movement lands in the CHOSEN warehouse.
        const movement = database_1.default.prepare(`
      SELECT * FROM stock_movements
      WHERE item_id = ? AND reference_docno = ? AND movement_type = 'ADJUSTMENT'
        AND reference_doctype = 'RETURN'
    `).get(itemId, invoiceNo);
        expect(movement).toBeTruthy();
        expect(movement.warehouse_id).toBe(restockWarehouseId);
        expect(movement.quantity).toBe(2);
        // Stock: sale took 3 from the sale warehouse; the return adds 2 to
        // the restock warehouse (which started at 0).
        const saleBalance = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(itemId, saleWarehouseId);
        expect(saleBalance.quantity).toBe(7);
        const restockBalance = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(itemId, restockWarehouseId);
        expect(restockBalance.quantity).toBe(2);
    });
    it('falls back to the sale-origin warehouse when warehouse_id is omitted', async () => {
        const { invoiceId, invoiceNo, invoiceItemId } = await createInvoice(2);
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/invoices/${invoiceId}/return`)
            .set('Cookie', authCookie)
            .send({
            reason: 'Wrong colour',
            disposition: 'credit',
            items: [{ invoice_item_id: invoiceItemId, return_quantity: 1 }],
        });
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        const movement = database_1.default.prepare(`
      SELECT * FROM stock_movements
      WHERE item_id = ? AND reference_docno = ? AND movement_type = 'ADJUSTMENT'
        AND reference_doctype = 'RETURN'
    `).get(itemId, invoiceNo);
        expect(movement.warehouse_id).toBe(saleWarehouseId);
    });
    it('rejects an invalid warehouse_id', async () => {
        const { invoiceId, invoiceItemId } = await createInvoice(1);
        const res = await (0, supertest_1.default)(app_1.default)
            .post(`/api/invoices/${invoiceId}/return`)
            .set('Cookie', authCookie)
            .send({
            reason: 'x',
            disposition: 'credit',
            warehouse_id: -5,
            items: [{ invoice_item_id: invoiceItemId, return_quantity: 1 }],
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/valid warehouse_id/);
    });
    it('customer ledger returns one row per entry with resolved links after a multi-allocation payment + full return', async () => {
        // Self-contained seeds (the shared customer/item carry state from the
        // tests above): a fresh item, warehouse, stock and customer.
        const wh = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/warehouses')
            .set('Cookie', authCookie)
            .send({ warehouse_code: 'WH-LEDGER', warehouse_name: 'Ledger Test WH' });
        expect(wh.status).toBe(201);
        const whId = wh.body.id;
        const item = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: 'LEDGER-ITEM', item_name: 'Ledger Test Item' });
        expect(item.status).toBe(201);
        const itmId = item.body.id;
        const purchase = await (0, supertest_1.default)(app_1.default)
            .post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itmId,
            warehouse_id: whId,
            quantity: 20,
            unit_cost: 10,
            purchase_date: '2026-08-01',
            supplier_name: 'Ledger Test Supplier',
        });
        expect(purchase.status).toBe(201);
        const customer = await (0, supertest_1.default)(app_1.default)
            .post('/api/customers')
            .set('Cookie', authCookie)
            .send({ customer_name: 'Ledger Test Customer', phone: '555-0999' });
        expect(customer.status).toBe(201);
        const custId = customer.body.data.id;
        let counter = 5000;
        async function makeInvoice(quantity) {
            counter += 1;
            const invoice = await (0, supertest_1.default)(app_1.default)
                .post('/api/invoices')
                .set('Cookie', authCookie)
                .send({
                invoice_no: `INV-2026-${counter}`,
                customer_id: custId,
                invoice_date: '2026-08-10',
                due_date: '2026-08-20',
                status: 'Unpaid',
                total_amount: quantity * 100,
                items: [{ item_id: itmId, quantity, unit_price: 100, warehouse_id: whId }],
            });
            expect(invoice.status).toBe(201);
            const invoiceId = invoice.body.id;
            const invoiceNo = invoice.body.invoice_no;
            const invoiceItem = database_1.default.prepare('SELECT id FROM invoice_items WHERE invoice_id = ?').get(invoiceId);
            return { invoiceId, invoiceNo, invoiceItemId: invoiceItem.id };
        }
        const invA = await makeInvoice(6); // 600
        const invB = await makeInvoice(6); // 600
        // ONE payment allocated across BOTH invoices — the duplicate-row
        // trigger: the old query emitted the PAYMENT ledger row once per
        // allocation, doubling its credit in the running balance.
        const multiAlloc = await (0, supertest_1.default)(app_1.default)
            .post('/api/payments')
            .set('Cookie', authCookie)
            .send({
            customer_id: custId,
            payment_date: '2026-08-11',
            amount: 600,
            payment_method: 'Cash',
            invoice_allocations: [
                { invoice_id: invA.invoiceId, amount: 300 },
                { invoice_id: invB.invoiceId, amount: 300 },
            ],
        });
        expect(multiAlloc.status).toBe(201);
        const multiAllocPaymentNo = multiAlloc.body.data.payment_no;
        // Finish paying both invoices with single-allocation payments.
        for (const [invoiceId, amount] of [
            [invB.invoiceId, 300],
            [invA.invoiceId, 300],
        ]) {
            const pay = await (0, supertest_1.default)(app_1.default)
                .post('/api/payments')
                .set('Cookie', authCookie)
                .send({
                customer_id: custId,
                payment_date: '2026-08-12',
                amount,
                payment_method: 'Cash',
                invoice_allocations: [{ invoice_id: invoiceId, amount }],
            });
            expect(pay.status).toBe(201);
        }
        // Fully return invoice B with a cash refund (RETURN + REFUND pair).
        const ret = await (0, supertest_1.default)(app_1.default)
            .post(`/api/invoices/${invB.invoiceId}/return`)
            .set('Cookie', authCookie)
            .send({
            reason: 'regression test',
            disposition: 'refund',
            items: [{ invoice_item_id: invB.invoiceItemId, return_quantity: 6 }],
        });
        expect(ret.status).toBe(200);
        expect(ret.body.success).toBe(true);
        const ledgerRes = await (0, supertest_1.default)(app_1.default)
            .get(`/api/customers/${custId}/ledger?sortBy=id&sortOrder=ASC`)
            .set('Cookie', authCookie);
        expect(ledgerRes.status).toBe(200);
        const ledger = ledgerRes.body.data;
        // Every customer_ledger row appears exactly once (no allocation fan-out).
        expect(ledger.length).toBe(new Set(ledger.map((e) => e.id)).size);
        // The multi-allocation payment is a single row carrying BOTH invoices.
        const multi = ledger.filter((e) => e.transaction_type === 'PAYMENT' && e.reference_no === multiAllocPaymentNo);
        expect(multi).toHaveLength(1);
        const linkedNos = (multi[0].linked_invoice_no || '').split(',').map((s) => s.trim());
        expect(linkedNos).toEqual(expect.arrayContaining([invA.invoiceNo, invB.invoiceNo]));
        // The RETURN entry resolves to the returned invoice via its refund
        // payment (legacy query required amount = 0 and never matched).
        const retEntry = ledger.find((e) => e.transaction_type === 'RETURN');
        expect(retEntry).toBeTruthy();
        expect(retEntry.linked_invoice_no).toBe(invB.invoiceNo);
        const refundEntry = ledger.find((e) => e.transaction_type === 'REFUND');
        expect(refundEntry).toBeTruthy();
        expect(refundEntry.linked_invoice_no).toBe(invB.invoiceNo);
        // True AR: (600 + 600 + 600) − (600 + 300 + 300 + 600) = 0.
        const debit = ledger.reduce((s, e) => s + e.debit, 0);
        const credit = ledger.reduce((s, e) => s + e.credit, 0);
        expect(debit - credit).toBe(0);
    });
});
