import express from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { applySupplierPrepayment, createSupplierPrepayment, getSupplierPrepayment, getSupplierPrepaymentTargets, listSupplierPrepayments, voidSupplierPrepayment } from '../controllers/supplierPrepaymentController';

const router = express.Router();
router.use(authenticateToken);
router.get('/', requirePermission('payments', 'read'), listSupplierPrepayments);
router.get('/:id', requirePermission('payments', 'read'), getSupplierPrepayment);
router.get('/:id/targets', requirePermission('payments', 'read'), getSupplierPrepaymentTargets);
router.post('/', requirePermission('payments', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.supplierPrepayment), createSupplierPrepayment);
router.post('/:id/apply', requirePermission('payments', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.supplierPrepaymentApplication), applySupplierPrepayment);
router.post('/:id/void', requirePermission('payments', 'delete'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.financialVoid), voidSupplierPrepayment);
export default router;
