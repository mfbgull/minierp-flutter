import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';
import EmployeeModel from '../models/Employee';
import { EmployeeLoanModel } from '../models/EmployeeLoan';
import { AccountingService } from '../services/accountingService';
import { isValidPaymentMethod } from '../services/cashService';
import fs from 'fs';
import path from 'path';
import {
  IDEMPOTENCY_SCOPES,
  claimIdempotencyKey,
  hashRequestPayload,
  startIdempotentRequest,
} from '../utils/idempotency';

import { errorMessage, errorCode } from '../utils/errorMessage';
import { roundCurrency } from '../utils/currency';
import { defaultUploadsDir } from '../utils/serverRoot';
import { BusinessRuleError, handleBusinessError } from '../utils/businessRuleError';
import { assertCashTimeline } from '../services/cashBalanceGuard';

function getEmployees(req: Request, res: Response): void {
  try {
    const { search, department, status, sortBy, sortOrder, page, limit } = req.query;
    const result = EmployeeModel.getAll(
      db,
      {
        search: search as string | undefined,
        department: department as string | undefined,
        status: status as string | undefined,
      },
      (sortBy as string) || 'employee_code',
      (sortOrder as string) || 'ASC',
      parseInt(page as string, 10) || 1,
      parseInt(limit as string, 10) || 20
    );

    const safePage = parseInt(page as string, 10) || 1;
    const safeLimit = parseInt(limit as string, 10) || 20;

    res.json({
      success: true,
      data: result.data,
      pagination: {
        page: safePage,
        limit: safeLimit,
        total: result.total,
        totalPages: Math.ceil(result.total / safeLimit)
      }
    });
  } catch (error) {
    logger.error('Error fetching employees:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch employees'
    });
  }
}

function getEmployee(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }
    res.json({ success: true, data: employee });
  } catch (error) {
    logger.error('Error fetching employee:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch employee' });
  }
}

function createEmployee(req: Request, res: Response): void {
  try {
    const {
      first_name, last_name, email, phone, mobile, cnic_no,
      address, city, state, postal_code, country, date_of_birth,
      gender, department, designation, employment_type, date_of_joining,
      date_of_leaving, salary, bank_name, bank_account_no, bank_iban,
      emergency_contact_name, emergency_contact_phone, profile_photo, notes
    } = req.body;

    // Validation
    if (!first_name || !first_name.trim()) {
      res.status(422).json({ success: false, error: 'First name is required' });
      return;
    }
    if (!last_name || !last_name.trim()) {
      res.status(422).json({ success: false, error: 'Last name is required' });
      return;
    }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      res.status(422).json({ success: false, error: 'Invalid email format' });
      return;
    }

    // Generate employee code
    initializeSequenceFromMax(db, 'EMP_last_no', 'employees', 'employee_code', 'EMP-');
    const nextNumber = getNextSequenceNumber(db, 'EMP_last_no');
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    const employee_code = `EMP-${month}${year}-${String(nextNumber).padStart(5, '0')}`;

    const id = EmployeeModel.create({
      employee_code,
      first_name: first_name.trim(),
      last_name: last_name.trim(),
      email, phone, mobile, cnic_no, address, city, state, postal_code,
      country, date_of_birth, gender, department, designation, employment_type,
      date_of_joining, date_of_leaving, salary, bank_name, bank_account_no,
      bank_iban, emergency_contact_name, emergency_contact_phone,
      profile_photo, notes,
      is_active: true,
      created_by: (req as AuthRequest).user?.id
    }, db);

    logCRUD(ActionType.EMPLOYEE_CREATE, 'Employee', id, `Created employee: ${first_name} ${last_name} (${employee_code})`, (req as AuthRequest).user?.id);
    req.activityLogged = true;

    const employee = EmployeeModel.getById(id, db);
    res.status(201).json({ success: true, data: employee });
  } catch (error: unknown) {
    logger.error('Error creating employee:', error);
    if (errorCode(error) === 'SQLITE_CONSTRAINT_UNIQUE') {
      res.status(409).json({ success: false, error: 'Employee code already exists' });
    } else {
      res.status(500).json({ success: false, error: 'Failed to create employee' });
    }
  }
}

