import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';
import EmployeeModel from '../models/Employee';
import { EmployeeLoanModel } from '../models/EmployeeLoan';
import { AccountingService } from '../services/accountingService';
import fs from 'fs';
import path from 'path';

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
    const employee_code = `EMP-${String(nextNumber).padStart(3, '0')}`;

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
  } catch (error: any) {
    logger.error('Error creating employee:', error);
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
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
    const code = `EMP-${String(nextNumber).padStart(3, '0')}`;
    res.json({ success: true, data: { code } });
  } catch (error) {
    logger.error('Error generating employee code:', error);
    const code = 'EMP-001';
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

    const { amount, payment_date, payment_method, reference_no, notes, payment_type } = req.body;
    if (!amount || amount <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
      return;
    }
    if (!payment_date) {
      res.status(422).json({ success: false, error: 'Payment date is required' });
      return;
    }

    const safeType = ['full', 'advance', 'partial'].includes(payment_type) ? payment_type : 'full';

    // Duplicate guard: reject a 'full' payment if one already exists for the month.
    // Advance and partial payments are always allowed.
    if (safeType === 'full') {
      const payPeriod = payment_date.substring(0, 7); // YYYY-MM
      const existingFull = db.prepare(
        `SELECT id FROM salary_payments WHERE employee_id = ? AND pay_period = ? AND payment_type = 'full'`
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
      const paymentId = EmployeeModel.addSalaryPayment({
        employee_id: employeeId,
        amount,
        payment_date,
        payment_method: payment_method || 'bank',
        reference_no,
        notes,
        paid_by: authReq.user?.id,
        payment_type: safeType,
      }, db);

      let journalEntryId: number | null = null;
      try {
        const result = AccountingService.postSalaryEntry(db, {
          salaryPaymentId: paymentId,
          employeeName: `${employee.first_name} ${employee.last_name}`,
          employeeCode: employee.employee_code,
          amount,
          paymentDate: payment_date,
          paymentMethod: payment_method,
          userId: authReq.user?.id,
        });
        if (result) journalEntryId = result.journal_entry_id;
      } catch (glError: any) {
        throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
      }

      if (journalEntryId) {
        db.prepare(`UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?`)
          .run(journalEntryId, paymentId);
      }

      // Overpayment: if total payments this month exceed salary, create advance for next month
      let advanceCreated: number | null = null;
      if (employee.salary > 0) {
        const payPeriod = payment_date.substring(0, 7);
        const totalRow = db.prepare(
          `SELECT SUM(amount) AS total_paid FROM salary_payments WHERE employee_id = ? AND pay_period = ?`
        ).get(employeeId, payPeriod) as { total_paid: number } | undefined;
        const totalPaid = totalRow?.total_paid ?? 0;
        if (totalPaid > employee.salary) {
          const excess = totalPaid - employee.salary;
          // Compute next month's pay_period
          const [year, month] = payPeriod.split('-').map(Number);
          const nextDate = new Date(year, month, 1); // First day of next month
          const nextPayPeriod = `${nextDate.getFullYear()}-${String(nextDate.getMonth() + 1).padStart(2, '0')}`;
          const nextPaymentDate = `${nextPayPeriod}-01`;

          advanceCreated = EmployeeModel.addSalaryPayment({
            employee_id: employeeId,
            amount: excess,
            payment_date: nextPaymentDate,
            payment_method: payment_method || 'bank',
            reference_no: `ADV-${payPeriod}`,
            notes: `Auto-advance from overpayment in ${payPeriod}`,
            paid_by: authReq.user?.id,
            payment_type: 'advance',
          }, db);

          // Post GL entry for the advance
          try {
            const advResult = AccountingService.postSalaryEntry(db, {
              salaryPaymentId: advanceCreated,
              employeeName: `${employee.first_name} ${employee.last_name}`,
              employeeCode: employee.employee_code,
              amount: excess,
              paymentDate: nextPaymentDate,
              paymentMethod: payment_method,
              userId: authReq.user?.id,
            });
            if (advResult) {
              db.prepare(`UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?`)
                .run(advResult.journal_entry_id, advanceCreated);
            }
          } catch (glError: any) {
            logger.error('Failed to post GL for advance:', glError);
          }
        }
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
  } catch (error: any) {
    logger.error('Error paying salary:', error);
    res.status(500).json({ success: false, error: error.message || 'Failed to process salary payment' });
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

    const payment = EmployeeModel.getSalaryPayment(salaryPaymentId, db) as { employee_id: number; journal_entry_id?: number | null; amount: number; payment_date: string } | undefined;
    if (!payment || payment.employee_id !== employeeId) {
      res.status(404).json({ success: false, error: 'Salary payment not found' });
      return;
    }

    // Void GL journal entry if one was posted
    if (payment.journal_entry_id) {
      AccountingService.voidJournalLinesByReference(db, 'SALARY_PAYMENT', salaryPaymentId, {
        voidedBy: authReq.user?.id,
        voidReason: `Salary payment deleted for ${employee.first_name} ${employee.last_name}`,
      });
    }

    EmployeeModel.deleteSalaryPayment(salaryPaymentId, db);

    logCRUD(ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId,
      `Salary payment deleted: ${employee.first_name} ${employee.last_name} (amount: ${payment.amount})`, authReq.user?.id);
    req.activityLogged = true;

    res.status(204).send();
  } catch (error: any) {
    logger.error('Error deleting salary payment:', error);
    res.status(500).json({ success: false, error: error.message || 'Failed to delete salary payment' });
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
    const uploadedFile = (req as any).file;
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

    // Delete file if it exists
    const doc = db.prepare('SELECT file_path FROM employee_documents WHERE id = ?').get(documentId) as { file_path?: string } | undefined;
    if (doc?.file_path) {
      const filePath = path.join(__dirname, '../../uploads/employees', doc.file_path);
      if (fs.existsSync(filePath)) {
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
  } catch (error: any) {
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
    if (!amount || amount <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
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
      } catch (glError: any) {
        throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateJournalEntry(loanId, journalEntryId, db);
      }

      const loan = EmployeeLoanModel.getById(loanId, db);
      res.status(201).json({ success: true, data: loan });
    });

    trx();
  } catch (error: any) {
    logger.error('Create loan error:', error);
    res.status(500).json({ success: false, error: error.message || 'Failed to create loan' });
  }
}

function getLoanDetail(req: Request, res: Response): void {
  try {
    const { id, loanId } = req.params;
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
  } catch (error: any) {
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
    if (!loan) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }
    if (loan.status !== 'active' && loan.status !== 'overdue') {
      res.status(409).json({ success: false, error: 'Loan is not active' });
      return;
    }

    const { amount, payment_date, payment_method, reference_no, notes, salary_payment_id } = req.body;
    if (!amount || amount <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
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
      const repaymentId = EmployeeLoanModel.addRepayment({
        loan_id: parsedLoanId,
        employee_id: employeeId,
        amount,
        payment_date,
        payment_method,
        reference_no,
        notes,
        repayment_type: repaymentType,
        salary_payment_id: salary_payment_id || undefined,
        created_by: authReq.user?.id,
      }, db);

      // Deduct from loan balance
      EmployeeLoanModel.deductBalance(parsedLoanId, amount, db);

      // Post GL entry only for direct repayments
      let journalEntryId: number | null = null;
      if (!isSalaryDeduction && employee) {
        try {
          const result = AccountingService.postLoanRepayment(db, {
            repaymentId,
            loanId: parsedLoanId,
            employeeName: `${employee.first_name} ${employee.last_name}`,
            employeeCode: employee.employee_code,
            amount,
            paymentDate: payment_date,
            paymentMethod: payment_method,
            userId: authReq.user?.id,
          });
          if (result) journalEntryId = result.journal_entry_id;
        } catch (glError: any) {
          throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
        }
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateRepaymentJournal(repaymentId, journalEntryId, db);
      }

      const updatedLoan = EmployeeLoanModel.getById(parsedLoanId, db);
      res.status(201).json({
        success: true,
        data: {
          id: repaymentId,
          amount,
          loan_balance: updatedLoan?.balance ?? 0,
          loan_status: updatedLoan?.status ?? 'active',
          journal_entry_id: journalEntryId,
        },
      });
    });

    trx();
  } catch (error: any) {
    logger.error('Repay loan error:', error);
    res.status(500).json({ success: false, error: error.message || 'Failed to record repayment' });
  }
}

