import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import purchaseController from '../controllers/purchaseController';

router.use(authenticateToken);

router.post('/purchases', requirePermission('purchases', 'create'), sensitiveOperationLimiter, purchaseController.recordPurchase);
router.get('/purchases', requirePermission('purchases', 'read'), purchaseController.getPurchases);
router.get('/purchases/:id', requirePermission('purchases', 'read'), purchaseController.getPurchase);
router.get('/purchases/:id/payments', requirePermission('purchases', 'read'), purchaseController.getPurchasePayments);
router.delete('/purchases/:id', requirePermission('purchases', 'delete'), sensitiveOperationLimiter, purchaseController.deletePurchase);
router.get('/purchases/summary/item/:item_id', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByItem);
router.get('/purchases/summary/daterange', requirePermission('purchases', 'read'), purchaseController.getPurchaseSummaryByDateRange);
router.get('/purchases/top-suppliers', requirePermission('purchases', 'read'), purchaseController.getTopSuppliers);

export default router;
