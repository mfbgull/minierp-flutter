"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const BUSINESS_TABLES = [
    'users', 'roles', 'permissions', 'role_permissions',
    'customers', 'suppliers', 'items', 'warehouses',
    'invoices', 'invoice_items', 'payments', 'payment_allocations',
    'purchases', 'purchase_order_items', 'purchase_returns',
    'quotations', 'quotation_items', 'sales_orders', 'sales_order_items',
    'productions', 'boms', 'bom_items', 'expenses',
    'stock_movements', 'stock_balances', 'stock_batches',
    'journal_entries', 'journal_lines', 'accounting_periods',
    'customer_ledger', 'supplier_ledger', 'activity_log', 'settings',
];
function fingerprint(db) {
    const out = {};
    for (const t of BUSINESS_TABLES) {
        const exists = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name=?`).get(t);
        if (!exists)
            continue;
        const rows = db.prepare(`SELECT * FROM "${t}" ORDER BY rowid`).all();
        out[t] = JSON.stringify(rows);
    }
    return out;
}
describe('boot idempotency (task 3.9)', () => {
    it('second boot leaves every business table byte-identical', () => {
        jest.resetModules();
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        let db = require('../config/database').default;
        const before = fingerprint(db);
        jest.resetModules();
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        db = require('../config/database').default;
        const after = fingerprint(db);
        const diffs = Object.keys(before).filter(t => before[t] !== after[t]);
        expect(diffs).toEqual([]);
    });
});
