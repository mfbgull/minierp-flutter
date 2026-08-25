"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.toggleBOMActive = exports.deleteBOM = exports.updateBOM = exports.createBOM = exports.getBOMsByFinishedItem = exports.getBOMById = exports.getAllBOMs = void 0;
const queryUtils_1 = require("../utils/queryUtils");
const BOM_1 = __importDefault(require("../models/BOM"));
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const getAllBOMs = (req, res, next) => {
    try {
        const page = (0, queryUtils_1.getQueryInteger)(req.query.page, 1);
        const limit = (0, queryUtils_1.getQueryInteger)(req.query.limit, 10);
        const search = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortBy = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrder = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const { rows, total, pageNum, limitNum } = BOM_1.default.getAll({
            search: search || undefined,
            sortBy: sortBy || undefined,
            sortOrder: sortOrder || undefined,
            page,
            limit
        }, database_1.default);
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
        next(error);
    }
};
exports.getAllBOMs = getAllBOMs;
const getBOMById = (req, res, next) => {
    try {
        const { id } = req.params;
        const bom = BOM_1.default.getById(Number(id), database_1.default);
        if (!bom) {
            res.status(404).json({ error: 'BOM not found' });
            return;
        }
        res.json(bom);
    }
    catch (error) {
        next(error);
    }
};
exports.getBOMById = getBOMById;
const getBOMsByFinishedItem = (req, res, next) => {
    try {
        const { itemId } = req.params;
        const boms = BOM_1.default.getByFinishedItem(Number(itemId), database_1.default);
        res.json(boms);
    }
    catch (error) {
        next(error);
    }
};
exports.getBOMsByFinishedItem = getBOMsByFinishedItem;
const createBOM = (req, res, next) => {
    try {
        const { finished_item_id, quantity, bom_name, items } = req.body;
        if (!finished_item_id || !quantity || !bom_name || !items || items.length === 0) {
            res.status(400).json({
                error: 'finished_item_id, quantity, bom_name, and at least one item are required'
            });
            return;
        }
        for (const item of items) {
            if (!item.item_id || !item.quantity || item.quantity <= 0) {
                res.status(400).json({
                    error: 'Each item must have item_id and quantity > 0'
                });
                return;
            }
        }
        const bom = BOM_1.default.create(req.body, req.user.id, database_1.default);
        logger_1.default.info(`Created BOM: ${bom.bom_no} for ${bom.finished_item_name}`);
        // Log BOM creation using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.BOM_CREATE, 'BOM', bom.id, `Created BOM: ${bom.bom_no} for ${bom.finished_item_name}`, req.user.id);
        req.activityLogged = true;
        res.status(201).json(bom);
    }
    catch (error) {
        next(error);
    }
};
exports.createBOM = createBOM;
const updateBOM = (req, res, next) => {
    try {
        const { id } = req.params;
        if (!req.user) {
            res.status(401).json({ error: 'Authentication required' });
            return;
        }
        const bom = BOM_1.default.update(Number(id), req.body, req.user.id, database_1.default);
        logger_1.default.info(`Updated BOM: ${bom.bom_no}`);
        // Log BOM update using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.BOM_UPDATE, 'BOM', bom.id, `Updated BOM: ${bom.bom_no}`, req.user.id);
        req.activityLogged = true;
        res.json(bom);
    }
    catch (error) {
        next(error);
    }
};
exports.updateBOM = updateBOM;
const deleteBOM = (req, res, next) => {
    try {
        const { id } = req.params;
        const bom = BOM_1.default.getById(Number(id), database_1.default);
        if (!bom) {
            res.status(404).json({ error: 'BOM not found' });
            return;
        }
        BOM_1.default.delete(Number(id), database_1.default);
        logger_1.default.info(`Deleted BOM: ${bom.bom_no}`);
        // Log BOM deletion using activity logger
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.BOM_DELETE, 'BOM', Number(id), `Deleted BOM: ${bom.bom_no}`, req.user.id);
        req.activityLogged = true;
        res.json({ message: 'BOM deleted successfully' });
    }
    catch (error) {
        next(error);
    }
};
exports.deleteBOM = deleteBOM;
const toggleBOMActive = (req, res, next) => {
    try {
        const { id } = req.params;
        const bom = BOM_1.default.toggleActive(Number(id), database_1.default);
        logger_1.default.info(`${bom.is_active ? 'Activated' : 'Deactivated'} BOM: ${bom.bom_no}`);
        res.json(bom);
    }
    catch (error) {
        next(error);
    }
};
exports.toggleBOMActive = toggleBOMActive;
