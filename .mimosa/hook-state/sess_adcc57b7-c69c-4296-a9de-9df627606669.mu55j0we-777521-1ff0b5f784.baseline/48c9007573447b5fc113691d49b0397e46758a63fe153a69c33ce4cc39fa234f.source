import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import purchaseReturnController from '../controllers/purchaseReturnController';

router.use(authenticateToken);

// Purchase Returns — the redesigned first-class return documents.
router.get('/', requirePermission('purchase_returns', 'read'), purchaseReturnController.getPurchaseReturns);
router.get('/:id', requirePermission('purchase_returns', 'read'), purchaseReturnController.getPurchaseReturn);
router.post('/', requirePermission('purchase_returns', 'create'), validateZodBody(zodBodySchemas.purchaseReturnCreate), sensitiveOperationLimiter, purchaseReturnController.createPurchaseReturn);
router.post('/:id/void', requirePermission('purchase_returns', 'void'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, purchaseReturnController.voidPurchaseReturn);

export default router;
