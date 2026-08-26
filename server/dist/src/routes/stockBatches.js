"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.initStockBatchesRoutes = initStockBatchesRoutes;
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const logger_1 = __importDefault(require("../utils/logger"));
const paginate_1 = require("../utils/paginate");
const router = (0, express_1.Router)();
router.use(auth_1.authenticateToken);
// Will be injected via initStockBatchesRoutes
let db;
function initStockBatchesRoutes(database) {
    db = database;
    return router;
}
/**
 * GET /api/inventory/stock-batches
 * List batches with optional filters
 */
router.get('/stock-batches', (0, requirePermission_1.requirePermission)('inventory', 'read'), (req, res) => {
    try {
        const { item_id, warehouse_id, halted } = req.query;
        // Task 8.7: bounded listing. Legacy callers (no page/limit params) keep
        // the bare-array response; passing `page` opts into the envelope shape.
        const wantsPagination = req.query.page !== undefined || req.query.limit !== undefined;
        const countSql = `
      SELECT COUNT(*) AS c
      FROM stock_batches sb
      WHERE sb.quantity_remaining > 0
    `;
        let sql = `
      SELECT sb.*,
        i.item_code, i.item_name,
        w.warehouse_code, w.warehouse_name
      FROM stock_batches sb
      LEFT JOIN items i ON sb.item_id = i.id
      LEFT JOIN warehouses w ON sb.warehouse_id = w.id
      WHERE sb.quantity_remaining > 0
    `;
        const params = [];
        const countParams = [];
        const applyFilters = (target, into) => {
            let out = target;
            if (item_id) {
                out += ' AND sb.item_id = ?';
                into.push(Number(item_id));
            }
            if (warehouse_id) {
                out += ' AND sb.warehouse_id = ?';
                into.push(Number(warehouse_id));
            }
            if (halted !== undefined) {
                out += ' AND sb.halted = ?';
                into.push(halted === 'true' ? 1 : 0);
            }
            return out;
        };
        const filteredCountSql = applyFilters(countSql, countParams);
        sql = applyFilters(sql, params);
        sql += ' ORDER BY sb.received_date ASC, sb.id ASC';
        if (wantsPagination) {
            const { c: total } = db.prepare(filteredCountSql).get(...countParams);
            const p = (0, paginate_1.parsePageParams)(req);
            sql += ' LIMIT ? OFFSET ?';
            params.push(p.limit, p.offset);
            const batches = db.prepare(sql).all(...params);
            res.json({ success: true, data: batches, pagination: (0, paginate_1.envelope)(total, p) });
        }
        else {
            const batches = db.prepare(sql).all(...params);
            res.json(batches);
        }
    }
    catch (error) {
        logger_1.default.error('Get stock batches error:', error);
        res.status(500).json({ error: 'Failed to fetch stock batches' });
    }
});
/**
 * PATCH /api/inventory/stock-batches/:id
 * Update batch expiry_date
 */
router.patch('/stock-batches/:id', (0, requirePermission_1.requirePermission)('inventory', 'write'), (req, res) => {
    try {
        const batchId = Number(req.params.id);
        const { expiry_date } = req.body;
        const batch = db.prepare('SELECT id FROM stock_batches WHERE id = ?').get(batchId);
        if (!batch) {
            res.status(404).json({ error: 'Batch not found' });
            return;
        }
        db.prepare(`
      UPDATE stock_batches
      SET expiry_date = ?
      WHERE id = ?
    `).run(expiry_date || null, batchId);
        const updated = db.prepare('SELECT * FROM stock_batches WHERE id = ?').get(batchId);
        res.json(updated);
    }
    catch (error) {
        logger_1.default.error('Update batch expiry error:', error);
        res.status(500).json({ error: 'Failed to update batch expiry date' });
    }
});
/**
 * PATCH /api/inventory/stock-batches/:id/halt
 * Halt a batch (exclude from FEFO consumption)
 */
router.patch('/stock-batches/:id/halt', (0, requirePermission_1.requirePermission)('inventory', 'write'), (req, res) => {
    try {
        const batchId = Number(req.params.id);
        const { reason } = req.body;
        const batch = db.prepare('SELECT id, halted FROM stock_batches WHERE id = ?').get(batchId);
        if (!batch) {
            res.status(404).json({ error: 'Batch not found' });
            return;
        }
        if (batch.halted) {
            res.status(400).json({ error: 'Batch is already halted' });
            return;
        }
        db.prepare(`
      UPDATE stock_batches
      SET halted = 1, halted_reason = ?
      WHERE id = ?
    `).run(reason || null, batchId);
        const updated = db.prepare('SELECT * FROM stock_batches WHERE id = ?').get(batchId);
        res.json(updated);
    }
    catch (error) {
        logger_1.default.error('Halt batch error:', error);
        res.status(500).json({ error: 'Failed to halt batch' });
    }
});
/**
 * PATCH /api/inventory/stock-batches/:id/unhalt
 * Unhalt a batch (re-enable in FEFO consumption)
 */
router.patch('/stock-batches/:id/unhalt', (0, requirePermission_1.requirePermission)('inventory', 'write'), (req, res) => {
    try {
        const batchId = Number(req.params.id);
        const batch = db.prepare('SELECT id, halted FROM stock_batches WHERE id = ?').get(batchId);
        if (!batch) {
            res.status(404).json({ error: 'Batch not found' });
            return;
        }
        if (!batch.halted) {
            res.status(400).json({ error: 'Batch is not halted' });
            return;
        }
        db.prepare(`
      UPDATE stock_batches
      SET halted = 0, halted_reason = NULL
      WHERE id = ?
    `).run(batchId);
        const updated = db.prepare('SELECT * FROM stock_batches WHERE id = ?').get(batchId);
        res.json(updated);
    }
    catch (error) {
        logger_1.default.error('Unhalt batch error:', error);
        res.status(500).json({ error: 'Failed to unhalt batch' });
    }
});
exports.default = router;
