import express from 'express';
const router = express.Router();
import suppliersController from '../controllers/suppliersController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

// All supplier routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('suppliers', 'read'), suppliersController.getSuppliers);
router.get('/next-code', requirePermission('suppliers', 'read'), suppliersController.getNextSupplierCode);
router.get('/:id', requirePermission('suppliers', 'read'), suppliersController.getSupplierById);
router.get('/:id/ledger', requirePermission('suppliers', 'read'), suppliersController.getSupplierLedger);
router.get('/:id/statement', requirePermission('suppliers', 'read'), suppliersController.getSupplierStatement);
router.get('/:id/balance', requirePermission('suppliers', 'read'), suppliersController.getSupplierBalance);
router.post('/', requirePermission('suppliers', 'create'), suppliersController.createSupplier);
router.put('/:id', requirePermission('suppliers', 'update'), suppliersController.updateSupplier);
router.delete('/:id', requirePermission('suppliers', 'delete'), suppliersController.deleteSupplier);
router.post('/recalculate-balances', requirePermission('suppliers', 'update'), suppliersController.recalculateAllBalances);

export default router;
