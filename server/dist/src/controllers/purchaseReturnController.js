"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const PurchaseReturn_1 = __importDefault(require("../models/PurchaseReturn"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function getPurchaseReturns(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const startDate = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDate = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const type = (0, queryUtils_1.getQueryParam)(req.query.type);
        const status = (0, queryUtils_1.getQueryParam)(req.query.status);
        const warehouseIdParam = (0, queryUtils_1.getQueryParam)(req.query.warehouse_id);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            search: search || undefined,
            start_date: startDate || undefined,
            end_date: endDate || undefined,
            type: type || undefined,
            status: status || undefined,
            warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        };
        const { rows, total, pageNum, limitNum } = PurchaseReturn_1.default.getAll(filters, database_1.default);
        // Flat envelope (data = list, pagination a sibling) — the shape the
        // client's `getPaged` helper parses.
        res.json({
            success: true,
            data: rows,
            pagination: {
                currentPage: pageNum,
                totalPages: Math.ceil(total / limitNum),
                totalItems: total,
                hasNext: pageNum < Math.ceil(total / limitNum),
                hasPrev: pageNum > 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Get purchase returns error:', error);
        res.status(500).json({ error: 'Failed to get purchase returns' });
    }
}
function getPurchaseReturn(req, res) {
    try {
        const purchaseReturn = PurchaseReturn_1.default.getById(Number(req.params.id), database_1.default);
        if (!purchaseReturn) {
            res.status(404).json({ error: 'Purchase return not found' });
            return;
        }
        res.json(purchaseReturn);
    }
    catch (error) {
        logger_1.default.error('Get purchase return error:', error);
        res.status(500).json({ error: 'Failed to get purchase return' });
    }
}
function createPurchaseReturn(req, res) {
    try {
        const body = req.body;
        if (!body.return_date) {
            return res.status(400).json({ error: 'return_date is required' });
        }
        if (body.source_type !== 'PURCHASE' && body.source_type !== 'PURCHASE_ORDER') {
            return res.status(400).json({ error: 'source_type must be PURCHASE or PURCHASE_ORDER' });
        }
        if (!body.source_id || body.source_id <= 0) {
            return res.status(400).json({ error: 'A valid source_id is required' });
        }
        if (!body.warehouse_id || body.warehouse_id <= 0) {
            return res.status(400).json({ error: 'A valid warehouse_id is required' });
        }
        if (!body.items || body.items.length === 0) {
            return res.status(400).json({ error: 'At least one return item is required' });
        }
        const created = PurchaseReturn_1.default.create({
            return_date: body.return_date,
            source_type: body.source_type,
            source_id: body.source_id,
            warehouse_id: body.warehouse_id,
            reason: body.reason,
            items: body.items,
        }, req.user.id, database_1.default);
        res.status(201).json({
            success: true,
            message: `Purchase return ${created.return_no} created successfully`,
            data: created,
        });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Create purchase return error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
function voidPurchaseReturn(req, res) {
    try {
        const id = Number(req.params.id);
        const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
        const voided = PurchaseReturn_1.default.voidReturn(id, req.user.id, reason || '', database_1.default);
        res.json({
            success: true,
            message: `Purchase return ${voided.return_no} voided successfully`,
            data: voided,
        });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Void purchase return error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
exports.default = {
    getPurchaseReturns,
    getPurchaseReturn,
    createPurchaseReturn,
    voidPurchaseReturn,
};
