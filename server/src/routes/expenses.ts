import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodQuery, validateZodBody, zodSchemas, zodBodySchemas } from '../middleware/validation';
import expenseController from '../controllers/expenseController';

router.use(authenticateToken);

router.get('/categories', requirePermission('expenses', 'read'), expenseController.getExpenseCategories);
router.get('/status-options', requirePermission('expenses', 'read'), expenseController.getExpenseStatusOptions);
router.get('/payment-method-options', requirePermission('expenses', 'read'), expenseController.getExpensePaymentMethodOptions);

router.post('/', requirePermission('expenses', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.expenseCreate), expenseController.createExpense);
router.get('/', requirePermission('expenses', 'read'), validateZodQuery(zodSchemas.listQuery), expenseController.getExpenses);
router.get('/summary', requirePermission('expenses', 'read'), expenseController.getExpenseSummary);
router.get('/date-range', requirePermission('expenses', 'read'), expenseController.getExpensesByDateRange);
router.get('/category/:category', requirePermission('expenses', 'read'), expenseController.getExpensesByCategory);
router.get('/:id', requirePermission('expenses', 'read'), expenseController.getExpenseById);
router.put('/:id', requirePermission('expenses', 'update'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), expenseController.updateExpense);
router.post('/categories', requirePermission('expenses', 'create'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.expenseCategoryCreate), expenseController.createExpenseCategory);
router.put('/categories/:id', requirePermission('expenses', 'update'), sensitiveOperationLimiter, validateZodBody(zodBodySchemas.object), expenseController.updateExpenseCategory);
router.delete('/categories/:id', requirePermission('expenses', 'delete'), sensitiveOperationLimiter, expenseController.deleteExpenseCategory);

export default router;
