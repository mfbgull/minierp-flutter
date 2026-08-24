"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.runBackfillGlPreposting = runBackfillGlPreposting;
const logger_1 = __importDefault(require("../utils/logger"));
/** Same mapping as AccountingService._cashOrBankAccountCode /
 * cashService.normalizeCashMethod, kept local to avoid a service import
 * (and its transitive db import) inside the boot migration graph. */
function methodToAccountCode(paymentMethod) {
    if (!paymentMethod)
        return '1000';
    const m = String(paymentMethod).toLowerCase().trim();
    if (m === 'cash')
        return '1000';
    if (m === 'easypaisa')
        return '1020';
    if (m === 'jazzcash' || m === 'jazz')
        return '1030';
    if (m === 'upaisa')
        return '1040';
    if (m === 'credit')
        return null; // AR adjustment — no money movement
    return '1010';
}
const OPENING_KEY_TO_CODE = {
    cash: '1000',
    bank: '1010',
    easypaisa: '1020',
    jazzcash: '1030',
    upaisa: '1040',
};
function runBackfillGlPreposting(db) {
    const accounts = db.prepare(`SELECT id, code FROM chart_of_accounts`).all();
    const acctId = new Map(accounts.map(a => [a.code, a.id]));
    const requiredCodes = ['1000', '1010', '1020', '1030', '1040', '1100', '1200', '2000', '3000', '6000', '6100'];
    const missing = requiredCodes.filter(c => !acctId.has(c));
    if (missing.length > 0) {
        logger_1.default.warn(`[backfill-gl] skipping — chart_of_accounts missing codes: ${missing.join(', ')}`);
        return;
    }
    const insertLine = db.prepare(`
    INSERT INTO journal_lines (
      journal_entry_id, account_id, debit, credit, description,
      line_date, reference_type, reference_id, voided
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
  `);
    const insertEntry = db.prepare(`
    INSERT INTO journal_entries (
      reference_type, reference_id, entry_date, description,
      debit_account, credit_account, amount
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
    const hasActiveLines = db.prepare(`
    SELECT 1 FROM journal_lines
    WHERE reference_type = ? AND reference_id = ? AND voided = 0
    LIMIT 1
  `);
    const post = (date, description, referenceType, referenceId, lines) => {
        const totalDebit = lines.reduce((s, l) => s + (l.debit || 0), 0);
        const totalCredit = lines.reduce((s, l) => s + (l.credit || 0), 0);
        if (Math.abs(totalDebit - totalCredit) > 0.01) {
            throw new Error(`[backfill-gl] unbalanced group for ${referenceType}#${referenceId}: D ${totalDebit} vs C ${totalCredit}`);
        }
        if (totalDebit === 0)
            return false;
        // Task 10.4 finding: the original backfill wrote journal_lines without a
        // parent journal_entries row, leaving every line dangling. Create the
        // entry header first and use ITS rowid — the old manual entryId counter
        // (MAX(journal_lines.journal_entry_id)) diverges from the entries table's
        // AUTOINCREMENT sequence, so lines pointed at nonexistent entries.
        const entryResult = insertEntry.run(referenceType, referenceId, date, description, lines[0]?.code ?? '', lines[1]?.code ?? '', totalDebit);
        const lineEntryId = Number(entryResult.lastInsertRowid);
        for (const l of lines) {
            insertLine.run(lineEntryId, acctId.get(l.code), l.debit || 0, l.credit || 0, `${l.label} (${description})`, date, referenceType, referenceId);
        }
        return true;
    };
    const round2 = (v) => Math.round(v * 100) / 100;
    const reviewList = [];
    let postedCount = 0;
    const run = () => {
        // ── 1. Direct purchases ──────────────────────────────────────────
        const purchases = db.prepare(`
      SELECT id, purchase_no, total_cost, purchase_date FROM purchases
      WHERE total_cost > 0
    `).all();
        for (const p of purchases) {
            if (hasActiveLines.get('PURCHASE', p.id))
                continue;
            if (post(p.purchase_date, p.purchase_no, 'PURCHASE', p.id, [
                { code: '1200', debit: round2(p.total_cost), label: `Inventory received via ${p.purchase_no} (backfill)` },
                { code: '2000', credit: round2(p.total_cost), label: `AP created for ${p.purchase_no} (backfill)` },
            ]))
                postedCount += 1;
        }
        // ── 2+3. Payments (supplier out / customer in-or-refund) ─────────
        const payments = db.prepare(`
      SELECT id, payment_no, amount, payment_date, payment_method,
             supplier_id, customer_id
      FROM payments WHERE amount <> 0
    `).all();
        for (const pay of payments) {
            if (hasActiveLines.get('PAYMENT', pay.id))
                continue;
            const amount = round2(Math.abs(pay.amount));
            const code = methodToAccountCode(pay.payment_method);
            if (pay.supplier_id !== null && pay.supplier_id !== undefined) {
                if (!code) {
                    reviewList.push(`supplier payment ${pay.payment_no}: non-cash method '${pay.payment_method}'`);
                    continue;
                }
                if (pay.amount <= 0) {
                    reviewList.push(`supplier payment ${pay.payment_no}: non-positive amount`);
                    continue;
                }
                if (post(pay.payment_date, pay.payment_no, 'PAYMENT', pay.id, [
                    { code: '2000', debit: amount, label: `AP settled by ${pay.payment_no} (backfill)` },
                    { code, credit: amount, label: `Cash paid via ${pay.payment_no} (backfill)` },
                ]))
                    postedCount += 1;
                continue;
            }
            if (pay.customer_id === null || pay.customer_id === undefined)
                continue;
            if (!code) {
                reviewList.push(`customer payment ${pay.payment_no}: non-cash method '${pay.payment_method}'`);
                continue;
            }
            if (pay.amount > 0) {
                if (post(pay.payment_date, pay.payment_no, 'PAYMENT', pay.id, [
                    { code, debit: amount, label: `Cash received via ${pay.payment_no} (backfill)` },
                    { code: '1100', credit: amount, label: `AR reduced by ${pay.payment_no} (backfill)` },
                ]))
                    postedCount += 1;
            }
            else {
                // Refund paid out to the customer.
                if (post(pay.payment_date, pay.payment_no, 'PAYMENT', pay.id, [
                    { code: '1100', debit: amount, label: `AR adjusted for refund ${pay.payment_no} (backfill)` },
                    { code, credit: amount, label: `Cash refunded via ${pay.payment_no} (backfill)` },
                ]))
                    postedCount += 1;
            }
        }
        // ── 4. Expenses (draft/cancelled never drained the till) ─────────
        const expenses = db.prepare(`
      SELECT id, expense_no, amount, expense_date, payment_method FROM expenses
      WHERE amount > 0 AND status NOT IN ('Cancelled', 'Draft')
    `).all();
        for (const e of expenses) {
            if (hasActiveLines.get('EXPENSE', e.id))
                continue;
            const code = methodToAccountCode(e.payment_method) ?? '1000';
            if (post(e.expense_date, e.expense_no, 'EXPENSE', e.id, [
                { code: '6000', debit: round2(e.amount), label: `Expense incurred via ${e.expense_no} (backfill)` },
                { code, credit: round2(e.amount), label: `Cash paid for ${e.expense_no} (backfill)` },
            ]))
                postedCount += 1;
        }
        // ── 5. Salary payments ────────────────────────────────────────────
        const salaries = db.prepare(`
      SELECT id, amount, payment_date, payment_method FROM salary_payments
      WHERE amount > 0 AND status != 'cancelled'
    `).all();
        for (const s of salaries) {
            if (hasActiveLines.get('SALARY_PAYMENT', s.id))
                continue;
            const code = methodToAccountCode(s.payment_method) ?? '1000';
            if (post(s.payment_date, `salary payment #${s.id}`, 'SALARY_PAYMENT', s.id, [
                { code: '6100', debit: round2(s.amount), label: `Salary paid (backfill)` },
                { code, credit: round2(s.amount), label: `Cash paid for salary (backfill)` },
            ]))
                postedCount += 1;
        }
        // ── 6. Opening capital from operational opening_balances ─────────
        const openingPosted = db.prepare(`
      SELECT 1 FROM journal_lines WHERE reference_type = 'BACKFILL_OPENING' AND voided = 0 LIMIT 1
    `).get();
        if (!openingPosted) {
            const openings = db.prepare(`SELECT account_key, amount FROM opening_balances WHERE amount <> 0`).all();
            const lines = [];
            for (const o of openings) {
                const code = OPENING_KEY_TO_CODE[o.account_key];
                if (!code) {
                    reviewList.push(`opening_balances key '${o.account_key}' has no GL account`);
                    continue;
                }
                const amt = round2(o.amount);
                if (amt > 0) {
                    lines.push({ code, debit: amt, label: `Opening balance ${o.account_key} (backfill)` });
                    lines.push({ code: '3000', credit: amt, label: `Opening capital ${o.account_key} (backfill)` });
                }
                else {
                    lines.push({ code: '3000', debit: -amt, label: `Opening capital adjustment ${o.account_key} (backfill)` });
                    lines.push({ code, credit: -amt, label: `Opening balance ${o.account_key} (backfill)` });
                }
            }
            if (lines.length > 0) {
                const today = db.prepare(`SELECT date('now', 'localtime') as d`).get().d;
                if (post(today, 'opening capital from opening_balances', 'BACKFILL_OPENING', 0, lines))
                    postedCount += 1;
            }
        }
        // ── Sanity: the whole table must still foot ───────────────────────
        const totals = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) as d, COALESCE(SUM(credit), 0) as c
      FROM journal_lines WHERE voided = 0
    `).get();
        if (Math.abs(totals.d - totals.c) > 0.01) {
            throw new Error(`[backfill-gl] journal_lines do not foot after backfill: D ${totals.d} vs C ${totals.c}`);
        }
        logger_1.default.info(`[backfill-gl] posted ${postedCount} entries; ` +
            `journal_lines footing ${totals.d.toFixed(2)} == ${totals.c.toFixed(2)}` +
            (reviewList.length > 0 ? `; ${reviewList.length} item(s) need review:` : ''));
        for (const item of reviewList)
            logger_1.default.warn(`[backfill-gl] review: ${item}`);
    };
    db.transaction(run)();
}
//# sourceMappingURL=backfillGlPreposting.js.map