"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CASH_ACCOUNTS = void 0;
exports.normalizeCashMethod = normalizeCashMethod;
exports.getOpeningBalances = getOpeningBalances;
exports.saveOpeningBalance = saveOpeningBalance;
exports.getCashAccountTotals = getCashAccountTotals;
exports.getCashAccountTransactions = getCashAccountTransactions;
/** The tracked cash accounts, in display order. `key` matches both the
 * reconciliation table's `account_key` column and the normalized
 * payment-method value. */
exports.CASH_ACCOUNTS = [
    { key: 'cash', name: 'Cash' },
    { key: 'bank', name: 'Bank' },
    { key: 'easypaisa', name: 'Easypaisa' },
    { key: 'jazzcash', name: 'JazzCash' },
    { key: 'upaisa', name: 'UPaisa' },
];
/**
 * Normalize a payment-method string to one of the tracked account keys,
 * or null when the method represents no actual money movement (e.g.
 * 'Credit' — an AR adjustment between invoices). Everything money-like
 * that isn't a named wallet falls through to 'bank'.
 */
function normalizeCashMethod(method) {
    if (!method)
        return null;
    const m = method.toLowerCase().trim();
    if (m === 'cash')
        return 'cash';
    if (m === 'easypaisa')
        return 'easypaisa';
    if (m === 'jazzcash' || m === 'jazz')
        return 'jazzcash';
    if (m === 'upaisa')
        return 'upaisa';
    if (m === 'credit')
        return null; // credit adjustment — not money in/out
    return 'bank'; // check, card, bank transfer, online payment, ...
}
/** Cumulative inflow/outflow per account for every row on or before
 * `uptoDate`. Eight small indexed GROUP BYs — fine for an ERP database. */
