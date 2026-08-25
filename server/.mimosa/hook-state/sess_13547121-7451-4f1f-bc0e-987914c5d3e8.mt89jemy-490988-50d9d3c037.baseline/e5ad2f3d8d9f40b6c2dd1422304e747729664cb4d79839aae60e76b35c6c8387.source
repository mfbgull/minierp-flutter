import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import expenseController from '../controllers/expenseController';

router.use(authenticateToken);

router.get('/categories', requirePermission('expenses', 'read'), expenseController.getExpenseCategories);
router.get('/status-options', requirePermission('expenses', 'read'), expenseController.getExpenseStatusOptions);
router.get('/payment-method-options', requirePermission('expenses', 'read'), expenseController.getExpensePaymentMethodOptions);

router.post('/', requirePermission('expenses', 'create'), sensitiveOperationLimiter, expenseController.createExpense);
router.get('/', requirePermission('expenses', 'read'), expenseController.getExpenses);
router.get('/summary', requirePermission('expenses', 'read'), expenseController.getExpenseSummary);
router.get('/date-range', requirePermission('expenses', 'read'), expenseController.getExpensesByDateRange);
router.get('/category/:category', requirePermission('expenses', 'read'), expenseController.getExpensesByCategory);
router.get('/:id', requirePermission('expenses', 'read'), expenseController.getExpenseById);
router.put('/:id', requirePermission('expenses', 'update'), sensitiveOperationLimiter, expenseController.updateExpense);
router.post('/categories', requirePermission('expenses', 'create'), sensitiveOperationLimiter, expenseController.createExpenseCategory);
router.put('/categories/:id', requirePermission('expenses', 'update'), sensitiveOperationLimiter, expenseController.updateExpenseCategory);
router.delete('/categories/:id', requirePermission('expenses', 'delete'), sensitiveOperationLimiter, expenseController.deleteExpenseCategory);

export default router;
