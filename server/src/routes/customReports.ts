/**
 * Custom Reports Routes
 * API endpoints for the ad-hoc report builder.
 */

import { Router } from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import customReportsController from '../controllers/customReportsController';

const router: Router = Router();

// All routes require authentication
router.use(authenticateToken);

// ── Entity Discovery (no saved report needed) ───────────────
router.get('/entities', requirePermission('reports', 'read'), customReportsController.listEntities);
router.get('/entities/:key', requirePermission('reports', 'read'), customReportsController.getEntityDetail);

// ── Templates ───────────────────────────────────────────────
router.get('/templates', requirePermission('reports', 'read'), customReportsController.listTemplates);
router.post('/templates', requirePermission('reports', 'create'), validateZodBody(zodBodySchemas.object), customReportsController.createTemplate);

// ── Saved Reports CRUD ──────────────────────────────────────
router.get('/', requirePermission('reports', 'read'), customReportsController.listReports);
router.get('/:id', requirePermission('reports', 'read'), customReportsController.getReport);
router.post('/', requirePermission('reports', 'create'), validateZodBody(zodBodySchemas.reportCreate), customReportsController.createReport);
router.put('/:id', requirePermission('reports', 'update'), validateZodBody(zodBodySchemas.object), customReportsController.updateReport);
router.delete('/:id', requirePermission('reports', 'delete'), customReportsController.deleteReport);
router.post('/:id/duplicate', requirePermission('reports', 'create'), validateZodBody(zodBodySchemas.object), customReportsController.duplicateReport);

// ── Report Execution ─────────────────────────────────────────
router.post('/run', requirePermission('reports', 'create'), validateZodBody(zodBodySchemas.object), customReportsController.runReport);

export default router;
