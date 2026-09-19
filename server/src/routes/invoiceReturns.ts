import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import invoiceReturnController from '../controllers/invoiceReturnController';

router.use(authenticateToken);

// Settlements are money movements on the invoice's own permission module.
router.post('/invoice-returns/:id/settle', requirePermission('invoices', 'update'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, invoiceReturnController.settleReturn);
router.post('/invoice-returns/:id/void', requirePermission('invoices', 'void'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, invoiceReturnController.voidReturn);
router.post('/return-settlements/:id/void', requirePermission('invoices', 'void'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, invoiceReturnController.voidSettlement);

export default router;
