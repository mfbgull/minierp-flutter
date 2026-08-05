"use strict";
/**
 * Custom Reports Controller
 * API endpoints for managing saved report definitions.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const CustomReport_1 = __importDefault(require("../models/CustomReport"));
const entityRegistry_1 = require("../services/entityRegistry");
const reportQueryEngine_1 = require("../services/reportQueryEngine");
const logger_1 = __importDefault(require("../utils/logger"));
/**
 * Validate a report config structure before saving.
 * Ensures the entity exists, columns are specified, and field references are valid.
 */
function validateReportConfig(config) {
    const errors = [];
    if (!config.entity || typeof config.entity !== 'string') {
        errors.push({ field: 'entity', message: 'Entity is required' });
        return errors; // Can't validate further without an entity
    }
    const entity = (0, entityRegistry_1.getEntity)(config.entity);
    if (!entity) {
        errors.push({ field: 'entity', message: `Entity "${config.entity}" not found in registry` });
        return errors;
    }
    // Build a set of valid field names (including computed column names)
    const validFields = new Set(entity.fields.map((f) => f.name));
    // Validate columns
    if (!Array.isArray(config.columns) || config.columns.length === 0) {
        errors.push({ field: 'columns', message: 'At least one column is required' });
    }
    else {
        for (let i = 0; i < config.columns.length; i++) {
            const col = config.columns[i];
            if (!col.field || typeof col.field !== 'string') {
                errors.push({ field: `columns[${i}].field`, message: 'Column field name is required' });
            }
            else if (!validFields.has(col.field)) {
                // Check if it's a computed column reference
                const isComputed = Array.isArray(config.computedColumns) &&
                    config.computedColumns.some((cc) => cc.name === col.field);
                if (!isComputed) {
                    errors.push({ field: `columns[${i}].field`, message: `Field "${col.field}" not found on entity "${config.entity}"` });
                }
            }
        }
    }
    // Validate sort fields
    if (Array.isArray(config.sort)) {
        for (let i = 0; i < config.sort.length; i++) {
            const s = config.sort[i];
            if (!s.field || typeof s.field !== 'string') {
                errors.push({ field: `sort[${i}].field`, message: 'Sort field name is required' });
            }
            else if (!validFields.has(s.field)) {
                const isComputed = Array.isArray(config.computedColumns) &&
                    config.computedColumns.some((cc) => cc.name === s.field);
                if (!isComputed) {
                    errors.push({ field: `sort[${i}].field`, message: `Sort field "${s.field}" not found on entity "${config.entity}"` });
                }
            }
            if (s.direction && !['asc', 'desc'].includes(s.direction.toLowerCase())) {
                errors.push({ field: `sort[${i}].direction`, message: 'Sort direction must be "asc" or "desc"' });
            }
        }
    }
    // Validate filter fields
    if (Array.isArray(config.filters)) {
        for (let i = 0; i < config.filters.length; i++) {
            const f = config.filters[i];
            if (f.field && !validFields.has(f.field)) {
                errors.push({ field: `filters[${i}].field`, message: `Filter field "${f.field}" not found on entity "${config.entity}"` });
            }
        }
    }
    return errors;
}
// ── Saved Report CRUD ────────────────────────────────────────
/**
 * GET /api/reports/custom
 * List all reports for the current user.
 */
function listReports(req, res) {
    try {
        const userId = req.user.id;
        const reports = CustomReport_1.default.findByUser(userId);
        res.json({ success: true, data: reports });
    }
    catch (error) {
        logger_1.default.error('List custom reports error:', error.message);
        res.status(500).json({ error: 'Failed to list reports' });
    }
}
/**
 * GET /api/reports/custom/:id
 * Get a single report by ID (user-scoped).
 */
