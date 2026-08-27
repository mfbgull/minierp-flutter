import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import ownerEquityController from '../controllers/ownerEquityController';

router.use(authenticateToken);

// Shared
router.get('/summary', requirePermission('owner_equity', 'read'), ownerEquityController.getSummary);
router.get('/payment-method-options', requirePermission('owner_equity', 'read'), ownerEquityController.getPaymentMethodOptions);

// Owner capital
router.post('/capital', requirePermission('owner_equity', 'create'), sensitiveOperationLimiter, ownerEquityController.createCapital);
router.get('/capital', requirePermission('owner_equity', 'read'), ownerEquityController.getCapitalList);
router.put('/capital/:id', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerEquityController.updateCapital);
router.delete('/capital/:id', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerEquityController.voidCapital);

// Owner withdrawals (quote must precede /:id routes)
router.post('/withdrawals/quote', requirePermission('owner_equity', 'read'), ownerEquityController.quoteWithdrawal);
router.post('/withdrawals', requirePermission('owner_equity', 'create'), sensitiveOperationLimiter, ownerEquityController.createWithdrawal);
router.get('/withdrawals', requirePermission('owner_equity', 'read'), ownerEquityController.getWithdrawalList);
router.get('/withdrawals/:id', requirePermission('owner_equity', 'read'), ownerEquityController.getWithdrawalById);
router.put('/withdrawals/:id', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerEquityController.updateWithdrawal);
router.delete('/withdrawals/:id', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerEquityController.voidWithdrawal);

export default router;