function updateEmployee(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const existing = EmployeeModel.getById(employeeId, db);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const { email } = req.body;
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      res.status(422).json({ success: false, error: 'Invalid email format' });
      return;
    }

    const result = EmployeeModel.update(employeeId, req.body, db);

    if (result.changes === 0) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    logCRUD(ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId, `Updated employee: ${req.body.first_name || existing.first_name} ${req.body.last_name || existing.last_name}`, (req as AuthRequest).user?.id);
    req.activityLogged = true;

    const updated = EmployeeModel.getById(employeeId, db);
    res.json({ success: true, data: updated });
  } catch (error) {
    logger.error('Error updating employee:', error);
    res.status(500).json({ success: false, error: 'Failed to update employee' });
  }
}

function deleteEmployee(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const existing = EmployeeModel.getById(employeeId, db);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    EmployeeModel.delete(employeeId, db);

    logCRUD(ActionType.EMPLOYEE_DELETE, 'Employee', employeeId, `Deleted employee: ${existing.first_name} ${existing.last_name} (${existing.employee_code})`, (req as AuthRequest).user?.id);
    req.activityLogged = true;

    res.status(204).send();
  } catch (error) {
    logger.error('Error deleting employee:', error);
    res.status(500).json({ success: false, error: 'Failed to delete employee' });
  }
}

function getNextEmployeeCode(req: Request, res: Response): void {
  try {
    initializeSequenceFromMax(db, 'EMP_last_no', 'employees', 'employee_code', 'EMP-');
    const nextNumber = getNextSequenceNumber(db, 'EMP_last_no');
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    const code = `EMP-${month}${year}-${String(nextNumber).padStart(5, '0')}`;
    res.json({ success: true, data: { code } });
  } catch (error) {
    logger.error('Error generating employee code:', error);
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const year = String(now.getFullYear()).slice(-2);
    const code = `EMP-${month}${year}-00001`;
    res.json({ success: true, data: { code } });
  }
}

