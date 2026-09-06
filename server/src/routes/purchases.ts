import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodQuery, validateZodBody, zodSchemas, zodBodySchemas } from '../middleware/validation';
import purchaseController from '../controllers/purchaseController';

router.use(authenticateToken);

router.post('/', requirePermission('purchases', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), purchaseController.recordPurchase);
router.get('/', requirePermission('purchases', 'read'), validateZodQuery(zodSchemas.listQuery), purchaseController.getPurchases);
router.get('/:id', requirePermission('purchases', 'read'), purchaseController.getPurchase);
router.get('/:id/payments', requirePermission('purchases', 'read'), purchaseController.getPurchasePayments);
router.post('/:id/void', requirePermission('purchases', 'delete'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), purchaseController.voidPurchase);
router.get('/summary/item/:item_id', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByItem);
router.get('/summary/daterange', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByDateRange);
router.get('/top-suppliers', requirePermission('purchases', 'read'), purchaseController.getTopSuppliers);

export default router;
