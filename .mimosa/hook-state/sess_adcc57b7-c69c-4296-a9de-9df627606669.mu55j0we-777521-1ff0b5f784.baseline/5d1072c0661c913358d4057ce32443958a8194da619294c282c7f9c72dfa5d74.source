/**
 * DashboardLayout Controller
 *
 * CRUD endpoints for per-user customizable dashboard layouts.
 * Layout operations are scoped to the authenticated user's own layouts.
 *
 * @see dashboard-customization-spec.md §5 — API Endpoints
 */

import { Response } from 'express';
import { AuthRequest } from '../types';
import logger from '../utils/logger';
import DashboardLayoutModel from '../models/DashboardLayout';

// ═══════════════════════════════════════════════════════════════
//  LAYOUT CRUD
// ═══════════════════════════════════════════════════════════════

/**
 * GET /api/dashboard/layout/active
 * Get the active layout for the current user.
 * Returns 404 (with data: null) if no layout exists yet.
 */
function getActiveLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layout = DashboardLayoutModel.getActiveLayout(userId);

    if (!layout) {
      res.status(404).json({ success: true, data: null });
      return;
    }

    res.json({ success: true, data: layout });
  } catch (error) {
    logger.error('Get active layout error:', error);
    res.status(500).json({ error: 'Failed to fetch active layout' });
  }
}

/**
 * POST /api/dashboard/layout
 * Create a new layout for the current user.
 * If `is_active` is true (default), any other active layout is deactivated.
 * Body: { layout_name?, blocks?, is_active? }
 */
function createLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const { layout_name, blocks, is_active } = req.body;

    const layout = DashboardLayoutModel.createLayout(
      {
        user_id: userId,
        layout_name: layout_name || 'Default',
        blocks: blocks || [],
      },
      is_active !== false,
    );

    res.status(201).json({ success: true, data: layout });
  } catch (error: any) {
    // Handle UNIQUE constraint violation (duplicate layout name)
    if (error?.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      res.status(409).json({ error: 'A layout with this name already exists' });
      return;
    }
    logger.error('Create layout error:', error);
    res.status(500).json({ error: 'Failed to create layout' });
  }
}

/**
 * PUT /api/dashboard/layout/:id
 * Update an existing layout's blocks and/or name.
 * Body: { blocks?, layout_name? }
 */
function updateLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layoutId = Number(req.params.id);
    const { blocks, layout_name } = req.body;

    const updated = DashboardLayoutModel.updateLayout(layoutId, userId, {
      blocks,
      layout_name,
    });

    if (!updated) {
      res.status(404).json({ error: 'Layout not found' });
      return;
    }

    res.json({ success: true, message: 'Layout updated' });
  } catch (error) {
    logger.error('Update layout error:', error);
    res.status(500).json({ error: 'Failed to update layout' });
  }
}

/**
 * PATCH /api/dashboard/layout/:id/rename
 * Rename a layout.
 * Body: { layout_name }
 */
function renameLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layoutId = Number(req.params.id);
    const { layout_name } = req.body;

    if (!layout_name || typeof layout_name !== 'string' || layout_name.trim().length === 0) {
      res.status(400).json({ error: 'layout_name is required and cannot be empty' });
      return;
    }

    const updated = DashboardLayoutModel.renameLayout(layoutId, userId, layout_name.trim());

    if (!updated) {
      res.status(404).json({ error: 'Layout not found' });
      return;
    }

    res.json({ success: true, message: 'Layout renamed' });
  } catch (error: any) {
    if (error?.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      res.status(409).json({ error: 'A layout with this name already exists' });
      return;
    }
    logger.error('Rename layout error:', error);
    res.status(500).json({ error: 'Failed to rename layout' });
  }
}

/**
 * DELETE /api/dashboard/layout/:id
 * Delete a layout by ID, scoped to the current user.
 */
function deleteLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layoutId = Number(req.params.id);

    const deleted = DashboardLayoutModel.deleteLayout(layoutId, userId);

    if (!deleted) {
      res.status(404).json({ error: 'Layout not found' });
      return;
    }

    res.json({ success: true, message: 'Layout deleted' });
  } catch (error) {
    logger.error('Delete layout error:', error);
    res.status(500).json({ error: 'Failed to delete layout' });
  }
}

/**
 * GET /api/dashboard/layouts
 * List all layouts for the current user, most recently updated first.
 */
function listLayouts(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layouts = DashboardLayoutModel.listLayouts(userId);

    res.json({ success: true, data: layouts });
  } catch (error) {
    logger.error('List layouts error:', error);
    res.status(500).json({ error: 'Failed to list layouts' });
  }
}

/**
 * PUT /api/dashboard/layout/:id/activate
 * Set a layout as the active layout (deactivates all others for this user).
 */
function setActiveLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const layoutId = Number(req.params.id);

    const activated = DashboardLayoutModel.setActiveLayout(layoutId, userId);

    if (!activated) {
      res.status(404).json({ error: 'Layout not found' });
      return;
    }

    res.json({ success: true, message: 'Layout activated' });
  } catch (error) {
    logger.error('Set active layout error:', error);
    res.status(500).json({ error: 'Failed to set active layout' });
  }
}

/**
 * POST /api/dashboard/layout/duplicate
 * Duplicate an existing layout with "(Copy)" appended to the name.
 * Body: { id }
 */
function duplicateLayout(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const { id } = req.body;

    if (!id || typeof id !== 'number') {
      res.status(400).json({ error: 'Layout id is required and must be a number' });
      return;
    }

    const newLayout = DashboardLayoutModel.duplicateLayout(id, userId);

    if (!newLayout) {
      res.status(404).json({ error: 'Layout not found' });
      return;
    }

    res.status(201).json({ success: true, data: newLayout });
  } catch (error) {
    logger.error('Duplicate layout error:', error);
    res.status(500).json({ error: 'Failed to duplicate layout' });
  }
}

export default {
  getActiveLayout,
  createLayout,
  updateLayout,
  renameLayout,
  deleteLayout,
  listLayouts,
  setActiveLayout,
  duplicateLayout,
};
