import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import productionController from '../controllers/productionController';

router.use(authenticateToken);

router.post('/productions', requirePermission('production', 'create'), sensitiveOperationLimiter, productionController.recordProduction);
router.get('/productions', requirePermission('production', 'read'), productionController.getProductions);
router.get('/productions/:id', requirePermission('production', 'read'), productionController.getProduction);
router.delete('/productions/:id', requirePermission('production', 'delete'), sensitiveOperationLimiter, productionController.deleteProduction);
router.get('/productions/summary/item/:item_id', requirePermission('production', 'read'), productionController.getProductionSummaryByItem);

export default router;
