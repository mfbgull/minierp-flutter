"use strict";
/**
 * Custom Reports Routes
 * API endpoints for the ad-hoc report builder.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const customReportsController_1 = __importDefault(require("../controllers/customReportsController"));
const router = (0, express_1.Router)();
// All routes require authentication
router.use(auth_1.authenticateToken);
// ── Entity Discovery (no saved report needed) ───────────────
router.get('/entities', (0, requirePermission_1.requirePermission)('reports', 'read'), customReportsController_1.default.listEntities);
router.get('/entities/:key', (0, requirePermission_1.requirePermission)('reports', 'read'), customReportsController_1.default.getEntityDetail);
// ── Templates ───────────────────────────────────────────────
router.get('/templates', (0, requirePermission_1.requirePermission)('reports', 'read'), customReportsController_1.default.listTemplates);
router.post('/templates', (0, requirePermission_1.requirePermission)('reports', 'create'), customReportsController_1.default.createTemplate);
// ── Saved Reports CRUD ──────────────────────────────────────
router.get('/', (0, requirePermission_1.requirePermission)('reports', 'read'), customReportsController_1.default.listReports);
router.get('/:id', (0, requirePermission_1.requirePermission)('reports', 'read'), customReportsController_1.default.getReport);
router.post('/', (0, requirePermission_1.requirePermission)('reports', 'create'), customReportsController_1.default.createReport);
router.put('/:id', (0, requirePermission_1.requirePermission)('reports', 'update'), customReportsController_1.default.updateReport);
router.delete('/:id', (0, requirePermission_1.requirePermission)('reports', 'delete'), customReportsController_1.default.deleteReport);
router.post('/:id/duplicate', (0, requirePermission_1.requirePermission)('reports', 'create'), customReportsController_1.default.duplicateReport);
// ── Report Execution ─────────────────────────────────────────
router.post('/run', (0, requirePermission_1.requirePermission)('reports', 'create'), customReportsController_1.default.runReport);
exports.default = router;
//# sourceMappingURL=customReports.js.map