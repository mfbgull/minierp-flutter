import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import { getRouteParam } from '../utils/queryUtils';
import logger from '../utils/logger';
import ExpenseModel from '../models/Expense';

function createExpense(req: AuthRequest, res: Response): void {
  try {
    const { expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project, status } = req.body;
    const userId = req.user!.id;

    if (!expense_category || !amount || !expense_date) {
      res.status(400).json({ success: false, error: 'Expense category, amount, and expense date are required' });
      return;
    }

    const parsedAmount = parseFloat(amount);
    if (isNaN(parsedAmount)) {
      res.status(400).json({ success: false, error: 'Amount must be a valid number' });
      return;
    }

    const expenseNo = ExpenseModel.generateExpenseNo(db, expense_date);
    const expenseId = ExpenseModel.create(db, {
      expense_no: expenseNo, expense_category, description: description || '', amount: parsedAmount,
      expense_date, payment_method, reference_no, vendor_name, project, status: status || 'Approved', created_by: userId,
    });

    logCRUD(ActionType.EXPENSE_CREATE, 'Expense', expenseId, `Created expense: ${expenseNo} - ${expense_category} ($${parsedAmount})`, userId, { expense_no: expenseNo, expense_category, amount: parsedAmount, vendor_name });
    req.activityLogged = true;

    res.status(201).json({
      success: true, message: 'Expense created successfully',
      data: { id: expenseId, expense_no: expenseNo, expense_category, description, amount: parsedAmount, expense_date, payment_method, reference_no, vendor_name, project, status: status || 'Approved', created_by: userId }
    });
  } catch (error) {
    logger.error('Error creating expense:', error);
    res.status(500).json({ success: false, error: 'Failed to create expense' });
  }
}

function getExpenses(req: Request, res: Response): void {
  try {
    const pageParam = getQueryParam(req.query.page);
    const limitParam = getQueryParam(req.query.limit);
    const categoryParam = getQueryParam(req.query.category);
    const statusParam = getQueryParam(req.query.status);
    const vendorParam = getQueryParam(req.query.vendor);
    const fromDateParam = getQueryParam(req.query.from_date);
    const toDateParam = getQueryParam(req.query.to_date);
    const searchParam = getQueryParam(req.query.search);

    const filters = {
      page: parseInt(pageParam as string) || 1,
      limit: parseInt(limitParam as string) || 10,
      category: categoryParam as string,
      status: statusParam as string,
      vendor: vendorParam as string,
      from_date: fromDateParam as string,
      to_date: toDateParam as string,
      search: searchParam as string,
    };

    const expenses = ExpenseModel.getAll(db, filters);
    const totalCount = ExpenseModel.getCount(db, filters);
    const pageNum = filters.page;
    const limitNum = filters.limit;

    res.json({
      success: true, data: expenses,
      pagination: { current_page: pageNum, total_pages: Math.ceil(totalCount / limitNum), total_expenses: totalCount, per_page: limitNum }
    });
  } catch (error) {
    logger.error('Error fetching expenses:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expenses' });
  }
}

function getExpenseById(req: Request, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const expense = ExpenseModel.getById(db, id);
    if (!expense) { res.status(404).json({ success: false, error: 'Expense not found' }); return; }
    res.json({ success: true, data: expense });
  } catch (error) {
    logger.error('Error fetching expense:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expense' });
  }
}

function updateExpense(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const { expense_category, description, amount, expense_date, payment_method, reference_no, vendor_name, project, status } = req.body;

    const existing = ExpenseModel.getById(db, id) as Record<string, unknown> | undefined;
    if (!existing) { res.status(404).json({ success: false, error: 'Expense not found' }); return; }

    ExpenseModel.update(db, id, {
      expense_category, description, amount: amount !== undefined ? parseFloat(amount) : undefined,
      expense_date, payment_method, reference_no, vendor_name, project, status,
    });

    logCRUD(ActionType.EXPENSE_UPDATE, 'Expense', id, `Updated expense: ${existing.expense_no}`, req.user!.id, { expense_no: existing.expense_no, changes: Object.keys(req.body).filter(k => req.body[k] !== undefined) });
    req.activityLogged = true;

    res.json({ success: true, message: 'Expense updated successfully', data: ExpenseModel.getById(db, id) });
  } catch (error) {
    logger.error('Error updating expense:', error);
    res.status(500).json({ success: false, error: 'Failed to update expense' });
  }
}

function deleteExpense(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const existing = ExpenseModel.getById(db, id) as { expense_no: string; amount: number } | undefined;
    if (!existing) { res.status(404).json({ success: false, error: 'Expense not found' }); return; }

    ExpenseModel.delete(db, id);

    logCRUD(ActionType.EXPENSE_DELETE, 'Expense', id, `Deleted expense: ${existing.expense_no}`, req.user!.id, { expense_no: existing.expense_no, amount: existing.amount });
    req.activityLogged = true;

    res.json({ success: true, message: 'Expense deleted successfully' });
  } catch (error) {
    logger.error('Error deleting expense:', error);
    res.status(500).json({ success: false, error: 'Failed to delete expense' });
  }
}

