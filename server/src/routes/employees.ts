import express from 'express';
const router = express.Router();
import employeeController from '../controllers/employeeController';
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { uploadEmployeeDoc } from '../middleware/upload';
import { employeeDocsDir } from '../middleware/upload';
import path from 'path';

// All employee routes require authentication
router.use(authenticateToken);

router.get('/', requirePermission('employees', 'read'), employeeController.getEmployees);
router.get('/next-code', requirePermission('employees', 'read'), employeeController.getNextEmployeeCode);
router.get('/:id', requirePermission('employees', 'read'), employeeController.getEmployee);
router.post('/', requirePermission('employees', 'create'), employeeController.createEmployee);
router.put('/:id', requirePermission('employees', 'update'), employeeController.updateEmployee);
router.delete('/:id', requirePermission('employees', 'delete'), employeeController.deleteEmployee);

// Salary payment routes
router.post('/:id/salary/pay', requirePermission('employees', 'update'), employeeController.paySalary);
router.get('/:id/salary/history', requirePermission('employees', 'read'), employeeController.getSalaryHistory);
router.get('/:id/salary/month/:payPeriod', requirePermission('employees', 'read'), employeeController.getSalaryMonthDetail);
router.delete('/:id/salary/:paymentId', requirePermission('employees', 'update'), employeeController.deleteSalaryPayment);

// Loan routes
router.get('/:id/loans', requirePermission('employees', 'read'), employeeController.getLoans);
router.post('/:id/loans', requirePermission('employees', 'update'), employeeController.createLoan);
router.get('/:id/loans/:loanId', requirePermission('employees', 'read'), employeeController.getLoanDetail);
router.post('/:id/loans/:loanId/repay', requirePermission('employees', 'update'), employeeController.repayLoan);
router.post('/:id/loans/:loanId/write-off', requirePermission('employees', 'update'), employeeController.writeOffLoan);
router.delete('/:id/loans/:loanId', requirePermission('employees', 'update'), employeeController.deleteLoan);
router.post('/:id/loans/:loanId/repayments/:repaymentId/void', requirePermission('employees', 'update'), employeeController.voidLoanRepayment);

// Document sub-routes
router.get('/:id/documents', requirePermission('employees', 'read'), employeeController.getEmployeeDocuments);
router.post('/:id/documents', requirePermission('employees', 'update'), uploadEmployeeDoc.single('file'), employeeController.addEmployeeDocument);
router.delete('/:id/documents/:docId', requirePermission('employees', 'update'), employeeController.removeEmployeeDocument);

// Serve uploaded document files
router.get('/:id/documents/file/:filename', requirePermission('employees', 'read'), (req, res) => {
  const filename = Array.isArray(req.params.filename) ? req.params.filename[0] : req.params.filename;
  const safeName = path.basename(filename);
  if (safeName !== filename || filename.includes('..')) {
    res.status(400).json({ success: false, error: 'Invalid filename' });
    return;
  }
  const filePath = path.join(employeeDocsDir, safeName);
  res.sendFile(filePath, (err) => {
    if (err) {
      res.status(404).json({ success: false, error: 'File not found' });
    }
  });
});

export default router;
