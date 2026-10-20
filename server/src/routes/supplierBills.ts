import express from 'express';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { createSupplierBill, getSupplierBill, listSupplierBills, paySupplierBill, voidSupplierBill } from '../controllers/supplierBillController';

const router = express.Router();
router.use(authenticateToken);
router.get('/', requirePermission('purchases', 'read'), listSupplierBills);
router.get('/:id', requirePermission('purchases', 'read'), getSupplierBill);
router.post('/', requirePermission('purchases', 'create'), requirePermission('expenses', 'approve'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.supplierBill), createSupplierBill);
router.post('/:id/payments', requirePermission('payments', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.expensePayment), paySupplierBill);
router.post('/:id/void', requirePermission('purchases', 'delete'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.financialVoid), voidSupplierBill);
export default router;
