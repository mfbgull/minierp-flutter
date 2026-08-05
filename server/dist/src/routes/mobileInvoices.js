"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const mobileInvoiceController_1 = __importDefault(require("../controllers/mobileInvoiceController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
// All routes require authentication
router.use(auth_1.authenticateToken);
// Draft management - for saving incomplete invoice state
router.post('/draft', (0, requirePermission_1.requirePermission)('invoices', 'create'), mobileInvoiceController_1.default.createDraft);
router.put('/draft/:id', (0, requirePermission_1.requirePermission)('invoices', 'update'), mobileInvoiceController_1.default.updateDraft);
router.get('/draft/:id', (0, requirePermission_1.requirePermission)('invoices', 'read'), mobileInvoiceController_1.default.getDraft);
router.delete('/draft/:id', (0, requirePermission_1.requirePermission)('invoices', 'delete'), mobileInvoiceController_1.default.deleteDraft);
// Search endpoints for mobile autocomplete
router.get('/items/search', (0, requirePermission_1.requirePermission)('invoices', 'read'), mobileInvoiceController_1.default.searchItems);
router.get('/customers/search', (0, requirePermission_1.requirePermission)('invoices', 'read'), mobileInvoiceController_1.default.searchCustomers);
// Configuration endpoints
router.get('/tax-rates', (0, requirePermission_1.requirePermission)('invoices', 'read'), mobileInvoiceController_1.default.getTaxRates);
router.get('/payment-terms', (0, requirePermission_1.requirePermission)('invoices', 'read'), mobileInvoiceController_1.default.getPaymentTerms);
// Final submission - creates actual invoice from draft or direct data
router.post('/submit', (0, requirePermission_1.requirePermission)('invoices', 'create'), mobileInvoiceController_1.default.submitInvoice);
exports.default = router;
//# sourceMappingURL=mobileInvoices.js.map