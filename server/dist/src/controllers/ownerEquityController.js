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
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const OwnerCapital_1 = __importStar(require("../models/OwnerCapital"));
const OwnerWithdrawal_1 = __importStar(require("../models/OwnerWithdrawal"));
const Expense_1 = __importDefault(require("../models/Expense"));
/**
 * Business-rule violations (funds guard, stock guard, closed periods,
 * double-posting, validation) are client errors; anything else is a
 * server fault. Matched on the message prefixes the models/services throw.
 */
function isClientError(message) {
    const markers = [
        'Insufficient funds',
        'Insufficient stock',
        'Insufficient stock for',
        'Batch coverage shortfall',
        'All batches for',
        'closed accounting period',
        'already exists for',
        'refusing to double-post',
        'Cannot reverse withdrawal',
        'cannot be edited',
        'already voided',
        'not found',
        'Not found',
        'must be',
        'requires at least one',
        'computed as zero',
        'required account',
        'Unbalanced goods withdrawal',
        'Invalid',
        'Unknown',
        'A journal entry must have',
        'Unbalanced journal entry',
        'No open accounting period',
        'Line amounts',
        'Line must have',
        'Line must be debit',
    ];
    return markers.some((m) => message.includes(m));
}
function fail(res, error, fallback) {
    const message = error instanceof Error ? error.message : String(error);
    if (isClientError(message)) {
        res.status(400).json({ success: false, error: message });
        return;
    }
    logger_1.default.error(`${fallback}:`, error);
    res.status(500).json({ success: false, error: fallback });
}
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
// ---------------------------------------------------------------------
// Owner capital
// ---------------------------------------------------------------------
function createCapital(req, res) {
    try {
        const { capital_date, amount, payment_method, note } = req.body;
        const userId = req.user.id;
        if (!capital_date || !DATE_RE.test(String(capital_date))) {
            res.status(400).json({ success: false, error: 'A valid capital_date (YYYY-MM-DD) is required' });
            return;
        }
        const parsedAmount = Number(amount);
        if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
            res.status(400).json({ success: false, error: 'Amount must be a positive number' });
            return;
        }
        let capitalId;
        let capitalNo;
        database_1.default.transaction(() => {
            capitalNo = (0, OwnerCapital_1.generateCapitalNo)(database_1.default, capital_date);
            const dto = {
                capital_no: capitalNo,
                capital_date,
                amount: parsedAmount,
                payment_method: payment_method || undefined,
                note: note || undefined,
                created_by: userId,
            };
            capitalId = OwnerCapital_1.default.create(database_1.default, dto);
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'OwnerCapital', capitalId, `Created owner capital ${capitalNo} (${parsedAmount})`, userId, {
            capital_no: capitalNo, amount: parsedAmount, payment_method: payment_method ?? null,
        });
        req.activityLogged = true;
        res.status(201).json({
            success: true,
            message: 'Owner capital recorded successfully',
            data: { id: capitalId, capital_no: capitalNo, amount: parsedAmount },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to record owner capital');
    }
}
function getCapitalList(req, res) {
    try {
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)((0, queryUtils_1.getQueryParam)(req.query.sortBy) || 'oc.capital_date', (0, queryUtils_1.getQueryParam)(req.query.sortOrder) || 'DESC', sqlSanitizer_1.OWNER_CAPITAL_SORT_COLUMNS, 'oc.capital_date', 'DESC');
        const filters = {
            page: parseInt((0, queryUtils_1.getQueryParam)(req.query.page)) || 1,
            limit: parseInt((0, queryUtils_1.getQueryParam)(req.query.limit)) || 10,
            status: (0, queryUtils_1.getQueryParam)(req.query.status),
            from_date: (0, queryUtils_1.getQueryParam)(req.query.from_date),
            to_date: (0, queryUtils_1.getQueryParam)(req.query.to_date),
            search: (0, queryUtils_1.getQueryParam)(req.query.search),
            sortBy: sortParams.column,
            sortOrder: sortParams.order,
        };
        const rows = OwnerCapital_1.default.getAll(database_1.default, filters);
        const totalItems = OwnerCapital_1.default.getCount(database_1.default, filters);
        const totalPages = Math.ceil(totalItems / filters.limit);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: filters.page,
                totalPages,
                totalItems,
                hasNext: filters.page < totalPages,
                hasPrev: filters.page > 1,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch owner capital');
    }
}
function updateCapital(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const { capital_date, amount, payment_method, note } = req.body;
        const userId = req.user.id;
        if (capital_date !== undefined && !DATE_RE.test(String(capital_date))) {
            res.status(400).json({ success: false, error: 'capital_date must be YYYY-MM-DD' });
            return;
        }
        if (amount !== undefined && (!Number.isFinite(Number(amount)) || Number(amount) <= 0)) {
            res.status(400).json({ success: false, error: 'Amount must be a positive number' });
            return;
        }
        const existing = OwnerCapital_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Owner capital entry not found' });
            return;
        }
        const dto = {
            capital_date,
            amount: amount !== undefined ? Number(amount) : undefined,
            payment_method,
            note,
        };
        OwnerCapital_1.default.update(database_1.default, id, dto, { userId });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'OwnerCapital', id, `Updated owner capital ${existing.capital_no}`, userId, {
            capital_no: existing.capital_no, changes: dto,
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Owner capital updated successfully', data: { id } });
    }
    catch (error) {
        fail(res, error, 'Failed to update owner capital');
    }
}
function voidCapital(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
        const existing = OwnerCapital_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Owner capital entry not found' });
            return;
        }
        OwnerCapital_1.default.softVoid(database_1.default, id, { userId, reason });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SETTING_UPDATE, 'OwnerCapital', id, `Voided owner capital ${existing.capital_no}`, userId, {
            capital_no: existing.capital_no, reason: reason ?? null,
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Owner capital voided', data: { id, status: 'voided' } });
    }
    catch (error) {
        fail(res, error, 'Failed to void owner capital');
    }
}
// ---------------------------------------------------------------------
// Owner withdrawals
// ---------------------------------------------------------------------
function validateItemLines(raw) {
    if (!Array.isArray(raw) || raw.length === 0) {
        return { error: 'A goods withdrawal requires at least one item line' };
    }
    const lines = [];
    for (const item of raw) {
        // Server-authoritative costing: the client names item/warehouse/qty only.
        if (item === null || typeof item !== 'object' ||
            'unit_cost' in item || 'batch_id' in item || 'line_total' in item) {
            return { error: 'Client-supplied costing fields (unit_cost/batch_id/line_total) are not accepted' };
        }
        const itemId = Number(item.item_id);
        const warehouseId = Number(item.warehouse_id);
        const quantity = Number(item.quantity);
        if (!Number.isInteger(itemId) || itemId <= 0)
            return { error: 'Each line needs a valid item_id' };
        if (!Number.isInteger(warehouseId) || warehouseId <= 0)
            return { error: 'Each line needs a valid warehouse_id' };
        if (!Number.isFinite(quantity) || quantity <= 0)
            return { error: 'Line quantities must be positive numbers' };
        lines.push({ item_id: itemId, warehouse_id: warehouseId, quantity });
    }
    return { lines };
}
function createWithdrawal(req, res) {
    try {
        const { withdrawal_date, kind, amount, payment_method, note, items } = req.body;
        const userId = req.user.id;
        if (!withdrawal_date || !DATE_RE.test(String(withdrawal_date))) {
            res.status(400).json({ success: false, error: 'A valid withdrawal_date (YYYY-MM-DD) is required' });
            return;
        }
        if (kind !== 'cash' && kind !== 'goods') {
            res.status(400).json({ success: false, error: "kind must be 'cash' or 'goods'" });
            return;
        }
        if (kind === 'cash') {
            const parsedAmount = Number(amount);
            if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
                res.status(400).json({ success: false, error: 'Cash withdrawal amount must be a positive number' });
                return;
            }
        }
        else if (amount !== undefined) {
            // Goods value is always server-calculated from batch costs.
            res.status(400).json({ success: false, error: 'Goods withdrawal amount is system-calculated and cannot be supplied' });
            return;
        }
        let lines;
        if (kind === 'goods') {
            const check = validateItemLines(items);
            if (check.error) {
                res.status(400).json({ success: false, error: check.error });
                return;
            }
            lines = check.lines;
        }
        let withdrawalId;
        let withdrawalNo;
        let recordedAmount;
        database_1.default.transaction(() => {
            withdrawalNo = (0, OwnerWithdrawal_1.generateWithdrawalNo)(database_1.default, withdrawal_date);
            const result = OwnerWithdrawal_1.default.create(database_1.default, {
                withdrawal_no: withdrawalNo,
                withdrawal_date,
                kind,
                amount: kind === 'cash' ? Number(amount) : undefined,
                payment_method: kind === 'cash' ? payment_method : undefined,
                note: note || undefined,
                items: lines,
                created_by: userId,
            });
            withdrawalId = result.id;
            recordedAmount = result.amount;
        })();
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', withdrawalId, `Created owner withdrawal ${withdrawalNo} (${kind}, ${recordedAmount.toFixed(2)})`, userId, {
            withdrawal_no: withdrawalNo, kind, amount: recordedAmount,
        });
        req.activityLogged = true;
        res.status(201).json({
            success: true,
            message: 'Owner withdrawal recorded successfully',
            data: { id: withdrawalId, withdrawal_no: withdrawalNo, amount: recordedAmount },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to record owner withdrawal');
    }
}
function quoteWithdrawal(req, res) {
    try {
        const check = validateItemLines(req.body?.items);
        if (check.error) {
            res.status(400).json({ success: false, error: check.error });
            return;
        }
        const quote = OwnerWithdrawal_1.default.quote(database_1.default, check.lines);
        res.json({ success: true, data: quote });
    }
    catch (error) {
        fail(res, error, 'Failed to quote withdrawal cost');
    }
}
function getWithdrawalList(req, res) {
    try {
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)((0, queryUtils_1.getQueryParam)(req.query.sortBy) || 'ow.withdrawal_date', (0, queryUtils_1.getQueryParam)(req.query.sortOrder) || 'DESC', sqlSanitizer_1.OWNER_WITHDRAWAL_SORT_COLUMNS, 'ow.withdrawal_date', 'DESC');
        const filters = {
            page: parseInt((0, queryUtils_1.getQueryParam)(req.query.page)) || 1,
            limit: parseInt((0, queryUtils_1.getQueryParam)(req.query.limit)) || 10,
            status: (0, queryUtils_1.getQueryParam)(req.query.status),
            kind: (0, queryUtils_1.getQueryParam)(req.query.kind),
            from_date: (0, queryUtils_1.getQueryParam)(req.query.from_date),
            to_date: (0, queryUtils_1.getQueryParam)(req.query.to_date),
            search: (0, queryUtils_1.getQueryParam)(req.query.search),
            sortBy: sortParams.column,
            sortOrder: sortParams.order,
        };
        const rows = OwnerWithdrawal_1.default.getAll(database_1.default, filters);
        const totalItems = OwnerWithdrawal_1.default.getCount(database_1.default, filters);
        const totalPages = Math.ceil(totalItems / filters.limit);
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: filters.page,
                totalPages,
                totalItems,
                hasNext: filters.page < totalPages,
                hasPrev: filters.page > 1,
            },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch owner withdrawals');
    }
}
function getWithdrawalById(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const withdrawal = OwnerWithdrawal_1.default.getById(database_1.default, id);
        if (!withdrawal) {
            res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
            return;
        }
        const items = OwnerWithdrawal_1.default.getItems(database_1.default, id);
        const movements = OwnerWithdrawal_1.default.getMovements(database_1.default, withdrawal.withdrawal_no);
        res.json({
            success: true,
            data: { ...withdrawal, items, movements },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch owner withdrawal');
    }
}
function updateWithdrawal(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const { withdrawal_date, amount, payment_method, note, items } = req.body;
        const userId = req.user.id;
        if (withdrawal_date !== undefined && !DATE_RE.test(String(withdrawal_date))) {
            res.status(400).json({ success: false, error: 'withdrawal_date must be YYYY-MM-DD' });
            return;
        }
        const existing = OwnerWithdrawal_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
            return;
        }
        if (existing.kind === 'goods' && amount !== undefined) {
            res.status(400).json({ success: false, error: 'Goods withdrawal amount is system-calculated and cannot be supplied' });
            return;
        }
        let lines;
        if (existing.kind === 'goods' && items !== undefined) {
            if (items === null) {
                lines = null; // explicit clear rejected below via empty-lines rule
            }
            else {
                const check = validateItemLines(items);
                if (check.error) {
                    res.status(400).json({ success: false, error: check.error });
                    return;
                }
                lines = check.lines;
            }
        }
        const result = OwnerWithdrawal_1.default.update(database_1.default, id, {
            withdrawal_date,
            amount: existing.kind === 'cash' && amount !== undefined ? Number(amount) : undefined,
            payment_method,
            note,
            items: lines,
        }, { userId });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', id, `Updated owner withdrawal ${existing.withdrawal_no}`, userId, {
            withdrawal_no: existing.withdrawal_no, new_amount: result.amount,
        });
        req.activityLogged = true;
        res.json({
            success: true,
            message: 'Owner withdrawal updated successfully',
            data: { id, amount: result.amount },
        });
    }
    catch (error) {
        fail(res, error, 'Failed to update owner withdrawal');
    }
}
function voidWithdrawal(req, res) {
    try {
        const id = parseInt((0, queryUtils_1.getRouteParam)(req.params.id), 10);
        const userId = req.user.id;
        const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
        const existing = OwnerWithdrawal_1.default.getById(database_1.default, id);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Owner withdrawal not found' });
            return;
        }
        OwnerWithdrawal_1.default.softVoid(database_1.default, id, { userId, reason });
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.STOCK_MOVEMENT, 'OwnerWithdrawal', id, `Voided owner withdrawal ${existing.withdrawal_no}`, userId, {
            withdrawal_no: existing.withdrawal_no, reason: reason ?? null,
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Owner withdrawal voided', data: { id, status: 'voided' } });
    }
    catch (error) {
        fail(res, error, 'Failed to void owner withdrawal');
    }
}
// ---------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------
function getSummary(_req, res) {
    try {
        res.json({ success: true, data: OwnerCapital_1.default.getSummaryTotals(database_1.default) });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch owner equity summary');
    }
}
function getPaymentMethodOptions(_req, res) {
    try {
        res.json({ success: true, data: Expense_1.default.getPaymentMethodOptions() });
    }
    catch (error) {
        fail(res, error, 'Failed to fetch payment method options');
    }
}
exports.default = {
    createCapital,
    getCapitalList,
    updateCapital,
    voidCapital,
    createWithdrawal,
    quoteWithdrawal,
    getWithdrawalList,
    getWithdrawalById,
    updateWithdrawal,
    voidWithdrawal,
    getSummary,
    getPaymentMethodOptions,
};