function paySalary(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const authReq = req as AuthRequest;

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const { amount, payment_date, payment_method, reference_no, notes, payment_type, loan_deduction, loan_id } = req.body;
    if (loan_deduction !== undefined && (typeof loan_deduction !== 'number' || !Number.isFinite(loan_deduction) || loan_deduction < 0)) {
      throw new BusinessRuleError(400, 'Loan deduction must be a non-negative finite amount');
    }
    if (typeof amount !== 'number' || !Number.isFinite(amount) || roundCurrency(amount) <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
      return;
    }
    if (!payment_date) {
      res.status(422).json({ success: false, error: 'Payment date is required' });
      return;
    }

    const safeType = ['full', 'advance', 'partial'].includes(payment_type) ? payment_type : 'full';

    // Same default the row stores — before this the GL posted to 1000 Cash
    // (method undefined) while the row and cash flows said 'bank' (1010).
    const method = payment_method || 'bank';
    if (payment_method !== undefined && !isValidPaymentMethod(payment_method)) {
      res.status(422).json({
        success: false,
        error: `Invalid payment_method "${payment_method}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`,
      });
      return;
    }

    // audit-3 task 08: salary is cash OUT plus a GL entry and possibly a
    // next-month advance, so a retry after a lost response must replay
    // rather than pay the employee twice.
    const hash = hashRequestPayload(req.body);
    const start = startIdempotentRequest(db, req.headers, IDEMPOTENCY_SCOPES.EMPLOYEE_SALARY_PAY, hash);
    if (start.kind === 'error') {
      res.status(start.status).json({ success: false, error: start.message });
      return;
    }
    if (start.kind === 'replay') {
      // Same status as the original success, so a client cannot tell a
      // replay from a first response by status alone (matches the
      // invoice-create replay, which also answers 201).
      res.set('X-Idempotent-Replay', 'true');
      res.status(201).json({ success: true, idempotentReplay: true, data: { paymentId: start.resourceId } });
      return;
    }

    // Duplicate guard: reject a 'full' payment if one already exists for the month.
    // Advance and partial payments are always allowed.
    if (safeType === 'full') {
      const payPeriod = payment_date.substring(0, 7); // YYYY-MM
      const existingFull = db.prepare(
        `SELECT id FROM salary_payments WHERE employee_id = ? AND pay_period = ? AND payment_type = 'full' AND voided_at IS NULL`
      ).get(employeeId, payPeriod) as { id: number } | undefined;
      if (existingFull) {
        const monthName = new Date(payPeriod + '-01').toLocaleString('en-US', { month: 'long', year: 'numeric' });
        res.status(409).json({
          success: false,
          error: `Full salary already paid for ${monthName}`,
        });
        return;
      }
    }

    const trx = db.transaction(() => {
      const paidAmount = roundCurrency(Number(amount));
      const payPeriod = payment_date.substring(0, 7);
      const paid = db.prepare<[number, string], { total: number }>(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM salary_payments WHERE employee_id = ? AND pay_period = ? AND voided_at IS NULL'
      ).get(employeeId, payPeriod);
      const remaining = Math.max(0, roundCurrency(employee.salary - (paid?.total ?? 0)));
      const salaryAmount = employee.salary > 0 ? Math.min(paidAmount, remaining) : paidAmount;
      const excess = roundCurrency(paidAmount - salaryAmount);
      const paymentId = EmployeeModel.addSalaryPayment({
        employee_id: employeeId,
        amount: salaryAmount,
        payment_date,
        payment_method: method,
        reference_no,
        notes,
        paid_by: authReq.user?.id,
        payment_type: safeType,
      }, db);

      if (start.key) {
        claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.EMPLOYEE_SALARY_PAY, start.key, hash, paymentId);
      }

      let journalEntryId: number | null = null;
      try {
        const result = AccountingService.postSalaryEntry(db, {
          salaryPaymentId: paymentId,
          employeeName: `${employee.first_name} ${employee.last_name}`,
          employeeCode: employee.employee_code,
          amount: salaryAmount,
          paymentDate: payment_date,
          paymentMethod: method,
          userId: authReq.user?.id,
        });
        if (result) journalEntryId = result.journal_entry_id;
      } catch (glError: unknown) {
        throw new Error(`GL posting failed: ${errorMessage(glError)}`, { cause: glError });
      }

      if (journalEntryId) {
        db.prepare(`UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?`)
          .run(journalEntryId, paymentId);
      }

      let advanceCreated: number | null = null;
      if (excess > 0) {
        const [year, month] = payPeriod.split('-').map(Number);
        const nextDate = new Date(year, month, 1);
        const nextPayPeriod = `${nextDate.getFullYear()}-${String(nextDate.getMonth() + 1).padStart(2, '0')}`;
        advanceCreated = EmployeeModel.addSalaryPayment({
          employee_id: employeeId,
          amount: excess,
          payment_date,
          payment_method: method,
          reference_no: `ADV-${payPeriod}`,
          notes: `Auto-advance from overpayment in ${payPeriod}`,
          paid_by: authReq.user?.id,
          payment_type: 'advance',
          parent_payment_id: paymentId,
          pay_period: nextPayPeriod,
        }, db);
        const advanceEntry = AccountingService.postSalaryEntry(db, {
          salaryPaymentId: advanceCreated,
          employeeName: `${employee.first_name} ${employee.last_name}`,
          employeeCode: employee.employee_code,
          amount: excess,
          paymentDate: payment_date,
          paymentMethod: method,
          userId: authReq.user?.id,
          postingKind: 'advance',
        });
        if (advanceEntry) {
          db.prepare('UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?')
            .run(advanceEntry.journal_entry_id, advanceCreated);
        }
      }

      const deduction = roundCurrency(loan_deduction ?? 0);
      if (deduction > 0) {
        if (!Number.isSafeInteger(loan_id) || loan_id <= 0) {
          throw new BusinessRuleError(400, 'Loan deduction requires a valid loan');
        }
        const loan = EmployeeLoanModel.getById(loan_id, db);
        if (!loan || loan.employee_id !== employeeId || loan.voided_at || !['active', 'overdue'].includes(loan.status)) {
          throw new BusinessRuleError(400, 'Loan deduction requires an active loan for this employee');
        }
        if (payment_date < loan.disbursement_date || deduction > loan.balance || deduction > salaryAmount) {
          throw new BusinessRuleError(400, 'Loan deduction exceeds the loan or salary balance, or precedes disbursement');
        }
        const repaymentId = EmployeeLoanModel.addRepayment({
          loan_id: loan.id, employee_id: employeeId, amount: deduction,
          payment_date, payment_method: method, repayment_type: 'salary_deduction',
          salary_payment_id: paymentId, created_by: authReq.user?.id,
          notes: 'Loan deduction from salary payment',
        }, db);
        EmployeeLoanModel.deductBalance(loan.id, deduction, db);
        const repaymentEntry = AccountingService.postLoanRepayment(db, {
          repaymentId, loanId: loan.id, employeeName: `${employee.first_name} ${employee.last_name}`,
          employeeCode: employee.employee_code, amount: deduction, paymentDate: payment_date,
          paymentMethod: method, userId: authReq.user?.id,
        });
        if (repaymentEntry) EmployeeLoanModel.updateRepaymentJournal(repaymentId, repaymentEntry.journal_entry_id, db);
      }

      logCRUD(ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId,
        `Salary paid: ${employee.first_name} ${employee.last_name} (amount: ${amount})`, authReq.user?.id);
      req.activityLogged = true;

      return { paymentId, journalEntryId, advanceCreated };
    });

    const result = trx();

    res.status(201).json({
      success: true,
      data: { id: result.paymentId, journal_entry_id: result.journalEntryId, advance_created: result.advanceCreated },
    });
  } catch (error: unknown) {
    handleBusinessError(res, error, 'Pay salary', 'Failed to process salary payment', { success: true });
  }
}

