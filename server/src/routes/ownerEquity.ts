import express from 'express';
const router = express.Router();
import { authenticateToken } from '../middleware/auth';
import { requirePermission } from '../middleware/requirePermission';
import { sensitiveOperationLimiter } from '../middleware/rateLimiter';
import { validateZodBody, zodBodySchemas } from '../middleware/validation';
import ownerEquityController from '../controllers/ownerEquityController';
import ownerPersonalLoansController from '../controllers/ownerPersonalLoansController';

router.use(authenticateToken);

// Shared
router.get('/summary', requirePermission('owner_equity', 'read'), ownerEquityController.getSummary);
router.get('/payment-method-options', requirePermission('owner_equity', 'read'), ownerEquityController.getPaymentMethodOptions);

// Owner capital
router.post('/capital', requirePermission('owner_equity', 'create'), validateZodBody(zodBodySchemas.ownerCapital), sensitiveOperationLimiter, ownerEquityController.createCapital);
router.get('/capital', requirePermission('owner_equity', 'read'), ownerEquityController.getCapitalList);
router.put('/capital/:id', requirePermission('owner_equity', 'edit'), validateZodBody(zodBodySchemas.ownerCapital), sensitiveOperationLimiter, ownerEquityController.updateCapital);
router.delete('/capital/:id', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerEquityController.voidCapital);

// Owner withdrawals (quote must precede /:id routes)
router.post('/withdrawals/quote', requirePermission('owner_equity', 'read'), validateZodBody(zodBodySchemas.ownerWithdrawalQuote), ownerEquityController.quoteWithdrawal);
router.post('/withdrawals', requirePermission('owner_equity', 'create'), validateZodBody(zodBodySchemas.ownerWithdrawal), sensitiveOperationLimiter, ownerEquityController.createWithdrawal);
router.get('/withdrawals', requirePermission('owner_equity', 'read'), ownerEquityController.getWithdrawalList);
router.get('/withdrawals/:id', requirePermission('owner_equity', 'read'), ownerEquityController.getWithdrawalById);
router.put('/withdrawals/:id', requirePermission('owner_equity', 'edit'), validateZodBody(zodBodySchemas.ownerWithdrawal), sensitiveOperationLimiter, ownerEquityController.updateWithdrawal);
router.delete('/withdrawals/:id', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerEquityController.voidWithdrawal);

// ── Owner Personal Loans (purely record-keeping, no GL impact) ──

// Loans
router.get('/personal-loans', requirePermission('owner_equity', 'read'), ownerPersonalLoansController.listLoans);
router.post('/personal-loans', requirePermission('owner_equity', 'create'), validateZodBody(zodBodySchemas.personalLoanCreate), sensitiveOperationLimiter, ownerPersonalLoansController.createLoan);
router.get('/personal-loans/summary', requirePermission('owner_equity', 'read'), ownerPersonalLoansController.summary);
router.get('/personal-loans/:id', requirePermission('owner_equity', 'read'), ownerPersonalLoansController.getLoanDetail);
router.put('/personal-loans/:id', requirePermission('owner_equity', 'edit'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, ownerPersonalLoansController.updateLoan);
router.delete('/personal-loans/:id', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerPersonalLoansController.deleteLoan);

// Repayments
router.post('/personal-loans/:id/repayments', requirePermission('owner_equity', 'create'), validateZodBody(zodBodySchemas.repaymentCreate), sensitiveOperationLimiter, ownerPersonalLoansController.addRepayment);
router.delete('/personal-loans/:id/repayments/:repId', requirePermission('owner_equity', 'delete'), sensitiveOperationLimiter, ownerPersonalLoansController.deleteRepayment);

// Borrowers
router.get('/borrowers', requirePermission('owner_equity', 'read'), ownerPersonalLoansController.listBorrowers);
router.post('/borrowers', requirePermission('owner_equity', 'create'), validateZodBody(zodBodySchemas.object), sensitiveOperationLimiter, ownerPersonalLoansController.createBorrower);
router.put('/borrowers/:id', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerPersonalLoansController.updateBorrower);
router.put('/borrowers/:id/deactivate', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerPersonalLoansController.deactivateBorrower);
router.put('/borrowers/:id/reactivate', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerPersonalLoansController.reactivateBorrower);
router.put('/borrowers/:id/unlink', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerPersonalLoansController.unlinkBorrower);
router.post('/borrowers/:id/merge', requirePermission('owner_equity', 'edit'), sensitiveOperationLimiter, ownerPersonalLoansController.mergeBorrowers);

export default router;
