import express from 'express';
const router = express.Router();
import forecastsController from '../controllers/forecastsController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

router.use(authenticateToken);

// ============ EXISTING ROUTES ============

router.get('/dashboard', requirePermission('forecasts', 'read'), forecastsController.getDashboard);
router.get('/demand', requirePermission('forecasts', 'read'), forecastsController.getDemand);
router.get('/trends', requirePermission('forecasts', 'read'), forecastsController.getTrends);
router.post('/generate', requirePermission('forecasts', 'create'), forecastsController.generateForecasts);

// ============ ACCURACY ROUTES ============

router.get('/accuracy', requirePermission('forecasts', 'read'), forecastsController.getAccuracyData);
router.get('/accuracy/:itemId', requirePermission('forecasts', 'read'), forecastsController.getAccuracyDetail);
router.post('/compute-accuracy', requirePermission('forecasts', 'create'), forecastsController.postComputeAccuracy);

// ============ MODEL CONFIG ROUTES ============

router.get('/models/:itemId', requirePermission('forecasts', 'read'), forecastsController.getModelConfigHandler);
router.put('/models/:itemId', requirePermission('forecasts', 'create'), forecastsController.setModelConfigHandler);

// ============ OVERRIDE ROUTES ============

router.post('/override', requirePermission('forecasts', 'create'), forecastsController.postOverride);

// ============ SAFETY STOCK ROUTES ============

router.get('/safety-stock', requirePermission('forecasts', 'read'), forecastsController.getSafetyStockHandler);

// ============ SEASONAL EVENTS ROUTES ============

router.get('/seasonal-events', requirePermission('forecasts', 'read'), forecastsController.getSeasonalEventsHandler);
router.post('/seasonal-events', requirePermission('forecasts', 'create'), forecastsController.postSeasonalEvent);
router.delete('/seasonal-events/:id', requirePermission('forecasts', 'delete'), forecastsController.deleteSeasonalEventHandler);

// ============ EXPORT & RUNS ============

router.get('/export', requirePermission('forecasts', 'read'), forecastsController.getExport);
router.get('/runs', requirePermission('forecasts', 'read'), forecastsController.getRuns);

export default router;
