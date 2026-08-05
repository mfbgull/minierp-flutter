"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const forecastsController_1 = __importDefault(require("../controllers/forecastsController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
router.use(auth_1.authenticateToken);
// ============ EXISTING ROUTES ============
router.get('/dashboard', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getDashboard);
router.get('/demand', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getDemand);
router.get('/trends', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getTrends);
router.post('/generate', (0, requirePermission_1.requirePermission)('forecasts', 'create'), forecastsController_1.default.generateForecasts);
// ============ ACCURACY ROUTES ============
router.get('/accuracy', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getAccuracyData);
router.get('/accuracy/:itemId', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getAccuracyDetail);
router.post('/compute-accuracy', (0, requirePermission_1.requirePermission)('forecasts', 'create'), forecastsController_1.default.postComputeAccuracy);
// ============ MODEL CONFIG ROUTES ============
router.get('/models/:itemId', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getModelConfigHandler);
router.put('/models/:itemId', (0, requirePermission_1.requirePermission)('forecasts', 'create'), forecastsController_1.default.setModelConfigHandler);
// ============ OVERRIDE ROUTES ============
router.post('/override', (0, requirePermission_1.requirePermission)('forecasts', 'create'), forecastsController_1.default.postOverride);
// ============ SAFETY STOCK ROUTES ============
router.get('/safety-stock', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getSafetyStockHandler);
// ============ SEASONAL EVENTS ROUTES ============
router.get('/seasonal-events', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getSeasonalEventsHandler);
router.post('/seasonal-events', (0, requirePermission_1.requirePermission)('forecasts', 'create'), forecastsController_1.default.postSeasonalEvent);
router.delete('/seasonal-events/:id', (0, requirePermission_1.requirePermission)('forecasts', 'delete'), forecastsController_1.default.deleteSeasonalEventHandler);
// ============ EXPORT & RUNS ============
router.get('/export', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getExport);
router.get('/runs', (0, requirePermission_1.requirePermission)('forecasts', 'read'), forecastsController_1.default.getRuns);
exports.default = router;
//# sourceMappingURL=forecasts.js.map