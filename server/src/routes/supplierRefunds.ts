import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import supplierRefundController from '../controllers/supplierRefundController';

router.use(authenticateToken);

// Supplier refunds — cash payout against supplier credit notes.
router.get('/', requirePermission('supplier_refunds', 'read'), supplierRefundController.getSupplierRefunds);
router.get('/:id', requirePermission('supplier_refunds', 'read'), supplierRefundController.getSupplierRefund);
router.get('/credit-notes/:id/refundable', requirePermission('supplier_refunds', 'read'), supplierRefundController.getCreditNoteRefundable);
router.post('/', requirePermission('supplier_refunds', 'create'), validateZodBody(zodBodySchemas.supplierRefundCreate), sensitiveOperationLimiter, supplierRefundController.createSupplierRefund);
router.post('/:id/void', requirePermission('supplier_refunds', 'void'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, supplierRefundController.voidSupplierRefund);

export default router;
