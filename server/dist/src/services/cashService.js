"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CASH_GL_CODES = exports.CASH_ACCOUNTS = void 0;
exports.normalizeCashMethod = normalizeCashMethod;
exports.isValidPaymentMethod = isValidPaymentMethod;
exports.collectFlows = collectFlows;
exports.getOpeningBalances = getOpeningBalances;
exports.saveOpeningBalance = saveOpeningBalance;
exports.syncOpeningBalancesToGl = syncOpeningBalancesToGl;
exports.getCashAccountTotals = getCashAccountTotals;
exports.getCashAccountTransactions = getCashAccountTransactions;
const accountingService_1 = __importDefault(require("./accountingService"));
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
/** GL account code backing each tracked account (1020/1030/1040 seeded by
 * runCashAccountsMigration; keep in sync with
 * AccountingService._cashOrBankAccountCode). */
exports.CASH_GL_CODES = {
    cash: '1000',
    bank: '1010',
    easypaisa: '1020',
    jazzcash: '1030',
    upaisa: '1040',
};
/**
 * Normalize a payment-method string to one of the tracked account keys,
 * or null when the method represents no actual money movement (e.g.
 * 'Credit' — an AR adjustment between invoices). Everything money-like
 * that isn't a named wallet falls through to 'bank'.
 */
const CASH_METHOD_KEYS = ['cash', 'easypaisa', 'jazzcash', 'upaisa', 'bank', 'unclassified'];
/**
 * CASH-02 (financial-audit-p0-remediation 1.2): explicit whitelist.
 * Named wallets map to themselves; bank-like instruments → 'bank';
 * credit adjustments → null (no money movement); anything unknown lands
 * in 'unclassified' instead of silently inflating the bank balance.
 */
function normalizeCashMethod(method) {
    if (!method)
        return 'unclassified';
    const m = method.toLowerCase().trim();
    if (!m)
        return 'unclassified';
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
    if (/bank|cheque|check|card|transfer|online|raast/.test(m))
        return 'bank';
    return 'unclassified';
}
/** Valid payment-method values for create/update validation (task 1.4). */
function isValidPaymentMethod(method) {
    if (!method)
        return false;
    const k = normalizeCashMethod(method);
    return k !== null && k !== 'unclassified';
}
/** Seed an 'unclassified' bucket alongside the named accounts. */
function ensureBucket(totals, key) {
    let t = totals.get(key);
    if (!t) {
        t = { inflow: 0, outflow: 0 };
        totals.set(key, t);
    }
    return t;
}
/** Cumulative inflow/outflow per account for every row on or before
 * `uptoDate`, bounded below by `floorDate` (task 8.3: default 90 days back —
 * the dashboard never needs older detail, and the date bound keeps every
 * scan on an index). Rows older than the floor fold into a single
 * pre-floor inflow/outflow pair so balances stay exact. */
