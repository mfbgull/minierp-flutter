import Database from 'better-sqlite3';

export interface Employee {
  id: number;
  employee_code: string;
  first_name: string;
  last_name: string;
  email?: string;
  phone?: string;
  mobile?: string;
  cnic_no?: string;
  address?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  country?: string;
  date_of_birth?: string;
  gender?: string;
  department?: string;
  designation?: string;
  employment_type?: string;
  date_of_joining?: string;
  date_of_leaving?: string;
  salary: number;
  bank_name?: string;
  bank_account_no?: string;
  bank_iban?: string;
  emergency_contact_name?: string;
  emergency_contact_phone?: string;
  profile_photo?: string;
  notes?: string;
  is_active: number;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
}

export interface CreateEmployeeDTO {
  employee_code: string;
  first_name: string;
  last_name: string;
  email?: string;
  phone?: string;
  mobile?: string;
  cnic_no?: string;
  address?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  country?: string;
  date_of_birth?: string;
  gender?: string;
  department?: string;
  designation?: string;
  employment_type?: string;
  date_of_joining?: string;
  date_of_leaving?: string;
  salary?: number;
  bank_name?: string;
  bank_account_no?: string;
  bank_iban?: string;
  emergency_contact_name?: string;
  emergency_contact_phone?: string;
  profile_photo?: string;
  notes?: string;
  is_active?: boolean;
  created_by?: number;
}

export interface UpdateEmployeeDTO {
  first_name?: string;
  last_name?: string;
  email?: string;
  phone?: string;
  mobile?: string;
  cnic_no?: string;
  address?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  country?: string;
  date_of_birth?: string;
  gender?: string;
  department?: string;
  designation?: string;
  employment_type?: string;
  date_of_joining?: string;
  date_of_leaving?: string;
  salary?: number;
  bank_name?: string;
  bank_account_no?: string;
  bank_iban?: string;
  emergency_contact_name?: string;
  emergency_contact_phone?: string;
  profile_photo?: string;
  notes?: string;
  is_active?: boolean;
}

export interface EmployeeDocument {
  id: number;
  employee_id: number;
  document_name: string;
  document_type?: string;
  document_number?: string;
  issue_date?: string;
  expiry_date?: string;
  file_path?: string;
  notes?: string;
  created_at?: string;
  updated_at?: string;
}

class EmployeeModel {
  static getAll(
    db: Database.Database,
    params: { search?: string; department?: string; status?: string } = {},
    sortBy: string = 'employee_code',
    sortOrder: string = 'ASC',
    page: number = 1,
    limit: number = 20
  ): { data: Employee[]; total: number } {
    const safeSort = ['employee_code', 'first_name', 'last_name', 'department', 'designation', 'created_at'].includes(sortBy)
      ? sortBy : 'employee_code';
    const safeOrder = sortOrder.toUpperCase() === 'DESC' ? 'DESC' : 'ASC';
    const safeLimit = Math.min(Math.max(1, limit), 100);
    const safePage = Math.max(1, page);
    const offset = (safePage - 1) * safeLimit;

    const whereClauses: string[] = [];
    const bindValues: (string | number)[] = [];

    // Default active filter — skipped when explicitly requesting inactive
    if (params.status !== 'inactive') {
      whereClauses.push('e.is_active = 1');
    } else {
      whereClauses.push('e.is_active = 0');
    }

    if (params.search) {
      whereClauses.push(
        `(e.employee_code LIKE ? OR e.first_name LIKE ? OR e.last_name LIKE ? OR e.email LIKE ? OR e.phone LIKE ? OR e.cnic_no LIKE ?)`
      );
      const like = `%${params.search}%`;
      bindValues.push(like, like, like, like, like, like);
    }

    if (params.department) {
      whereClauses.push('e.department = ?');
      bindValues.push(params.department);
    }

    const whereSQL = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

    const countRow = db.prepare(
      `SELECT COUNT(*) as count FROM employees e ${whereSQL}`
    ).get(...bindValues) as { count: number };

    const data = db.prepare(
      `SELECT e.* FROM employees e ${whereSQL} ORDER BY e.${safeSort} ${safeOrder} LIMIT ? OFFSET ?`
    ).all(...bindValues, safeLimit, offset) as Employee[];

    return { data, total: countRow.count };
  }

  static getById(id: number, db: Database.Database): Employee | undefined {
    return db.prepare('SELECT * FROM employees WHERE id = ?').get(id) as Employee | undefined;
  }

