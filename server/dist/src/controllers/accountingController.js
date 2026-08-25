"use strict";
/**
 * Accounting Controller
 * ---------------------
 * REST surface for the chart of accounts and accounting periods.
 *
 * Layering (per project AGENTS.md):
 *   - request validation + response formatting lives here
 *   - all database access is delegated to models / services
 *   - no SQL strings, no business logic
 *
 * Response shape uses the standard helpers in utils/apiResponse:
 *   { success: true, data: ... }      on success
 *   { success: false, error: {...} }  on failure
 *
 * Auth:
 *   - All endpoints require a valid token (authenticateToken).
 *   - State-changing endpoints (open / close period) require admin.
 *   - Read endpoints are available to any authenticated user.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = __importDefault(require("../config/database"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
const Period_1 = __importDefault(require("../models/Period"));
const Reports_1 = __importDefault(require("../models/Reports"));
const activityLogger_1 = require("../services/activityLogger");
const logger_1 = __importDefault(require("../utils/logger"));
const queryUtils_1 = require("../utils/queryUtils");
const apiResponse_1 = require("../utils/apiResponse");
const PERIOD_ENTITY = 'ACCOUNTING_PERIOD';
// ============================================================================
// Helpers
// ============================================================================
/** YYYY-MM-DD validator. Accepts only the ISO date format used in the DB. */
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
function isValidIsoDate(s) {
    return typeof s === 'string' && ISO_DATE_RE.test(s) && !isNaN(Date.parse(s));
}
// ============================================================================
// Account endpoints
// ============================================================================
/**
 * GET /api/accounting/accounts[?includeInactive=true]
 * List all accounts in the chart of accounts.
 */
function listAccounts(req, res) {
    try {
        const includeInactive = req.query.includeInactive === 'true';
        const accounts = accountingService_1.default.listAccounts(database_1.default, includeInactive);
        (0, apiResponse_1.sendSuccess)(res, { count: accounts.length, accounts });
    }
    catch (error) {
        logger_1.default.error('List accounts error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch accounts');
    }
}
/**
 * GET /api/accounting/accounts/:code
 * Look up a single account by its code (e.g. "1100", "4000").
 */
function getAccount(req, res) {
    try {
        const code = (0, queryUtils_1.getRouteParam)(req.params.code);
        if (!code) {
            (0, apiResponse_1.sendBadRequest)(res, 'Account code is required');
            return;
        }
        const account = accountingService_1.default.getAccountByCode(database_1.default, code);
        if (!account) {
            (0, apiResponse_1.sendNotFound)(res, `Account ${code}`);
            return;
        }
        (0, apiResponse_1.sendSuccess)(res, account);
    }
    catch (error) {
        logger_1.default.error('Get account error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch account');
    }
}
/**
 * GET /api/accounting/accounts/balances[?asOfDate=YYYY-MM-DD]
 * Trial-balance data: every account's debit / credit / signed balance
 * as of the given date (defaults to today).
 */
function listAccountBalances(req, res) {
    try {
        const asOfDate = (0, queryUtils_1.getQueryParam)(req.query.asOfDate) ?? new Date().toISOString().slice(0, 10);
        if (!isValidIsoDate(asOfDate)) {
            (0, apiResponse_1.sendBadRequest)(res, 'asOfDate must be a valid YYYY-MM-DD date');
            return;
        }
        const balances = accountingService_1.default.getAllAccountBalances(database_1.default, asOfDate);
        const totalDebit = balances.reduce((s, b) => s + b.total_debit, 0);
        const totalCredit = balances.reduce((s, b) => s + b.total_credit, 0);
        (0, apiResponse_1.sendSuccess)(res, {
            asOfDate,
            accounts: balances,
            totalDebit,
            totalCredit,
            balanced: Math.abs(totalDebit - totalCredit) < 0.01,
        });
    }
    catch (error) {
        logger_1.default.error('List account balances error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch account balances');
    }
}
/**
 * GET /api/accounting/accounts/:code/balance[?asOfDate=YYYY-MM-DD]
 * Balance for a single account as of a given date.
 */