function writeOffLoan(req: Request, res: Response): void {
  try {
    const { id, loanId } = req.params;
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
        } catch (glError: any) {
          throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
        }
      }

      if (journalEntryId) {
        EmployeeLoanModel.updateJournalEntry(parsedLoanId, journalEntryId, db);
      }

      const updatedLoan = EmployeeLoanModel.getById(parsedLoanId, db);
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
  } catch (error: any) {
    logger.error('Write off loan error:', error);
    res.status(500).json({ success: false, error: error.message || 'Failed to write off loan' });
  }
}

function deleteLoan(req: Request, res: Response): void {
  try {
    const { id, loanId } = req.params;
    const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
    const authReq = req as AuthRequest;

    const loan = EmployeeLoanModel.getById(parsedLoanId, db);
    if (!loan) {
      res.status(404).json({ success: false, error: 'Loan not found' });
      return;
    }
    if (EmployeeLoanModel.hasRepayments(parsedLoanId, db)) {
      res.status(409).json({ success: false, error: 'Cannot delete loan with repayment history' });
      return;
    }

    const trx = db.transaction(() => {
      // Void GL lines
      if (loan.journal_entry_id) {
        AccountingService.voidJournalLinesByReference(db, 'LOAN_DISBURSEMENT', parsedLoanId, {
          voidedBy: authReq.user?.id,
          voidReason: 'Loan deleted',
        });
      }

      EmployeeLoanModel.delete(parsedLoanId, db);
      res.json({ success: true });
    });

    trx();
  } catch (error: any) {
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
    if (!repayment) {
      res.status(404).json({ success: false, error: 'Repayment not found' });
      return;
    }

    const trx = db.transaction(() => {
      // Void GL lines for direct repayments
      if (repayment.repayment_type === 'direct' && repayment.journal_entry_id) {
        AccountingService.voidJournalLinesByReference(db, 'LOAN_REPAYMENT', parsedRepaymentId, {
          voidedBy: authReq.user?.id,
          voidReason: 'Repayment voided',
        });
      }

      // Restore loan balance
      EmployeeLoanModel.restoreBalance(parsedLoanId, repayment.amount, db);

      // Delete repayment record
      EmployeeLoanModel.deleteRepayment(parsedRepaymentId, db);

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
  } catch (error: any) {
    logger.error('Void loan repayment error:', error);
    res.status(500).json({ success: false, error: 'Failed to void repayment' });
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
