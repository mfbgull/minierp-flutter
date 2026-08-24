"use strict";
/**
 * Admin Health Routes
 * -------------------
 * Read-only operational health endpoints for administrators.
 *
 * Mount point: /api/admin
 *
 * Auth:
 *   - All routes gated by authenticateToken + requirePermission('admin', 'read').
 *     The Admin role bypasses permission checks, so effectively admins-only.
 */
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const database_1 = require("../config/database");
const router = (0, express_1.Router)();
// All endpoints require authentication.
router.use(auth_1.authenticateToken);
/**
 * GET /api/admin/health/stock-discrepancies
 * Read-only list of (item, warehouse) pairs where stock_balances.quantity
 * diverges from SUM(stock_movements). Boot never repairs these — see the
 * boot-task-gating spec. Repair happens via the explicit gated scripts.
 */
router.get('/health/stock-discrepancies', (0, requirePermission_1.requirePermission)('admin', 'read'), (_req, res) => {
    try {
        const discrepancies = (0, database_1.getStockDiscrepancies)();
        res.json({
            success: true,
            data: discrepancies,
            count: discrepancies.length,
            error: null,
        });
    }
    catch (error) {
        res.status(500).json({
            success: false,
            data: null,
            error: 'Failed to read stock discrepancies',
        });
    }
});
exports.default = router;
//# sourceMappingURL=adminHealth.js.map