function getSalaryHistory(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const history = EmployeeModel.getSalaryHistory(employeeId, db);
    res.json({ success: true, data: history });
  } catch (error) {
    logger.error('Error fetching salary history:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch salary history' });
  }
}

function getSalaryMonthDetail(req: Request, res: Response): void {
  try {
    const { id, payPeriod: rawPeriod } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const payPeriod = Array.isArray(rawPeriod) ? rawPeriod[0] : rawPeriod;

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const detail = EmployeeModel.getSalaryMonthDetail(employeeId, payPeriod, db);
    res.json({ success: true, data: detail });
  } catch (error) {
    logger.error('Error fetching salary month detail:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch salary month detail' });
  }
}

function deleteSalaryPayment(req: Request, res: Response): void {
  try {
    const { id, paymentId } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const salaryPaymentId = parseInt(Array.isArray(paymentId) ? paymentId[0] : paymentId, 10);
    const authReq = req as AuthRequest;

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const payment = EmployeeModel.getSalaryPayment(salaryPaymentId, db);
    if (!payment || payment.employee_id !== employeeId) {
      res.status(404).json({ success: false, error: 'Salary payment not found' });
      return;
    }
    if (payment.voided_at) {
      res.status(409).json({ success: false, error: 'Salary payment is already voided' });
      return;
    }
    if (payment.parent_payment_id) {
      res.status(409).json({ success: false, error: `Void parent salary payment #${payment.parent_payment_id} to reverse its linked advance.` });
      return;
    }

    AccountingService.assertPeriodNotClosed(db, payment.payment_date, `Salary payment #${salaryPaymentId}`);

    // C6 (reversal-rules): one transaction wraps GL void, soft-void and
    // activity log so a failure at any step rolls back everything. GL
    // lines are voided by reference — unconditionally. Older payment rows
    // (pre-GL-link backfill) carry journal_entry_id NULL, but their GL
    // lines still exist keyed by reference_type/reference_id; skipping
    // the void on a NULL link orphans those lines forever and corrupts
    // the cash/bank GL balances.
    const trx = db.transaction(() => {
      const advances = db.prepare<[number], { id: number; payment_date: string }>(
        'SELECT id, payment_date FROM salary_payments WHERE parent_payment_id = ? AND voided_at IS NULL'
      ).all(salaryPaymentId);
      for (const advance of advances) {
        AccountingService.assertPeriodNotClosed(db, advance.payment_date, `Salary advance #${advance.id}`);
        AccountingService.voidJournalLinesByReference(db, 'SALARY_PAYMENT', advance.id, {
          voidedBy: authReq.user?.id, voidReason: `Parent salary payment ${salaryPaymentId} voided`,
        });
        EmployeeModel.deleteSalaryPayment(advance.id, db, authReq.user?.id ?? null,
          `Parent salary payment ${salaryPaymentId} voided`);
      }
      AccountingService.voidJournalLinesByReference(db, 'SALARY_PAYMENT', salaryPaymentId, {
        voidedBy: authReq.user?.id,
        voidReason: `Salary payment voided for ${employee.first_name} ${employee.last_name}`,
      });

      // Salary-deduction repayments linked to this payment must be
      // voided with it — otherwise the loan stays 'repaid' while the
      // salary cash is reversed. Restore each loan balance first.
      const linkedRepayments = db.prepare(
        'SELECT id, loan_id, amount, payment_date FROM employee_loan_repayments WHERE salary_payment_id = ? AND voided_at IS NULL'
      ).all(salaryPaymentId) as Array<{ id: number; loan_id: number; amount: number; payment_date: string }>;
      for (const repayment of linkedRepayments) {
        AccountingService.assertPeriodNotClosed(db, repayment.payment_date, `Loan repayment #${repayment.id}`);
        AccountingService.voidJournalLinesByReference(db, 'LOAN_REPAYMENT', repayment.id, {
          voidedBy: authReq.user?.id, voidReason: `Salary payment ${salaryPaymentId} voided`,
        });
        EmployeeLoanModel.restoreBalance(repayment.loan_id, repayment.amount, db);
        EmployeeLoanModel.deleteRepayment(repayment.id, db, authReq.user?.id ?? null,
          `Salary payment ${salaryPaymentId} voided`);
      }

      EmployeeModel.deleteSalaryPayment(salaryPaymentId, db, authReq.user?.id ?? null,
        `Salary payment voided for ${employee.first_name} ${employee.last_name}`);

      logCRUD(ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId,
        `Salary payment voided: ${employee.first_name} ${employee.last_name} (amount: ${payment.amount})`, authReq.user?.id);
      req.activityLogged = true;
    });

    trx();
    res.status(204).send();
  } catch (error: unknown) {
    const message = errorMessage(error) || 'Failed to delete salary payment';
    if (message.includes('inside closed accounting period')) {
      res.status(409).json({ success: false, error: message });
      return;
    }
    logger.error('Error deleting salary payment:', error);
    res.status(500).json({ success: false, error: message });
  }
}