  static create(data: CreateEmployeeDTO, db: Database.Database): number {
    const result = db.prepare(`
      INSERT INTO employees (
        employee_code, first_name, last_name, email, phone, mobile,
        cnic_no, address, city, state, postal_code, country,
        date_of_birth, gender, department, designation, employment_type,
        date_of_joining, date_of_leaving, salary, bank_name, bank_account_no,
        bank_iban, emergency_contact_name, emergency_contact_phone,
        profile_photo, notes, is_active, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.employee_code,
      data.first_name,
      data.last_name,
      data.email || null,
      data.phone || null,
      data.mobile || null,
      data.cnic_no || null,
      data.address || null,
      data.city || null,
      data.state || null,
      data.postal_code || null,
      data.country || 'Pakistan',
      data.date_of_birth || null,
      data.gender || null,
      data.department || null,
      data.designation || null,
      data.employment_type || 'Full-time',
      data.date_of_joining || null,
      data.date_of_leaving || null,
      data.salary || 0,
      data.bank_name || null,
      data.bank_account_no || null,
      data.bank_iban || null,
      data.emergency_contact_name || null,
      data.emergency_contact_phone || null,
      data.profile_photo || null,
      data.notes || null,
      data.is_active !== undefined ? (data.is_active ? 1 : 0) : 1,
      data.created_by || null
    );
    return result.lastInsertRowid as number;
  }

  static update(id: number, data: UpdateEmployeeDTO, db: Database.Database): Database.RunResult {
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
    `).run(
      data.first_name ?? null,
      data.last_name ?? null,
      data.email ?? null,
      data.phone ?? null,
      data.mobile ?? null,
      data.cnic_no ?? null,
      data.address ?? null,
      data.city ?? null,
      data.state ?? null,
      data.postal_code ?? null,
      data.country ?? null,
      data.date_of_birth ?? null,
      data.gender ?? null,
      data.department ?? null,
      data.designation ?? null,
      data.employment_type ?? null,
      data.date_of_joining ?? null,
      data.date_of_leaving ?? null,
      data.salary ?? null,
      data.bank_name ?? null,
      data.bank_account_no ?? null,
      data.bank_iban ?? null,
      data.emergency_contact_name ?? null,
      data.emergency_contact_phone ?? null,
      data.profile_photo ?? null,
      data.notes ?? null,
      data.is_active !== undefined ? (data.is_active ? 1 : 0) : null,
      id
    );
  }