function getReport(req, res) {
    try {
        const id = Number(req.params.id);
        const userId = req.user.id;
        const report = CustomReport_1.default.findById(id, userId);
        if (!report) {
            res.status(404).json({ error: 'Report not found' });
            return;
        }
        // Parse the stored JSON config so the frontend gets an object
        const parsed = {
            ...report,
            config: JSON.parse(report.config),
        };
        res.json({ success: true, data: parsed });
    }
    catch (error) {
        logger_1.default.error('Get custom report error:', error.message);
        res.status(500).json({ error: 'Failed to get report' });
    }
}
/**
 * POST /api/reports/custom
 * Create a new saved report.
 */
function createReport(req, res) {
    try {
        const userId = req.user.id;
        const { name, description, config } = req.body;
        if (!name || typeof name !== 'string' || name.trim().length === 0) {
            res.status(400).json({ error: 'Report name is required' });
            return;
        }
        if (name.length > 100) {
            res.status(400).json({ error: 'Report name must be 100 characters or less' });
            return;
        }
        if (!config || typeof config !== 'object') {
            res.status(400).json({ error: 'Report config is required and must be an object' });
            return;
        }
        const validationErrors = validateReportConfig(config);
        if (validationErrors.length > 0) {
            res.status(400).json({ error: 'Invalid report config', details: validationErrors });
            return;
        }
        const report = CustomReport_1.default.create({
            user_id: userId,
            name: name.trim(),
            description: description || undefined,
            config,
        });
        res.status(201).json({ success: true, data: report });
    }
    catch (error) {
        logger_1.default.error('Create custom report error:', error.message);
        res.status(500).json({ error: 'Failed to create report' });
    }
}
/**
 * PUT /api/reports/custom/:id
 * Update a saved report.
 */
function updateReport(req, res) {
    try {
        const id = Number(req.params.id);
        const userId = req.user.id;
        const { name, description, config } = req.body;
        if (name !== undefined && (typeof name !== 'string' || name.trim().length === 0)) {
            res.status(400).json({ error: 'Report name must be a non-empty string' });
            return;
        }
        if (config !== undefined) {
            if (typeof config !== 'object') {
                res.status(400).json({ error: 'Report config must be an object' });
                return;
            }
            const validationErrors = validateReportConfig(config);
            if (validationErrors.length > 0) {
                res.status(400).json({ error: 'Invalid report config', details: validationErrors });
                return;
            }
        }
        const updated = CustomReport_1.default.update(id, userId, {
            name: name !== undefined ? name.trim() : undefined,
            description,
            config,
        });
        if (!updated) {
            res.status(404).json({ error: 'Report not found or not owned by user' });
            return;
        }
        // Return the updated report
        const report = CustomReport_1.default.findById(id, userId);
        const parsed = report ? { ...report, config: JSON.parse(report.config) } : null;
        res.json({ success: true, data: parsed });
    }
    catch (error) {
        logger_1.default.error('Update custom report error:', error.message);
        res.status(500).json({ error: 'Failed to update report' });
    }
}
/**
 * DELETE /api/reports/custom/:id
 * Delete a saved report.
 */
function deleteReport(req, res) {
    try {
        const id = Number(req.params.id);
        const userId = req.user.id;
        const deleted = CustomReport_1.default.remove(id, userId);
        if (!deleted) {
            res.status(404).json({ error: 'Report not found or not owned by user' });
            return;
        }
        res.json({ success: true, message: 'Report deleted' });
    }
    catch (error) {
        logger_1.default.error('Delete custom report error:', error.message);
        res.status(500).json({ error: 'Failed to delete report' });
    }
}
/**
 * POST /api/reports/custom/:id/duplicate
 * Duplicate a saved report.
 */
function duplicateReport(req, res) {
    try {
        const id = Number(req.params.id);
        const userId = req.user.id;
        const newReport = CustomReport_1.default.duplicate(id, userId);
        if (!newReport) {
            res.status(404).json({ error: 'Report not found' });
            return;
        }
        res.status(201).json({ success: true, data: newReport });
    }
    catch (error) {
        logger_1.default.error('Duplicate custom report error:', error.message);
        res.status(500).json({ error: 'Failed to duplicate report' });
    }
}
// ── Report Execution ─────────────────────────────────────────
/**
 * POST /api/reports/custom/run
 * Execute a report — either from a saved report ID or from an inline config.
 * Body: { reportId?: number, config?: ReportConfig }
 */