function getEmployeeDocuments(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const documents = EmployeeModel.getDocuments(employeeId, db);
    res.json({ success: true, data: documents });
  } catch (error) {
    logger.error('Error fetching employee documents:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch employee documents' });
  }
}

function addEmployeeDocument(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const { document_name, document_type, document_number, issue_date, expiry_date, file_path, notes } = req.body;

    if (!document_name || !document_name.trim()) {
      res.status(422).json({ success: false, error: 'Document name is required' });
      return;
    }

    // Handle file upload
    const uploadedFile = (req as AuthRequest & { file?: Express.Multer.File }).file;
    // FILE-001: a stored file name is later used to delete the file, so a name
    // supplied in the body must be a bare file name - never a path.
    if (!uploadedFile && file_path && (path.basename(String(file_path)) !== String(file_path) || String(file_path).includes('..'))) {
      res.status(400).json({ success: false, error: 'Invalid file_path' });
      return;
    }
    const filePath = uploadedFile ? uploadedFile.filename : file_path || null;

    const docId = EmployeeModel.addDocument({
      employee_id: employeeId,
      document_name: document_name.trim(),
      document_type,
      document_number,
      issue_date,
      expiry_date,
      file_path: filePath,
      notes
    }, db);

    res.status(201).json({ success: true, data: { id: docId } });
  } catch (error) {
    logger.error('Error adding employee document:', error);
    res.status(500).json({ success: false, error: 'Failed to add employee document' });
  }
}

function removeEmployeeDocument(req: Request, res: Response): void {
  try {
    const { id, docId } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const documentId = parseInt(Array.isArray(docId) ? docId[0] : docId, 10);

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    // The document must belong to the employee in the URL (FILE-001).
    const doc = db.prepare('SELECT file_path FROM employee_documents WHERE id = ? AND employee_id = ?')
      .get(documentId, employeeId) as { file_path?: string } | undefined;
    if (!doc) {
      res.status(404).json({ success: false, error: 'Document not found' });
      return;
    }
    // Delete the file only if it really lives inside the upload folder.
    if (doc.file_path) {
      const docsRoot = path.join(defaultUploadsDir(), 'employees');
      const filePath = path.resolve(docsRoot, doc.file_path);
      if (filePath.startsWith(docsRoot + path.sep) && fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    }

    EmployeeModel.removeDocument(documentId, db);
    res.status(204).send();
  } catch (error) {
    logger.error('Error removing employee document:', error);
    res.status(500).json({ success: false, error: 'Failed to remove employee document' });
  }
}

// ═══════════════════════════════════════════════════════════
// Employee Loans
// ═══════════════════════════════════════════════════════════

function getLoans(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    // Auto-update overdue statuses
    EmployeeLoanModel.updateOverdueStatuses(db);

    const loans = EmployeeLoanModel.getByEmployee(employeeId, db);
    const summary = EmployeeLoanModel.getSummary(employeeId, db);

    res.json({
      success: true,
      data: {
        loans: loans.map(l => ({
          ...l,
          repaid_amount: l.amount - l.balance,
          repayment_count: EmployeeLoanModel.hasRepayments(l.id, db) ? 1 : 0,
          is_overdue: l.status === 'overdue',
        })),
        summary,
      },
    });
  } catch (error: unknown) {
    logger.error('Get loans error:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch loans' });
  }
}

