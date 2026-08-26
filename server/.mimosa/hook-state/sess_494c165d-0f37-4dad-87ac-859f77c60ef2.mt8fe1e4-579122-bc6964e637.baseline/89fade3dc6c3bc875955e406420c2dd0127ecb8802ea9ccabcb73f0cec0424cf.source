/**
 * Custom Reports Controller
 * API endpoints for managing saved report definitions.
 */

import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import CustomReport from '../models/CustomReport';
import { getAllEntities, getEntity } from '../services/entityRegistry';
import { executeReport } from '../services/reportQueryEngine';
import type { ReportConfig } from '../services/reportQueryEngine';
import { validateConfigExpressions, ExpressionValidationError } from '../services/expressionValidator';
import logger from '../utils/logger';

// ── Config Validation ────────────────────────────────────────

interface ValidationError {
  field: string;
  message: string;
}

/**
 * Validate a report config structure before saving.
 * Ensures the entity exists, columns are specified, and field references are valid.
 */
function validateReportConfig(config: any): ValidationError[] {
  const errors: ValidationError[] = [];

  if (!config.entity || typeof config.entity !== 'string') {
    errors.push({ field: 'entity', message: 'Entity is required' });
    return errors; // Can't validate further without an entity
  }

  const entity = getEntity(config.entity);
  if (!entity) {
    errors.push({ field: 'entity', message: `Entity "${config.entity}" not found in registry` });
    return errors;
  }

  // Build a set of valid field names (including computed column names)
  const validFields = new Set(entity.fields.map((f: any) => f.name));

  // Validate columns
  if (!Array.isArray(config.columns) || config.columns.length === 0) {
    errors.push({ field: 'columns', message: 'At least one column is required' });
  } else {
    for (let i = 0; i < config.columns.length; i++) {
      const col = config.columns[i];
      if (!col.field || typeof col.field !== 'string') {
        errors.push({ field: `columns[${i}].field`, message: 'Column field name is required' });
      } else if (!validFields.has(col.field)) {
        // Check if it's a computed column reference
        const isComputed = Array.isArray(config.computedColumns) &&
          config.computedColumns.some((cc: any) => cc.name === col.field);
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
      } else if (!validFields.has(s.field)) {
        const isComputed = Array.isArray(config.computedColumns) &&
          config.computedColumns.some((cc: any) => cc.name === s.field);
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
  // REP-18: computed-column expressions must pass the safe-grammar
  // validator before a config may be stored.
  if (Array.isArray(config.computedColumns)) {
    try {
      validateConfigExpressions(config, validFields);
    } catch (error) {
      if (error instanceof ExpressionValidationError) {
        errors.push({
          field: 'computedColumns',
          message: `Invalid expression: ${error.message}`,
        });
      } else {
        throw error;
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
function listReports(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const reports = CustomReport.findByUser(userId);
    res.json({ success: true, data: reports });
  } catch (error: any) {
    logger.error('List custom reports error:', error.message);
    res.status(500).json({ error: 'Failed to list reports' });
  }
}

/**
 * GET /api/reports/custom/:id
 * Get a single report by ID (user-scoped).
 */
function getReport(req: AuthRequest, res: Response): void {
  try {
    const id = Number(req.params.id);
    const userId = req.user!.id;
    const report = CustomReport.findById(id, userId);

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
  } catch (error: any) {
    logger.error('Get custom report error:', error.message);
    res.status(500).json({ error: 'Failed to get report' });
  }
}

/**
 * POST /api/reports/custom
 * Create a new saved report.
 */
function createReport(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
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

    const report = CustomReport.create({
      user_id: userId,
      name: name.trim(),
      description: description || undefined,
      config,
    });

    res.status(201).json({ success: true, data: report });
  } catch (error: any) {
    logger.error('Create custom report error:', error.message);
    res.status(500).json({ error: 'Failed to create report' });
  }
}

/**
 * PUT /api/reports/custom/:id
 * Update a saved report.
 */
function updateReport(req: AuthRequest, res: Response): void {
  try {
    const id = Number(req.params.id);
    const userId = req.user!.id;
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

    const updated = CustomReport.update(id, userId, {
      name: name !== undefined ? name.trim() : undefined,
      description,
      config,
    });

    if (!updated) {
      res.status(404).json({ error: 'Report not found or not owned by user' });
      return;
    }

    // Return the updated report
    const report = CustomReport.findById(id, userId);
    const parsed = report ? { ...report, config: JSON.parse(report.config) } : null;

    res.json({ success: true, data: parsed });
  } catch (error: any) {
    logger.error('Update custom report error:', error.message);
    res.status(500).json({ error: 'Failed to update report' });
  }
}

/**
 * DELETE /api/reports/custom/:id
 * Delete a saved report.
 */
function deleteReport(req: AuthRequest, res: Response): void {
  try {
    const id = Number(req.params.id);
    const userId = req.user!.id;

    const deleted = CustomReport.remove(id, userId);

    if (!deleted) {
      res.status(404).json({ error: 'Report not found or not owned by user' });
      return;
    }

    res.json({ success: true, message: 'Report deleted' });
  } catch (error: any) {
    logger.error('Delete custom report error:', error.message);
    res.status(500).json({ error: 'Failed to delete report' });
  }
}

/**
 * POST /api/reports/custom/:id/duplicate
 * Duplicate a saved report.
 */
function duplicateReport(req: AuthRequest, res: Response): void {
  try {
    const id = Number(req.params.id);
    const userId = req.user!.id;

    const newReport = CustomReport.duplicate(id, userId);

    if (!newReport) {
      res.status(404).json({ error: 'Report not found' });
      return;
    }

    res.status(201).json({ success: true, data: newReport });
  } catch (error: any) {
    logger.error('Duplicate custom report error:', error.message);
    res.status(500).json({ error: 'Failed to duplicate report' });
  }
}

// ── Report Execution ─────────────────────────────────────────

/**
 * POST /api/reports/custom/run
 * Execute a report — either from a saved report ID or from an inline config.
 * Body: { reportId?: number, config?: ReportConfig }
 */
function runReport(req: AuthRequest, res: Response): void {
  try {
    const userId = req.user!.id;
    const { reportId, config: inlineConfig } = req.body;

    let config: ReportConfig;

    if (reportId) {
      // Load from saved report
      const report = CustomReport.findById(reportId, userId);
      if (!report) {
        res.status(404).json({ error: 'Report not found' });
        return;
      }
      config = JSON.parse(report.config) as ReportConfig;

      // Mark as last run
      CustomReport.markRun(reportId);
    } else if (inlineConfig) {
      config = inlineConfig as ReportConfig;
    } else {
      res.status(400).json({ error: 'Either reportId or config is required' });
      return;
    }

    const result = executeReport(config);
    res.json({
      success: true,
      data: result,
    });
  } catch (error: unknown) {
    // REP-18: unsafe computed-column expressions surface as a 400 naming
    // the offending token — identical for stored and inline configs.
    if (error instanceof ExpressionValidationError) {
      res.status(400).json({ error: `Invalid report config: ${error.message}` });
      return;
    }
    const message = error instanceof Error ? error.message : String(error);
    logger.error('Run report error:', message);
    res.status(400).json({ error: message });
  }
}

// ── Entity & Template Discovery ──────────────────────────────

/**
 * GET /api/reports/custom/entities
 * List all available entities with their fields and join info.
 */
function listEntities(_req: Request, res: Response): void {
  try {
    const entities = getAllEntities();
    res.json({ success: true, data: entities });
  } catch (error: any) {
    logger.error('List entities error:', error.message);
    res.status(500).json({ error: 'Failed to list entities' });
  }
}

/**
 * GET /api/reports/custom/entities/:key
 * Get a single entity definition by key.
 */
function getEntityDetail(req: Request, res: Response): void {
  try {
    const entityKey = String(req.params.key);
    const entity = getEntity(entityKey);
    if (!entity) {
      res.status(404).json({ error: 'Entity not found' });
      return;
    }
    res.json({ success: true, data: entity });
  } catch (error: any) {
    logger.error('Get entity error:', error.message);
    res.status(500).json({ error: 'Failed to get entity' });
  }
}

/**
 * POST /api/reports/custom/templates
 * Save the current report config as a reusable template.
 */
function createTemplate(req: AuthRequest, res: Response): void {
  try {
    // authz-hardening (reporting-search-remediation / REP-19): every
    // template created here is a SYSTEM template (user_id 0) visible to
    // all users — planting one must not be within reach of an ordinary
    // reports:create holder.
    if (req.user?.role !== 'admin') {
      res.status(403).json({ error: 'Only administrators can create system report templates' });
      return;
    }

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

    // REP-18: template configs are executed later — expressions must pass
    // the safe-grammar validator before storage.
    try {
      validateConfigExpressions(config, entityFieldNames(config.entity));
    } catch (error) {
      if (error instanceof ExpressionValidationError) {
        res.status(400).json({ error: `Invalid template config: ${error.message}` });
        return;
      }
      throw error;
    }

    const template = CustomReport.createTemplate({
      name: name.trim(),
      description: description || undefined,
      config,
    });

    const parsed = { ...template, config: JSON.parse(template.config) };
    res.status(201).json({ success: true, data: parsed });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create template';
    logger.error('Create template error:', message);
    res.status(500).json({ error: 'Failed to create template' });
  }
}

/**
 * Field-name scope for expression validation: every field of the config's
 * entity. Computed-column names are added inside the validator.
 */
function entityFieldNames(entityKey: unknown): Set<string> {
  const entity = typeof entityKey === 'string' ? getEntity(entityKey) : undefined;
  if (!entity) {
    return new Set();
  }
  return new Set(entity.fields.map((f: { name: string }) => f.name));
}

/**
 * GET /api/reports/custom/templates
 * List pre-built report templates.
 */
function listTemplates(_req: Request, res: Response): void {
  try {
    const templates = CustomReport.getTemplates();
    const parsed = templates.map(t => ({
      ...t,
      config: JSON.parse(t.config),
    }));
    res.json({ success: true, data: parsed });
  } catch (error: any) {
    logger.error('List templates error:', error.message);
    res.status(500).json({ error: 'Failed to list templates' });
  }
}

export default {
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
