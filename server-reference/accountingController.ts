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

import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import PeriodModel from '../models/Period';
import { logCRUD, ActionType } from '../services/activityLogger';
import logger from '../utils/logger';
import { getQueryParam, getRouteParam } from '../utils/queryUtils';
import {
  sendSuccess,
  sendCreated,
  sendBadRequest,
  sendNotFound,
  sendConflict,
  sendInternalError,
  sendForbidden,
} from '../utils/apiResponse';

const PERIOD_ENTITY = 'ACCOUNTING_PERIOD';

// ============================================================================
// Helpers
// ============================================================================

/** YYYY-MM-DD validator. Accepts only the ISO date format used in the DB. */
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isValidIsoDate(s: unknown): s is string {
  return typeof s === 'string' && ISO_DATE_RE.test(s) && !isNaN(Date.parse(s));
}

// ============================================================================
// Account endpoints
// ============================================================================

/**
 * GET /api/accounting/accounts[?includeInactive=true]
 * List all accounts in the chart of accounts.
 */
function listAccounts(req: AuthRequest, res: Response): void {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const accounts = AccountingService.listAccounts(db, includeInactive);
    sendSuccess(res, { count: accounts.length, accounts });
  } catch (error: unknown) {
    logger.error('List accounts error:', error);
    sendInternalError(res, 'Failed to fetch accounts');
  }
}

/**
 * GET /api/accounting/accounts/:code
 * Look up a single account by its code (e.g. "1100", "4000").
 */
function getAccount(req: AuthRequest, res: Response): void {
  try {
    const code = getRouteParam(req.params.code);
    if (!code) { sendBadRequest(res, 'Account code is required'); return; }

    const account = AccountingService.getAccountByCode(db, code);
    if (!account) { sendNotFound(res, `Account ${code}`); return; }

    sendSuccess(res, account);
  } catch (error: unknown) {
    logger.error('Get account error:', error);
    sendInternalError(res, 'Failed to fetch account');
  }
}

/**
 * GET /api/accounting/accounts/balances[?asOfDate=YYYY-MM-DD]
 * Trial-balance data: every account's debit / credit / signed balance
 * as of the given date (defaults to today).
 */
function listAccountBalances(req: AuthRequest, res: Response): void {
  try {
    const asOfDate = getQueryParam(req.query.asOfDate) ?? new Date().toISOString().slice(0, 10);
    if (!isValidIsoDate(asOfDate)) {
      sendBadRequest(res, 'asOfDate must be a valid YYYY-MM-DD date');
      return;
    }

    const balances = AccountingService.getAllAccountBalances(db, asOfDate);
    const totalDebit = balances.reduce((s, b) => s + b.total_debit, 0);
    const totalCredit = balances.reduce((s, b) => s + b.total_credit, 0);

    sendSuccess(res, {
      asOfDate,
      accounts: balances,
      totalDebit,
      totalCredit,
      balanced: Math.abs(totalDebit - totalCredit) < 0.01,
    });
  } catch (error: unknown) {
    logger.error('List account balances error:', error);
    sendInternalError(res, 'Failed to fetch account balances');
  }
}

/**
 * GET /api/accounting/accounts/:code/balance[?asOfDate=YYYY-MM-DD]
 * Balance for a single account as of a given date.
 */
function getAccountBalance(req: AuthRequest, res: Response): void {
  try {
    const code = getRouteParam(req.params.code);
    if (!code) { sendBadRequest(res, 'Account code is required'); return; }

    const account = AccountingService.getAccountByCode(db, code);
    if (!account) { sendNotFound(res, `Account ${code}`); return; }

    const asOfDate = getQueryParam(req.query.asOfDate) ?? new Date().toISOString().slice(0, 10);
    if (!isValidIsoDate(asOfDate)) {
      sendBadRequest(res, 'asOfDate must be a valid YYYY-MM-DD date');
      return;
    }

    const balance = AccountingService.getAccountBalance(db, account.id, asOfDate);
    sendSuccess(res, balance);
  } catch (error: unknown) {
    logger.error('Get account balance error:', error);
    sendInternalError(res, 'Failed to fetch account balance');
  }
}

// ============================================================================
// Period endpoints
// ============================================================================

/**
 * GET /api/accounting/periods
 * List all accounting periods, newest first.
 */
function listPeriods(req: AuthRequest, res: Response): void {
  try {
    const periods = PeriodModel.getAll(db);
    sendSuccess(res, { count: periods.length, periods });
  } catch (error: unknown) {
    logger.error('List periods error:', error);
    sendInternalError(res, 'Failed to fetch periods');
  }
}

/**
 * GET /api/accounting/periods/current
 * The open period covering today, if any.
 */
function getCurrentPeriod(req: AuthRequest, res: Response): void {
  try {
    const period = PeriodModel.getCurrentOpen(db);
    if (!period) {
      sendSuccess(res, { current: null, message: 'No open period covers today' });
      return;
    }
    sendSuccess(res, { current: period });
  } catch (error: unknown) {
    logger.error('Get current period error:', error);
    sendInternalError(res, 'Failed to fetch current period');
  }
}

