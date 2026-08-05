-- Add Expenses Table

-- Create expenses table
CREATE TABLE IF NOT EXISTS expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    expense_no VARCHAR(50) UNIQUE NOT NULL,
    expense_category VARCHAR(100) NOT NULL,
    description TEXT,
    amount DECIMAL(15,2) NOT NULL,
    expense_date DATE NOT NULL,
    payment_method VARCHAR(50), -- Cash, Check, Bank Transfer, Card, Credit
    reference_no VARCHAR(100), -- Receipt number, check number, etc.
    vendor_name VARCHAR(200), -- Name of vendor/supplier
    project VARCHAR(100), -- Project or department associated with expense
    status VARCHAR(20) DEFAULT 'Approved', -- Draft, Submitted, Approved, Paid, Cancelled
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Create expense categories table for predefined categories
CREATE TABLE IF NOT EXISTS expense_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert default expense categories
INSERT OR IGNORE INTO expense_categories (category_name, description) VALUES
('Office Supplies', 'Stationery, printing, office materials'),
('Travel', 'Transportation, accommodation, meals during business travel'),
('Utilities', 'Electricity, water, internet, phone bills'),
('Rent', 'Office or warehouse rental expenses'),
('Salaries', 'Employee salaries and wages'),
('Marketing', 'Advertising, promotion, marketing expenses'),
('Maintenance', 'Equipment maintenance, repair costs'),
('Insurance', 'Business insurance premiums'),
('Taxes', 'Tax payments and fees'),
('Professional Services', 'Consulting, legal, accounting fees'),
('Training', 'Employee training and development'),
('Equipment', 'Purchase of equipment and tools'),
('Fuel', 'Fuel expenses for company vehicles'),
('Meals', 'Business meals and entertainment'),
('Other', 'Miscellaneous business expenses');

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(expense_category);
CREATE INDEX IF NOT EXISTS idx_expenses_status ON expenses(status);
CREATE INDEX IF NOT EXISTS idx_expenses_created_by ON expenses(created_by);