function runReport(req, res) {
    try {
        const userId = req.user.id;
        const { reportId, config: inlineConfig } = req.body;
        let config;
        if (reportId) {
            // Load from saved report
            const report = CustomReport_1.default.findById(reportId, userId);
            if (!report) {
                res.status(404).json({ error: 'Report not found' });
                return;
            }
            config = JSON.parse(report.config);
            // Mark as last run
            CustomReport_1.default.markRun(reportId);
        }
        else if (inlineConfig) {
            config = inlineConfig;
        }
        else {
            res.status(400).json({ error: 'Either reportId or config is required' });
            return;
        }
        const result = (0, reportQueryEngine_1.executeReport)(config);
        res.json({
            success: true,
            data: result,
        });
    }
    catch (error) {
        logger_1.default.error('Run report error:', error.message);
        res.status(400).json({ error: error.message });
    }
}
// ── Entity & Template Discovery ──────────────────────────────
/**
 * GET /api/reports/custom/entities
 * List all available entities with their fields and join info.
 */
function listEntities(_req, res) {
    try {
        const entities = (0, entityRegistry_1.getAllEntities)();
        res.json({ success: true, data: entities });
    }
    catch (error) {
        logger_1.default.error('List entities error:', error.message);
        res.status(500).json({ error: 'Failed to list entities' });
    }
}
/**
 * GET /api/reports/custom/entities/:key
 * Get a single entity definition by key.
 */
function getEntityDetail(req, res) {
    try {
        const entityKey = String(req.params.key);
        const entity = (0, entityRegistry_1.getEntity)(entityKey);
        if (!entity) {
            res.status(404).json({ error: 'Entity not found' });
            return;
        }
        res.json({ success: true, data: entity });
    }
    catch (error) {
        logger_1.default.error('Get entity error:', error.message);
        res.status(500).json({ error: 'Failed to get entity' });
    }
}
/**
 * POST /api/reports/custom/templates
 * Save the current report config as a reusable template.
 */
function createTemplate(req, res) {
    try {
        const { name, description, config } = req.body;
        if (!name || typeof name !== 'string' || name.trim().length === 0) {
            res.status(400).json({ error: 'Template name is required' });
            return;
        }
        if (name.length > 100) {
            res.status(400).json({ error: 'Template name must be 100 characters or less' });
            return;
        }
        if (!config || typeof config !== 'object') {
            res.status(400).json({ error: 'Template config is required' });
            return;
        }
        const template = CustomReport_1.default.createTemplate({
            name: name.trim(),
            description: description || undefined,
            config,
        });
        const parsed = { ...template, config: JSON.parse(template.config) };
        res.status(201).json({ success: true, data: parsed });
    }
    catch (error) {
        logger_1.default.error('Create template error:', error.message);
        res.status(500).json({ error: 'Failed to create template' });
    }
}
/**
 * GET /api/reports/custom/templates
 * List pre-built report templates.
 */
function listTemplates(_req, res) {
    try {
        const templates = CustomReport_1.default.getTemplates();
        const parsed = templates.map(t => ({
            ...t,
            config: JSON.parse(t.config),
        }));
        res.json({ success: true, data: parsed });
    }
    catch (error) {
        logger_1.default.error('List templates error:', error.message);
        res.status(500).json({ error: 'Failed to list templates' });
    }
}
exports.default = {
    listReports,
    getReport,
    createReport,
    updateReport,
    deleteReport,
    duplicateReport,
    listEntities,
    getEntityDetail,
    listTemplates,
    createTemplate,
    runReport,
};
//# sourceMappingURL=customReportsController.js.map