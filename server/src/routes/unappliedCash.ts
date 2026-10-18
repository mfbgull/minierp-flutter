import express from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody } from '../middleware/validation';
import { applyCashBody, refundCashBody } from '../middleware/unappliedCashValidation';
import { applyUnappliedCash, refundUnappliedCash, getUnappliedCashCapabilities } from '../controllers/unappliedCashController';

const router = express.Router();
router.use(authenticateToken);
router.get('/capabilities', getUnappliedCashCapabilities);
router.post('/apply', requirePermission('payments', 'update'), sensitiveOperationLimiter, validateZodBody(applyCashBody), applyUnappliedCash);
router.post('/refund', requirePermission('payments', 'create'), sensitiveOperationLimiter, validateZodBody(refundCashBody), refundUnappliedCash);

export default router;
