import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import supplierRefundController from '../controllers/supplierRefundController';
import {
  getRefundClaims,
  getRefundClaim,
  getRefundsDue,
  createRefundClaim,
  cancelRefundClaim,
  writeOffRefundClaim,
} from '../controllers/supplierRefundClaimController';

router.use(authenticateToken);

// Refund claims (PRET-002) — the expected → received lifecycle. Claims
// post no GL; receipts (POST / below) carry the cash movement.
router.get('/claims', requirePermission('supplier_refunds', 'read'), getRefundClaims);
router.get('/claims/due', requirePermission('supplier_refunds', 'read'), getRefundsDue);
router.get('/claims/:id', requirePermission('supplier_refunds', 'read'), getRefundClaim);
router.post('/claims', requirePermission('supplier_refunds', 'create'), validateZodBody(zodBodySchemas.supplierRefundClaimCreate), sensitiveOperationLimiter, createRefundClaim);
router.post('/claims/:id/cancel', requirePermission('supplier_refunds', 'create'), validateZodBody(zodBodySchemas.supplierRefundClaimCancel), sensitiveOperationLimiter, cancelRefundClaim);
router.post('/claims/:id/write-off', requirePermission('supplier_refunds', 'write_off'), validateZodBody(zodBodySchemas.supplierRefundClaimWriteOff), sensitiveOperationLimiter, writeOffRefundClaim);

// Supplier refunds — refund RECEIPTS (cash payout against a claim or a
// legacy credit note). Idempotency-Key is required on create.
router.get('/', requirePermission('supplier_refunds', 'read'), supplierRefundController.getSupplierRefunds);
router.get('/:id', requirePermission('supplier_refunds', 'read'), supplierRefundController.getSupplierRefund);
router.get('/credit-notes/:id/refundable', requirePermission('supplier_refunds', 'read'), supplierRefundController.getCreditNoteRefundable);
router.post('/', requirePermission('supplier_refunds', 'create'), validateZodBody(zodBodySchemas.supplierRefundCreate), sensitiveOperationLimiter, supplierRefundController.createSupplierRefund);
router.post('/:id/void', requirePermission('supplier_refunds', 'void'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, supplierRefundController.voidSupplierRefund);

export default router;
