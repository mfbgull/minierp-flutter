import express from 'express';
const router = express.Router();
import customersController from '../controllers/customersController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodQuery, validateZodParams, zodSchemas } from '../middleware/validation';
import { z } from 'zod';

// All customer routes require authentication
router.use(authenticateToken);

const customerListQuery = z.object({
  ...zodSchemas.pagination.shape,
  ...zodSchemas.search.shape,
  ...zodSchemas.sorting(['customer_name', 'customer_code', 'created_at', 'id', 'current_balance', 'credit_limit']).shape,
  status: z.enum(['active', 'inactive', 'all']).optional().default('all'),
});

router.get('/', requirePermission('customers', 'read'), validateZodQuery(customerListQuery), customersController.getCustomers);
router.get('/:id', requirePermission('customers', 'read'), validateZodParams(zodSchemas.id), customersController.getCustomer);
router.post('/', requirePermission('customers', 'create'), customersController.createCustomer);
router.put('/:id', requirePermission('customers', 'update'), customersController.updateCustomer);
router.delete('/:id', requirePermission('customers', 'delete'), customersController.deleteCustomer);
router.get('/:id/ledger', requirePermission('customers', 'read'), customersController.getCustomerLedger);
router.get('/:id/statement', requirePermission('customers', 'read'), customersController.getCustomerStatement);
router.get('/:id/balance', requirePermission('customers', 'read'), customersController.getCustomerBalance);
router.post('/recalculate-balances', requirePermission('customers', 'update'), customersController.recalculateAllBalances);

export default router;
