import express from 'express';
const router = express.Router();
import invoiceController from '../controllers/invoiceController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';

router.use(authenticateToken);

router.get('/', requirePermission('invoices', 'read'), invoiceController.getInvoices);
router.get('/returns', requirePermission('invoices', 'read'), invoiceController.getInvoiceReturnHistory);
router.get('/:id', requirePermission('invoices', 'read'), invoiceController.getInvoice);
router.get('/:id/payments', requirePermission('invoices', 'read'), invoiceController.getInvoicePayments);
router.post('/', requirePermission('invoices', 'create'), validateZodBody(zodBodySchemas.invoiceCreate), invoiceController.createInvoice);
router.put('/:id', requirePermission('invoices', 'update'), validateZodBody(zodBodySchemas.object), invoiceController.updateInvoice);
router.delete('/:id', requirePermission('invoices', 'delete'), invoiceController.deleteInvoice);
router.post('/:id/restore', requirePermission('invoices', 'update'), invoiceController.restoreInvoice);
router.put('/:id/cancel', requirePermission('invoices', 'update'), validateZodBody(zodBodySchemas.object), invoiceController.cancelInvoice);
router.post('/:id/return', requirePermission('invoices', 'update'), validateZodBody(zodBodySchemas.object), invoiceController.returnInvoiceItems);

export default router;
