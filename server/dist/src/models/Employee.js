"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class EmployeeModel {
    static getAll(db, params = {}, sortBy = 'employee_code', sortOrder = 'ASC', page = 1, limit = 20) {
        const safeSort = ['employee_code', 'first_name', 'last_name', 'department', 'designation', 'created_at'].includes(sortBy)
            ? sortBy : 'employee_code';
        const safeOrder = sortOrder.toUpperCase() === 'DESC' ? 'DESC' : 'ASC';
        const safeLimit = Math.min(Math.max(1, limit), 100);
        const safePage = Math.max(1, page);
        const offset = (safePage - 1) * safeLimit;
        const whereClauses = [];
        const bindValues = [];
        // Default active filter — skipped when explicitly requesting inactive
        if (params.status !== 'inactive') {
            whereClauses.push('e.is_active = 1');
        }
        else {
            whereClauses.push('e.is_active = 0');
        }
        if (params.search) {
            whereClauses.push(`(e.employee_code LIKE ? OR e.first_name LIKE ? OR e.last_name LIKE ? OR e.email LIKE ? OR e.phone LIKE ? OR e.cnic_no LIKE ?)`);
            const like = `%${params.search}%`;
            bindValues.push(like, like, like, like, like, like);
        }
        if (params.department) {
            whereClauses.push('e.department = ?');
            bindValues.push(params.department);
        }
        const whereSQL = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
        const countRow = db.prepare(`SELECT COUNT(*) as count FROM employees e ${whereSQL}`).get(...bindValues);
        const data = db.prepare(`SELECT e.* FROM employees e ${whereSQL} ORDER BY e.${safeSort} ${safeOrder} LIMIT ? OFFSET ?`).all(...bindValues, safeLimit, offset);
        return { data, total: countRow.count };
    }
    static getById(id, db) {
        return db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
    }
    static create(data, db) {
        const result = db.prepare(`
      INSERT INTO employees (
        employee_code, first_name, last_name, email, phone, mobile,
        cnic_no, address, city, state, postal_code, country,
        date_of_birth, gender, department, designation, employment_type,
        date_of_joining, date_of_leaving, salary, bank_name, bank_account_no,
        bank_iban, emergency_contact_name, emergency_contact_phone,
        profile_photo, notes, is_active, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.employee_code, data.first_name, data.last_name, data.email || null, data.phone || null, data.mobile || null, data.cnic_no || null, data.address || null, data.city || null, data.state || null, data.postal_code || null, data.country || 'Pakistan', data.date_of_birth || null, data.gender || null, data.department || null, data.designation || null, data.employment_type || 'Full-time', data.date_of_joining || null, data.date_of_leaving || null, data.salary || 0, data.bank_name || null, data.bank_account_no || null, data.bank_iban || null, data.emergency_contact_name || null, data.emergency_contact_phone || null, data.profile_photo || null, data.notes || null, data.is_active !== undefined ? (data.is_active ? 1 : 0) : 1, data.created_by || null);
        return result.lastInsertRowid;
    }
    static update(id, data, db) {
        return db.prepare(`
      UPDATE employees SET
        first_name = COALESCE(?, first_name),
        last_name = COALESCE(?, last_name),
        email = COALESCE(?, email),
        phone = COALESCE(?, phone),
        mobile = COALESCE(?, mobile),
        cnic_no = COALESCE(?, cnic_no),
        address = COALESCE(?, address),
        city = COALESCE(?, city),
        state = COALESCE(?, state),
        postal_code = COALESCE(?, postal_code),
        country = COALESCE(?, country),
        date_of_birth = COALESCE(?, date_of_birth),
        gender = COALESCE(?, gender),
        department = COALESCE(?, department),
        designation = COALESCE(?, designation),
        employment_type = COALESCE(?, employment_type),
        date_of_joining = COALESCE(?, date_of_joining),
        date_of_leaving = COALESCE(?, date_of_leaving),
        salary = COALESCE(?, salary),
        bank_name = COALESCE(?, bank_name),
        bank_account_no = COALESCE(?, bank_account_no),
        bank_iban = COALESCE(?, bank_iban),
        emergency_contact_name = COALESCE(?, emergency_contact_name),
        emergency_contact_phone = COALESCE(?, emergency_contact_phone),
        profile_photo = COALESCE(?, profile_photo),
        notes = COALESCE(?, notes),
        is_active = COALESCE(?, is_active),
        updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(data.first_name ?? null, data.last_name ?? null, data.email ?? null, data.phone ?? null, data.mobile ?? null, data.cnic_no ?? null, data.address ?? null, data.city ?? null, data.state ?? null, data.postal_code ?? null, data.country ?? null, data.date_of_birth ?? null, data.gender ?? null, data.department ?? null, data.designation ?? null, data.employment_type ?? null, data.date_of_joining ?? null, data.date_of_leaving ?? null, data.salary ?? null, data.bank_name ?? null, data.bank_account_no ?? null, data.bank_iban ?? null, data.emergency_contact_name ?? null, data.emergency_contact_phone ?? null, data.profile_photo ?? null, data.notes ?? null, data.is_active !== undefined ? (data.is_active ? 1 : 0) : null, id);
    }
    static delete(id, db) {
        return db.prepare('UPDATE employees SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(id);
    }
    static getDocuments(employeeId, db) {
        return db.prepare('SELECT * FROM employee_documents WHERE employee_id = ? ORDER BY created_at DESC').all(employeeId);
    }
    static addDocument(data, db) {
        const result = db.prepare(`
      INSERT INTO employee_documents (
        employee_id, document_name, document_type, document_number,
        issue_date, expiry_date, file_path, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.employee_id, data.document_name, data.document_type || null, data.document_number || null, data.issue_date || null, data.expiry_date || null, data.file_path || null, data.notes || null);
        return result.lastInsertRowid;
    }
    static removeDocument(id, db) {
        return db.prepare('DELETE FROM employee_documents WHERE id = ?').run(id);
    }
    // ------------------------------------------------------------------
    // Salary payments
    // ------------------------------------------------------------------
    static getSalaryHistory(employeeId, db) {
        return db.prepare(`SELECT * FROM salary_payments WHERE employee_id = ? ORDER BY payment_date DESC`).all(employeeId);
    }
    static addSalaryPayment(data, db) {
        const result = db.prepare(`
      INSERT INTO salary_payments (
        employee_id, amount, payment_date, payment_method,
        reference_no, notes, journal_entry_id, paid_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(data.employee_id, data.amount, data.payment_date, data.payment_method || 'bank', data.reference_no || null, data.notes || null, data.journal_entry_id || null, data.paid_by || null);
        return result.lastInsertRowid;
    }
}
exports.default = EmployeeModel;
