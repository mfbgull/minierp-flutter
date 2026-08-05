import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import purchaseController from '../controllers/purchaseController';

router.use(authenticateToken);

router.post('/purchases', requirePermission('purchases', 'create'), sensitiveOperationLimiter, purchaseController.recordPurchase);
router.get('/purchases', requirePermission('purchases', 'read'), purchaseController.getPurchases);
router.get('/purchases/returns', requirePermission('purchases', 'read'), purchaseController.getReturnHistory);
router.get('/purchases/:id', requirePermission('purchases', 'read'), purchaseController.getPurchase);
router.delete('/purchases/:id', requirePermission('purchases', 'delete'), sensitiveOperationLimiter, purchaseController.deletePurchase);
router.post('/purchases/:id/return', requirePermission('purchases', 'update'), sensitiveOperationLimiter, purchaseController.returnPurchaseItems);
router.get('/purchases/summary/item/:item_id', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByItem);
router.get('/purchases/summary/daterange', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByDateRange);
router.get('/purchases/top-suppliers', requirePermission('purchases', 'read'), purchaseController.getTopSuppliers);

export default router;
