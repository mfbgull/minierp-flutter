"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const employeeController_1 = __importDefault(require("../controllers/employeeController"));
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const upload_1 = require("../middleware/upload");
const upload_2 = require("../middleware/upload");
const validation_1 = require("../middleware/validation");
const path_1 = __importDefault(require("path"));
// All employee routes require authentication
router.use(auth_1.authenticateToken);
router.get('/', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getEmployees);
router.get('/next-code', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getNextEmployeeCode);
router.get('/:id', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getEmployee);
router.post('/', (0, requirePermission_1.requirePermission)('employees', 'create'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.employeeCreate), employeeController_1.default.createEmployee);
router.put('/:id', (0, requirePermission_1.requirePermission)('employees', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), employeeController_1.default.updateEmployee);
router.delete('/:id', (0, requirePermission_1.requirePermission)('employees', 'delete'), employeeController_1.default.deleteEmployee);
// Salary payment routes
router.post('/:id/salary/pay', (0, requirePermission_1.requirePermission)('employees', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), employeeController_1.default.paySalary);
router.get('/:id/salary/history', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getSalaryHistory);
router.get('/:id/salary/month/:payPeriod', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getSalaryMonthDetail);
router.delete('/:id/salary/:paymentId', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.deleteSalaryPayment);
// Loan routes
router.get('/:id/loans', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getLoans);
router.post('/:id/loans', (0, requirePermission_1.requirePermission)('employees', 'update'), (0, validation_1.validateZodBody)(validation_1.zodBodySchemas.object), employeeController_1.default.createLoan);
router.get('/:id/loans/:loanId', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getLoanDetail);
router.post('/:id/loans/:loanId/repay', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.repayLoan);
router.post('/:id/loans/:loanId/write-off', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.writeOffLoan);
router.delete('/:id/loans/:loanId', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.deleteLoan);
router.post('/:id/loans/:loanId/repayments/:repaymentId/void', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.voidLoanRepayment);
// Document sub-routes
router.get('/:id/documents', (0, requirePermission_1.requirePermission)('employees', 'read'), employeeController_1.default.getEmployeeDocuments);
router.post('/:id/documents', (0, requirePermission_1.requirePermission)('employees', 'update'), upload_1.uploadEmployeeDoc.single('file'), employeeController_1.default.addEmployeeDocument);
router.delete('/:id/documents/:docId', (0, requirePermission_1.requirePermission)('employees', 'update'), employeeController_1.default.removeEmployeeDocument);
// Serve uploaded document files
router.get('/:id/documents/file/:filename', (0, requirePermission_1.requirePermission)('employees', 'read'), (req, res) => {
    const filename = Array.isArray(req.params.filename) ? req.params.filename[0] : req.params.filename;
    const safeName = path_1.default.basename(filename);
    if (safeName !== filename || filename.includes('..')) {
        res.status(400).json({ success: false, error: 'Invalid filename' });
        return;
    }
    const filePath = path_1.default.join(upload_2.employeeDocsDir, safeName);
    res.sendFile(filePath, (err) => {
        if (err) {
            res.status(404).json({ success: false, error: 'File not found' });
        }
    });
});
exports.default = router;
