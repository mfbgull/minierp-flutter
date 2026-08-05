"use strict";
/**
 * AccountingService
 * -----------------
 * Phase 1 of the GL refactor. Wraps chart-of-accounts-aware operations:
 *   - listing and looking up accounts
 *   - computing account balances (used by the new TB and BS)
 *   - posting multi-line journal entries (with double-entry validation
 *     and an open-period check)
 *   - period open/close
 *
 * Design notes
 *   - This service does NOT replace the old journal_entries table
 *     (single debit_account + single credit_account, TEXT). That table
 *     is still used by postFinancialEntryForAdjustment / production
 *     and by historical rows. New postings can go through either path.
 *   - The new journal_lines table is the canonical home for new
 *     multi-line entries. The reports UNION both sources so the
 *     historical data remains visible.
 *   - No data backfill is performed. The system starts clean from
 *     the moment the new code is in use; historical balances remain
 *     accessible via the non-journal sources used by the BS (AR from
 *     invoices, AP from supplier_ledger, inventory from stock_batches).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AccountingService = void 0;
class AccountingService {
    // ------------------------------------------------------------------
    // Account lookups
    // ------------------------------------------------------------------
    static listAccounts(db, includeInactive = false) {
        const rows = includeInactive
            ? db.prepare(`SELECT * FROM chart_of_accounts ORDER BY code`).all()
            : db.prepare(`SELECT * FROM chart_of_accounts WHERE is_active = 1 ORDER BY code`).all();
        return rows;
    }
    static getAccountByCode(db, code) {
        return db.prepare(`SELECT * FROM chart_of_accounts WHERE code = ?`).get(code);
    }
    static getAccountByTextCode(db, textCode) {
        return db.prepare(`SELECT * FROM chart_of_accounts WHERE text_code = ?`).get(textCode);
    }
    // ------------------------------------------------------------------
    // Balances
    // ------------------------------------------------------------------
    /**
     * Balance for a single chart-of-accounts account, as of asOfDate.
     * Combines:
     *   - journal_lines entries (new, multi-line, account_id-based)
     *   - journal_entries rows where the TEXT account matches this
     *     account's text_code (legacy single-line postings)
     * Returns debit/credit totals and a signed balance. Convention:
     *   for debit-normal accounts (asset, expense) balance = debit - credit
     *   for credit-normal accounts (liability, equity, revenue) balance = credit - debit
     */
    static getAccountBalance(db, accountId, asOfDate) {
        const acct = db.prepare(`SELECT * FROM chart_of_accounts WHERE id = ?`).get(accountId);
        if (!acct) {
            throw new Error(`Account not found: ${accountId}`);
        }
        // New (canonical) postings: journal_lines
        const newRow = db.prepare(`
      SELECT
        COALESCE(SUM(debit), 0) as total_debit,
        COALESCE(SUM(credit), 0) as total_credit
      FROM journal_lines
      WHERE account_id = ?
        AND line_date <= ?
        AND voided = 0
    `).get(accountId, asOfDate);
        // Legacy postings: journal_entries matched by text_code
        let legacyRow = { total_debit: 0, total_credit: 0 };
        if (acct.text_code) {
            legacyRow = db.prepare(`
        SELECT
          COALESCE(SUM(CASE WHEN debit_account = ?  THEN amount ELSE 0 END), 0) as total_debit,
          COALESCE(SUM(CASE WHEN credit_account = ? THEN amount ELSE 0 END), 0) as total_credit
        FROM journal_entries
        WHERE entry_date <= ?
          AND voided = 0
      `).get(acct.text_code, acct.text_code, asOfDate);
        }
        const totalDebit = (newRow.total_debit || 0) + (legacyRow.total_debit || 0);
        const totalCredit = (newRow.total_credit || 0) + (legacyRow.total_credit || 0);
        const balance = acct.normal_balance === 'debit'
            ? totalDebit - totalCredit
            : totalCredit - totalDebit;
        return {
            account_id: acct.id,
            account_code: acct.code,
            account_name: acct.name,
            type: acct.type,
            normal_balance: acct.normal_balance,
            total_debit: totalDebit,
            total_credit: totalCredit,
            balance,
            text_code: acct.text_code
        };
    }
    /**
     * All account balances as of asOfDate. This is the data the
     * (new) trial balance report consumes.
     */
    static getAllAccountBalances(db, asOfDate) {
        const accounts = AccountingService.listAccounts(db);
        return accounts.map(a => AccountingService.getAccountBalance(db, a.id, asOfDate));
    }
    // ------------------------------------------------------------------
    // Posting (multi-line, double-entry)
    // ------------------------------------------------------------------
    /**
     * Post a multi-line journal entry. Validates:
     *   - at least 2 lines
     *   - every line has positive debit XOR positive credit
     *   - total debits == total credits
     *   - entry_date falls within an open accounting period
     *
     * Returns the new journal_entry_id (logical grouping) and totals.
     */
    static postEntry(db, input) {
        if (!input.lines || input.lines.length < 2) {
            throw new Error('A journal entry must have at least 2 lines');
        }
        if (!input.entry_date) {
            throw new Error('entry_date is required');
        }
        // Validate every line
        let totalDebit = 0;
        let totalCredit = 0;
        for (const line of input.lines) {
            const debit = Number(line.debit || 0);
            const credit = Number(line.credit || 0);
            if (debit < 0 || credit < 0) {
                throw new Error(`Line amounts must be non-negative (account ${line.account_id})`);
            }
            if (debit > 0 && credit > 0) {
                throw new Error(`Line must be debit OR credit, not both (account ${line.account_id})`);
            }
            if (debit === 0 && credit === 0) {
                throw new Error(`Line must have a non-zero amount (account ${line.account_id})`);
            }
            totalDebit += debit;
            totalCredit += credit;
            // Verify the account exists
            const exists = db.prepare(`SELECT 1 FROM chart_of_accounts WHERE id = ?`).get(line.account_id);
            if (!exists) {
                throw new Error(`Account not found: ${line.account_id}`);
            }
        }
        // Reject unbalanced entries (within rounding tolerance)
        if (Math.abs(totalDebit - totalCredit) > 0.01) {
            throw new Error(`Unbalanced journal entry: total debit ${totalDebit.toFixed(2)} != ` +
                `total credit ${totalCredit.toFixed(2)}`);
        }
        // Period check
        const openPeriod = db.prepare(`
      SELECT id, period_name FROM accounting_periods
      WHERE status = 'open'
        AND start_date <= ? AND end_date >= ?
    `).get(input.entry_date, input.entry_date);
        if (!openPeriod) {
            throw new Error(`No open accounting period covers ${input.entry_date}. ` +
                `Open a period in accounting_periods before posting.`);
        }
        // Insert. We use a single transaction so all lines commit or none.
        const insertLine = db.prepare(`
      INSERT INTO journal_lines (
        journal_entry_id, account_id, debit, credit, description,
        line_date, reference_type, reference_id, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
        // Group id: a simple monotonic counter. We use the highest
        // existing journal_entry_id + 1 to keep it stable across the
        // whole install. For a fresh install with no journal_lines,
        // this is 1. If journal_lines has been used, this is max+1.
        const lastEntry = db.prepare(`SELECT COALESCE(MAX(journal_entry_id), 0) as last_id FROM journal_lines`).get();
        const entryId = lastEntry.last_id + 1;
        const trx = db.transaction(() => {
            for (const line of input.lines) {
                insertLine.run(entryId, line.account_id, Number(line.debit || 0), Number(line.credit || 0), line.description || null, input.entry_date, input.reference_type || null, input.reference_id || null, input.created_by || null);
            }
        });
        trx();
        return {
            journal_entry_id: entryId,
            line_count: input.lines.length,
            total_debit: totalDebit,
            total_credit: totalCredit
        };
    }
    // ------------------------------------------------------------------
    // Convenience helpers for transactional postings
    // ------------------------------------------------------------------
    /**
     * Post a sales invoice. Dr Accounts Receivable, Cr Sales Revenue (net),
     * and when taxAmount > 0, additionally Cr Tax Payable (tax).
     *
     * When taxAmount is omitted or 0, the full totalAmount goes to
     * Sales Revenue (backward-compatible 2-line entry).
     * When taxAmount > 0, the net revenue is totalAmount - taxAmount.
     *
     * Returns the posted entry's journal_entry_id, or null if the
     * total is zero (nothing to post).
     */
    static postInvoiceEntry(db, args) {
        if (!args.totalAmount || args.totalAmount <= 0)
            return null;
        const ar = AccountingService.getAccountByCode(db, '1100');
        const revenue = AccountingService.getAccountByCode(db, '4000');
        if (!ar || !revenue) {
            throw new Error('Chart of accounts is missing required accounts: 1100 (AR) or 4000 (Sales Revenue)');
        }
        const taxAmount = Number(args.taxAmount) || 0;
        const netAmount = args.totalAmount - taxAmount;
        if (taxAmount > 0) {
            const taxPayable = AccountingService.getAccountByCode(db, '2100');
            if (!taxPayable) {
                throw new Error('Chart of accounts is missing required account: 2100 (Tax Payable)');
            }
            return AccountingService.postEntry(db, {
                entry_date: args.invoiceDate,
                description: `Sales invoice ${args.invoiceNo} — total ${args.totalAmount.toFixed(2)} (net ${netAmount.toFixed(2)} + tax ${taxAmount.toFixed(2)})`,
                reference_type: 'INVOICE',
                reference_id: args.invoiceId,
                created_by: args.userId,
                lines: [
                    { account_id: ar.id, debit: args.totalAmount, description: `AR for ${args.invoiceNo}` },
                    { account_id: revenue.id, credit: netAmount, description: `Sales revenue for ${args.invoiceNo}` },
                    { account_id: taxPayable.id, credit: taxAmount, description: `Sales tax on ${args.invoiceNo}` },
                ],
            });
        }
        // No tax — backward-compatible 2-line entry
        return AccountingService.postEntry(db, {
            entry_date: args.invoiceDate,
            description: `Sales invoice ${args.invoiceNo} — total ${args.totalAmount.toFixed(2)}`,
            reference_type: 'INVOICE',
            reference_id: args.invoiceId,
            created_by: args.userId,
            lines: [
                { account_id: ar.id, debit: args.totalAmount, description: `AR for ${args.invoiceNo}` },
                { account_id: revenue.id, credit: args.totalAmount, description: `Sales revenue for ${args.invoiceNo}` },
            ],
        });
    }
    /**
     * Post a payment received from a customer. Dr Cash (or Bank, by
     * payment method), Cr Accounts Receivable.
     */
    static postPaymentEntry(db, args) {
        if (!args.amount || args.amount <= 0)
            return null;
        const cashCode = AccountingService._cashOrBankAccountCode(args.paymentMethod);
        const cash = AccountingService.getAccountByCode(db, cashCode);
        const ar = AccountingService.getAccountByCode(db, '1100');
        if (!cash || !ar) {
            throw new Error(`Chart of accounts is missing required accounts: ${cashCode} or 1100 (AR)`);
        }
        return AccountingService.postEntry(db, {
            entry_date: args.paymentDate,
            description: `Payment ${args.paymentNo} — ${args.amount.toFixed(2)} (${cashCode})`,
            reference_type: 'PAYMENT',
            reference_id: args.paymentId,
            created_by: args.userId,
            lines: [
                { account_id: cash.id, debit: args.amount, description: `Cash/Bank in for ${args.paymentNo}` },
                { account_id: ar.id, credit: args.amount, description: `AR reduced for ${args.paymentNo}` },
            ],
        });
    }
    /**
     * Post a purchase order commitment. Dr Inventory Asset, Cr Accounts
     * Payable. Posted at PO creation in this implementation; in
     * stricter systems you'd post at goods receipt instead. Either
     * approach is acceptable as long as the trial balance is consistent
     * (PO postings here are paired with the supplier_ledger running
     * balance that drives the BS AP line).
     */
    static postPurchaseOrderEntry(db, args) {
        if (!args.totalAmount || args.totalAmount <= 0)
            return null;
        const inventory = AccountingService.getAccountByCode(db, '1200');
        const ap = AccountingService.getAccountByCode(db, '2000');
        if (!inventory || !ap) {
            throw new Error('Chart of accounts is missing required accounts: 1200 (Inventory Asset) or 2000 (AP)');
        }
        return AccountingService.postEntry(db, {
            entry_date: args.poDate,
            description: `Purchase order ${args.poNo} — total ${args.totalAmount.toFixed(2)}`,
            reference_type: 'PURCHASE_ORDER',
            reference_id: args.purchaseOrderId,
            created_by: args.userId,
            lines: [
                { account_id: inventory.id, debit: args.totalAmount, description: `Inventory received against ${args.poNo}` },
                { account_id: ap.id, credit: args.totalAmount, description: `AP created for ${args.poNo}` },
            ],
        });
    }
    /**
     * Map a payment method string to a chart-of-accounts code. Cash
     * defaults to 1000 (Cash), everything else to 1010 (Bank). This
     * matches the seed data; if you add more accounts (e.g. mobile
     * money, PayPal), extend this method.
     */
    static _cashOrBankAccountCode(paymentMethod) {
        if (!paymentMethod)
            return '1000';
        const m = paymentMethod.toLowerCase().trim();
        if (m === 'cash')
            return '1000';
        return '1010';
    }
    // ------------------------------------------------------------------
    // COGS posting
    // ------------------------------------------------------------------
    /**
     * Post COGS (Cost of Goods Sold) for a sales invoice.
     * Dr COGS (5000), Cr Inventory Asset (1200) at the actual FIFO cost.
     *
     * Must be called AFTER stock movements have been recorded so that
     * the caller can provide the total COGS amount computed from
     * consumption (sum of consumed qty * unit cost across all batches).
     */
    static postCOGSEntry(db, args) {
        if (!args.cogsAmount || args.cogsAmount <= 0)
            return null;
        const cogs = AccountingService.getAccountByCode(db, '5000');
        const inventory = AccountingService.getAccountByCode(db, '1200');
        if (!cogs || !inventory) {
            throw new Error('Chart of accounts is missing required accounts: ' +
                '5000 (COGS) or 1200 (Inventory Asset)');
        }
        return AccountingService.postEntry(db, {
            entry_date: args.invoiceDate,
            description: `COGS for Invoice ${args.invoiceNo} — ${args.cogsAmount.toFixed(2)}`,
            reference_type: 'INVOICE',
            reference_id: args.invoiceId,
            created_by: args.userId,
            lines: [
                { account_id: cogs.id, debit: args.cogsAmount, description: `COGS for ${args.invoiceNo}` },
                { account_id: inventory.id, credit: args.cogsAmount, description: `Inventory relieved for ${args.invoiceNo}` },
            ],
        });
    }
    // ------------------------------------------------------------------
    // Return / reversal posting
    // ------------------------------------------------------------------
    /**
     * Post COGS reversal for returned items. Reverses what postCOGSEntry
     * originally posted:
     *   Dr Inventory Asset (1200) — restore inventory value
     *   Cr COGS (5000) — reverse cost of goods sold
     *
     * Must be called with the actual FIFO cost of the returned items.
     */
    static postCOGSReversalEntry(db, args) {
        if (!args.cogsAmount || args.cogsAmount <= 0)
            return null;
        const inventory = AccountingService.getAccountByCode(db, '1200');
        const cogs = AccountingService.getAccountByCode(db, '5000');
        if (!inventory || !cogs) {
            throw new Error('Chart of accounts is missing required accounts: ' +
                '1200 (Inventory Asset) or 5000 (COGS)');
        }
        return AccountingService.postEntry(db, {
            entry_date: args.entryDate,
            description: `COGS reversal for Invoice return ${args.invoiceNo} — ${args.cogsAmount.toFixed(2)}`,
            reference_type: 'INVOICE_RETURN',
            reference_id: args.invoiceId,
            created_by: args.userId,
            lines: [
                { account_id: inventory.id, debit: args.cogsAmount, description: `Inventory restored for return of ${args.invoiceNo}` },
                { account_id: cogs.id, credit: args.cogsAmount, description: `COGS reversed for return of ${args.invoiceNo}` },
            ],
        });
    }
    /**
     * Post GL reversal for a sales invoice return, with optional restocking fee.
     * Reverses what postInvoiceEntry originally posted:
     *   Cr AR (1100) — reduce receivable by NET (gross - deduction)
     *   Dr Sales Returns (4100) — full gross return (contra-revenue)
     *   Dr Tax Payable (2100) — reverse tax liability (if any)
     *   Cr Restocking Fee Income (4150) — fee the shop keeps (if deduction > 0)
     *
     * Returns the posted entry's journal_entry_id, or null if total is zero.
     */
    static postInvoiceReturnEntry(db, args) {
        if (!args.grossReturn || args.grossReturn <= 0)
            return null;
        const ar = AccountingService.getAccountByCode(db, '1100');
        const salesReturns = AccountingService.getAccountByCode(db, '4100');
        if (!ar || !salesReturns) {
            throw new Error('Chart of accounts is missing required accounts: 1100 (AR) or 4100 (Sales Returns)');
        }
        const taxAmount = Number(args.taxAmount) || 0;
        const deduction = Number(args.deduction) || 0;
        const grossAmount = args.grossReturn;
        const netAmount = args.netReturn; // gross - deduction (further reduced by tax if applicable — handled below)
        let restockingFeeAcct;
        if (deduction > 0) {
            restockingFeeAcct = AccountingService.getAccountByCode(db, '4150');
            if (!restockingFeeAcct) {
                throw new Error('Chart of accounts is missing required account: 4150 (Restocking Fee Income)');
            }
        }
        // Build lines array
        if (taxAmount > 0) {
            const taxPayable = AccountingService.getAccountByCode(db, '2100');
            if (!taxPayable) {
                throw new Error('Chart of accounts is missing required account: 2100 (Tax Payable)');
            }
            const lines = [];
            // Cr AR by netReturn (what AR is actually reduced by)
            lines.push({
                account_id: ar.id,
                debit: 0,
                credit: netAmount,
                description: `AR reduced for return of ${args.invoiceNo}`,
            });
            // Dr Sales Returns by grossReturn (full reversal of revenue before any deduction)
            lines.push({
                account_id: salesReturns.id,
                debit: grossAmount,
                credit: 0,
                description: `Sales returns contra-revenue for ${args.invoiceNo}`,
            });
            // Dr Tax Payable by taxAmount
            lines.push({
                account_id: taxPayable.id,
                debit: taxAmount,
                credit: 0,
                description: `Tax reversal for return of ${args.invoiceNo}`,
            });
            // Cr Restocking Fee Income by deduction (if any)
            if (restockingFeeAcct && deduction > 0) {
                lines.push({
                    account_id: restockingFeeAcct.id,
                    debit: 0,
                    credit: deduction,
                    description: `Restocking fee on return of ${args.invoiceNo}`,
                });
            }
            return AccountingService.postEntry(db, {
                entry_date: args.invoiceDate,
                description: `Sales return for ${args.invoiceNo} — ${grossAmount.toFixed(2)} gross, ${netAmount.toFixed(2)} net${deduction > 0 ? `, fee ${deduction.toFixed(2)}` : ''}${taxAmount > 0 ? `, tax ${taxAmount.toFixed(2)}` : ''}`,
                reference_type: 'INVOICE_RETURN',
                reference_id: args.invoiceId,
                created_by: args.userId,
                lines,
            });
        }
        // No tax — 2 or 3 line reversal depending on deduction
        const lines = [];
        // Cr AR by netReturn
        lines.push({
            account_id: ar.id,
            debit: 0,
            credit: netAmount,
            description: `AR reduced for return of ${args.invoiceNo}`,
        });
        // Dr Sales Returns by grossReturn
        lines.push({
            account_id: salesReturns.id,
            debit: grossAmount,
            credit: 0,
            description: `Sales returns contra-revenue for ${args.invoiceNo}`,
        });
        // Cr Restocking Fee Income by deduction (if any)
        if (restockingFeeAcct && deduction > 0) {
            lines.push({
                account_id: restockingFeeAcct.id,
                debit: 0,
                credit: deduction,
                description: `Restocking fee on return of ${args.invoiceNo}`,
            });
        }
        return AccountingService.postEntry(db, {
            entry_date: args.invoiceDate,
            description: `Sales return for ${args.invoiceNo} — ${grossAmount.toFixed(2)} gross, ${netAmount.toFixed(2)} net${deduction > 0 ? `, fee ${deduction.toFixed(2)}` : ''}`,
            reference_type: 'INVOICE_RETURN',
            reference_id: args.invoiceId,
            created_by: args.userId,
            lines,
        });
    }
    /**
     * Post GL reversal for a purchase return.
     * Reverses what postPurchaseOrderEntry originally posted:
     *   Dr AP (2000) — reduce liability
     *   Cr Inventory Asset (1200) — remove returned stock value
     *
     * Returns the posted entry's journal_entry_id, or null if total is zero.
     */
    static postPurchaseReturnEntry(db, args) {
        if (!args.returnAmount || args.returnAmount <= 0)
            return null;
        const inventory = AccountingService.getAccountByCode(db, '1200');
        const ap = AccountingService.getAccountByCode(db, '2000');
        if (!inventory || !ap) {
            throw new Error('Chart of accounts is missing required accounts: 1200 (Inventory Asset) or 2000 (AP)');
        }
        return AccountingService.postEntry(db, {
            entry_date: args.returnDate,
            description: `Purchase return for ${args.purchaseNo} — ${args.returnAmount.toFixed(2)}`,
            reference_type: 'PURCHASE_RETURN',
            reference_id: args.purchaseId,
            created_by: args.userId,
            lines: [
                { account_id: ap.id, debit: args.returnAmount, description: `AP reduced for return of ${args.purchaseNo}` },
                { account_id: inventory.id, credit: args.returnAmount, description: `Inventory removed for return of ${args.purchaseNo}` },
            ],
        });
    }
    /**
     * Post GL entry for a refund paid out to a customer.
     * Reverses the cash impact of a return when the customer gets money back:
     *   Dr Accounts Receivable (1100) — bring AR back to $0 (reverses the credit balance)
     *   Cr Cash/Bank (1000/1010) — cash paid out
     *
     * This is paired with postInvoiceReturnEntry which already did:
     *   Cr AR / Dr Sales Returns
     *
     * The combined effect for a refund is:
     *   Dr Sales Returns (revenue contra)
     *   Cr Cash/Bank (cash paid out)
     *   (AR goes from $0 -> credit -> back to $0)
     */
    static postRefundEntry(db, args) {
        if (!args.amount || args.amount <= 0)
            return null;
        const cashCode = AccountingService._cashOrBankAccountCode(args.paymentMethod);
        const cash = AccountingService.getAccountByCode(db, cashCode);
        const ar = AccountingService.getAccountByCode(db, '1100');
        if (!cash || !ar) {
            throw new Error(`Chart of accounts is missing required accounts: ${cashCode} or 1100 (AR)`);
        }
        return AccountingService.postEntry(db, {
            entry_date: args.refundDate,
            description: `Refund ${args.refundPaymentNo} — ${args.amount.toFixed(2)} (${cashCode})`,
            reference_type: 'REFUND',
            reference_id: args.refundPaymentId,
            created_by: args.userId,
            lines: [
                { account_id: ar.id, debit: args.amount, description: `AR adjusted for refund ${args.refundPaymentNo}` },
                { account_id: cash.id, credit: args.amount, description: `Cash/Bank out for refund ${args.refundPaymentNo}` },
            ],
        });
    }
    // ------------------------------------------------------------------
    // Void / reversal
    // ------------------------------------------------------------------
    /**
     * Void journal lines by reference type + ID. Sets voided = 1 so that
     * balance queries (which filter AND voided = 0) will exclude them.
     * This is the canonical cleanup path when an invoice or payment is
     * deleted — it preserves the audit trail while excluding the stale
     * lines from reports.
     *
     * Safe to call even if no matching lines exist (no-op). Returns the
     * number of lines voided.
     */
    static voidJournalLinesByReference(db, referenceType, referenceId) {
        const result = db.prepare(`
      UPDATE journal_lines
      SET voided = 1
      WHERE reference_type = ?
        AND reference_id = ?
        AND voided = 0
    `).run(referenceType, referenceId);
        return result.changes;
    }
    // ------------------------------------------------------------------
    // Period management
    // ------------------------------------------------------------------
    static listPeriods(db) {
        return db.prepare(`
      SELECT id, period_name, start_date, end_date, status
      FROM accounting_periods
      ORDER BY start_date DESC
    `).all();
    }
    static closePeriod(db, periodId, closedBy) {
        db.prepare(`
      UPDATE accounting_periods
      SET status = 'closed', closed_at = CURRENT_TIMESTAMP, closed_by = ?
      WHERE id = ? AND status = 'open'
    `).run(closedBy || null, periodId);
    }
    static openPeriod(db, periodName, startDate, endDate) {
        // Will throw on UNIQUE collision if period_name already exists
        const result = db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES (?, ?, ?, 'open')
    `).run(periodName, startDate, endDate);
        return Number(result.lastInsertRowid);
    }
    // ------------------------------------------------------------------
    // Salary payment posting
    // ------------------------------------------------------------------
    /**
     * Post a salary payment. Dr Wages & Salaries (6100), Cr Cash/Bank.
     */
    static postSalaryEntry(db, args) {
        if (!args.amount || args.amount <= 0)
            return null;
        const wageAcct = AccountingService.getAccountByCode(db, '6100');
        const cashCode = AccountingService._cashOrBankAccountCode(args.paymentMethod);
        const cashAcct = AccountingService.getAccountByCode(db, cashCode);
        if (!wageAcct || !cashAcct) {
            throw new Error(`Chart of accounts is missing: 6100 (Wages & Salaries) or ${cashCode}`);
        }
        return AccountingService.postEntry(db, {
            entry_date: args.paymentDate,
            description: `Salary payment to ${args.employeeName} (${args.employeeCode}) — ${args.amount.toFixed(2)}`,
            reference_type: 'SALARY_PAYMENT',
            reference_id: args.salaryPaymentId,
            created_by: args.userId,
            lines: [
                { account_id: wageAcct.id, debit: args.amount, description: `Salary for ${args.employeeCode}` },
                { account_id: cashAcct.id, credit: args.amount, description: `Salary paid to ${args.employeeCode}` },
            ],
        });
    }
    // ------------------------------------------------------------------
    // Report helpers
    // ------------------------------------------------------------------
    /**
     * Sum of debits minus credits (raw, not signed) across an account.
     * Useful when callers want a raw "debit total" without the
     * signed-balance convention applied.
     */
    static getAccountRawTotals(db, accountId, asOfDate) {
        const bal = AccountingService.getAccountBalance(db, accountId, asOfDate);
        return { debit: bal.total_debit, credit: bal.total_credit };
    }
}
exports.AccountingService = AccountingService;
exports.default = AccountingService;
//# sourceMappingURL=accountingService.js.map