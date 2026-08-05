"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const Purchase_1 = __importDefault(require("../models/Purchase"));
const accountingService_1 = __importDefault(require("../services/accountingService"));
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
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const itemIdParam = (0, queryUtils_1.getQueryParam)(req.query.item_id);
        const warehouseIdParam = (0, queryUtils_1.getQueryParam)(req.query.warehouse_id);
        const supplierNameParam = (0, queryUtils_1.getQueryParam)(req.query.supplier_name);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const filters = {
            start_date: startDateParam,
            end_date: endDateParam,
            item_id: itemIdParam ? Number(itemIdParam) : undefined,
            warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
            supplier_name: supplierNameParam,
            limit: limitParam ? parseInt(String(limitParam)) : undefined
        };
        const purchases = Purchase_1.default.getAll(filters, database_1.default);
        res.json(purchases);
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
function getReturnHistory(req, res) {
    try {
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const itemIdParam = (0, queryUtils_1.getQueryParam)(req.query.item_id);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const filters = {
            start_date: startDateParam,
            end_date: endDateParam,
            item_id: itemIdParam ? Number(itemIdParam) : undefined,
            limit: limitParam ? parseInt(String(limitParam)) : undefined
        };
        const returns = Purchase_1.default.getReturnHistory(filters, database_1.default);
        res.json(returns);
    }
    catch (error) {
        logger_1.default.error('Get purchase return history error:', error);
        res.status(500).json({ error: 'Failed to get purchase return history' });
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
function deletePurchase(req, res) {
    try {
        Purchase_1.default.delete(Number(req.params.id), req.user.id, database_1.default);
        res.json({ success: true, message: 'Purchase deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete purchase error:', error);
        res.status(500).json({ error: error.message || 'Failed to delete purchase' });
    }
}
function returnPurchaseItems(req, res) {
    try {
        const { id } = req.params;
        const purchaseId = parseInt(id, 10);
        const userId = req.user.id;
        const { quantity, reason } = req.body;
        if (!quantity || quantity <= 0) {
            return res.status(400).json({ error: 'A positive return quantity is required' });
        }
        // Wrap everything in a transaction so GL posting is atomic with stock return
        let result;
        database_1.default.transaction(() => {
            // Fetch purchase first to get its number for the GL entry
            const purchase = Purchase_1.default.getById(purchaseId, database_1.default);
            if (!purchase)
                throw new Error('Purchase not found');
            // Return stock and get the cost for GL posting
            result = Purchase_1.default.returnPurchaseItems(database_1.default, purchaseId, quantity, userId, reason);
            // Post GL reversal — Dr AP, Cr Inventory
            accountingService_1.default.postPurchaseReturnEntry(database_1.default, {
                purchaseId,
                purchaseNo: purchase.purchase_no,
                returnAmount: result.totalCost,
                returnDate: new Date().toISOString().split('T')[0],
                userId,
            });
        })();
        res.json({ success: true, message: 'Return processed successfully', data: result });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        logger_1.default.error('Return purchase items error:', { error: errorMessage });
        res.status(400).json({ error: errorMessage });
    }
}
exports.default = {
    recordPurchase,
    getPurchases,
    getPurchase,
    getPurchaseSummaryByItem,
    getPurchaseSummaryByDateRange,
    getTopSuppliers,
    getReturnHistory,
    deletePurchase,
    returnPurchaseItems,
};
//# sourceMappingURL=purchaseController.js.map