function getExpensesByDateRange(req: Request, res: Response): void {
  try {
    const fromDateParam = getQueryParam(req.query.from_date);
    const toDateParam = getQueryParam(req.query.to_date);
    const from_date = fromDateParam as string;
    const to_date = toDateParam as string;

    if (!from_date || !to_date) { res.status(400).json({ success: false, error: 'from_date and to_date are required' }); return; }

    const result = ExpenseModel.getByDateRange(db, from_date, to_date);
    res.json({ success: true, data: result.expenses, summary: { total_expenses: result.expenses.length, total_amount: result.total_amount } });
  } catch (error) {
    logger.error('Error fetching expenses by date range:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expenses by date range' });
  }
}

function getExpensesByCategory(req: Request, res: Response): void {
  try {
    const { category } = req.params;
    const categoryParam = Array.isArray(category) ? category[0] : category;
    const fromDateParam = getQueryParam(req.query.from_date);
    const toDateParam = getQueryParam(req.query.to_date);

    const result = ExpenseModel.getByCategory(db, categoryParam, fromDateParam as string, toDateParam as string);
    res.json({ success: true, data: result.expenses, summary: { category: categoryParam, total_expenses: result.expenses.length, total_amount: result.total_amount } });
  } catch (error) {
    logger.error('Error fetching expenses by category:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expenses by category' });
  }
}

function getExpenseSummary(req: Request, res: Response): void {
  try {
    const fromDateParam = getQueryParam(req.query.from_date);
    const toDateParam = getQueryParam(req.query.to_date);
    const summary = ExpenseModel.getSummary(db, fromDateParam as string, toDateParam as string);
    res.json({ success: true, data: { category_summary: summary.category_summary, overall_summary: summary.overall_summary } });
  } catch (error) {
    logger.error('Error fetching expense summary:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expense summary' });
  }
}

function getExpenseCategories(req: Request, res: Response): void {
  try {
    const categories = ExpenseModel.getAllCategories(db);
    res.json({ success: true, data: categories });
  } catch (error) {
    logger.error('Error fetching expense categories:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch expense categories' });
  }
}

function createExpenseCategory(req: AuthRequest, res: Response): void {
  try {
    const { category_name, description } = req.body;
    if (!category_name) { res.status(400).json({ success: false, error: 'Category name is required' }); return; }

    const id = ExpenseModel.createCategory(db, { category_name, description });

    logCRUD(ActionType.EXPENSE_CATEGORY_CREATE, 'ExpenseCategory', id, `Created expense category: ${category_name}`, req.user!.id);
    req.activityLogged = true;

    res.status(201).json({ success: true, message: 'Expense category created successfully', data: { id, category_name, description: description || '', is_active: 1 } });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to create expense category';
    if (message.includes('already exists')) { res.status(400).json({ success: false, error: message }); return; }
    logger.error('Error creating expense category:', error);
    res.status(500).json({ success: false, error: 'Failed to create expense category' });
  }
}

function updateExpenseCategory(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const { category_name, description, is_active } = req.body;

    const existing = ExpenseModel.getCategoryById(db, id) as Record<string, unknown> | undefined;
    if (!existing) { res.status(404).json({ success: false, error: 'Expense category not found' }); return; }

    ExpenseModel.updateCategory(db, id, { category_name, description, is_active });

    logCRUD(ActionType.EXPENSE_CATEGORY_UPDATE, 'ExpenseCategory', id, `Updated expense category: ${existing.category_name}`, req.user!.id);
    req.activityLogged = true;

    res.json({ success: true, message: 'Expense category updated successfully', data: ExpenseModel.getCategoryById(db, id) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to update expense category';
    if (message.includes('not found')) { res.status(404).json({ success: false, error: message }); return; }
    if (message.includes('already exists')) { res.status(400).json({ success: false, error: message }); return; }
    logger.error('Error updating expense category:', error);
    res.status(500).json({ success: false, error: 'Failed to update expense category' });
  }
}

function deleteExpenseCategory(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const existing = ExpenseModel.getCategoryById(db, id) as { category_name: string } | undefined;
    if (!existing) { res.status(404).json({ success: false, error: 'Expense category not found' }); return; }

    ExpenseModel.deleteCategory(db, id);

    logCRUD(ActionType.EXPENSE_CATEGORY_DELETE, 'ExpenseCategory', id, `Deleted expense category: ${existing.category_name}`, req.user!.id);
    req.activityLogged = true;

    res.json({ success: true, message: 'Expense category deleted successfully' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to delete expense category';
    if (message.includes('not found') || message.includes('being used')) { res.status(400).json({ success: false, error: message }); return; }
    logger.error('Error deleting expense category:', error);
    res.status(500).json({ success: false, error: 'Failed to delete expense category' });
  }
}

function getExpenseStatusOptions(req: Request, res: Response): void {
  res.json({ success: true, data: ExpenseModel.getStatusOptions() });
}

function getExpensePaymentMethodOptions(req: Request, res: Response): void {
  res.json({ success: true, data: ExpenseModel.getPaymentMethodOptions() });
}

export default {
  createExpense, getExpenses, getExpenseById, updateExpense, deleteExpense,
  getExpensesByDateRange, getExpensesByCategory, getExpenseSummary,
  getExpenseCategories, createExpenseCategory, updateExpenseCategory, deleteExpenseCategory,
  getExpenseStatusOptions, getExpensePaymentMethodOptions,
};
