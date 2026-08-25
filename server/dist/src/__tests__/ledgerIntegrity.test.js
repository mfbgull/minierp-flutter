"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Ledger integrity + reconciliation tests (gl-posting-completeness §4-§8).
 *
 * 4.4  Append-only ledgers: reversal row pairs, no reachable DELETE,
 *      counterparty-scoped reference operations.
 * 5.5  Backdated insert lands in (transaction_date, id) position; stored
 *      balance column equals the statement footing.
 * 6.3  current_balance always equals the ledger-derived figure.
 * 7.5  Inflated client total → 400 with nothing written; legit totals pass;
 *      discount/tax reflected in stored amounts.
 * 8.2  Reconciliation: clean fixture reconciles within 0.01; drift shows.
 */
const supertest_1 = __importDefault(require("supertest"));
const app_1 = __importDefault(require("../app"));
const database_1 = __importDefault(require("../config/database"));
const ledgerUtils_1 = __importDefault(require("../utils/ledgerUtils"));
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
function ledgerRows(table, where, ...params) {
    return database_1.default.prepare(`SELECT * FROM ${table} WHERE ${where}`).all(...params);
}
describe('ledger integrity and reconciliation', () => {
    let authCookie;
    let itemId;
    let customerId;
    let customerId2;
    let warehouseId;
    let counter = Date.now() % 100000;
    beforeAll(async () => {
        authCookie = await getAuthCookie();
        expect(authCookie).not.toBe('');
        warehouseId = database_1.default.prepare(`SELECT id FROM warehouses ORDER BY id LIMIT 1`).get().id;
        const item = await (0, supertest_1.default)(app_1.default).post('/api/inventory/items')
            .set('Cookie', authCookie)
            .send({ item_code: `LGR-${Date.now()}`, item_name: 'Ledger Integrity Item' });
        expect(item.status).toBe(201);
        itemId = item.body.id;
        const supplierRes = await (0, supertest_1.default)(app_1.default).post('/api/purchases')
            .set('Cookie', authCookie)
            .send({
            item_id: itemId,
            warehouse_id: warehouseId,
            quantity: 500,
            unit_cost: 10,
            purchase_date: '2026-05-01',
            supplier_name: 'Ledger Integrity Supplier',
        });
        expect(supplierRes.status).toBe(201);
        for (const name of ['Ledger Customer One', 'Ledger Customer Two']) {
            const c = await (0, supertest_1.default)(app_1.default).post('/api/customers')
                .set('Cookie', authCookie)
                .send({ customer_name: name, phone: `555-${counter}` });
            expect(c.status).toBe(201);
            if (!customerId) {
                customerId = c.body.data?.id ?? c.body.id;
            }
            else {
                customerId2 = c.body.data?.id ?? c.body.id;
            }
        }
    });
    async function createInvoice(customerIdArg, totalAmount, date) {
        counter += 1;
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-LGR-${counter}`,
            customer_id: customerIdArg,
            invoice_date: date,
            due_date: date,
            status: 'Unpaid',
            items: [{ item_id: itemId, quantity: totalAmount / 100, unit_price: 100, warehouse_id: warehouseId }],
        });
        expect(res.status).toBe(201);
        return { invoiceId: res.body.id, invoiceNo: res.body.invoice_no };
    }
    // ------------------------------------------------------------------
    // 4.4 Append-only ledger
    // ------------------------------------------------------------------
    it('invoice delete leaves voided original plus REVERSAL rows — no DELETE', async () => {
        const { invoiceId, invoiceNo } = await createInvoice(customerId, 200, '2026-07-01');
        const beforeCount = ledgerRows('customer_ledger', 'customer_id = ? AND reference_no = ? AND transaction_type = ?', customerId, invoiceNo, 'INVOICE').length;
        expect(beforeCount).toBe(1);
        const del = await (0, supertest_1.default)(app_1.default).delete(`/api/invoices/${invoiceId}`)
            .set('Cookie', authCookie);
        expect(del.status).toBe(200);
        // Original row survives, voided; a REVERSAL pair exists.
        const original = database_1.default.prepare(`SELECT voided FROM customer_ledger WHERE customer_id = ? AND reference_no = ? AND transaction_type = 'INVOICE'`).get(customerId, invoiceNo);
        expect(Number(original.voided)).toBe(1);
        const reversal = database_1.default.prepare(`SELECT id, reversed_by FROM customer_ledger WHERE customer_id = ? AND transaction_type LIKE 'REVERSAL:%' AND reference_no = ?`).get(customerId, invoiceNo);
        expect(reversal).toBeDefined();
    });
    it('a colliding reference across customers affects only the owning party', async () => {
        // Seed two ledger rows with the same reference_no but different customers.
        const collisionRef = `COLLIDE-${counter}`;
        const seed = (custId) => {
            const r = database_1.default.prepare(`
        INSERT INTO customer_ledger (customer_id, transaction_date, transaction_type, reference_no, debit, credit, balance)
        VALUES (?, ?, 'INVOICE', ?, 50, 0, 50)
      `).run(custId, '2026-07-02', collisionRef);
            return r.lastInsertRowid;
        };
        const ownRowId = seed(customerId);
        const otherRowId = seed(customerId2);
        // Reversal scoped by counterparty touches only the owner's row.
        const InvoiceModel = (await Promise.resolve().then(() => __importStar(require('../models/Invoice')))).default;
        InvoiceModel.deleteLedgerEntryByReference(database_1.default, collisionRef, customerId);
        const ownVoided = database_1.default.prepare('SELECT voided FROM customer_ledger WHERE id = ?').get(ownRowId).voided;
        const otherVoided = database_1.default.prepare('SELECT voided FROM customer_ledger WHERE id = ?').get(otherRowId).voided;
        expect(Number(ownVoided)).toBe(1);
        expect(Number(otherVoided)).toBe(0);
        // Cleanup the untouched decoy so later tests see a clean chain.
        database_1.default.prepare('DELETE FROM customer_ledger WHERE id = ?').run(otherRowId);
        database_1.default.prepare('DELETE FROM customer_ledger WHERE reversed_by = ?').run(ownRowId);
    });
    // ------------------------------------------------------------------
    // 5.5 Ledger chain truth
    // ------------------------------------------------------------------
    it('backdated insert lands in date position and footing equals stored balances', async () => {
        // Chain: invoice on 2026-06-10 (300), payment on 2026-06-20 (100).
        const invA = await createInvoice(customerId2, 300, '2026-06-10');
        expect(invA.invoiceId).toBeGreaterThan(0);
        const pay = await (0, supertest_1.default)(app_1.default).post('/api/payments')
            .set('Cookie', authCookie)
            .send({
            customer_id: customerId2,
            payment_date: '2026-06-20',
            amount: 100,
            payment_method: 'Cash',
            invoice_allocations: [{ invoice_id: invA.invoiceId, amount: 100 }],
        });
        expect([200, 201]).toContain(pay.status);
        // Backdated invoice between them (150 on 2026-06-15).
        const invB = await createInvoice(customerId2, 150, '2026-06-15');
        const rows = ledgerRows('customer_ledger', 'customer_id = ? AND voided = 0 ORDER BY transaction_date ASC, id ASC', customerId2);
        const dates = rows.map(r => r.transaction_date);
        expect(dates.indexOf('2026-06-15')).toBeGreaterThan(-1);
        expect(dates.indexOf('2026-06-20')).toBeGreaterThan(dates.indexOf('2026-06-15'));
        // Statement footing: running sum over non-voided rows in date order
        // must equal every stored balance value, including the backdated one.
        let running = 0;
        for (const row of rows) {
            running += Number(row.debit) - Number(row.credit);
            expect(Number(row.balance)).toBeCloseTo(running, 2);
        }
        // The final stored balance is also what recalc derives.
        const derived = ledgerUtils_1.default.recalcCustomerBalanceFromLedger(customerId2);
        expect(derived).toBeCloseTo(running, 2);
    });
    // ------------------------------------------------------------------
    // 6.3 Single balance writer
    // ------------------------------------------------------------------
    it('current_balance equals the ledger-derived figure after mutations', async () => {
        const preExistingBalance = ledgerUtils_1.default.recalcCustomerBalanceFromLedger(customerId);
        const inv = await createInvoice(customerId, 400, '2026-05-01');
        const pay = await (0, supertest_1.default)(app_1.default).post('/api/payments')
            .set('Cookie', authCookie)
            .send({
            customer_id: customerId,
            payment_date: '2026-05-05',
            amount: 250,
            payment_method: 'Cash',
            invoice_allocations: [{ invoice_id: inv.invoiceId, amount: 250 }],
        });
        expect([200, 201]).toContain(pay.status);
        const stored = database_1.default.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId).current_balance;
        // Contract (6.3): whatever mutations happened before, current_balance
        // must equal the ledger-derived figure exactly.
        const derived = ledgerUtils_1.default.recalcCustomerBalanceFromLedger(customerId);
        expect(Number(stored)).toBeCloseTo(derived, 2);
        // Sanity: this test's own two rows net to 400 − 250 = 150 against the
        // pre-existing chain position captured above.
        expect(derived).toBeCloseTo(preExistingBalance + 150, 2);
    });
    // ------------------------------------------------------------------
    // 7.5 Server-authoritative totals
    // ------------------------------------------------------------------
    it('inflated client total is rejected with nothing written', async () => {
        const invoicesBefore = database_1.default.prepare('SELECT COUNT(*) AS c FROM invoices').get().c;
        const movementsBefore = database_1.default.prepare('SELECT COUNT(*) AS c FROM stock_movements').get().c;
        const linesBefore = database_1.default.prepare('SELECT COUNT(*) AS c FROM journal_lines').get().c;
        counter += 1;
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-LGR-BAD-${counter}`,
            customer_id: customerId,
            invoice_date: '2026-07-10',
            due_date: '2026-07-10',
            total_amount: 100000, // line items sum to 100
            items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toContain('total_amount disagrees with line items');
        expect(database_1.default.prepare('SELECT COUNT(*) AS c FROM invoices').get().c).toBe(invoicesBefore);
        expect(database_1.default.prepare('SELECT COUNT(*) AS c FROM stock_movements').get().c).toBe(movementsBefore);
        expect(database_1.default.prepare('SELECT COUNT(*) AS c FROM journal_lines').get().c).toBe(linesBefore);
    });
    it('discount and tax are reflected in the stored line amount and header', async () => {
        counter += 1;
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-LGR-DISC-${counter}`,
            customer_id: customerId,
            invoice_date: '2026-07-12',
            due_date: '2026-07-12',
            // Flutter-shaped legitimate total: qty×price=200, 10% discount → 180, 5% tax → 189
            total_amount: 189,
            items: [{
                    item_id: itemId,
                    quantity: 2,
                    unit_price: 100,
                    discount_type: 'percentage',
                    discount_value: 10,
                    tax_rate: 5,
                    warehouse_id: warehouseId,
                }],
        });
        expect(res.status).toBe(201);
        const line = database_1.default.prepare('SELECT amount FROM invoice_items WHERE invoice_id = ?').get(res.body.id);
        expect(Number(line.amount)).toBeCloseTo(189, 2);
        const header = database_1.default.prepare('SELECT total_amount FROM invoices WHERE id = ?').get(res.body.id);
        expect(Number(header.total_amount)).toBeCloseTo(189, 2);
    });
    it('invoice-scope header discount nets into the accepted/stored total', async () => {
        counter += 1;
        // Form contract: gross 200, invoice-scope flat discount 50 → grand
        // total 150. Before computeInvoiceGrandTotal this was rejected as a
        // mismatch because the header discount was ignored.
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-LGR-INVDC-${counter}`,
            customer_id: customerId,
            invoice_date: '2026-07-13',
            due_date: '2026-07-13',
            status: 'Unpaid',
            discount_scope: 'invoice',
            discount_type: 'flat',
            discount_value: 50,
            total_amount: 150,
            items: [{
                    item_id: itemId,
                    quantity: 2,
                    unit_price: 100,
                    warehouse_id: warehouseId,
                }],
        });
        expect(res.status).toBe(201);
        const header = database_1.default.prepare('SELECT total_amount FROM invoices WHERE id = ?').get(res.body.id);
        expect(Number(header.total_amount)).toBeCloseTo(150, 2);
    });
    it('loose amount-driven line bills the entered amount, not qty × price', async () => {
        counter += 1;
        // Flip-model loose line (§5.2): the user billed a flat 60 for
        // 1.75 units — qty × price would disagree by design.
        const res = await (0, supertest_1.default)(app_1.default).post('/api/invoices')
            .set('Cookie', authCookie)
            .send({
            invoice_no: `INV-LGR-LOOSE-${counter}`,
            customer_id: customerId,
            invoice_date: '2026-07-14',
            due_date: '2026-07-14',
            status: 'Unpaid',
            total_amount: 60,
            items: [{
                    item_id: itemId,
                    quantity: 1.75,
                    unit_price: 33.333,
                    amount: 60,
                    warehouse_id: warehouseId,
                }],
        });
        expect(res.status).toBe(201);
        const line = database_1.default.prepare('SELECT amount FROM invoice_items WHERE invoice_id = ?').get(res.body.id);
        expect(Number(line.amount)).toBeCloseTo(60, 2);
    });
    // ------------------------------------------------------------------
    // 8.2 Reconciliation report
    // ------------------------------------------------------------------
    it('reconciliation endpoint returns GL vs operational pairs', async () => {
        const res = await (0, supertest_1.default)(app_1.default).get('/api/accounting/reconciliation')
            .set('Cookie', authCookie);
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        const pairings = res.body.data.pairings;
        expect(pairings.length).toBeGreaterThanOrEqual(4);
        const inventory = pairings.find(p => p.account_code === '1200');
        expect(inventory).toBeDefined();
        expect(typeof inventory.gl_balance).toBe('number');
        expect(typeof inventory.operational_balance).toBe('number');
        // Clean seeded fixture: purchases post to the GL now, sales consume
        // FIFO cost — inventory delta must reconcile within tolerance.
        expect(Math.abs(inventory.delta)).toBeLessThanOrEqual(0.01);
    });
});
