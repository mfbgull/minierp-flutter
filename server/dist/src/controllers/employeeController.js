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
const EmployeeLoan_1 = require("../models/EmployeeLoan");
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
            const existingFull = database_1.default.prepare(`SELECT id FROM salary_payments WHERE employee_id = ? AND pay_period = ? AND payment_type = 'full'`).get(employeeId, payPeriod);
            if (existingFull) {
                const monthName = new Date(payPeriod + '-01').toLocaleString('en-US', { month: 'long', year: 'numeric' });
                res.status(409).json({
                    success: false,
                    error: `Full salary already paid for ${monthName}`,
                });
                return;
            }
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
                payment_type: safeType,
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
            // Overpayment: if total payments this month exceed salary, create advance for next month
            let advanceCreated = null;
            if (employee.salary > 0) {
                const payPeriod = payment_date.substring(0, 7);
                const totalRow = database_1.default.prepare(`SELECT SUM(amount) AS total_paid FROM salary_payments WHERE employee_id = ? AND pay_period = ?`).get(employeeId, payPeriod);
                const totalPaid = totalRow?.total_paid ?? 0;
                if (totalPaid > employee.salary) {
                    const excess = totalPaid - employee.salary;
                    // Compute next month's pay_period
                    const [year, month] = payPeriod.split('-').map(Number);
                    const nextDate = new Date(year, month, 1); // First day of next month
                    const nextPayPeriod = `${nextDate.getFullYear()}-${String(nextDate.getMonth() + 1).padStart(2, '0')}`;
                    const nextPaymentDate = `${nextPayPeriod}-01`;
                    advanceCreated = Employee_1.default.addSalaryPayment({
                        employee_id: employeeId,
                        amount: excess,
                        payment_date: nextPaymentDate,
                        payment_method: payment_method || 'bank',
                        reference_no: `ADV-${payPeriod}`,
                        notes: `Auto-advance from overpayment in ${payPeriod}`,
                        paid_by: authReq.user?.id,
                        payment_type: 'advance',
                    }, database_1.default);
                    // Post GL entry for the advance
                    try {
                        const advResult = accountingService_1.AccountingService.postSalaryEntry(database_1.default, {
                            salaryPaymentId: advanceCreated,
                            employeeName: `${employee.first_name} ${employee.last_name}`,
                            employeeCode: employee.employee_code,
                            amount: excess,
                            paymentDate: nextPaymentDate,
                            paymentMethod: payment_method,
                            userId: authReq.user?.id,
                        });
                        if (advResult) {
                            database_1.default.prepare(`UPDATE salary_payments SET journal_entry_id = ? WHERE id = ?`)
                                .run(advResult.journal_entry_id, advanceCreated);
                        }
                    }
                    catch (glError) {
                        logger_1.default.error('Failed to post GL for advance:', glError);
                    }
                }
            }
            (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId, `Salary paid: ${employee.first_name} ${employee.last_name} (amount: ${amount})`, authReq.user?.id);
            req.activityLogged = true;
            return { paymentId, journalEntryId, advanceCreated };
        });
        const result = trx();
        res.status(201).json({
            success: true,
            data: { id: result.paymentId, journal_entry_id: result.journalEntryId, advance_created: result.advanceCreated },
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
function getSalaryMonthDetail(req, res) {
    try {
        const { id, payPeriod: rawPeriod } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const payPeriod = Array.isArray(rawPeriod) ? rawPeriod[0] : rawPeriod;
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        const detail = Employee_1.default.getSalaryMonthDetail(employeeId, payPeriod, database_1.default);
        res.json({ success: true, data: detail });
    }
    catch (error) {
        logger_1.default.error('Error fetching salary month detail:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch salary month detail' });
    }
}
function deleteSalaryPayment(req, res) {
    try {
        const { id, paymentId } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const salaryPaymentId = parseInt(Array.isArray(paymentId) ? paymentId[0] : paymentId, 10);
        const authReq = req;
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        const payment = Employee_1.default.getSalaryPayment(salaryPaymentId, database_1.default);
        if (!payment || payment.employee_id !== employeeId) {
            res.status(404).json({ success: false, error: 'Salary payment not found' });
            return;
        }
        // Void GL journal entry if one was posted
        if (payment.journal_entry_id) {
            accountingService_1.AccountingService.voidJournalLinesByReference(database_1.default, 'SALARY_PAYMENT', salaryPaymentId, {
                voidedBy: authReq.user?.id,
                voidReason: `Salary payment deleted for ${employee.first_name} ${employee.last_name}`,
            });
        }
        Employee_1.default.deleteSalaryPayment(salaryPaymentId, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.EMPLOYEE_UPDATE, 'Employee', employeeId, `Salary payment deleted: ${employee.first_name} ${employee.last_name} (amount: ${payment.amount})`, authReq.user?.id);
        req.activityLogged = true;
        res.status(204).send();
    }
    catch (error) {
        logger_1.default.error('Error deleting salary payment:', error);
        res.status(500).json({ success: false, error: error.message || 'Failed to delete salary payment' });
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
// ═══════════════════════════════════════════════════════════
// Employee Loans
// ═══════════════════════════════════════════════════════════
function getLoans(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        if (!employee) {
            res.status(404).json({ success: false, error: 'Employee not found' });
            return;
        }
        // Auto-update overdue statuses
        EmployeeLoan_1.EmployeeLoanModel.updateOverdueStatuses(database_1.default);
        const loans = EmployeeLoan_1.EmployeeLoanModel.getByEmployee(employeeId, database_1.default);
        const summary = EmployeeLoan_1.EmployeeLoanModel.getSummary(employeeId, database_1.default);
        res.json({
            success: true,
            data: {
                loans: loans.map(l => ({
                    ...l,
                    repaid_amount: l.amount - l.balance,
                    repayment_count: EmployeeLoan_1.EmployeeLoanModel.hasRepayments(l.id, database_1.default) ? 1 : 0,
                    is_overdue: l.status === 'overdue',
                })),
                summary,
            },
        });
    }
    catch (error) {
        logger_1.default.error('Get loans error:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch loans' });
    }
}
function createLoan(req, res) {
    try {
        const { id } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const authReq = req;
        const employee = Employee_1.default.getById(employeeId, database_1.default);
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
        const trx = database_1.default.transaction(() => {
            const loanId = EmployeeLoan_1.EmployeeLoanModel.create({
                employee_id: employeeId,
                amount,
                disbursement_date,
                due_date,
                purpose,
                payment_method,
                monthly_installment,
                notes,
                created_by: authReq.user?.id,
            }, database_1.default);
            // Post GL entry
            let journalEntryId = null;
            try {
                const result = accountingService_1.AccountingService.postLoanDisbursement(database_1.default, {
                    loanId,
                    employeeName: `${employee.first_name} ${employee.last_name}`,
                    employeeCode: employee.employee_code,
                    amount,
                    disbursementDate: disbursement_date,
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
                EmployeeLoan_1.EmployeeLoanModel.updateJournalEntry(loanId, journalEntryId, database_1.default);
            }
            const loan = EmployeeLoan_1.EmployeeLoanModel.getById(loanId, database_1.default);
            res.status(201).json({ success: true, data: loan });
        });
        trx();
    }
    catch (error) {
        logger_1.default.error('Create loan error:', error);
        res.status(500).json({ success: false, error: error.message || 'Failed to create loan' });
    }
}
function getLoanDetail(req, res) {
    try {
        const { id, loanId } = req.params;
        const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
        const loan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Loan not found' });
            return;
        }
        const repayments = EmployeeLoan_1.EmployeeLoanModel.getRepayments(parsedLoanId, database_1.default);
        res.json({
            success: true,
            data: { ...loan, repayments },
        });
    }
    catch (error) {
        logger_1.default.error('Get loan detail error:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch loan detail' });
    }
}
function repayLoan(req, res) {
    try {
        const { id, loanId } = req.params;
        const employeeId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
        const authReq = req;
        const loan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
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
        const employee = Employee_1.default.getById(employeeId, database_1.default);
        const trx = database_1.default.transaction(() => {
            const repaymentId = EmployeeLoan_1.EmployeeLoanModel.addRepayment({
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
            }, database_1.default);
            // Deduct from loan balance
            EmployeeLoan_1.EmployeeLoanModel.deductBalance(parsedLoanId, amount, database_1.default);
            // Post GL entry only for direct repayments
            let journalEntryId = null;
            if (!isSalaryDeduction && employee) {
                try {
                    const result = accountingService_1.AccountingService.postLoanRepayment(database_1.default, {
                        repaymentId,
                        loanId: parsedLoanId,
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
            }
            if (journalEntryId) {
                EmployeeLoan_1.EmployeeLoanModel.updateRepaymentJournal(repaymentId, journalEntryId, database_1.default);
            }
            const updatedLoan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Repay loan error:', error);
        res.status(500).json({ success: false, error: error.message || 'Failed to record repayment' });
    }
}
function writeOffLoan(req, res) {
    try {
        const { id, loanId } = req.params;
        const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
        const authReq = req;
        const loan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Loan not found' });
            return;
        }
        if (loan.status !== 'active' && loan.status !== 'overdue') {
            res.status(409).json({ success: false, error: 'Loan is not active' });
            return;
        }
        const employee = Employee_1.default.getById(loan.employee_id, database_1.default);
        const writeOffAmount = loan.balance;
        const trx = database_1.default.transaction(() => {
            // Write off
            EmployeeLoan_1.EmployeeLoanModel.writeOff(parsedLoanId, database_1.default);
            // Post GL entry
            let journalEntryId = null;
            if (employee) {
                try {
                    const result = accountingService_1.AccountingService.postLoanWriteOff(database_1.default, {
                        loanId: parsedLoanId,
                        employeeName: `${employee.first_name} ${employee.last_name}`,
                        employeeCode: employee.employee_code,
                        amount: writeOffAmount,
                        writeOffDate: new Date().toISOString().substring(0, 10),
                        userId: authReq.user?.id,
                    });
                    if (result)
                        journalEntryId = result.journal_entry_id;
                }
                catch (glError) {
                    throw new Error(`GL posting failed: ${glError.message}`, { cause: glError });
                }
            }
            if (journalEntryId) {
                EmployeeLoan_1.EmployeeLoanModel.updateJournalEntry(parsedLoanId, journalEntryId, database_1.default);
            }
            const updatedLoan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Write off loan error:', error);
        res.status(500).json({ success: false, error: error.message || 'Failed to write off loan' });
    }
}
function deleteLoan(req, res) {
    try {
        const { id, loanId } = req.params;
        const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
        const authReq = req;
        const loan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
        if (!loan) {
            res.status(404).json({ success: false, error: 'Loan not found' });
            return;
        }
        if (EmployeeLoan_1.EmployeeLoanModel.hasRepayments(parsedLoanId, database_1.default)) {
            res.status(409).json({ success: false, error: 'Cannot delete loan with repayment history' });
            return;
        }
        const trx = database_1.default.transaction(() => {
            // Void GL lines
            if (loan.journal_entry_id) {
                accountingService_1.AccountingService.voidJournalLinesByReference(database_1.default, 'LOAN_DISBURSEMENT', parsedLoanId, {
                    voidedBy: authReq.user?.id,
                    voidReason: 'Loan deleted',
                });
            }
            EmployeeLoan_1.EmployeeLoanModel.delete(parsedLoanId, database_1.default);
            res.json({ success: true });
        });
        trx();
    }
    catch (error) {
        logger_1.default.error('Delete loan error:', error);
        res.status(500).json({ success: false, error: 'Failed to delete loan' });
    }
}
function voidLoanRepayment(req, res) {
    try {
        const { id, loanId, repaymentId } = req.params;
        const parsedLoanId = parseInt(Array.isArray(loanId) ? loanId[0] : loanId, 10);
        const parsedRepaymentId = parseInt(Array.isArray(repaymentId) ? repaymentId[0] : repaymentId, 10);
        const authReq = req;
        const repayment = EmployeeLoan_1.EmployeeLoanModel.getRepaymentById(parsedRepaymentId, database_1.default);
        if (!repayment) {
            res.status(404).json({ success: false, error: 'Repayment not found' });
            return;
        }
        const trx = database_1.default.transaction(() => {
            // Void GL lines for direct repayments
            if (repayment.repayment_type === 'direct' && repayment.journal_entry_id) {
                accountingService_1.AccountingService.voidJournalLinesByReference(database_1.default, 'LOAN_REPAYMENT', parsedRepaymentId, {
                    voidedBy: authReq.user?.id,
                    voidReason: 'Repayment voided',
                });
            }
            // Restore loan balance
            EmployeeLoan_1.EmployeeLoanModel.restoreBalance(parsedLoanId, repayment.amount, database_1.default);
            // Delete repayment record
            EmployeeLoan_1.EmployeeLoanModel.deleteRepayment(parsedRepaymentId, database_1.default);
            const updatedLoan = EmployeeLoan_1.EmployeeLoanModel.getById(parsedLoanId, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Void loan repayment error:', error);
        res.status(500).json({ success: false, error: 'Failed to void repayment' });
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
