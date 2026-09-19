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

import { Router, Request, Response } from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { getStockDiscrepancies } from '../config/database';

const router = Router();

// All endpoints require authentication.
router.use(authenticateToken);

/**
 * GET /api/admin/health/stock-discrepancies
 * Read-only list of (item, warehouse) pairs where stock_balances.quantity
 * diverges from SUM(stock_movements). Boot never repairs these — see the
 * boot-task-gating spec. Repair happens via the explicit gated scripts.
 */
router.get('/health/stock-discrepancies', requirePermission('admin', 'read'), (_req: Request, res: Response): void => {
  try {
    const discrepancies = getStockDiscrepancies();
    res.json({
      success: true,
      data: discrepancies,
      count: discrepancies.length,
      error: null,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      data: null,
      error: 'Failed to read stock discrepancies',
    });
  }
});

export default router;