function createLoan(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const authReq = req as AuthRequest;

    const employee = EmployeeModel.getById(employeeId, db);
    if (!employee) {
      res.status(404).json({ success: false, error: 'Employee not found' });
      return;
    }

    const { amount, disbursement_date, due_date, purpose, payment_method, monthly_installment, notes } = req.body;
    if (typeof amount !== 'number' || !Number.isFinite(amount) || roundCurrency(amount) <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
      return;
    }
    if (payment_method !== undefined && !isValidPaymentMethod(payment_method)) {
      res.status(422).json({
        success: false,
        error: `Invalid payment_method "${payment_method}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`,
      });
      return;
    }
    if (!disbursement_date) {
      res.status(422).json({ success: false, error: 'Disbursement date is required' });
      return;
    }

    const trx = db.transaction(() => {
      const loanId = EmployeeLoanModel.create({
        employee_id: employeeId,
        amount,
        disbursement_date,
        due_date,
        purpose,
        payment_method,
        monthly_installment,
        notes,
        created_by: authReq.user?.id,
      }, db);

      // Post GL entry
      let journalEntryId: number | null = null;
      try {
        const result = AccountingService.postLoanDisbursement(db, {
          loanId,
          employeeName: `${employee.first_name} ${employee.last_name}`,
          employeeCode: employee.employee_code,
          amount,
          disbursementDate: disbursement_date,
          paymentMethod: payment_method,
          userId: authReq.user?.id,
        });
        if (result) journalEntryId = result.journal_entry_id;
      } catch (glError: unknown) {
        throw new Error(`GL posting failed: ${errorMessage(glError)}`, { cause: glError });
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateJournalEntry(loanId, journalEntryId, db);
      }

      return EmployeeLoanModel.getById(loanId, db);
    });

    const loan = trx();
    res.status(201).json({ success: true, data: loan });
  } catch (error: unknown) {
    handleBusinessError(res, error, 'Create employee loan', 'Failed to create loan', { success: true });
  }
}

function getLoanDetail(req: Request, res: Response): void {
  try {
    const { loanId } = req.params;
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);

    const loan = EmployeeLoanModel.getById(parsedLoanId, db);
    if (!loan) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }

    const repayments = EmployeeLoanModel.getRepayments(parsedLoanId, db);

    res.json({
      success: true,
      data: { ...loan, repayments },
    });
  } catch (error: unknown) {
    logger.error('Get loan detail error:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch loan detail' });
  }
}

