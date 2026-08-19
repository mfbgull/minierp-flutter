"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const Production_1 = __importDefault(require("../models/Production"));
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
function recordProduction(req, res) {
    try {
        const { output_item_id, output_quantity, warehouse_id, raw_materials_warehouse_id, production_date, input_items, overhead_cost } = req.body;
        if (!output_item_id || !output_quantity || !warehouse_id || !production_date || !input_items || !input_items.length) {
            res.status(400).json({ error: 'Output item, quantity, warehouse, date, and input items are required' });
            return;
        }
        if (output_quantity <= 0) {
            res.status(400).json({ error: 'Output quantity must be positive' });
            return;
        }
        const productionData = {
            ...req.body,
            raw_materials_warehouse_id: raw_materials_warehouse_id || warehouse_id,
            overhead_cost: overhead_cost ? parseFloat(String(overhead_cost)) : 0
        };
        const production = Production_1.default.recordProduction(productionData, req.user.id, database_1.default);
        // Log production creation using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.WO_CREATE, 'WorkOrder', production.id, `Created production: ${production.production_no} - ${production.output_item_name} (${production.output_quantity} units)`, req.user.id);
        req.activityLogged = true;
        res.status(201).json(production);
    }
    catch (error) {
        logger_1.default.error('Record production error:', error);
        res.status(500).json({ error: 'Failed to record production' });
    }
}
function getProductions(req, res) {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const startDateParam = (0, queryUtils_1.getQueryParam)(req.query.start_date);
        const endDateParam = (0, queryUtils_1.getQueryParam)(req.query.end_date);
        const outputItemIdParam = (0, queryUtils_1.getQueryParam)(req.query.output_item_id);
        const warehouseIdParam = (0, queryUtils_1.getQueryParam)(req.query.warehouse_id);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const filters = {
            start_date: startDateParam,
            end_date: endDateParam,
            output_item_id: outputItemIdParam ? Number(outputItemIdParam) : undefined,
            warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
            search: search || undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        };
        const { rows, total, pageNum, limitNum } = Production_1.default.getAll(filters, database_1.default);
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
        logger_1.default.error('Get productions error:', error);
        res.status(500).json({ error: 'Failed to get productions' });
    }
}
function getProduction(req, res) {
    try {
        const production = Production_1.default.getById(Number(req.params.id), database_1.default);
        if (!production) {
            res.status(404).json({ error: 'Production not found' });
            return;
        }
        res.json(production);
    }
    catch (error) {
        logger_1.default.error('Get production error:', error);
        res.status(500).json({ error: 'Failed to get production' });
    }
}
function getProductionSummaryByItem(req, res) {
    try {
        const { item_id } = req.params;
        if (!item_id) {
            res.status(400).json({ error: 'Item ID is required' });
            return;
        }
        res.json(Production_1.default.getSummaryByItem(Number(item_id), database_1.default));
    }
    catch (error) {
        logger_1.default.error('Get production summary error:', error);
        res.status(500).json({ error: 'Failed to get production summary' });
    }
}
function deleteProduction(req, res) {
    try {
        const productionId = Number(req.params.id);
        const production = Production_1.default.getById(productionId, database_1.default);
        Production_1.default.delete(productionId, req.user.id, database_1.default);
        // Log production deletion using activity logger
        if (production) {
            (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.WO_DELETE, 'WorkOrder', productionId, `Deleted production: ${production.production_no}`, req.user.id);
            req.activityLogged = true;
        }
        res.json({ success: true, message: 'Production deleted successfully' });
    }
    catch (error) {
        logger_1.default.error('Delete production error:', error);
        res.status(500).json({ error: 'Failed to delete production' });
    }
}
exports.default = {
    recordProduction,
    getProductions,
    getProduction,
    getProductionSummaryByItem,
    deleteProduction
};
//# sourceMappingURL=productionController.js.map