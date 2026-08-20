import { Router } from 'express';
import Database from 'better-sqlite3';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import logger from '../utils/logger';

const router = Router();
router.use(authenticateToken);

// Will be injected via initStockBatchesRoutes
let db: Database.Database;

export function initStockBatchesRoutes(database: Database.Database): Router {
  db = database;
  return router;
}

/**
 * GET /api/stock-batches
 * List batches with optional filters
 */
router.get('/stock-batches', requirePermission('inventory', 'read'), (req, res) => {
  try {
    const { item_id, warehouse_id, halted } = req.query;

    let sql = `
      SELECT sb.*,
        i.item_code, i.item_name,
        w.warehouse_code, w.warehouse_name
      FROM stock_batches sb
      LEFT JOIN items i ON sb.item_id = i.id
      LEFT JOIN warehouses w ON sb.warehouse_id = w.id
      WHERE sb.quantity_remaining > 0
    `;
    const params: any[] = [];

    if (item_id) {
      sql += ' AND sb.item_id = ?';
      params.push(Number(item_id));
    }
    if (warehouse_id) {
      sql += ' AND sb.warehouse_id = ?';
      params.push(Number(warehouse_id));
    }
    if (halted !== undefined) {
      sql += ' AND sb.halted = ?';
      params.push(halted === 'true' ? 1 : 0);
    }

    sql += ' ORDER BY sb.received_date ASC, sb.id ASC';

    const batches = db.prepare(sql).all(...params);
    res.json(batches);
  } catch (error: any) {
    logger.error('Get stock batches error:', error);
    res.status(500).json({ error: 'Failed to fetch stock batches' });
  }
});

/**
 * PATCH /api/stock-batches/:id
 * Update batch expiry_date
 */
router.patch('/stock-batches/:id', requirePermission('inventory', 'write'), (req, res) => {
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
  } catch (error: any) {
    logger.error('Update batch expiry error:', error);
    res.status(500).json({ error: 'Failed to update batch expiry date' });
  }
});

/**
 * PATCH /api/stock-batches/:id/halt
 * Halt a batch (exclude from FEFO consumption)
 */
router.patch('/stock-batches/:id/halt', requirePermission('inventory', 'write'), (req, res) => {
  try {
    const batchId = Number(req.params.id);
    const { reason } = req.body;

    const batch = db.prepare('SELECT id, halted FROM stock_batches WHERE id = ?').get(batchId) as { id: number; halted: number } | undefined;
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
  } catch (error: any) {
    logger.error('Halt batch error:', error);
    res.status(500).json({ error: 'Failed to halt batch' });
  }
});

/**
 * PATCH /api/stock-batches/:id/unhalt
 * Unhalt a batch (re-enable in FEFO consumption)
 */
router.patch('/stock-batches/:id/unhalt', requirePermission('inventory', 'write'), (req, res) => {
  try {
    const batchId = Number(req.params.id);

    const batch = db.prepare('SELECT id, halted FROM stock_batches WHERE id = ?').get(batchId) as { id: number; halted: number } | undefined;
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
  } catch (error: any) {
    logger.error('Unhalt batch error:', error);
    res.status(500).json({ error: 'Failed to unhalt batch' });
  }
});

export default router;