function repayLoan(req: Request, res: Response): void {
  try {
    const { id, loanId } = req.params;
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
    const authReq = req as AuthRequest;

    const loan = EmployeeLoanModel.getById(parsedLoanId, db);
    if (!loan || loan.employee_id !== employeeId || loan.voided_at) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }
    if (loan.status !== 'active' && loan.status !== 'overdue') {
      res.status(409).json({ success: false, error: 'Loan is not active' });
      return;
    }

    const { amount, payment_date, payment_method, reference_no, notes, salary_payment_id } = req.body;
    if (typeof amount !== 'number' || !Number.isFinite(amount) || roundCurrency(amount) <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
      return;
    }
    if (payment_method !== undefined && !isValidPaymentMethod(payment_method)) {
      res.status(422).json({
        success: false,
        error: `Invalid payment_method "${payment_method}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`,
      });
      return;
    }
    if (amount > loan.balance) {
      res.status(422).json({ success: false, error: 'Repayment exceeds loan balance' });
      return;
    }
    if (!payment_date) {
      res.status(422).json({ success: false, error: 'Payment date is required' });
      return;
    }

    const isSalaryDeduction = !!salary_payment_id;
    const repaymentType = isSalaryDeduction ? 'salary_deduction' : 'direct';

    const employee = EmployeeModel.getById(employeeId, db);

    const trx = db.transaction(() => {
      let repaymentMethod: string = payment_method || 'cash';
      if (isSalaryDeduction) {
        const salaryPayment = EmployeeModel.getSalaryPayment(Number(salary_payment_id), db);
        if (!salaryPayment || salaryPayment.employee_id !== employeeId || salaryPayment.voided_at || salaryPayment.parent_payment_id) {
          throw new BusinessRuleError(400, 'Salary deduction requires an active salary payment for this employee');
        }
        if (payment_date < salaryPayment.payment_date) {
          throw new BusinessRuleError(400, 'Salary deduction cannot precede its salary payment');
        }
        if (payment_method && AccountingService._cashOrBankAccountCode(payment_method) !==
            AccountingService._cashOrBankAccountCode(salaryPayment.payment_method)) {
          throw new BusinessRuleError(400, 'Salary deduction must use the salary payment account');
        }
        const deducted = db.prepare<[number], { total: number }>(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM employee_loan_repayments WHERE salary_payment_id = ? AND voided_at IS NULL'
        ).get(salaryPayment.id);
        if (roundCurrency((deducted?.total ?? 0) + Number(amount)) > salaryPayment.amount) {
          throw new BusinessRuleError(400, 'Salary deductions exceed the salary payment amount');
        }
        repaymentMethod = salaryPayment.payment_method;
      }
      const repaymentId = EmployeeLoanModel.addRepayment({
        loan_id: parsedLoanId,
        employee_id: employeeId,
        amount,
        payment_date,
        payment_method: repaymentMethod,
        reference_no,
        notes,
        repayment_type: repaymentType,
        salary_payment_id: salary_payment_id || undefined,
        created_by: authReq.user?.id,
      }, db);

      // Deduct from loan balance
      EmployeeLoanModel.deductBalance(parsedLoanId, amount, db);

      let journalEntryId: number | null = null;
      if (employee) {
        try {
          const result = AccountingService.postLoanRepayment(db, {
            repaymentId,
            loanId: parsedLoanId,
            employeeName: `${employee.first_name} ${employee.last_name}`,
            employeeCode: employee.employee_code,
            amount,
            paymentDate: payment_date,
            paymentMethod: repaymentMethod,
            userId: authReq.user?.id,
          });
          if (result) journalEntryId = result.journal_entry_id;
        } catch (glError: unknown) {
          throw new Error(`GL posting failed: ${errorMessage(glError)}`, { cause: glError });
        }
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateRepaymentJournal(repaymentId, journalEntryId, db);
      }

      const updatedLoan = EmployeeLoanModel.getById(parsedLoanId, db);
      return {
        id: repaymentId,
        amount,
        loan_balance: updatedLoan?.balance ?? 0,
        loan_status: updatedLoan?.status ?? 'active',
        journal_entry_id: journalEntryId,
      };
    });

    const repayment = trx();
    res.status(201).json({ success: true, data: repayment });
  } catch (error: unknown) {
    handleBusinessError(res, error, 'Repay employee loan', 'Failed to record repayment', { success: true });
  }
}

function writeOffLoan(req: Request, res: Response): void {
  try {
    const { loanId } = req.params;
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
    const authReq = req as AuthRequest;

    const loan = EmployeeLoanModel.getById(parsedLoanId, db);
    if (!loan) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }
    if (loan.status !== 'active' && loan.status !== 'overdue') {
      res.status(409).json({ success: false, error: 'Loan is not active' });
      return;
    }

    const employee = EmployeeModel.getById(loan.employee_id, db);
    const writeOffAmount = loan.balance;

    const trx = db.transaction(() => {
      // Write off
      EmployeeLoanModel.writeOff(parsedLoanId, db);

      // Post GL entry
      let journalEntryId: number | null = null;
      if (employee) {
        try {
          const result = AccountingService.postLoanWriteOff(db, {
            loanId: parsedLoanId,
            employeeName: `${employee.first_name} ${employee.last_name}`,
            employeeCode: employee.employee_code,
            amount: writeOffAmount,
            writeOffDate: new Date().toISOString().substring(0, 10),
            userId: authReq.user?.id,
          });
          if (result) journalEntryId = result.journal_entry_id;
        } catch (glError: unknown) {
          throw new Error(`GL posting failed: ${errorMessage(glError)}`, { cause: glError });
        }
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateJournalEntry(parsedLoanId, journalEntryId, db);
      }

      res.json({
        success: true,
        data: {
          id: parsedLoanId,
          status: 'written_off',
          written_off_amount: writeOffAmount,
          balance: 0,
          journal_entry_id: journalEntryId,
        },
      });
    });

    trx();
  } catch (error: unknown) {
    logger.error('Write off loan error:', error);
    res.status(500).json({ success: false, error: errorMessage(error) || 'Failed to write off loan' });
  }
}

