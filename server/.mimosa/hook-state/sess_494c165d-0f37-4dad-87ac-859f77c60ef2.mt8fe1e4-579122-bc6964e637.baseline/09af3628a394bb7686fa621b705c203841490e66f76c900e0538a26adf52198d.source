import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import purchaseReturnController from '../controllers/purchaseReturnController';

router.use(authenticateToken);

// Purchase Returns — the redesigned first-class return documents.
router.get('/purchase-returns', requirePermission('purchase_returns', 'read'), purchaseReturnController.getPurchaseReturns);
router.get('/purchase-returns/:id', requirePermission('purchase_returns', 'read'), purchaseReturnController.getPurchaseReturn);
router.post('/purchase-returns', requirePermission('purchase_returns', 'create'), sensitiveOperationLimiter, purchaseReturnController.createPurchaseReturn);
router.post('/purchase-returns/:id/void', requirePermission('purchase_returns', 'void'), sensitiveOperationLimiter, purchaseReturnController.voidPurchaseReturn);

export default router;