function collectFlows(db, uptoDate, floorDate) {
    const floor = floorDate
        ?? db.prepare(`SELECT date(?, '-90 day') AS d`).get(uptoDate).d;
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
        const t = ensureBucket(totals, key);
        t.inflow += inflow;
        t.outflow += outflow;
    };
    // Task 8.3: rows older than the floor are folded into one net
    // pre-floor movement per account, preserving exact balances while the
    // per-method GROUP BYs below only touch the bounded, indexed range.
    const preFloor = db.prepare(`
    SELECT payment_method,
      COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) as inflow,
      COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0) as outflow
    FROM payments
    WHERE payment_date < ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of preFloor) {
        add(row.payment_method, row.inflow, row.outflow);
    }
    // Owner equity (pre-floor fold): capital in / cash withdrawals out,
    // folded like payments so balances stay exact below the scan floor.
    const ownerPreFloor = db.prepare(`
    SELECT payment_method,
      COALESCE(SUM(amount), 0) as inflow
    FROM owner_capital
    WHERE status = 'posted' AND capital_date < ? AND capital_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    const ownerWdPreFloor = db.prepare(`
    SELECT payment_method,
      COALESCE(SUM(amount), 0) as outflow
    FROM owner_withdrawals
    WHERE status = 'posted' AND kind = 'cash' AND withdrawal_date < ? AND withdrawal_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of ownerPreFloor) {
        add(row.payment_method, row.inflow, 0);
    }
    for (const row of ownerWdPreFloor) {
        add(row.payment_method, 0, row.outflow);
    }
    // Employee loans (pre-floor fold): the disbursement moved cash out
    // regardless of later status (written-off loans were still paid out);
    // direct repayments move cash back in (salary deductions are already
    // counted via salary_payments).
    const loanPreFloor = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM employee_loans
    WHERE disbursement_date < ? AND disbursement_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    const loanRepayPreFloor = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as inflow
    FROM employee_loan_repayments
    WHERE repayment_type = 'direct' AND payment_date < ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of loanPreFloor) {
        add(row.payment_method, 0, row.outflow);
    }
    for (const row of loanRepayPreFloor) {
        add(row.payment_method, row.inflow, 0);
    }
    // Supplier refunds (pre-floor fold): POSTED rows are money back in.
    const refundPreFloor = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as inflow
    FROM supplier_refunds
    WHERE status = 'POSTED' AND refund_date < ? AND refund_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of refundPreFloor) {
        add(row.payment_method, row.inflow, 0);
    }
    // Customer payments: positive amounts are money in; negative amounts
    // (refunds paid out to customers) are money out.
    const customerPayments = db.prepare(`
    SELECT payment_method,
           COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) as inflow,
           COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0) as outflow
    FROM payments
    WHERE customer_id IS NOT NULL AND payment_date > ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of customerPayments) {
        add(row.payment_method, row.inflow, row.outflow);
    }
    // Supplier payments: money out.
    const supplierPayments = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM payments
    WHERE supplier_id IS NOT NULL AND amount > 0 AND payment_date > ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of supplierPayments) {
        add(row.payment_method, 0, row.outflow);
    }
    // Expenses: money out once approved/submitted (draft/cancelled are not).
    const expenses = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM expenses
    WHERE status NOT IN ('Cancelled', 'Draft') AND expense_date > ? AND expense_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of expenses) {
        add(row.payment_method, 0, row.outflow);
    }
    // Salary payments: money out (methods stored lowercase 'cash' | 'bank').
    const salaries = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM salary_payments
    WHERE status != 'cancelled' AND payment_date > ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of salaries) {
        add(row.payment_method, 0, row.outflow);
    }
    // Owner equity: capital contributions are money in; cash-kind
    // withdrawals are money out (goods withdrawals move no cash). Voided
    // rows are excluded so the till matches the GL.
    const ownerCapital = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as inflow
    FROM owner_capital
    WHERE status = 'posted' AND capital_date > ? AND capital_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of ownerCapital) {
        add(row.payment_method, row.inflow, 0);
    }
    const ownerCashOut = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM owner_withdrawals
    WHERE status = 'posted' AND kind = 'cash' AND withdrawal_date > ? AND withdrawal_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of ownerCashOut) {
        add(row.payment_method, 0, row.outflow);
    }
    // Employee loans: disbursements are money out (all statuses — the cash
    // left the till even when the loan is later written off); direct
    // repayments are money in. Salary-deduction repayments never touch
    // cash directly (the salary payment already carries the outflow).
    const loans = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as outflow
    FROM employee_loans
    WHERE disbursement_date > ? AND disbursement_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of loans) {
        add(row.payment_method, 0, row.outflow);
    }
    const loanRepayments = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as inflow
    FROM employee_loan_repayments
    WHERE repayment_type = 'direct' AND payment_date > ? AND payment_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of loanRepayments) {
        add(row.payment_method, row.inflow, 0);
    }
    // Supplier refunds: money in once POSTED (voided rows collected nothing).
    const supplierRefunds = db.prepare(`
    SELECT payment_method, COALESCE(SUM(amount), 0) as inflow
    FROM supplier_refunds
    WHERE status = 'POSTED' AND refund_date > ? AND refund_date <= ?
    GROUP BY payment_method
  `).all(floor, uptoDate);
    for (const row of supplierRefunds) {
        add(row.payment_method, row.inflow, 0);
    }
    // CASH-01 (financial-audit-p0-remediation 1.1): direct purchases are NOT
    // an extra cash outflow — paid purchases already appear here via supplier
    // payments (purchase_allocations). Counting them again made the till
    // wrong and double-count on payment.
    return totals;
}
/** GL balance per tracked account key as of `asOfDate`. Accounts whose
 * GL code does not exist yet (fresh installs before the wallet seeding)
 * read as 0. */