/**
 * GET /api/accounting/periods/:id
 * Single period lookup.
 */
function getPeriod(req: AuthRequest, res: Response): void {
  try {
    const idStr = getRouteParam(req.params.id);
    const id = parseInt(idStr, 10);
    if (!Number.isFinite(id) || id <= 0) {
      sendBadRequest(res, 'Period id must be a positive integer');
      return;
    }

    const period = PeriodModel.getById(db, id);
    if (!period) { sendNotFound(res, `Period ${id}`); return; }
    sendSuccess(res, period);
  } catch (error: unknown) {
    logger.error('Get period error:', error);
    sendInternalError(res, 'Failed to fetch period');
  }
}

/**
 * POST /api/accounting/periods
 * Open a new period. Admin only.
 *
 * Body: { period_name: string, start_date: YYYY-MM-DD, end_date: YYYY-MM-DD }
 */
function openPeriod(req: AuthRequest, res: Response): void {
  try {
    if (req.user?.role !== 'admin') {
      sendForbidden(res, 'Only admins can open accounting periods');
      return;
    }

    const { period_name, start_date, end_date } = req.body as {
      period_name?: unknown;
      start_date?: unknown;
      end_date?: unknown;
    };

    if (typeof period_name !== 'string' || !period_name.trim()) {
      sendBadRequest(res, 'period_name is required');
      return;
    }
    if (!isValidIsoDate(start_date)) {
      sendBadRequest(res, 'start_date must be a valid YYYY-MM-DD date');
      return;
    }
    if (!isValidIsoDate(end_date)) {
      sendBadRequest(res, 'end_date must be a valid YYYY-MM-DD date');
      return;
    }
    if (start_date > end_date) {
      sendBadRequest(res, 'start_date must be on or before end_date');
      return;
    }

    // Reject overlap with an existing open period. Closed periods are
    // allowed to overlap (a period can be re-opened for back-fills of
    // older transactions; overlap with an open one would be ambiguous).
    const overlaps = db
      .prepare(`
        SELECT id, period_name FROM accounting_periods
        WHERE status = 'open'
          AND NOT (end_date < ? OR start_date > ?)
      `)
      .get(start_date, end_date) as { id: number; period_name: string } | undefined;
    if (overlaps) {
      sendConflict(
        res,
        `Date range overlaps open period "${overlaps.period_name}" (id ${overlaps.id})`
      );
      return;
    }

    const created = PeriodModel.openPeriod(db, {
      period_name: period_name.trim(),
      start_date,
      end_date,
    });

    logCRUD(
      ActionType.SETTING_UPDATE,
      PERIOD_ENTITY,
      created.id,
      `Opened accounting period ${created.period_name} (${created.start_date} → ${created.end_date})`,
      req.user?.id,
      { period_name: created.period_name, start_date, end_date }
    );

    sendCreated(res, created);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to open period';
    if (message.includes('UNIQUE')) {
      sendConflict(res, 'A period with that name already exists');
      return;
    }
    logger.error('Open period error:', error);
    sendInternalError(res, message);
  }
}

/**
 * POST /api/accounting/periods/:id/close
 * Close an open period. Idempotent — closing an already-closed period
 * is a no-op and returns 200 with the existing state.
 * Admin only.
 */
function closePeriod(req: AuthRequest, res: Response): void {
  try {
    if (req.user?.role !== 'admin') {
      sendForbidden(res, 'Only admins can close accounting periods');
      return;
    }

    const idStr = getRouteParam(req.params.id);
    const id = parseInt(idStr, 10);
    if (!Number.isFinite(id) || id <= 0) {
      sendBadRequest(res, 'Period id must be a positive integer');
      return;
    }

    const existing = PeriodModel.getById(db, id);
    if (!existing) { sendNotFound(res, `Period ${id}`); return; }

    if (existing.status === 'closed') {
      sendSuccess(res, { period: existing, alreadyClosed: true });
      return;
    }

    PeriodModel.closePeriod(db, id, req.user?.id ?? null);
    const updated = PeriodModel.getById(db, id)!;

    logCRUD(
      ActionType.SETTING_UPDATE,
      PERIOD_ENTITY,
      updated.id,
      `Closed accounting period ${updated.period_name}`,
      req.user?.id,
      { period_name: updated.period_name, closed_at: updated.closed_at }
    );

    sendSuccess(res, { period: updated, alreadyClosed: false });
  } catch (error: unknown) {
    logger.error('Close period error:', error);
    sendInternalError(res, 'Failed to close period');
  }
}

// ============================================================================
// Exports
// ============================================================================

export default {
  // accounts
  listAccounts,
  getAccount,
  listAccountBalances,
  getAccountBalance,
  // periods
  listPeriods,
  getCurrentPeriod,
  getPeriod,
  openPeriod,
  closePeriod,
};
