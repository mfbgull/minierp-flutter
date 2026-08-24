import express from 'express';
const router = express.Router();
import invoiceController from '../controllers/invoiceController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

router.use(authenticateToken);

router.get('/', requirePermission('invoices', 'read'), invoiceController.getInvoices);
router.get('/returns', requirePermission('invoices', 'read'), invoiceController.getInvoiceReturnHistory);
router.get('/:id', requirePermission('invoices', 'read'), invoiceController.getInvoice);
router.get('/:id/payments', requirePermission('invoices', 'read'), invoiceController.getInvoicePayments);
router.post('/', requirePermission('invoices', 'create'), invoiceController.createInvoice);
router.put('/:id', requirePermission('invoices', 'update'), invoiceController.updateInvoice);
router.delete('/:id', requirePermission('invoices', 'delete'), invoiceController.deleteInvoice);
router.put('/:id/cancel', requirePermission('invoices', 'update'), invoiceController.cancelInvoice);
router.post('/:id/return', requirePermission('invoices', 'update'), invoiceController.returnInvoiceItems);

export default router;