function getAccountBalance(req, res) {
    try {
        const code = (0, queryUtils_1.getRouteParam)(req.params.code);
        if (!code) {
            (0, apiResponse_1.sendBadRequest)(res, 'Account code is required');
            return;
        }
        const account = accountingService_1.default.getAccountByCode(database_1.default, code);
        if (!account) {
            (0, apiResponse_1.sendNotFound)(res, `Account ${code}`);
            return;
        }
        const asOfDate = (0, queryUtils_1.getQueryParam)(req.query.asOfDate) ?? new Date().toISOString().slice(0, 10);
        if (!isValidIsoDate(asOfDate)) {
            (0, apiResponse_1.sendBadRequest)(res, 'asOfDate must be a valid YYYY-MM-DD date');
            return;
        }
        const balance = accountingService_1.default.getAccountBalance(database_1.default, account.id, asOfDate);
        (0, apiResponse_1.sendSuccess)(res, balance);
    }
    catch (error) {
        logger_1.default.error('Get account balance error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch account balance');
    }
}
/**
 * GET /api/accounting/reconciliation[?asOfDate=YYYY-MM-DD]
 * GL vs operational balances per pairing (inventory, AR, AP, cash
 * family). Read-only; makes every residual GL defect measurable.
 */
function getReconciliation(req, res) {
    try {
        const asOfDate = (0, queryUtils_1.getQueryParam)(req.query.asOfDate) ?? new Date().toISOString().slice(0, 10);
        if (!isValidIsoDate(asOfDate)) {
            (0, apiResponse_1.sendBadRequest)(res, 'asOfDate must be a valid YYYY-MM-DD date');
            return;
        }
        const report = Reports_1.default.getGLReconciliation(asOfDate, database_1.default);
        (0, apiResponse_1.sendSuccess)(res, report);
    }
    catch (error) {
        logger_1.default.error('GL reconciliation error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to build reconciliation report');
    }
}
// ============================================================================
// Period endpoints
// ============================================================================
/**
 * GET /api/accounting/periods
 * List all accounting periods, newest first.
 */
function listPeriods(req, res) {
    try {
        const periods = Period_1.default.getAll(database_1.default);
        (0, apiResponse_1.sendSuccess)(res, { count: periods.length, periods });
    }
    catch (error) {
        logger_1.default.error('List periods error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch periods');
    }
}
/**
 * GET /api/accounting/periods/current
 * The open period covering today, if any.
 */
function getCurrentPeriod(req, res) {
    try {
        const period = Period_1.default.getCurrentOpen(database_1.default);
        if (!period) {
            (0, apiResponse_1.sendSuccess)(res, { current: null, message: 'No open period covers today' });
            return;
        }
        (0, apiResponse_1.sendSuccess)(res, { current: period });
    }
    catch (error) {
        logger_1.default.error('Get current period error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch current period');
    }
}
/**
 * GET /api/accounting/periods/:id
 * Single period lookup.
 */
function getPeriod(req, res) {
    try {
        const idStr = (0, queryUtils_1.getRouteParam)(req.params.id);
        const id = parseInt(idStr, 10);
        if (!Number.isFinite(id) || id <= 0) {
            (0, apiResponse_1.sendBadRequest)(res, 'Period id must be a positive integer');
            return;
        }
        const period = Period_1.default.getById(database_1.default, id);
        if (!period) {
            (0, apiResponse_1.sendNotFound)(res, `Period ${id}`);
            return;
        }
        (0, apiResponse_1.sendSuccess)(res, period);
    }
    catch (error) {
        logger_1.default.error('Get period error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to fetch period');
    }
}
/**
 * POST /api/accounting/periods
 * Open a new period. Admin only.
 *
 * Body: { period_name: string, start_date: YYYY-MM-DD, end_date: YYYY-MM-DD }
 */
