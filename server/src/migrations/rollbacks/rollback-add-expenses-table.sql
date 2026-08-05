-- Rollback: Expenses table
-- Reverts: add-expenses-table.sql

DROP INDEX IF EXISTS idx_expenses_date;
DROP INDEX IF EXISTS idx_expenses_category;
DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS expense_categories;