function deleteLoan(req: Request, res: Response): void {
  try {
    const { loanId } = req.params;
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
    const authReq = req as AuthRequest;

    const loan = EmployeeLoanModel.getById(parsedLoanId, db);
    if (!loan) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }
    if (loan.voided_at) {
      res.status(409).json({ success: false, error: 'Loan is already voided' });
      return;
    }
    if (EmployeeLoanModel.hasRepayments(parsedLoanId, db)) {
      res.status(409).json({ success: false, error: 'Cannot delete loan with repayment history' });
      return;
    }

    const trx = db.transaction(() => {
      // C5 (reversal-rules): void by reference unconditionally. Legacy
      // loans created before the journal_entry_id link-backfill carry a
      // NULL link, but their GL lines exist keyed by reference; gating on
      // the link orphans those lines forever.
      AccountingService.voidJournalLinesByReference(db, 'LOAN_DISBURSEMENT', parsedLoanId, {
        voidedBy: authReq.user?.id,
        voidReason: 'Loan deleted',
      });

      EmployeeLoanModel.delete(parsedLoanId, db, authReq.user?.id ?? null, 'Loan deleted');
      res.json({ success: true });
    });

    trx();
  } catch (error: unknown) {
    logger.error('Delete loan error:', error);
    res.status(500).json({ success: false, error: 'Failed to delete loan' });
  }
}

function voidLoanRepayment(req: Request, res: Response): void {
  try {
    const { id, loanId, repaymentId } = req.params;
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
    const parsedRepaymentId = parseInt(Array.isArray(repaymentId) ? repaymentId[0] : repaymentId, 10);
    const authReq = req as AuthRequest;

    const repayment = EmployeeLoanModel.getRepaymentById(parsedRepaymentId, db);
    const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    if (!repayment || repayment.loan_id !== parsedLoanId || repayment.employee_id !== employeeId) {
      res.status(404).json({ success: false, error: 'Repayment not found' });
      return;
    }
    if (repayment.voided_at) {
      res.status(409).json({ success: false, error: 'Repayment is already voided' });
      return;
    }

    AccountingService.assertPeriodNotClosed(db, repayment.payment_date, `Loan repayment ${parsedRepaymentId}`);

    const trx = db.transaction(() => {
      AccountingService.voidJournalLinesByReference(db, 'LOAN_REPAYMENT', parsedRepaymentId, {
        voidedBy: authReq.user?.id,
        voidReason: 'Repayment voided',
      });
      assertCashTimeline(db, { paymentMethod: repayment.payment_method, fromDate: repayment.payment_date });

      // Restore loan balance
      EmployeeLoanModel.restoreBalance(parsedLoanId, repayment.amount, db);

      // Void repayment record (never hard-delete)
      EmployeeLoanModel.deleteRepayment(parsedRepaymentId, db, authReq.user?.id ?? null, 'Repayment voided');

      const updatedLoan = EmployeeLoanModel.getById(parsedLoanId, db);
      res.json({
        success: true,
        data: {
          loan_id: parsedLoanId,
          balance: updatedLoan?.balance ?? 0,
          status: updatedLoan?.status ?? 'active',
        },
      });
    });

    trx();
  } catch (error: unknown) {
    handleBusinessError(res, error, 'Void loan repayment', 'Failed to void repayment', { success: true });
  }
}

export default {
  getEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  deleteEmployee,
  getNextEmployeeCode,
  paySalary,
  getSalaryHistory,
  getSalaryMonthDetail,
  deleteSalaryPayment,
  getEmployeeDocuments,
  addEmployeeDocument,
  removeEmployeeDocument,
  getLoans,
  createLoan,
  getLoanDetail,
  repayLoan,
  writeOffLoan,
  deleteLoan,
  voidLoanRepayment,
};
