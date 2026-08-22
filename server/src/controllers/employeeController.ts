import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import logger from '../utils/logger';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';
import EmployeeModel from '../models/Employee';
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

    const { amount, payment_date, payment_method, reference_no, notes } = req.body;
    if (!amount || amount <= 0) {
      res.status(422).json({ success: false, error: 'Valid amount is required' });
      return;
    }
    if (!payment_date) {
      res.status(422).json({ success: false, error: 'Payment date is required' });
      return;
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

      logCRUD(ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId,
        `Salary paid: ${employee.first_name} ${employee.last_name} (amount: ${amount})`, authReq.user?.id);
      req.activityLogged = true;

      return { paymentId, journalEntryId };
    });

    const result = trx();

    res.status(201).json({
      success: true,
      data: { id: result.paymentId, journal_entry_id: result.journalEntryId },
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

export default {
  getEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  deleteEmployee,
  getNextEmployeeCode,
  paySalary,
  getSalaryHistory,
  getEmployeeDocuments,
  addEmployeeDocument,
  removeEmployeeDocument
};
