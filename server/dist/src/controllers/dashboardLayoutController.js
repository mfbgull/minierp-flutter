"use strict";
/**
 * DashboardLayout Controller
 *
 * CRUD endpoints for per-user customizable dashboard layouts.
 * Layout operations are scoped to the authenticated user's own layouts.
 *
 * @see dashboard-customization-spec.md §5 — API Endpoints
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const logger_1 = __importDefault(require("../utils/logger"));
const DashboardLayout_1 = __importDefault(require("../models/DashboardLayout"));
// ═══════════════════════════════════════════════════════════════
//  LAYOUT CRUD
// ═══════════════════════════════════════════════════════════════
/**
 * GET /api/dashboard/layout/active
 * Get the active layout for the current user.
 * Returns 404 (with data: null) if no layout exists yet.
 */
function getActiveLayout(req, res) {
    try {
        const userId = req.user.id;
        const layout = DashboardLayout_1.default.getActiveLayout(userId);
        if (!layout) {
            res.status(404).json({ success: true, data: null });
            return;
        }
        res.json({ success: true, data: layout });
    }
    catch (error) {
        logger_1.default.error('Get active layout error:', error);
        res.status(500).json({ error: 'Failed to fetch active layout' });
    }
}
/**
 * POST /api/dashboard/layout
 * Create a new layout for the current user.
 * If `is_active` is true (default), any other active layout is deactivated.
 * Body: { layout_name?, blocks?, is_active? }
 */
function createLayout(req, res) {
    try {
        const userId = req.user.id;
        const { layout_name, blocks, is_active } = req.body;
        const layout = DashboardLayout_1.default.createLayout({
            user_id: userId,
            layout_name: layout_name || 'Default',
            blocks: blocks || [],
        }, is_active !== false);
        res.status(201).json({ success: true, data: layout });
    }
    catch (error) {
        // Handle UNIQUE constraint violation (duplicate layout name)
        if (error?.code === 'SQLITE_CONSTRAINT_UNIQUE') {
            res.status(409).json({ error: 'A layout with this name already exists' });
            return;
        }
        logger_1.default.error('Create layout error:', error);
        res.status(500).json({ error: 'Failed to create layout' });
    }
}
/**
 * PUT /api/dashboard/layout/:id
 * Update an existing layout's blocks and/or name.
 * Body: { blocks?, layout_name? }
 */
function updateLayout(req, res) {
    try {
        const userId = req.user.id;
        const layoutId = Number(req.params.id);
        const { blocks, layout_name } = req.body;
        const updated = DashboardLayout_1.default.updateLayout(layoutId, userId, {
            blocks,
            layout_name,
        });
        if (!updated) {
            res.status(404).json({ error: 'Layout not found' });
            return;
        }
        res.json({ success: true, message: 'Layout updated' });
    }
    catch (error) {
        logger_1.default.error('Update layout error:', error);
        res.status(500).json({ error: 'Failed to update layout' });
    }
}
/**
 * PATCH /api/dashboard/layout/:id/rename
 * Rename a layout.
 * Body: { layout_name }
 */
function renameLayout(req, res) {
    try {
        const userId = req.user.id;
        const layoutId = Number(req.params.id);
        const { layout_name } = req.body;
        if (!layout_name || typeof layout_name !== 'string' || layout_name.trim().length === 0) {
            res.status(400).json({ error: 'layout_name is required and cannot be empty' });
            return;
        }
        const updated = DashboardLayout_1.default.renameLayout(layoutId, userId, layout_name.trim());
        if (!updated) {
            res.status(404).json({ error: 'Layout not found' });
            return;
        }
        res.json({ success: true, message: 'Layout renamed' });
    }
    catch (error) {
        if (error?.code === 'SQLITE_CONSTRAINT_UNIQUE') {
            res.status(409).json({ error: 'A layout with this name already exists' });
            return;
        }
        logger_1.default.error('Rename layout error:', error);
        res.status(500).json({ error: 'Failed to rename layout' });
    }
}
/**
 * DELETE /api/dashboard/layout/:id
 * Delete a layout by ID, scoped to the current user.
 */
function deleteLayout(req, res) {
    try {
        const userId = req.user.id;
        const layoutId = Number(req.params.id);
        const deleted = DashboardLayout_1.default.deleteLayout(layoutId, userId);
        if (!deleted) {
            res.status(404).json({ error: 'Layout not found' });
            return;
        }
        res.json({ success: true, message: 'Layout deleted' });
    }
    catch (error) {
        logger_1.default.error('Delete layout error:', error);
        res.status(500).json({ error: 'Failed to delete layout' });
    }
}
/**
 * GET /api/dashboard/layouts
 * List all layouts for the current user, most recently updated first.
 */
function listLayouts(req, res) {
    try {
        const userId = req.user.id;
        const layouts = DashboardLayout_1.default.listLayouts(userId);
        res.json({ success: true, data: layouts });
    }
    catch (error) {
        logger_1.default.error('List layouts error:', error);
        res.status(500).json({ error: 'Failed to list layouts' });
    }
}
/**
 * PUT /api/dashboard/layout/:id/activate
 * Set a layout as the active layout (deactivates all others for this user).
 */
function setActiveLayout(req, res) {
    try {
        const userId = req.user.id;
        const layoutId = Number(req.params.id);
        const activated = DashboardLayout_1.default.setActiveLayout(layoutId, userId);
        if (!activated) {
            res.status(404).json({ error: 'Layout not found' });
            return;
        }
        res.json({ success: true, message: 'Layout activated' });
    }
    catch (error) {
        logger_1.default.error('Set active layout error:', error);
        res.status(500).json({ error: 'Failed to set active layout' });
    }
}
/**
 * POST /api/dashboard/layout/duplicate
 * Duplicate an existing layout with "(Copy)" appended to the name.
 * Body: { id }
 */
function duplicateLayout(req, res) {
    try {
        const userId = req.user.id;
        const { id } = req.body;
        if (!id || typeof id !== 'number') {
            res.status(400).json({ error: 'Layout id is required and must be a number' });
            return;
        }
        const newLayout = DashboardLayout_1.default.duplicateLayout(id, userId);
        if (!newLayout) {
            res.status(404).json({ error: 'Layout not found' });
            return;
        }
        res.status(201).json({ success: true, data: newLayout });
    }
    catch (error) {
        logger_1.default.error('Duplicate layout error:', error);
        res.status(500).json({ error: 'Failed to duplicate layout' });
    }
}
exports.default = {
    getActiveLayout,
    createLayout,
    updateLayout,
    renameLayout,
    deleteLayout,
    listLayouts,
    setActiveLayout,
    duplicateLayout,
};
