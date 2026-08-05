import express from 'express';
const router = express.Router();
import mobileInvoiceController from '../controllers/mobileInvoiceController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';

// All routes require authentication
router.use(authenticateToken);

// Draft management - for saving incomplete invoice state
router.post('/draft', requirePermission('invoices', 'create'), mobileInvoiceController.createDraft);
router.put('/draft/:id', requirePermission('invoices', 'update'), mobileInvoiceController.updateDraft);
router.get('/draft/:id', requirePermission('invoices', 'read'), mobileInvoiceController.getDraft);
router.delete('/draft/:id', requirePermission('invoices', 'delete'), mobileInvoiceController.deleteDraft);

// Search endpoints for mobile autocomplete
router.get('/items/search', requirePermission('invoices', 'read'), mobileInvoiceController.searchItems);
router.get('/customers/search', requirePermission('invoices', 'read'), mobileInvoiceController.searchCustomers);

// Configuration endpoints
router.get('/tax-rates', requirePermission('invoices', 'read'), mobileInvoiceController.getTaxRates);
router.get('/payment-terms', requirePermission('invoices', 'read'), mobileInvoiceController.getPaymentTerms);

// Final submission - creates actual invoice from draft or direct data
router.post('/submit', requirePermission('invoices', 'create'), mobileInvoiceController.submitInvoice);

export default router;