function openPeriod(req, res) {
    try {
        if (req.user?.role !== 'admin') {
            (0, apiResponse_1.sendForbidden)(res, 'Only admins can open accounting periods');
            return;
        }
        const { period_name, start_date, end_date } = req.body;
        if (typeof period_name !== 'string' || !period_name.trim()) {
            (0, apiResponse_1.sendBadRequest)(res, 'period_name is required');
            return;
        }
        if (!isValidIsoDate(start_date)) {
            (0, apiResponse_1.sendBadRequest)(res, 'start_date must be a valid YYYY-MM-DD date');
            return;
        }
        if (!isValidIsoDate(end_date)) {
            (0, apiResponse_1.sendBadRequest)(res, 'end_date must be a valid YYYY-MM-DD date');
            return;
        }
        if (start_date > end_date) {
            (0, apiResponse_1.sendBadRequest)(res, 'start_date must be on or before end_date');
            return;
        }
        // Reject overlap with an existing open period. Closed periods are
        // allowed to overlap (a period can be re-opened for back-fills of
        // older transactions; overlap with an open one would be ambiguous).
        const overlaps = database_1.default
            .prepare(`
        SELECT id, period_name FROM accounting_periods
        WHERE status = 'open'
          AND NOT (end_date < ? OR start_date > ?)
      `)
            .get(start_date, end_date);
        if (overlaps) {
            (0, apiResponse_1.sendConflict)(res, `Date range overlaps open period "${overlaps.period_name}" (id ${overlaps.id})`);
            return;
        }
        const created = Period_1.default.openPeriod(database_1.default, {
            period_name: period_name.trim(),
            start_date,
            end_date,
        });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, PERIOD_ENTITY, created.id, `Opened accounting period ${created.period_name} (${created.start_date} → ${created.end_date})`, req.user?.id, { period_name: created.period_name, start_date, end_date });
        (0, apiResponse_1.sendCreated)(res, created);
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to open period';
        if (message.includes('UNIQUE')) {
            (0, apiResponse_1.sendConflict)(res, 'A period with that name already exists');
            return;
        }
        logger_1.default.error('Open period error:', error);
        (0, apiResponse_1.sendInternalError)(res, message);
    }
}
/**
 * POST /api/accounting/periods/:id/close
 * Close an open period. Idempotent — closing an already-closed period
 * is a no-op and returns 200 with the existing state.
 * Admin only.
 */
function closePeriod(req, res) {
    try {
        if (req.user?.role !== 'admin') {
            (0, apiResponse_1.sendForbidden)(res, 'Only admins can close accounting periods');
            return;
        }
        const idStr = (0, queryUtils_1.getRouteParam)(req.params.id);
        const id = parseInt(idStr, 10);
        if (!Number.isFinite(id) || id <= 0) {
            (0, apiResponse_1.sendBadRequest)(res, 'Period id must be a positive integer');
            return;
        }
        const existing = Period_1.default.getById(database_1.default, id);
        if (!existing) {
            (0, apiResponse_1.sendNotFound)(res, `Period ${id}`);
            return;
        }
        if (existing.status === 'closed') {
            (0, apiResponse_1.sendSuccess)(res, { period: existing, alreadyClosed: true });
            return;
        }
        Period_1.default.closePeriod(database_1.default, id, req.user?.id ?? null);
        const updated = Period_1.default.getById(database_1.default, id);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, PERIOD_ENTITY, updated.id, `Closed accounting period ${updated.period_name}`, req.user?.id, { period_name: updated.period_name, closed_at: updated.closed_at });
        (0, apiResponse_1.sendSuccess)(res, { period: updated, alreadyClosed: false });
    }
    catch (error) {
        logger_1.default.error('Close period error:', error);
        (0, apiResponse_1.sendInternalError)(res, 'Failed to close period');
    }
}
// ============================================================================
// Exports
// ============================================================================
exports.default = {
    // accounts
    listAccounts,
    getAccount,
    listAccountBalances,
    getAccountBalance,
    // reconciliation
    getReconciliation,
    // periods
    listPeriods,
    getCurrentPeriod,
    getPeriod,
    openPeriod,
    closePeriod,
};