function getGlBalances(db, asOfDate) {
    const map = new Map();
    for (const a of exports.CASH_ACCOUNTS) {
        const account = accountingService_1.default.getAccountByCode(db, exports.CASH_GL_CODES[a.key]);
        map.set(a.key, account ? accountingService_1.default.getAccountBalance(db, account.id, asOfDate).balance : 0);
    }
    return map;
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
/** Push the dashboard opening_balances seed into the GL: void any
 * existing opening-capital postings and post a fresh balanced entry
 * dated the earliest transaction in the system (so as-of balances for
 * every later date are correct). Runs inside the caller's transaction. */
function syncOpeningBalancesToGl(db, userId) {
    const opening = getOpeningBalances(db);
    const lines = [];
    for (const a of exports.CASH_ACCOUNTS) {
        const amount = Math.round((opening.get(a.key) ?? 0) * 100) / 100;
        if (amount === 0)
            continue;
        const code = exports.CASH_GL_CODES[a.key];
        if (amount > 0) {
            lines.push({ code, debit: amount, credit: 0, label: `Opening balance ${a.name}` });
            lines.push({ code: '3000', debit: 0, credit: amount, label: `Opening capital ${a.name}` });
        }
        else {
            lines.push({ code: '3000', debit: -amount, credit: 0, label: `Opening capital adjustment ${a.name}` });
            lines.push({ code, debit: 0, credit: -amount, label: `Opening balance ${a.name}` });
        }
    }
    accountingService_1.default.voidJournalLinesByReference(db, 'BACKFILL_OPENING', 0);
    accountingService_1.default.voidJournalLinesByReference(db, 'OPENING_BALANCE', 0);
    if (lines.length === 0)
        return; // zeroed seed → GL openings zeroed too
    // Date the entry one day before the earliest transaction so the seed
    // lands in the opening balance of the first transaction day instead of
    // double-counting with that day's flows; local today on empty books.
    const earliest = db.prepare(`
    SELECT MIN(d) as d FROM (
      SELECT MIN(payment_date) as d FROM payments
      UNION ALL SELECT MIN(expense_date) FROM expenses
      UNION ALL SELECT MIN(payment_date) FROM salary_payments
      UNION ALL SELECT MIN(capital_date) FROM owner_capital
      UNION ALL SELECT MIN(withdrawal_date) FROM owner_withdrawals
      UNION ALL SELECT MIN(disbursement_date) FROM employee_loans
      UNION ALL SELECT MIN(payment_date) FROM employee_loan_repayments
      UNION ALL SELECT MIN(refund_date) FROM supplier_refunds
    )
  `).get();
    const entryDate = earliest.d
        ? db.prepare(`SELECT date(?, '-1 day') as d`).get(earliest.d).d
        : db.prepare(`SELECT date('now', 'localtime') as d`).get().d;
    accountingService_1.default.postEntry(db, {
        entry_date: entryDate,
        description: 'Opening cash balances from dashboard seed',
        reference_type: 'OPENING_BALANCE',
        reference_id: 0,
        created_by: userId,
        lines: lines.map((l) => {
            const account = accountingService_1.default.getAccountByCode(db, l.code);
            if (!account)
                throw new Error(`Chart of accounts is missing required account: ${l.code}`);
            return { account_id: account.id, debit: l.debit, credit: l.credit, description: l.label };
        }),
    });
}
/** Per-account opening/day-flow/closing figures for `asOfDate`.
 * opening/closing come from the GL (single cash truth with the balance
 * sheet); inflow/outflow are the classified transactional movements of
 * the day; `flow_variance` exposes any residual disagreement. */
function getCashAccountTotals(db, asOfDate) {
    const prevDate = db.prepare(`SELECT date(?, '-1 day') as d`).get(asOfDate);
    const upTo = collectFlows(db, asOfDate);
    const before = collectFlows(db, prevDate.d);
    const glNow = getGlBalances(db, asOfDate);
    const glBefore = getGlBalances(db, prevDate.d);
    const rows = exports.CASH_ACCOUNTS.map((a) => {
        const now = upTo.get(a.key);
        const earlier = before.get(a.key);
        const closing = glNow.get(a.key);
        const opening = glBefore.get(a.key);
        const inflow = now.inflow - earlier.inflow;
        const outflow = now.outflow - earlier.outflow;
        const net = closing - opening;
        return {
            key: a.key,
            name: a.name,
            opening,
            inflow,
            outflow,
            net,
            closing,
            flow_variance: Math.round((net - (inflow - outflow)) * 100) / 100,
        };
    });
    // CASH-02 (task 1.3): surface the unclassified bucket as a flagged row so
    // unrecognized payment methods are visible in the reconciliation instead of
    // silently vanishing into bank. Flow-derived only — it has no GL account.
    const uncNow = upTo.get('unclassified');
    if (uncNow && (uncNow.inflow !== 0 || uncNow.outflow !== 0)) {
        const uncBefore = before.get('unclassified') ?? { inflow: 0, outflow: 0 };
        const inflow = uncNow.inflow - uncBefore.inflow;
        const outflow = uncNow.outflow - uncBefore.outflow;
        rows.push({
            key: 'unclassified',
            name: 'Unclassified (needs review)',
            opening: 0,
            inflow,
            outflow,
            net: inflow - outflow,
            closing: uncNow.inflow - uncNow.outflow,
            flow_variance: 0,
        });
    }
    return rows;
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
    // Owner capital contributions (money in).
    for (const r of db.prepare(`
    SELECT capital_date as date, payment_method as method, capital_no as reference,
           note as description, amount
    FROM owner_capital
    WHERE status = 'posted' AND capital_date <= ?
  `).all(uptoDate)) {
        push({
            method: r.method,
            date: r.date,
            reference: r.reference,
            description: r.description,
            amount: Number(r.amount) || 0,
            type: 'owner_capital',
        });
    }
    // Cash-kind owner withdrawals (money out); goods withdrawals move no
    // cash so they never appear on a till walk.
    for (const r of db.prepare(`
    SELECT withdrawal_date as date, payment_method as method, withdrawal_no as reference,
           note as description, amount
    FROM owner_withdrawals
    WHERE status = 'posted' AND kind = 'cash' AND withdrawal_date <= ?
  `).all(uptoDate)) {
        push({
            method: r.method,
            date: r.date,
            reference: r.reference,
            description: r.description,
            amount: -(Number(r.amount) || 0),
            type: 'owner_withdrawal',
        });
    }
    // Employee loan disbursements (money out) and direct repayments
    // (money in); salary deductions move no cash directly — they are
    // already inside the salary payment's outflow.
    for (const r of db.prepare(`
    SELECT id, disbursement_date as date, payment_method as method, purpose as description, amount
    FROM employee_loans
    WHERE disbursement_date <= ?
  `).all(uptoDate)) {
        push({
            method: r.method,
            date: r.date,
            reference: `#${r.id}`,
            description: r.description,
            amount: -(Number(r.amount) || 0),
            type: 'loan_disbursement',
        });
    }
    for (const r of db.prepare(`
    SELECT payment_date as date, payment_method as method, reference_no as reference,
           notes as description, amount
    FROM employee_loan_repayments
    WHERE repayment_type = 'direct' AND payment_date <= ?
  `).all(uptoDate)) {
        push({
            method: r.method,
            date: r.date,
            reference: r.reference,
            description: r.description,
            amount: Number(r.amount) || 0,
            type: 'loan_repayment',
        });
    }
    // Supplier refunds (money in once POSTED — voided rows collected nothing).
    for (const r of db.prepare(`
    SELECT refund_date as date, payment_method as method, refund_no as reference,
           reference_no as description, amount
    FROM supplier_refunds
    WHERE status = 'POSTED' AND refund_date <= ?
  `).all(uptoDate)) {
        push({
            method: r.method,
            date: r.date,
            reference: r.reference,
            description: r.description,
            amount: Number(r.amount) || 0,
            type: 'supplier_refund',
        });
    }
    out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
    return out;
}