  static delete(id: number, db: Database.Database): Database.RunResult {
    return db.prepare('UPDATE employees SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(id);
  }

  static getDocuments(employeeId: number, db: Database.Database): EmployeeDocument[] {
    return db.prepare(
      'SELECT * FROM employee_documents WHERE employee_id = ? ORDER BY created_at DESC'
    ).all(employeeId) as EmployeeDocument[];
  }

  static addDocument(data: { employee_id: number; document_name: string; document_type?: string; document_number?: string; issue_date?: string; expiry_date?: string; file_path?: string; notes?: string }, db: Database.Database): number {
    const result = db.prepare(`
      INSERT INTO employee_documents (
        employee_id, document_name, document_type, document_number,
        issue_date, expiry_date, file_path, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.employee_id,
      data.document_name,
      data.document_type || null,
      data.document_number || null,
      data.issue_date || null,
      data.expiry_date || null,
      data.file_path || null,
      data.notes || null
    );
    return result.lastInsertRowid as number;
  }

  static removeDocument(id: number, db: Database.Database): Database.RunResult {
    return db.prepare('DELETE FROM employee_documents WHERE id = ?').run(id);
  }

  // ------------------------------------------------------------------
  // Salary payments
  // ------------------------------------------------------------------

  /**
   * Aggregated salary history — one row per pay_period (month).
   * Returns: pay_period, employee_salary, total_paid, status, payment_count.
   */
  static getSalaryHistory(employeeId: number, db: Database.Database): any[] {
    const employee = db.prepare('SELECT salary FROM employees WHERE id = ?').get(employeeId) as { salary: number } | undefined;
    const salary = employee?.salary ?? 0;

    const rows = db.prepare(`
      SELECT
        pay_period,
        SUM(amount) AS total_paid,
        COUNT(*) AS payment_count,
        SUM(CASE WHEN reference_no LIKE 'ADV-%' THEN amount ELSE 0 END) AS auto_advance_amount,
        MIN(CASE WHEN reference_no LIKE 'ADV-%' THEN reference_no END) AS advance_reference,
        MIN(payment_date) AS first_payment_date,
        MAX(payment_date) AS last_payment_date
      FROM salary_payments
      WHERE employee_id = ?
      GROUP BY pay_period
      ORDER BY pay_period DESC
    `).all(employeeId) as Array<{
      pay_period: string;
      total_paid: number;
      payment_count: number;
      auto_advance_amount: number;
      advance_reference: string | null;
      first_payment_date: string;
      last_payment_date: string;
    }>;

    return rows.map((r) => {
      let status: string;
      if (r.total_paid >= salary && salary > 0) {
        status = 'paid';
      } else if (r.auto_advance_amount > 0 && r.auto_advance_amount === r.total_paid) {
        // All payments are auto-advances from prior month overpayment
        status = 'advance';
      } else if (r.total_paid > 0) {
        status = 'partial';
      } else {
        status = 'advance';
      }

      // Extract source month from ADV-YYYY-MM reference
      let advanceSourcePeriod: string | null = null;
      if (r.advance_reference) {
        const match = r.advance_reference.match(/^ADV-(\d{4}-\d{2})$/);
        if (match) advanceSourcePeriod = match[1];
      }

      return {
        pay_period: r.pay_period,
        employee_salary: salary,
        total_paid: r.total_paid,
        remaining: Math.max(0, salary - r.total_paid),
        status,
        payment_count: r.payment_count,
        advance_carryover: r.auto_advance_amount,
        advance_source_period: advanceSourcePeriod,
        first_payment_date: r.first_payment_date,
        last_payment_date: r.last_payment_date,
      };
    });
  }

  /**
   * Individual payments for a specific pay_period (month).
   */
  static getSalaryMonthDetail(employeeId: number, payPeriod: string, db: Database.Database): any {
    const employee = db.prepare('SELECT salary FROM employees WHERE id = ?').get(employeeId) as { salary: number } | undefined;
    const salary = employee?.salary ?? 0;

    const payments = db.prepare(
      `SELECT * FROM salary_payments WHERE employee_id = ? AND pay_period = ? ORDER BY payment_date ASC`
    ).all(employeeId, payPeriod);

    const totalPaid = (payments as Array<{ amount: number }>).reduce((sum, p) => sum + p.amount, 0);
    const advanceCarryover = EmployeeModel.getAdvanceCarryover(employeeId, payPeriod, db);

    return {
      pay_period: payPeriod,
      employee_salary: salary,
      total_paid: totalPaid,
      remaining: Math.max(0, salary - totalPaid),
      advance_carryover: advanceCarryover,
      payments,
    };
  }

  /**
   * Sum of advance payments in prior months that haven't been consumed.
   * Logic: sum advance payments for months < payPeriod, minus any partial/
   * full payments in those same months that brought total to salary level.
   */
  static getAdvanceCarryover(employeeId: number, beforePayPeriod: string, db: Database.Database): number {
    const employee = db.prepare('SELECT salary FROM employees WHERE id = ?').get(employeeId) as { salary: number } | undefined;
    const salary = employee?.salary ?? 0;
    if (salary <= 0) return 0;

    // Get all months before the given pay_period that have payments
    const months = db.prepare(`
      SELECT pay_period,
             SUM(CASE WHEN payment_type = 'full' THEN amount ELSE 0 END) AS full_amount,
             SUM(CASE WHEN payment_type IN ('advance', 'partial') THEN amount ELSE 0 END) AS non_full_amount
      FROM salary_payments
      WHERE employee_id = ? AND pay_period < ?
      GROUP BY pay_period
      ORDER BY pay_period
    `).all(employeeId, beforePayPeriod) as Array<{
      pay_period: string;
      full_amount: number;
      non_full_amount: number;
    }>;

    let carryover = 0;
    for (const m of months) {
      const totalForMonth = m.full_amount + m.non_full_amount;
      if (m.full_amount > 0) {
        // Full payment consumes the salary; any excess is carryover
        if (totalForMonth > salary) {
          carryover += totalForMonth - salary;
        }
        // Full payment resets carryover for that month
      } else {
        // Partial/advance only: if under salary, advance carries forward
        if (totalForMonth < salary) {
          // Not fully paid — advance doesn't carry (it's just a partial)
          // Only excess advance carries
        } else if (totalForMonth > salary) {
          carryover += totalForMonth - salary;
        }
        // Exactly salary = no carryover
      }
    }
    return carryover;
  }

  static getSalaryPayment(paymentId: number, db: Database.Database): any | undefined {
    return db.prepare(
      `SELECT * FROM salary_payments WHERE id = ?`
    ).get(paymentId);
  }

  static deleteSalaryPayment(paymentId: number, db: Database.Database): void {
    db.prepare('DELETE FROM salary_payments WHERE id = ?').run(paymentId);
  }

  static addSalaryPayment(data: {
    employee_id: number;
    amount: number;
    payment_date: string;
    payment_method: string;
    reference_no?: string;
    notes?: string;
    journal_entry_id?: number;
    paid_by?: number;
    payment_type?: string;
  }, db: Database.Database): number {
    const payPeriod = data.payment_date.substring(0, 7); // YYYY-MM
    const result = db.prepare(`
      INSERT INTO salary_payments (
        employee_id, amount, payment_date, payment_method,
        reference_no, notes, journal_entry_id, paid_by, pay_period, payment_type
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.employee_id,
      data.amount,
      data.payment_date,
      data.payment_method || 'bank',
      data.reference_no || null,
      data.notes || null,
      data.journal_entry_id || null,
      data.paid_by || null,
      payPeriod,
      data.payment_type || 'full'
    );
    return result.lastInsertRowid as number;
  }
}

export default EmployeeModel;
