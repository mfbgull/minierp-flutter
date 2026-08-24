"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const accountingService_1 = __importDefault(require("../services/accountingService"));
const cashService_1 = require("../services/cashService");
const reportSql_1 = require("../utils/reportSql");
function getARAgingReport(asOfDate, db) {
    const agingData = db.prepare(`
    SELECT c.customer_name, c.customer_code, SUM(i.balance_amount) as total_outstanding,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) <= 0 THEN i.balance_amount ELSE 0 END) as current_amount,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 0 AND julianday(?) - julianday(i.due_date) <= 30 THEN i.balance_amount ELSE 0 END) as days_1_30,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 30 AND julianday(?) - julianday(i.due_date) <= 60 THEN i.balance_amount ELSE 0 END) as days_31_60,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 60 AND julianday(?) - julianday(i.due_date) <= 90 THEN i.balance_amount ELSE 0 END) as days_61_90,
      SUM(CASE WHEN julianday(?) - julianday(i.due_date) > 90 THEN i.balance_amount ELSE 0 END) as days_over_90
    FROM invoices i JOIN customers c ON i.customer_id = c.id
    WHERE i.status IN ('Unpaid', 'Partially Paid', 'Overdue') AND i.balance_amount > 0
    GROUP BY i.customer_id, c.customer_name, c.customer_code ORDER BY total_outstanding DESC
  `).all(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    const summary = db.prepare(`
    SELECT SUM(balance_amount) as totalReceivables,
      SUM(CASE WHEN julianday(?) - julianday(due_date) <= 0 THEN balance_amount ELSE 0 END) as current_amount,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 0 AND julianday(?) - julianday(due_date) <= 30 THEN balance_amount ELSE 0 END) as total_1_30,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 30 AND julianday(?) - julianday(due_date) <= 60 THEN balance_amount ELSE 0 END) as total_31_60,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 60 AND julianday(?) - julianday(due_date) <= 90 THEN balance_amount ELSE 0 END) as total_61_90,
      SUM(CASE WHEN julianday(?) - julianday(due_date) > 90 THEN balance_amount ELSE 0 END) as total_over_90
    FROM invoices WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue') AND balance_amount > 0
  `).get(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    return { asOfDate, agingBuckets: agingData, summary };
}
// Moved from reportsController
function getCustomerStatements(db, customerId, startDate, endDate) {
    // reporting-search-remediation (report-query-integrity): rebuilt from
    // customer_ledger so statements actually foot. The old version summed
    // invoice header columns with two different join semantics — a date
    // filter on a selected customer landed in WHERE and annihilated the
    // LEFT JOIN (customers with no in-range invoices vanished), and
    // opening_balance was never folded into closing_balance.
    //
    // Now: opening = Σ(debit − credit) before the period; debits/credits =
    // ledger movement inside the period; closing = opening + debits − credits.
    // Date predicates live inside conditional aggregates, so childless
    // customers always survive the LEFT JOIN.
    const from = startDate && endDate ? startDate : '0001-01-01';
    const to = startDate && endDate ? endDate : '9999-12-31';
    const rows = db.prepare(`
    SELECT c.id as customer_id, c.customer_name, c.customer_code,
      COALESCE(SUM(CASE WHEN cl.transaction_date < :from THEN cl.debit - cl.credit ELSE 0 END), 0) as opening_balance,
      COALESCE(SUM(CASE WHEN cl.transaction_date BETWEEN :from AND :to THEN cl.debit ELSE 0 END), 0) as total_debits,
      COALESCE(SUM(CASE WHEN cl.transaction_date BETWEEN :from AND :to THEN cl.credit ELSE 0 END), 0) as total_credits,
      COUNT(CASE WHEN cl.transaction_type = 'INVOICE' AND cl.transaction_date BETWEEN :from AND :to THEN 1 END) as invoice_count,
      MAX(CASE WHEN cl.transaction_type = 'INVOICE' AND cl.transaction_date BETWEEN :from AND :to THEN cl.transaction_date END) as last_invoice_date
    FROM customers c
    LEFT JOIN customer_ledger cl ON cl.customer_id = c.id
    ${customerId ? 'WHERE c.id = :customerId' : ''}
    GROUP BY c.id ORDER BY c.customer_name
  `).all({
        from,
        to,
        ...(customerId ? { customerId } : {}),
    });
    const r2 = (v) => Math.round(v * 100) / 100;
    const statements = rows.map((row) => {
        const closing = r2(row.opening_balance + row.total_debits - row.total_credits);
        return {
            customer_id: row.customer_id,
            customer_name: row.customer_name,
            customer_code: row.customer_code,
            opening_balance: r2(row.opening_balance),
            total_debits: r2(row.total_debits),
            total_credits: r2(row.total_credits),
            closing_balance: closing,
            invoice_count: row.invoice_count,
            total_amount: r2(row.total_debits),
            paid_amount: r2(row.total_credits),
            balance: closing,
            last_invoice_date: row.last_invoice_date,
        };
    });
    return { statements };
}
// Moved from reportsController
function getTopDebtors(db, limit = 10, asOfDate) {
    const dateFilter = asOfDate ? ` AND i.invoice_date <= ?` : ``;
    const params = [limit];
    if (asOfDate)
        params.unshift(asOfDate);
    const rows = db.prepare(`
    SELECT c.customer_name, c.customer_code, SUM(i.balance_amount) as total_outstanding,
      SUM(i.balance_amount) as outstanding_balance,
      SUM(i.total_amount) as total_invoiced,
      COUNT(i.id) as invoice_count
    FROM invoices i JOIN customers c ON i.customer_id = c.id
    WHERE i.status IN ('Unpaid', 'Partially Paid', 'Overdue') AND i.balance_amount > 0${dateFilter}
    GROUP BY i.customer_id ORDER BY total_outstanding DESC LIMIT ?
  `).all(...params);
    return rows;
}
// Moved from reportsController
function getDSOMetric(db, startDateStr, endDateStr) {
    const days = Math.max(1, Math.ceil((new Date(endDateStr).getTime() - new Date(startDateStr).getTime()) / (1000 * 60 * 60 * 24)));
    const avgReceivables = db.prepare(`
    SELECT AVG(balance_amount) as avg_balance FROM invoices WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue') AND invoice_date BETWEEN ? AND ?
  `).get(startDateStr, endDateStr);
    const totalCreditSales = db.prepare(`SELECT ${(0, reportSql_1.netRevenueSum)()} as total FROM invoices WHERE invoice_date BETWEEN ? AND ? AND ${(0, reportSql_1.NET_REVENUE_STATUS)()}`).get(startDateStr, endDateStr);
    const dso = totalCreditSales.total > 0 ? (avgReceivables.avg_balance / totalCreditSales.total) * days : 0;
    const totalSales = totalCreditSales.total;
    const totalAR = avgReceivables.avg_balance;
    const avgInvoiceValue = totalCreditSales.total > 0 ? totalCreditSales.total / db.prepare(`SELECT COUNT(*) as count FROM invoices WHERE invoice_date BETWEEN ? AND ?`).get(startDateStr, endDateStr).count : 0;
    return { dso, avgReceivables: avgReceivables.avg_balance, totalCreditSales: totalCreditSales.total, totalSales, totalAR, avgInvoiceValue, period: { startDate: startDateStr, endDate: endDateStr } };
}
// Moved from reportsController
function getReceivablesSummary(db, asOfDate = new Date().toISOString().split('T')[0]) {
    // CRITICAL-2 fix: previously the function returned a synthetic row
    // built from a single SELECT with case-by-status SUMs, then mapped
    // those status sums to bucket fields (0-30, 31-60, ...) under
    // misleading names. As a result, total_1_30 was actually the
    // "Partially Paid" outstanding total, total_over_90 was the
    // "Overdue" outstanding total, and the 31-60 and 61-90 buckets were
    // hard-coded to 0. AR aging was essentially random.
    //
    // New behavior: compute aging buckets from each invoice's due_date
    // relative to the asOfDate parameter (which is now actually used as
    // a filter), classifying the invoice's current balance_amount into
    // one of 0-30, 31-60, 61-90, or 90+ days overdue. The "current"
    // bucket captures invoices not yet past due.
    //
    // The status breakdown is preserved as a separate, correctly-labeled
    // object. Status and age are independent: an invoice can be
    // "Partially Paid" AND 45 days past due, for example.
    // The bucket math is done in SQL via julianday() so we don't have to
    // pull every invoice row into Node. The CASE expression puts the
    // invoice's balance into exactly one of the five buckets.
    const result = db.prepare(`
    SELECT
      COUNT(*) as total_invoices,
      COALESCE(SUM(balance_amount), 0) as total_outstanding,
      COALESCE(SUM(paid_amount), 0) as total_paid,
      COALESCE(SUM(total_amount), 0) as total_invoiced,

      -- Buckets: days past due = asOfDate - due_date. Negative or zero
      -- (not yet due) goes into "current". > 90 goes into "over_90".
      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) <= 0 THEN balance_amount
        ELSE 0
      END), 0) as current_amount,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 1 AND 30 THEN balance_amount
        ELSE 0
      END), 0) as bucket_1_30,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 31 AND 60 THEN balance_amount
        ELSE 0
      END), 0) as bucket_31_60,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) BETWEEN 61 AND 90 THEN balance_amount
        ELSE 0
      END), 0) as bucket_61_90,

      COALESCE(SUM(CASE
        WHEN due_date IS NULL THEN 0
        WHEN julianday(?) - julianday(due_date) > 90 THEN balance_amount
        ELSE 0
      END), 0) as bucket_over_90,

      -- Per-status counts and totals, unchanged in spirit but
      -- separated from the aging buckets.
      COALESCE(SUM(CASE WHEN status = 'Unpaid' THEN balance_amount ELSE 0 END), 0) as unpaid_amount,
      COALESCE(SUM(CASE WHEN status = 'Partially Paid' THEN balance_amount ELSE 0 END), 0) as partially_paid_amount,
      COALESCE(SUM(CASE WHEN status = 'Overdue' THEN balance_amount ELSE 0 END), 0) as overdue_amount,
      COUNT(CASE WHEN status = 'Unpaid' THEN 1 END) as unpaid_count,
      COUNT(CASE WHEN status = 'Partially Paid' THEN 1 END) as partial_count,
      COUNT(CASE WHEN status = 'Overdue' THEN 1 END) as overdue_count
    FROM invoices
    WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue', 'Sent')
      AND balance_amount > 0
      AND invoice_date <= ?
  `).get(asOfDate, asOfDate, asOfDate, asOfDate, asOfDate, asOfDate);
    return {
        asOfDate,
        total_invoices: result.total_invoices,
        total_outstanding: result.total_outstanding,
        total_paid: result.total_paid,
        total_invoiced: result.total_invoiced,
        // Aging buckets. Field names match the previous API so the
        // frontend doesn't need to change, but the values are now correct.
        total_current: result.current_amount,
        total_1_30: result.bucket_1_30,
        total_31_60: result.bucket_31_60,
        total_61_90: result.bucket_61_90,
        total_over_90: result.bucket_over_90,
        // Status breakdown, unchanged in shape, still meaningful.
        statusBreakdown: {
            unpaid: { count: result.unpaid_count, amount: result.unpaid_amount },
            partiallyPaid: { count: result.partial_count, amount: result.partially_paid_amount },
            overdue: { count: result.overdue_count, amount: result.overdue_amount },
        },
    };
}
// Moved from reportsController
function getBatchTraceability(db, itemId) {
    const item = db.prepare('SELECT id, item_code, item_name, unit_of_measure FROM items WHERE id = ?').get(itemId);
    if (!item)
        return null;
    // Fetch all batches for this item with sold/remaining quantities
    const batches = db.prepare(`
    SELECT
      sb.id,
      sb.batch_no,
      sb.item_id,
      sb.warehouse_id,
      w.warehouse_name,
      sb.source_type,
      sb.source_id,
      sb.quantity_original,
      sb.quantity_remaining,
      sb.unit_cost,
      sb.received_date,
      (sb.quantity_original - sb.quantity_remaining) as quantity_sold
    FROM stock_batches sb
    JOIN warehouses w ON sb.warehouse_id = w.id
    WHERE sb.item_id = ?
    ORDER BY sb.received_date DESC
  `).all(itemId);
    // Summary
    const totalOriginal = batches.reduce((s, b) => s + b.quantity_original, 0);
    const totalRemaining = batches.reduce((s, b) => s + b.quantity_remaining, 0);
    const totalSold = batches.reduce((s, b) => s + b.quantity_sold, 0);
    const activeBatches = batches.filter(b => b.quantity_remaining > 0).length;
    return {
        item,
        batches,
        summary: {
            totalBatches: batches.length,
            activeBatches,
            totalOriginal,
            totalSold,
            totalRemaining,
        }
    };
}
function computeAPAging(asOfDate, db) {
    const debitRows = db.prepare(`
    SELECT sl.supplier_id, sl.transaction_date, sl.debit,
      COALESCE(s.supplier_name, '') AS supplier_name,
      s.supplier_code
    FROM supplier_ledger sl
    JOIN suppliers s ON s.id = sl.supplier_id
    WHERE sl.voided = 0 AND sl.debit > 0
    ORDER BY sl.supplier_id, sl.transaction_date ASC, sl.id ASC
  `).all();
    const creditTotals = new Map();
    const creditRows = db.prepare(`
    SELECT supplier_id, SUM(credit) AS credit FROM supplier_ledger
    WHERE voided = 0 AND credit > 0 GROUP BY supplier_id
  `).all();
    for (const r of creditRows)
        creditTotals.set(r.supplier_id, Number(r.credit));
    const buckets = new Map();
    for (const row of debitRows) {
        let b = buckets.get(row.supplier_id);
        if (!b) {
            b = {
                supplier_id: row.supplier_id,
                supplier_name: row.supplier_name,
                supplier_code: row.supplier_code,
                total_outstanding: 0, current_amount: 0, days_1_30: 0,
                days_31_60: 0, days_61_90: 0, days_over_90: 0,
            };
            buckets.set(row.supplier_id, b);
        }
        let outstanding = Number(row.debit);
        // Net credits FIFO against the oldest debits first.
        const credit = creditTotals.get(row.supplier_id) ?? 0;
        if (credit > 0) {
            const applied = Math.min(credit, outstanding);
            outstanding -= applied;
            creditTotals.set(row.supplier_id, credit - applied);
        }
        if (outstanding <= 0.005)
            continue; // fully offset — not outstanding
        const ageDays = Math.floor((new Date(asOfDate).getTime() - new Date(row.transaction_date).getTime()) / 86400000);
        b.total_outstanding += outstanding;
        if (ageDays <= 0)
            b.current_amount += outstanding;
        else if (ageDays <= 30)
            b.days_1_30 += outstanding;
        else if (ageDays <= 60)
            b.days_31_60 += outstanding;
        else if (ageDays <= 90)
            b.days_61_90 += outstanding;
        else
            b.days_over_90 += outstanding;
    }
    return [...buckets.values()]
        .filter((b) => b.total_outstanding > 0.005)
        .sort((a, b) => b.total_outstanding - a.total_outstanding);
}
function getAPAgingReport(asOfDate, db) {
    const agingBuckets = computeAPAging(asOfDate, db);
    const summary = {
        totalPayables: agingBuckets.reduce((sum, b) => sum + b.total_outstanding, 0),
        current_amount: agingBuckets.reduce((sum, b) => sum + b.current_amount, 0),
        total_1_30: agingBuckets.reduce((sum, b) => sum + b.days_1_30, 0),
        total_31_60: agingBuckets.reduce((sum, b) => sum + b.days_31_60, 0),
        total_61_90: agingBuckets.reduce((sum, b) => sum + b.days_61_90, 0),
        total_over_90: agingBuckets.reduce((sum, b) => sum + b.days_over_90, 0),
    };
    return { asOfDate, basis: 'supplier_ledger', agingBuckets, summary };
}
function getProfitLossReport(startDate, endDate, db) {
    // MAJOR-3 audit note: the original P&L formula here is correct
    //   gross_profit = revenue - cogs
    //   net_profit   = gross_profit - expenses
    // (verified against the current code). The only fix needed was
    // excluding Cancelled invoices from revenue. Note that historical
    // SALE stock_movements may have unit_cost = sale_price (see MAJOR-6
    // in the audit), so COGS will be slightly off until that flow is
    // also fixed; the SQL itself is correct.
    const revenue = db.prepare(`
    SELECT ${(0, reportSql_1.netRevenueSum)()} as total FROM invoices
    WHERE invoice_date BETWEEN ? AND ?
      AND ${(0, reportSql_1.NET_REVENUE_STATUS)()}
  `).get(startDate, endDate);
    // COGS via the shared helper (report-query-integrity): nets SALE
    // movements against their stock reversals so returned sales stop
    // counting as cost of goods sold.
    const cogs = { total: (0, reportSql_1.cogsForPeriod)(db, startDate, endDate) };
    const expenses = db.prepare(`SELECT expense_category, SUM(amount) as total FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY expense_category ORDER BY total DESC`).all(startDate, endDate);
    const totalExpenses = expenses.reduce((sum, e) => sum + e.total, 0);
    const grossProfit = revenue.total - cogs.total;
    const netProfit = grossProfit - totalExpenses;
    const grossProfitMargin = revenue.total > 0 ? (grossProfit / revenue.total) * 100 : 0;
    const netProfitMargin = revenue.total > 0 ? (netProfit / revenue.total) * 100 : 0;
    return { startDate, endDate, totalRevenue: revenue.total, totalCogs: cogs.total, grossProfit, expenses, totalExpenses, netProfit, grossProfitMargin, netProfitMargin };
}
function getBalanceSheet(asOfDate, db) {
    // reporting-search-remediation: the sheet is now fully GL-derived.
    // Every section reads AccountingService.getAllAccountBalances — the
    // same journal_lines ∪ legacy journal_entries source the trial
    // balance uses — so the two statements report identical account
    // balances by construction. With complete document posting
    // (migrations/backfillGlPreposting.ts) every flow hits both an
    // asset/liability and a revenue/expense/equity account, so
    // assets − liabilities == equity holds through the double-entry
    // identity rather than by coincidence between unrelated tables.
    const round2 = (v) => Math.round(v * 100) / 100;
    const balances = accountingService_1.default.getAllAccountBalances(db, asOfDate);
    const byCode = new Map(balances.map(b => [b.account_code, b]));
    const bal = (code) => byCode.get(code)?.balance ?? 0;
    const CASH_CODES = ['1000', '1010', '1020', '1030', '1040'];
    const sumType = (type) => round2(balances.filter(b => b.type === type).reduce((s, b) => s + b.balance, 0));
    // --- ASSETS ---
    const inventoryValue = bal('1200');
    const arTotal = bal('1100');
    const cashBalance = round2(CASH_CODES.reduce((s, c) => s + bal(c), 0));
    // Asset accounts outside the three display lines (custom accounts).
    const knownAssetCodes = new Set([...CASH_CODES, '1100', '1200']);
    const otherAssets = round2(balances.filter(b => b.type === 'asset' && !knownAssetCodes.has(b.account_code))
        .reduce((s, b) => s + b.balance, 0));
    const totalAssets = sumType('asset');
    // --- LIABILITIES ---
    const apTotal = bal('2000');
    const taxPayable = bal('2100');
    const otherLiabilities = round2(balances.filter(b => b.type === 'liability' && !['2000', '2100'].includes(b.account_code))
        .reduce((s, b) => s + b.balance, 0));
    const totalLiabilities = sumType('liability');
    // --- EQUITY ---
    // Revenue accounts are credit-normal except the contra-revenue Sales
    // Returns (4100, debit-normal), which reduces revenue.
    const revenueYtd = round2(balances.filter(b => b.type === 'revenue')
        .reduce((s, b) => s + (b.normal_balance === 'credit' ? b.balance : -b.balance), 0));
    const cogsYtd = bal('5000');
    const expensesYtd = round2(sumType('expense') - cogsYtd);
    const openingRetainedEarnings = sumType('equity'); // contributed capital + posted retained earnings
    const netIncomeYtd = round2(revenueYtd - cogsYtd - expensesYtd);
    const equity = round2(openingRetainedEarnings + netIncomeYtd);
    // --- ASSEMBLE ---
    const totalLiabAndEquity = round2(totalLiabilities + equity);
    const balanced = Math.abs(totalAssets - totalLiabAndEquity) < 0.01;
    return {
        asOfDate,
        assets: {
            inventory: round2(inventoryValue),
            accounts_receivable: round2(arTotal),
            cash: cashBalance,
            other: otherAssets,
            total: totalAssets
        },
        liabilities: {
            accounts_payable: round2(apTotal),
            tax_payable: round2(taxPayable),
            other: otherLiabilities,
            total: totalLiabilities
        },
        equity: {
            opening_retained_earnings: openingRetainedEarnings,
            net_income_ytd: netIncomeYtd,
            revenue_ytd: revenueYtd,
            cogs_ytd: round2(cogsYtd),
            expenses_ytd: expensesYtd,
            total: equity
        },
        totals: {
            total_assets: totalAssets,
            total_liabilities: totalLiabilities,
            total_equity: equity,
            total_liab_and_equity: totalLiabAndEquity,
            balanced
        }
    };
}
function getIncomeStatement(startDate, endDate, db) {
    // MAJOR-3 fix: previously this function was missing COGS entirely.
    // netIncome was revenue - expenses, treating COGS as zero. Fix:
    // delegate to getProfitLossReport so the two endpoints stay
    // consistent and the user gets a real income statement.
    const pl = getProfitLossReport(startDate, endDate, db);
    return {
        startDate,
        endDate,
        revenue: pl.totalRevenue,
        cogs: pl.totalCogs,
        expenses: pl.totalExpenses,
        netIncome: pl.netProfit,
        grossProfit: pl.grossProfit
    };
}
function getTrialBalance(asOfDate, db) {
    // MAJOR-1 fix (Phase 2 — GL refactor): now backed by
    // AccountingService.getAllAccountBalances which reads from
    // journal_lines (multi-line, account_id) UNION journal_entries
    // (legacy, text_code) and rolls them up per chart_of_accounts row.
    //
    // The output includes every account from chart_of_accounts, even
    // those with a zero balance, so the report shows the full account
    // list — not just the ones that happen to have movement. That is
    // the standard trial balance shape and is what auditors expect.
    const balances = accountingService_1.default.getAllAccountBalances(db, asOfDate);
    // Materialize as a per-account row in the standard TB shape:
    //   account, total_debit, total_credit, balance (signed)
    const accounts = balances.map((b) => ({
        account_code: b.account_code,
        account_name: b.account_name,
        account_type: b.type,
        total_debit: b.total_debit,
        total_credit: b.total_credit,
        balance: b.balance,
        is_zero: b.total_debit === 0 && b.total_credit === 0
    }));
    const totalDebit = accounts.reduce((s, r) => s + r.total_debit, 0);
    const totalCredit = accounts.reduce((s, r) => s + r.total_credit, 0);
    const balanced = Math.abs(totalDebit - totalCredit) < 0.01;
    return {
        asOfDate,
        accounts,
        total_debit: totalDebit,
        total_credit: totalCredit,
        balanced,
        note: 'Built from chart_of_accounts joined to journal_lines (canonical) ' +
            'and journal_entries (legacy, matched by text_code). ' +
            'New postings should use AccountingService.postEntry so they ' +
            'land in journal_lines with a proper account_id.'
    };
}
function getGeneralLedger(startDate, endDate, db) {
    // report-query-integrity: the general ledger reports the GL itself —
    // journal_lines joined to chart_of_accounts, voided lines excluded —
    // with a per-account running balance. The previous implementation
    // returned the customer subledger and survives renamed below.
    return db.prepare(`
    SELECT jl.id,
      jl.line_date as transaction_date,
      coa.code as account_code,
      coa.name as account_name,
      COALESCE(jl.reference_type, '') as transaction_type,
      -- Reference No is the source-document pointer (#id), not the
      -- description — aliasing description here made it duplicate the
      -- remarks column.
      COALESCE('#' || jl.reference_id, '') as reference_no,
      jl.reference_id,
      jl.debit,
      jl.credit,
      SUM(jl.debit - jl.credit) OVER (
        PARTITION BY coa.id ORDER BY jl.line_date, jl.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) as balance,
      jl.description as remarks
    FROM journal_lines jl
    JOIN chart_of_accounts coa ON coa.id = jl.account_id
    WHERE jl.voided = 0 AND jl.line_date BETWEEN ? AND ?
    ORDER BY jl.line_date, jl.id
  `).all(startDate, endDate);
}
/** Former body of getGeneralLedger — kept under its true name. */
function getCustomerLedgerReport(startDate, endDate, db) {
    return db.prepare(`
    SELECT * FROM customer_ledger WHERE transaction_date BETWEEN ? AND ? ORDER BY transaction_date, id
  `).all(startDate, endDate);
}
/** Batches carrying an expiry_date with stock remaining, classified as
 * expired / expiring (within `thresholdDays`) / normal. Backs
 * GET /reports/expiry. */
function getExpiryReport(db, opts = {}) {
    const threshold = opts.thresholdDays ?? 30;
    const rows = db.prepare(`
    SELECT sb.id, i.id as item_id, i.item_code, i.item_name, sb.batch_no,
      w.id as warehouse_id, w.warehouse_name,
      sb.quantity_remaining, sb.unit_cost, sb.received_date,
      date(sb.expiry_date) as expiry_date,
      CAST(julianday(sb.expiry_date) - julianday(date('now', 'localtime')) AS INTEGER) as days_remaining,
      ${columnExistsSafe(db, 'stock_batches', 'halted') ? 'sb.halted' : '0'} as halted
    FROM stock_batches sb
    JOIN items i ON sb.item_id = i.id
    JOIN warehouses w ON sb.warehouse_id = w.id
    WHERE sb.quantity_remaining > 0 AND sb.expiry_date IS NOT NULL
      ${opts.warehouseId ? 'AND sb.warehouse_id = @warehouseId' : ''}
    ORDER BY sb.expiry_date ASC
  `).all(opts.warehouseId ? { warehouseId: opts.warehouseId } : {});
    const classified = rows.map((r) => ({
        ...r,
        status: (r.days_remaining < 0 ? 'expired' : r.days_remaining <= threshold ? 'expiring' : 'normal'),
    }));
    if (opts.status && ['expired', 'expiring', 'normal'].includes(opts.status)) {
        return classified.filter((r) => r.status === opts.status);
    }
    return classified;
}
/** Batches expiring within `days` (expired ones first), for the dashboard
 * alert feed. Backs GET /dashboard/expiry-alerts. */
function getExpiryAlerts(db, days) {
    return db.prepare(`
    SELECT i.id as item_id, i.item_name, sb.batch_no,
      w.warehouse_name,
      date(sb.expiry_date) as expiry_date,
      CAST(julianday(sb.expiry_date) - julianday(date('now', 'localtime')) AS INTEGER) as days_remaining
    FROM stock_batches sb
    JOIN items i ON sb.item_id = i.id
    JOIN warehouses w ON sb.warehouse_id = w.id
    WHERE sb.quantity_remaining > 0 AND sb.expiry_date IS NOT NULL
      AND sb.expiry_date <= date('now', 'localtime', '+' || @days || ' days')
    ORDER BY sb.expiry_date ASC
    LIMIT 10
  `).all({ days });
}
/** Guarded column probe for optional schema additions (halted). */
function columnExistsSafe(db, table, column) {
    return db.pragma(`table_info('${table}')`).some(c => c.name === column);
}
function getCashFlow(startDate, endDate, db) {
    // Same money-movement tables as the dashboard cash position
    // (cashService.collectFlows — payments, expenses, salary_payments,
    // purchases) so the two reports agree by construction. The old
    // implementation only read customer_ledger PAYMENT credits and EXPENSE
    // debits, ignoring supplier payments, salaries, refunds and direct
    // purchases, so it systematically undercounted cash out.
    //
    // Period flow = cumulative flows at endDate minus cumulative flows at
    // the day before startDate. collectFlows seeds opening balances as
    // inflow on both sides, so they cancel out and only movements inside
    // the range remain. Summing across all accounts gives the company-wide
    // cash movement.
    const dayBeforeStart = db.prepare(`SELECT date(?, '-1 day') as d`).get(startDate);
    const atEnd = (0, cashService_1.collectFlows)(db, endDate);
    const beforeStart = (0, cashService_1.collectFlows)(db, dayBeforeStart.d);
    let totalInflow = 0;
    let totalOutflow = 0;
    for (const a of cashService_1.CASH_ACCOUNTS) {
        const now = atEnd.get(a.key);
        const earlier = beforeStart.get(a.key);
        totalInflow += now.inflow - earlier.inflow;
        totalOutflow += now.outflow - earlier.outflow;
    }
    return { startDate, endDate, totalInflow, totalOutflow, netCashFlow: totalInflow - totalOutflow };
}
function getTaxSummary(startDate, endDate, db) {
    // report-query-integrity: sum the stored per-line tax_amount instead of
    // re-deriving tax from `amount`, which is tax-INCLUSIVE on
    // quotation-sourced lines (re-deriving taxed the tax).
    return db.prepare(`
    SELECT COALESCE(SUM(ii.tax_amount), 0) as total_tax
    FROM invoice_items ii JOIN invoices i ON ii.invoice_id = i.id
    WHERE i.invoice_date BETWEEN ? AND ? AND ${(0, reportSql_1.NET_REVENUE_STATUS)('i')}
  `).get(startDate, endDate);
}
function getDailySales(startDate, endDate, db) {
    return db.prepare(`
    SELECT invoice_date, COUNT(*) as count, ${(0, reportSql_1.netRevenueSum)()} as total
    FROM invoices WHERE invoice_date BETWEEN ? AND ? AND ${(0, reportSql_1.NET_REVENUE_STATUS)()}
    GROUP BY invoice_date ORDER BY invoice_date
  `).all(startDate, endDate);
}
function getMonthlySales(year, db) {
    return db.prepare(`
    SELECT strftime('%m', invoice_date) as month, COUNT(*) as count, ${(0, reportSql_1.netRevenueSum)()} as total
    FROM invoices WHERE strftime('%Y', invoice_date) = ? AND ${(0, reportSql_1.NET_REVENUE_STATUS)()}
    GROUP BY month ORDER BY month
  `).all(year);
}
function getGrossProfit(startDate, endDate, db) {
    const revenue = db.prepare(`SELECT ${(0, reportSql_1.netRevenueSum)()} as total FROM invoices WHERE invoice_date BETWEEN ? AND ? AND ${(0, reportSql_1.NET_REVENUE_STATUS)()}`).get(startDate, endDate);
    const cogs = (0, reportSql_1.cogsForPeriod)(db, startDate, endDate);
    return { startDate, endDate, revenue: revenue.total, cogs, grossProfit: revenue.total - cogs, margin: revenue.total > 0 ? ((revenue.total - cogs) / revenue.total * 100) : 0 };
}
/**
 * End-of-day cash reconciliation for `date`: for every tracked account
 * (Cash, Bank, Easypaisa, JazzCash, UPaisa) the opening balance, day
 * inflow/outflow/net and the expected (book) closing balance, merged
 * with any previously saved counted amounts and variance.
 */
function getCashReconciliation(db, date) {
    const accounts = (0, cashService_1.getCashAccountTotals)(db, date);
    const savedRows = db.prepare(`
    SELECT account_key, counted_balance, notes, updated_at
    FROM cash_reconciliations
    WHERE reconciliation_date = ?
  `).all(date);
    const savedByKey = new Map(savedRows.map((r) => [r.account_key, r]));
    const rows = accounts.map((a) => {
        const saved = savedByKey.get(a.key);
        const counted = saved && saved.counted_balance !== null && saved.counted_balance !== undefined
            ? Math.round(Number(saved.counted_balance) * 100) / 100
            : null;
        return {
            key: a.key,
            name: a.name,
            opening_balance: a.opening,
            inflow: a.inflow,
            outflow: a.outflow,
            net: a.net,
            expected_balance: a.closing,
            counted_balance: counted,
            variance: counted === null ? null : Math.round((counted - a.closing) * 100) / 100,
            notes: saved?.notes ?? null,
            reconciled: counted !== null,
            reconciled_at: saved?.updated_at ?? null,
        };
    });
    return {
        date,
        accounts: rows,
        totals: {
            total_opening: rows.reduce((s, r) => s + r.opening_balance, 0),
            total_inflow: rows.reduce((s, r) => s + r.inflow, 0),
            total_outflow: rows.reduce((s, r) => s + r.outflow, 0),
            total_closing: rows.reduce((s, r) => s + r.expected_balance, 0),
        },
    };
}
/**
 * Save the counted end-of-day amounts for `date` (upsert per account).
 * Expected balances are snapshotted into the row so the audit trail
 * survives later transactions, and the variance is recomputed against
 * the snapshot. Returns the refreshed reconciliation for the date.
 */
function saveCashReconciliation(db, date, entries, userId) {
    const validKeys = new Set(cashService_1.CASH_ACCOUNTS.map((a) => a.key));
    const expected = new Map((0, cashService_1.getCashAccountTotals)(db, date).map((a) => [a.key, a.closing]));
    const upsert = db.prepare(`
    INSERT INTO cash_reconciliations (
      reconciliation_date, account_key, account_name,
      expected_balance, counted_balance, variance, notes, reconciled_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(reconciliation_date, account_key) DO UPDATE SET
      expected_balance = excluded.expected_balance,
      counted_balance = excluded.counted_balance,
      variance = excluded.variance,
      notes = excluded.notes,
      reconciled_by = excluded.reconciled_by,
      updated_at = CURRENT_TIMESTAMP
  `);
    db.transaction(() => {
        for (const entry of entries) {
            if (!validKeys.has(entry.key)) {
                throw new Error(`Unknown account key: ${entry.key}`);
            }
            const counted = entry.counted_balance === null || entry.counted_balance === undefined
                ? null
                : Math.round(Number(entry.counted_balance) * 100) / 100;
            const accountName = cashService_1.CASH_ACCOUNTS.find((a) => a.key === entry.key).name;
            const expectedBalance = expected.get(entry.key);
            const variance = counted === null ? null : Math.round((counted - expectedBalance) * 100) / 100;
            upsert.run(date, entry.key, accountName, expectedBalance, counted, variance, entry.notes?.trim() ? entry.notes.trim() : null, userId);
        }
    })();
    return getCashReconciliation(db, date);
}
/**
 * GL reconciliation report (ACC-10 short-term, design D8).
 * Per account pairing: the GL balance from journal_lines alongside its
 * operational derivation, plus the delta. Read-only; mutates nothing.
 *
 *   Inventory (1200)  ← stock_batches cost value (+ legacy item stock)
 *   AR (1100)         ← Σ open-invoice balance_amount
 *   AP (2000)         ← Σ latest supplier_ledger running balance
 *   Cash family       ← payment sums per method + opening balances
 */
function getGLReconciliation(asOfDate, db) {
    const acctId = (code) => db.prepare('SELECT id FROM chart_of_accounts WHERE code = ?').get(code)?.id;
    const glBalance = (code) => {
        const id = acctId(code);
        return id ? accountingService_1.default.getAccountBalance(db, id, asOfDate).balance : 0;
    };
    const round = (v) => Number(Math.round(Number(v + 'e+2')) + 'e-2');
    const rows = [];
    // --- Inventory: GL 1200 vs stock_batches cost value ---------------------
    const batchValue = db.prepare(`
    SELECT COALESCE(SUM(quantity_remaining * unit_cost), 0) as v
    FROM stock_batches WHERE quantity_remaining > 0
  `).get();
    const legacyValue = db.prepare(`
    SELECT COALESCE(SUM(i.current_stock * i.standard_cost), 0) as v
    FROM items i
    WHERE i.is_active = 1 AND i.current_stock > 0
      AND NOT EXISTS (SELECT 1 FROM stock_batches sb WHERE sb.item_id = i.id AND sb.quantity_remaining > 0)
  `).get();
    const inventoryOp = round(batchValue.v + legacyValue.v);
    rows.push({
        pairing: 'Inventory',
        account_code: '1200',
        gl_balance: round(glBalance('1200')),
        operational_balance: inventoryOp,
        delta: round(glBalance('1200') - inventoryOp),
    });
    // --- AR: GL 1100 vs open invoice balances --------------------------------
    const arOpRow = db.prepare(`
    SELECT COALESCE(SUM(balance_amount), 0) as total FROM invoices
    WHERE status IN ('Unpaid', 'Partially Paid', 'Overdue', 'Sent')
      AND balance_amount > 0
      AND invoice_date <= ?
  `).get(asOfDate);
    const arOp = round(arOpRow.total);
    rows.push({
        pairing: 'Accounts Receivable',
        account_code: '1100',
        gl_balance: round(glBalance('1100')),
        operational_balance: arOp,
        delta: round(glBalance('1100') - arOp),
    });
    // --- AP: GL 2000 vs latest supplier_ledger positions ----------------------
    const apOpRow = db.prepare(`
    SELECT COALESCE(SUM(balance), 0) as total FROM (
      SELECT sl1.supplier_id, sl1.balance
      FROM supplier_ledger sl1
      WHERE sl1.voided = 0
        AND sl1.id = (
          SELECT MAX(sl2.id) FROM supplier_ledger sl2
          WHERE sl2.supplier_id = sl1.supplier_id AND sl2.voided = 0
        )
    ) WHERE balance > 0
  `).get();
    const apOp = round(apOpRow.total);
    rows.push({
        pairing: 'Accounts Payable',
        account_code: '2000',
        gl_balance: round(glBalance('2000')),
        operational_balance: apOp,
        delta: round(glBalance('2000') - apOp),
    });
    // --- Cash family: GL cash accounts vs opening balances + payment flows ---
    for (const account of cashService_1.CASH_ACCOUNTS) {
        // Operational derivation mirrors getCashAccountTotals:
        // opening seed + cumulative inflows − cumulative outflows.
        const totals = (0, cashService_1.getCashAccountTotals)(db, asOfDate).find(t => t.key === account.key);
        const opBalance = totals ? round(totals.closing) : 0;
        const glCode = { cash: '1000', bank: '1010', easypaisa: '1020', jazzcash: '1030', upaisa: '1040' }[account.key] ?? null;
        const gl = glCode ? round(glBalance(glCode)) : 0;
        if (!glCode)
            continue;
        rows.push({
            pairing: `Cash (${account.name})`,
            account_code: glCode,
            gl_balance: gl,
            operational_balance: opBalance,
            delta: round(gl - opBalance),
        });
    }
    return { as_of_date: asOfDate, pairings: rows };
}
exports.default = {
    getARAgingReport, getAPAgingReport, getCustomerStatements, getTopDebtors, getDSOMetric,
    getReceivablesSummary, getProfitLossReport, getBalanceSheet, getIncomeStatement,
    getTrialBalance, getGeneralLedger, getCustomerLedgerReport, getCashFlow, getTaxSummary, getDailySales, getMonthlySales,
    getGrossProfit, getBatchTraceability,
    getCashReconciliation, saveCashReconciliation,
    getGLReconciliation,
    getExpiryReport, getExpiryAlerts,
};
//# sourceMappingURL=Reports.js.map