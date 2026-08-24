"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const sequence_1 = require("../utils/sequence");
const Employee_1 = __importDefault(require("../models/Employee"));
const accountingService_1 = require("../services/accountingService");
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
function getEmployees(req, res) {
    try {
        const { search, department, status, sortBy, sortOrder, page, limit } = req.query;
        const result = Employee_1.default.getAll(database_1.default, {
            search: search,
            department: department,
            status: status,
        }, sortBy || 'employee_code', sortOrder || 'ASC', parseInt(page, 10) || 1, parseInt(limit, 10) || 20);
        const safePage = parseInt(page, 10) || 1;
        const safeLimit = parseInt(limit, 10) || 20;
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
    }
    catch (error) {
        logger_1.default.error('Error fetching employees:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch employees'
        });
    }
}
function getEmployee(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        res.json({ success: true, data: employee });
    }
    catch (error) {
        logger_1.default.error('Error fetching employee:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch employee' });
    }
}
function createEmployee(req, res) {
    try {
        const { first_name, last_name, email, phone, mobile, cnic_no, address, city, state, postal_code, country, date_of_birth, gender, department, designation, employment_type, date_of_joining, date_of_leaving, salary, bank_name, bank_account_no, bank_iban, emergency_contact_name, emergency_contact_phone, profile_photo, notes } = req.body;
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
        (0, sequence_1.initializeSequenceFromMax)(database_1.default, 'EMP_last_no', 'employees', 'employee_code', 'EMP-');
        const nextNumber = (0, sequence_1.getNextSequenceNumber)(database_1.default, 'EMP_last_no');
        const employee_code = `EMP-${String(nextNumber).padStart(3, '0')}`;
        const id = Employee_1.default.create({
            employee_code,
            first_name: first_name.trim(),
            last_name: last_name.trim(),
            email, phone, mobile, cnic_no, address, city, state, postal_code,
            country, date_of_birth, gender, department, designation, employment_type,
            date_of_joining, date_of_leaving, salary, bank_name, bank_account_no,
            bank_iban, emergency_contact_name, emergency_contact_phone,
            profile_photo, notes,
            is_active: true,
            created_by: req.user?.id
        }, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_CREATE, 'Employee', id, `Created employee: ${first_name} ${last_name} (${employee_code})`, req.user?.id);
        req.activityLogged = true;
        const employee = Employee_1.default.getById(id, database_1.default);
        res.status(201).json({ success: true, data: employee });
    }
    catch (error) {
        logger_1.default.error('Error creating employee:', error);
        if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
            res.status(409).json({ success: false, error: 'Employee code already exists' });
        }
        else {
            res.status(500).json({ success: false, error: 'Failed to create employee' });
        }
    }
}
function updateEmployee(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const existing = Employee_1.default.getById(employeeId, database_1.default);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        const { email } = req.body;
        if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            res.status(422).json({ success: false, error: 'Invalid email format' });
            return;
        }
        const result = Employee_1.default.update(employeeId, req.body, database_1.default);
        if (result.changes === 0) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId, `Updated employee: ${req.body.first_name || existing.first_name} ${req.body.last_name || existing.last_name}`, req.user?.id);
        req.activityLogged = true;
        const updated = Employee_1.default.getById(employeeId, database_1.default);
        res.json({ success: true, data: updated });
    }
    catch (error) {
        logger_1.default.error('Error updating employee:', error);
        res.status(500).json({ success: false, error: 'Failed to update employee' });
    }
}
function deleteEmployee(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const existing = Employee_1.default.getById(employeeId, database_1.default);
        if (!existing) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        Employee_1.default.delete(employeeId, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_DELETE, 'Employee', employeeId, `Deleted employee: ${existing.first_name} ${existing.last_name} (${existing.employee_code})`, req.user?.id);
        req.activityLogged = true;
        res.status(204).send();
    }
    catch (error) {
        logger_1.default.error('Error deleting employee:', error);
        res.status(500).json({ success: false, error: 'Failed to delete employee' });
    }
}
function getNextEmployeeCode(req, res) {
    try {
        (0, sequence_1.initializeSequenceFromMax)(database_1.default, 'EMP_last_no', 'employees', 'employee_code', 'EMP-');
        const nextNumber = (0, sequence_1.getNextSequenceNumber)(database_1.default, 'EMP_last_no');
        const code = `EMP-${String(nextNumber).padStart(3, '0')}`;
        res.json({ success: true, data: { code } });
    }
    catch (error) {
        logger_1.default.error('Error generating employee code:', error);
        const code = 'EMP-001';
        res.json({ success: true, data: { code } });
    }
}
function paySalary(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const authReq = req;
        const employee = Employee_1.default.getById(employeeId, database_1.default);
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
        const trx = database_1.default.transaction(() => {
            const paymentId = Employee_1.default.addSalaryPayment({
                employee_id: employeeId,
                amount,
                payment_date,
                payment_method: payment_method || 'bank',
                reference_no,
                notes,
                paid_by: authReq.user?.id,
            }, database_1.default);
            let journalEntryId = null;
            try {
                const result = accountingService_1.AccountingService.postSalaryEntry(database_1.default, {
                    salaryPaymentId: paymentId,
                    employeeName: `${employee.first_name} ${employee.last_name}`,
                    employeeCode: employee.employee_code,
                    amount,
                    paymentDate: payment_date,
                    paymentMethod: payment_method,
                    userId: authReq.user?.id,
                });
                if (result)
                    journalEntryId = result.journal_entry_id;
            }
            catch (glError) {
                throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
            }
            if (journalEntryId) {
                database_1.default.prepare(`UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?`)
                    .run(journalEntryId, paymentId);
            }
            (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId, `Salary paid: ${employee.first_name} ${employee.last_name} (amount: ${amount})`, authReq.user?.id);
            req.activityLogged = true;
            return { paymentId, journalEntryId };
        });
        const result = trx();
        res.status(201).json({
            success: true,
            data: { id: result.paymentId, journal_entry_id: result.journalEntryId },
        });
    }
    catch (error) {
        logger_1.default.error('Error paying salary:', error);
        res.status(500).json({ success: false, error: error.message || 'Failed to process salary payment' });
    }
}
function getSalaryHistory(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        const history = Employee_1.default.getSalaryHistory(employeeId, database_1.default);
        res.json({ success: true, data: history });
    }
    catch (error) {
        logger_1.default.error('Error fetching salary history:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch salary history' });
    }
}
function getEmployeeDocuments(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        const documents = Employee_1.default.getDocuments(employeeId, database_1.default);
        res.json({ success: true, data: documents });
    }
    catch (error) {
        logger_1.default.error('Error fetching employee documents:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch employee documents' });
    }
}
function addEmployeeDocument(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
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
        const uploadedFile = req.file;
        const filePath = uploadedFile ? uploadedFile.filename : file_path || null;
        const docId = Employee_1.default.addDocument({
            employee_id: employeeId,
            document_name: document_name.trim(),
            document_type,
            document_number,
            issue_date,
            expiry_date,
            file_path: filePath,
            notes
        }, database_1.default);
        res.status(201).json({ success: true, data: { id: docId } });
    }
    catch (error) {
        logger_1.default.error('Error adding employee document:', error);
        res.status(500).json({ success: false, error: 'Failed to add employee document' });
    }
}
function removeEmployeeDocument(req, res) {
    try {
        const { id, docId } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const documentId = parseInt(Array.isArray(docId) ? docId[0] : docId, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        // Delete file if it exists
        const doc = database_1.default.prepare('SELECT file_path FROM employee_documents WHERE id = ?').get(documentId);
        if (doc?.file_path) {
            const filePath = path_1.default.join(__dirname, '../../uploads/employees', doc.file_path);
            if (fs_1.default.existsSync(filePath)) {
                fs_1.default.unlinkSync(filePath);
            }
        }
        Employee_1.default.removeDocument(documentId, database_1.default);
        res.status(204).send();
    }
    catch (error) {
        logger_1.default.error('Error removing employee document:', error);
        res.status(500).json({ success: false, error: 'Failed to remove employee document' });
    }
}
exports.default = {
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
//# sourceMappingURL=employeeController.js.map