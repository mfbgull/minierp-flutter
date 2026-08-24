"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
jest.setTimeout(30000);
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
describe('POST /api/inventory/stock-transfers (INV-02)', () => {
    let authCookie;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
    });
    it('transfers stock atomically with mirrored destination layers', async () => {
        // Seed item + warehouses
        if (!database_1.default.prepare('SELECT id FROM items WHERE id = 1').get()) {
            database_1.default.prepare(`INSERT INTO items (id,item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
        VALUES (1,'IT-T','TransferTest','Nos',5,1,1)`).run();
        }
        for (const wh of [1, 2]) {
            if (!database_1.default.prepare('SELECT id FROM warehouses WHERE id = ?').get(wh)) {
                database_1.default.prepare(`INSERT INTO warehouses (id,warehouse_code,warehouse_name,is_active)
          VALUES (?,?,'Warehouse',1)`).run(wh, `WH-T${wh}`);
            }
        }
        // Seed source batch: 10 @ 5 in WH 1
        database_1.default.prepare(`
      INSERT INTO stock_batches (batch_no, item_id, warehouse_id, source_type, source_id,
        quantity_original, quantity_remaining, unit_cost, received_date)
      VALUES ('B-TRF-SRC', 1, 1, 'PURCHASE', 9001, 10, 10, 5, '2026-01-01')
    `).run();
        if (!database_1.default.prepare('SELECT 1 FROM stock_balances WHERE item_id=1 AND warehouse_id=1').get()) {
            database_1.default.prepare('INSERT INTO stock_balances (item_id,warehouse_id,quantity) VALUES (1,1,10)').run();
        }
        else {
            database_1.default.prepare('UPDATE stock_balances SET quantity = 10 WHERE item_id=1 AND warehouse_id=1').run();
        }
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/stock-transfers')
            .set('Cookie', authCookie)
            .send({ item_id: 1, from_warehouse_id: 1, to_warehouse_id: 2, quantity: 4 });
        expect(res.status).toBe(201);
        // Source: balance 6, batch consumed
        const srcBal = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=1').get();
        expect(srcBal.quantity).toBe(6);
        const srcBatch = database_1.default.prepare(`SELECT quantity_remaining FROM stock_batches WHERE batch_no='B-TRF-SRC'`).get();
        expect(srcBatch.quantity_remaining).toBe(6);
        // Destination: balance 4, mirrored TRANSFER layer at same cost
        const dstBal = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=2').get();
        expect(dstBal.quantity).toBe(4);
        const mirror = database_1.default.prepare(`SELECT source_type, unit_cost, quantity_remaining FROM stock_batches WHERE warehouse_id=2 AND item_id=1 ORDER BY id DESC LIMIT 1`).get();
        expect(mirror.source_type).toBe('TRANSFER');
        expect(mirror.unit_cost).toBe(5);
        expect(mirror.quantity_remaining).toBe(4);
        // Both movements exist; the IN leg references the OUT leg's number
        const movements = database_1.default.prepare(`SELECT movement_no, warehouse_id, quantity, reference_docno FROM stock_movements WHERE movement_type='TRANSFER' ORDER BY id DESC LIMIT 2`).all();
        expect(movements.length).toBe(2);
        const inLeg = movements.find((m) => m.warehouse_id === 2);
        const outLeg = movements.find((m) => m.warehouse_id === 1);
        expect(outLeg.quantity).toBe(-4);
        expect(inLeg.quantity).toBe(4);
        expect(inLeg.reference_docno).toBe(outLeg.movement_no);
        // Coverage invariant: batches == balances on both warehouses
        for (const wh of [1, 2]) {
            const bal = database_1.default.prepare('SELECT quantity FROM stock_balances WHERE item_id=1 AND warehouse_id=?').get(wh).quantity;
            const cov = database_1.default.prepare('SELECT COALESCE(SUM(quantity_remaining),0) s FROM stock_batches WHERE item_id=1 AND warehouse_id=?').get(wh).s;
            expect(cov).toBeCloseTo(bal, 3);
        }
    });
    it('rejects a transfer exceeding availability without partial writes', async () => {
        const before = database_1.default.prepare(`SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type='TRANSFER'`).get();
        const beforeN = before?.n ?? 0;
        const res = await (0, supertest_1.default)(app_1.default)
            .post('/api/inventory/stock-transfers')
            .set('Cookie', authCookie)
            .send({ item_id: 1, from_warehouse_id: 1, to_warehouse_id: 2, quantity: 9999 });
        expect(res.status).toBe(400);
        const after = database_1.default.prepare(`SELECT COUNT(*) AS n FROM stock_movements WHERE movement_type='TRANSFER'`).get();
        expect(after.n).toBe(beforeN); // nothing recorded
    });
});
//# sourceMappingURL=stockTransfer.test.js.map