function collectFlows(db, uptoDate) {
    // Seed every account with its opening (business-start) balance — the
    // till didn't start at zero. `inflow` carries the seed so
    // balance = inflow − outflow includes it on every day.
    const opening = getOpeningBalances(db);
    const totals = new Map();
    for (const a of exports.CASH_ACCOUNTS) {
        totals.set(a.key, { inflow: opening.get(a.key) ?? 0, outflow: 0 });
    }
    const add = (method, inflow, outflow) => {
        const key = normalizeCashMethod(method);
        if (!key)
            return;
        const t = totals.get(key);
        t.inflow += inflow;
        t.outflow += outflow;
    };
    // Customer payments: positive amounts are money in; negative amounts
    // (refunds paid out to customers) are money out.
    const customerPayments = db.prepare(`
    SELECT payment_method,
           COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) as inflow,
           COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0) as outflow
    FROM payments
    WHERE customer_id IS NOT NULL AND payment_date <= ?
    GROUP BY payment_method
  `).all(uptoDate);
    for (const row of customerPayments) {
        add(row.payment_method, row.inflow, row.outflow);
    }
    // Supplier payments: money out.
    const supplierPayments = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM payments
    WHERE supplier_id IS NOT NULL AND amount > 0 AND payment_date <= ?
    GROUP BY payment_method
  `).all(uptoDate);
    for (const row of supplierPayments) {
        add(row.payment_method, 0, row.outflow);
    }
    // Expenses: money out once approved/submitted (draft/cancelled are not).
    const expenses = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM expenses
    WHERE status NOT IN ('Cancelled', 'Draft') AND expense_date <= ?
    GROUP BY payment_method
  `).all(uptoDate);
    for (const row of expenses) {
        add(row.payment_method, 0, row.outflow);
    }
    // Salary payments: money out (methods stored lowercase 'cash' | 'bank').
    const salaries = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM salary_payments
    WHERE status != 'cancelled' AND payment_date <= ?
    GROUP BY payment_method
  `).all(uptoDate);
    for (const row of salaries) {
        add(row.payment_method, 0, row.outflow);
    }
    return totals;
}
/** The opening (seed) balance per account — the cash a new business
 * starts with, set from the dashboard. Applied to every day's balance:
 * balance = opening + cumulative inflows − cumulative outflows. */
function getOpeningBalances(db) {
    const rows = db.prepare(`SELECT account_key, amount FROM opening_balances`).all();
    return new Map(rows.map((r) => [r.account_key, Number(r.amount) || 0]));
}
/** Upsert the opening balance for one account; returns the fresh map. */
function saveOpeningBalance(db, accountKey, amount) {
    db.prepare(`
    INSERT INTO opening_balances (account_key, amount, updated_at)
    VALUES (?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(account_key) DO UPDATE SET
      amount = excluded.amount,
      updated_at = CURRENT_TIMESTAMP
  `).run(accountKey, Math.round(amount * 100) / 100);
    return getOpeningBalances(db);
}
/** Per-account opening/day-flow/closing figures for `asOfDate`. */
function getCashAccountTotals(db, asOfDate) {
    const prevDate = db.prepare(`SELECT date(?, '-1 day') as d`).get(asOfDate);
    const upTo = collectFlows(db, asOfDate);
    const before = collectFlows(db, prevDate.d);
    return exports.CASH_ACCOUNTS.map((a) => {
        const now = upTo.get(a.key);
        const earlier = before.get(a.key);
        const closing = now.inflow - now.outflow;
        const opening = earlier.inflow - earlier.outflow;
        const inflow = now.inflow - earlier.inflow;
        const outflow = now.outflow - earlier.outflow;
        return {
            key: a.key,
            name: a.name,
            opening,
            inflow,
            outflow,
            net: inflow - outflow,
            closing,
        };
    });
}
/**
 * The individual money movements that make up one account's balance,
 * oldest first — the drill-down behind the dashboard cash-position card
 * so users can see *why* the balance is what it is.
 */
function getCashAccountTransactions(db, accountKey, uptoDate) {
    const out = [];
    const push = (row) => {
        if (normalizeCashMethod(row.method) !== accountKey)
            return;
        out.push({
            date: row.date,
            type: row.type,
            reference: row.reference,
            description: row.description,
            amount: row.amount,
        });
    };
    // Customer payments: positive = money in; negative amounts (refunds
    // paid back to the customer) = money out, labelled 'refund'.
    for (const r of db.prepare(`
    SELECT payment_date as date, payment_method as method, payment_no as reference,
           notes as description, amount
    FROM payments
    WHERE customer_id IS NOT NULL AND payment_date <= ?
  `).all(uptoDate)) {
        const amount = Number(r.amount) || 0;
        if (amount > 0) {
            push({ method: r.method, date: r.date, reference: r.reference, description: r.description, amount, type: 'payment_received' });
        }
        else if (amount < 0) {
            push({ method: r.method, date: r.date, reference: r.reference, description: r.description, amount, type: 'refund' });
        }
    }
    // Supplier payments (money out).
    for (const r of db.prepare(`
    SELECT payment_date as date, payment_method as method, payment_no as reference,
           notes as description, amount
    FROM payments
    WHERE supplier_id IS NOT NULL AND payment_date <= ?
  `).all(uptoDate)) {
        const amount = Number(r.amount) || 0;
        if (amount > 0) {
            push({ method: r.method, date: r.date, reference: r.reference, description: r.description, amount: -amount, type: 'supplier_payment' });
        }
    }
    // Expenses (money out once approved/submitted).
    for (const r of db.prepare(`
    SELECT expense_date as date, payment_method as method, expense_no as reference,
           description, amount
    FROM expenses
    WHERE status NOT IN ('Cancelled', 'Draft') AND expense_date <= ?
  `).all(uptoDate)) {
        const amount = Number(r.amount) || 0;
        push({ method: r.method, date: r.date, reference: r.reference, description: r.description, amount: -amount, type: 'expense' });
    }
    // Salary payments (money out).
    for (const r of db.prepare(`
    SELECT payment_date as date, payment_method as method, reference_no as reference,
           notes as description, amount
    FROM salary_payments
    WHERE status != 'cancelled' AND payment_date <= ?
  `).all(uptoDate)) {
        const amount = Number(r.amount) || 0;
        push({ method: r.method, date: r.date, reference: r.reference, description: r.description, amount: -amount, type: 'salary' });
    }
    out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
    return out;
}
//# sourceMappingURL=cashService.js.map