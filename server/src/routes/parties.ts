import express from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { addPartyCustomer, addPartySupplier, getPartyAdjustment, getPartyPosition, getPartyTargets, linkParty,
  listPartyAdjustments, postPartyAdjustment, reversePartyAdjustment, unlinkParty } from '../controllers/partyController';

const router = express.Router();
router.use(authenticateToken);
router.post('/link',requirePermission('parties','link'),requirePermission('customers','update'),requirePermission('suppliers','update'),sensitiveOperationLimiter,linkParty);
router.post('/:id/unlink',requirePermission('parties','link'),requirePermission('customers','update'),requirePermission('suppliers','update'),sensitiveOperationLimiter,unlinkParty);
router.post('/:id/customer',requirePermission('parties','link'),requirePermission('customers','create'),sensitiveOperationLimiter,addPartyCustomer);
router.post('/:id/supplier',requirePermission('parties','link'),requirePermission('suppliers','create'),sensitiveOperationLimiter,addPartySupplier);
router.get('/:id/position',requirePermission('parties','read'),getPartyPosition);
router.get('/:id/adjustment-targets',requirePermission('party_adjustments','read'),getPartyTargets);
router.get('/:id/adjustments',requirePermission('party_adjustments','read'),listPartyAdjustments);
router.get('/:id/adjustments/:adjustmentId',requirePermission('party_adjustments','read'),getPartyAdjustment);
router.post('/:id/adjustments',requirePermission('party_adjustments','create'),sensitiveOperationLimiter,postPartyAdjustment);
router.post('/:id/adjustments/:adjustmentId/reverse',requirePermission('party_adjustments','reverse'),sensitiveOperationLimiter,reversePartyAdjustment);
export default router;
