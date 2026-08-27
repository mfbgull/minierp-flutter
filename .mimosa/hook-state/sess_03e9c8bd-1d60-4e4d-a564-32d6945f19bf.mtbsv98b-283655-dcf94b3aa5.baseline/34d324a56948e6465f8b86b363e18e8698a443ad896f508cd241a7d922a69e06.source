import express from 'express';
const router = express.Router();
import paymentsController from '../controllers/paymentsController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodQuery, validateZodParams, zodSchemas } from '../middleware/validation';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { z } from 'zod';

router.use(authenticateToken);

const paymentListQuery = z.object({
  ...zodSchemas.pagination.shape,
  ...zodSchemas.search.shape,
  ...zodSchemas.sorting(['payment_date', 'payment_no', 'amount', 'customer_name', 'supplier_name', 'id', 'created_at']).shape,
  ...zodSchemas.dateRange.shape,
  customerId: z.string().regex(/^\d+$/).optional(),
  supplierId: z.string().regex(/^\d+$/).optional(),
});

router.get('/', requirePermission('payments', 'read'), validateZodQuery(paymentListQuery), paymentsController.getPayments);
router.get('/unified', requirePermission('payments', 'read'), paymentsController.getUnifiedPayments);
router.get('/:id', requirePermission('payments', 'read'), validateZodParams(zodSchemas.id), paymentsController.getPayment);
router.post('/', requirePermission('payments', 'create'), sensitiveOperationLimiter, paymentsController.createPayment);
router.put('/:id', requirePermission('payments', 'update'), sensitiveOperationLimiter, paymentsController.updatePayment);
router.delete('/:id', requirePermission('payments', 'delete'), sensitiveOperationLimiter, paymentsController.deletePayment);
router.get('/:id/receipt', requirePermission('payments', 'read'), validateZodParams(zodSchemas.id), paymentsController.getPaymentReceipt);
router.post('/:id/allocate', requirePermission('payments', 'update'), sensitiveOperationLimiter, paymentsController.allocatePaymentToInvoice);

export default router;
