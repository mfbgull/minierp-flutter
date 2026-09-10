-- Employees table
CREATE TABLE IF NOT EXISTS employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_code VARCHAR(50) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(50),
    mobile VARCHAR(50),
    cnic_no VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'Pakistan',
    date_of_birth DATE,
    gender VARCHAR(10),
    department VARCHAR(100),
    designation VARCHAR(100),
    employment_type VARCHAR(50) DEFAULT 'Full-time',
    date_of_joining DATE,
    date_of_leaving DATE,
    salary DECIMAL(15,2) DEFAULT 0,
    bank_name VARCHAR(100),
    bank_account_no VARCHAR(50),
    bank_iban VARCHAR(50),
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(50),
    profile_photo TEXT,
    notes TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Employee documents table
CREATE TABLE IF NOT EXISTS employee_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL,
    document_name VARCHAR(200) NOT NULL,
    document_type VARCHAR(50),
    document_number VARCHAR(100),
    issue_date DATE,
    expiry_date DATE,
    file_path TEXT,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
);

-- updated_at trigger for employees
CREATE TRIGGER IF NOT EXISTS trg_employees_updated_at
AFTER UPDATE ON employees
FOR EACH ROW
BEGIN
    UPDATE employees SET updated_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;

-- updated_at trigger for employee_documents
CREATE TRIGGER IF NOT EXISTS trg_employee_documents_updated_at
AFTER UPDATE ON employee_documents
FOR EACH ROW
BEGIN
    UPDATE employee_documents SET updated_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_employees_department ON employees(department);
CREATE INDEX IF NOT EXISTS idx_employees_designation ON employees(designation);
CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active);
CREATE INDEX IF NOT EXISTS idx_employee_documents_employee ON employee_documents(employee_id);
