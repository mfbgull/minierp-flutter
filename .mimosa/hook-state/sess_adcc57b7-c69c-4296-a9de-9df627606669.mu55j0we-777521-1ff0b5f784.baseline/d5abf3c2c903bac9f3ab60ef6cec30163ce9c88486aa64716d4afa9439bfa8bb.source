import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import productionController from '../controllers/productionController';

router.use(authenticateToken);

router.post('/', requirePermission('production', 'create'), validateZodBody(zodBodySchemas.productionCreate), sensitiveOperationLimiter, productionController.recordProduction);
router.get('/', requirePermission('production', 'read'), productionController.getProductions);
router.get('/:id', requirePermission('production', 'read'), productionController.getProduction);
router.delete('/:id', requirePermission('production', 'delete'), sensitiveOperationLimiter, productionController.deleteProduction);
router.get('/summary/item/:item_id', requirePermission('production', 'read'), productionController.getProductionSummaryByItem);

export default router;
