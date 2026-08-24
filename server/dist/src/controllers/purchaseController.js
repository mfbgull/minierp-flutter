"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const Purchase_1 = __importDefault(require("../models/Purchase"));
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function recordPurchase(req, res) {
    try {
        const { item_id, warehouse_id, quantity, unit_cost, purchase_date, } = req.body;
        if (!item_id || !warehouse_id || !quantity || !unit_cost || !purchase_date) {
            res.status(400).json({
                error: 'Item, warehouse, quantity, unit cost, and purchase date are required'
            });
            return;
        }
        if (quantity <= 0) {
            res.status(400).json({ error: 'Quantity must be positive' });
            return;
        }
        if (unit_cost < 0) {
            res.status(400).json({ error: 'Unit cost cannot be negative' });
            return;
        }
        const purchase = Purchase_1.default.recordPurchase(req.body, req.user.id, database_1.default);
        res.status(201).json(purchase);
    }
    catch (error) {
        logger_1.default.error('Record purchase error:', error);
        res.status(500).json({ error: error.message || 'Failed to record purchase' });
    }
}
function getPurchases(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const itemIdParam = (0, queryUtils_1.getQueryParam)(req.query.item_id);
        const warehouseIdParam = (0, queryUtils_1.getQueryParam)(req.query.warehouse_id);
        const supplierNameParam = (0, queryUtils_1.getQueryParam)(req.query.supplier_name);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            start_date: startDateParam,
            end_date: endDateParam,
            item_id: itemIdParam ? Number(itemIdParam) : undefined,
            warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
            supplier_name: supplierNameParam,
            search: search || undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        };
        const { rows, total, pageNum, limitNum } = Purchase_1.default.getAll(filters, database_1.default);
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
        logger_1.default.error('Get purchases error:', error);
        res.status(500).json({ error: 'Failed to get purchases' });
    }
}
function getPurchase(req, res) {
    try {
        const purchase = Purchase_1.default.getById(Number(req.params.id), database_1.default);
        if (!purchase) {
            res.status(404).json({ error: 'Purchase not found' });
            return;
        }
        res.json(purchase);
    }
    catch (error) {
        logger_1.default.error('Get purchase error:', error);
        res.status(500).json({ error: 'Failed to get purchase' });
    }
}
function getPurchasePayments(req, res) {
    try {
        const payments = Purchase_1.default.getPayments(Number(req.params.id), database_1.default);
        res.json({ success: true, data: payments });
    }
    catch (error) {
        logger_1.default.error('Get purchase payments error:', error);
        res.status(500).json({ error: 'Failed to get purchase payments' });
    }
}
function getPurchaseSummaryByItem(req, res) {
    try {
        const { item_id } = req.params;
        if (!item_id) {
            res.status(400).json({ error: 'Item ID is required' });
            return;
        }
        const summary = Purchase_1.default.getSummaryByItem(Number(item_id), database_1.default);
        res.json(summary);
    }
    catch (error) {
        logger_1.default.error('Get purchase summary error:', error);
        res.status(500).json({ error: 'Failed to get purchase summary' });
    }
}
function getPurchaseSummaryByDateRange(req, res) {
    try {
        const { start_date, end_date } = req.query;
        if (!start_date || !end_date) {
            res.status(400).json({ error: 'Start date and end date are required' });
            return;
        }
        const summary = Purchase_1.default.getSummaryByDateRange(start_date, end_date, database_1.default);
        res.json(summary);
    }
    catch (error) {
        logger_1.default.error('Get purchase summary error:', error);
        res.status(500).json({ error: 'Failed to get purchase summary' });
    }
}
function getTopSuppliers(req, res) {
    try {
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const limit = limitParam ? parseInt(String(limitParam)) : 10;
        const suppliers = Purchase_1.default.getTopSuppliers(limit, database_1.default);
        res.json(suppliers);
    }
    catch (error) {
        logger_1.default.error('Get top suppliers error:', error);
        res.status(500).json({ error: 'Failed to get top suppliers' });
    }
}
function voidPurchase(req, res) {
    try {
        const id = Number(req.params.id);
        const { reason } = req.body;
        if (!reason || !reason.trim()) {
            res.status(400).json({ success: false, error: 'A void reason is required' });
            return;
        }
        Purchase_1.default.void(id, req.user.id, reason, database_1.default);
        res.json({ success: true, message: 'Purchase voided successfully' });
    }
    catch (error) {
        const message = error?.message || 'Failed to void purchase';
        // Guard rejections are client errors — surface the reason.
        const isClientError = /Cannot void|already voided|not found|reason is required/i.test(message);
        logger_1.default.error('Void purchase error:', error);
        res.status(isClientError ? 400 : 500).json({ success: false, error: message });
    }
}
exports.default = {
    recordPurchase,
    getPurchases,
    getPurchase,
    getPurchasePayments,
    getPurchaseSummaryByItem,
    getPurchaseSummaryByDateRange,
    getTopSuppliers,
    voidPurchase,
};
//# sourceMappingURL=purchaseController.js.map