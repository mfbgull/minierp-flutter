import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import CustomerModel from '../models/Customer';
import { getRouteParam } from '../utils/queryUtils';
import { sanitizeSortParams, CUSTOMER_SORT_COLUMNS, LEDGER_SORT_COLUMNS } from '../utils/sqlSanitizer';
import logger from '../utils/logger';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';

function getCustomers(req: Request, res: Response): void {
  try {
    const pageParam = getQueryParam(req.query.page);
    const limitParam = getQueryParam(req.query.limit);
    const searchParam = getQueryParam(req.query.search);
    const sortByParam = getQueryParam(req.query.sortBy);
    const sortOrderParam = getQueryParam(req.query.sortOrder);
    const statusParam = getQueryParam(req.query.status);

    const page = Number(pageParam) || 1;
    const limit = Number(limitParam) || 10;
    const search = (searchParam as string) || '';
    const sortBy = (sortByParam as string) || 'customer_name';
    const sortOrder = (sortOrderParam as string) || 'ASC';
    const status = statusParam as string;

    const sortParams = sanitizeSortParams(sortBy, sortOrder, CUSTOMER_SORT_COLUMNS, 'customer_name');
    const { data: customers, total } = CustomerModel.getAll(
      { search, status }, sortParams.column, sortParams.order, page, limit, db
    );

    res.json({
      success: true,
      data: customers,
      pagination: {
        currentPage: page,
        totalPages: Math.ceil(total / limit),
        totalItems: total,
        hasNext: page < Math.ceil(total / limit),
        hasPrev: page > 1
      }
    });
  } catch (error) {
    logger.error('Error fetching customers:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customers' });
  }
}

function getCustomer(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const customer = CustomerModel.getById(id, db);

    if (!customer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    res.json({ success: true, data: customer });
  } catch (error) {
    logger.error('Error fetching customer:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customer' });
  }
}

function createCustomer(req: AuthRequest, res: Response): void {
  try {
    const { customer_name, phone, opening_balance } = req.body;

    if (!customer_name || !phone) {
      res.status(400).json({ success: false, error: 'Customer name and phone are required' });
      return;
    }

    initializeSequenceFromMax(db, 'CUST_last_no', 'customers', 'customer_code', 'CUST');
    const nextCustomerNo = getNextSequenceNumber(db, 'CUST_last_no');
    const newCustomerCode = `CUST${String(nextCustomerNo).padStart(3, '0')}`;

    const customerId = db.transaction(() => {
      const cid = CustomerModel.create({ ...req.body, opening_balance: opening_balance || 0 }, db);
      CustomerModel.updateCode(cid, newCustomerCode, db);

      if (opening_balance && parseFloat(opening_balance) !== 0) {
        CustomerModel.addOpeningBalanceLedger(cid, newCustomerCode, parseFloat(opening_balance), db);
      }

      return cid;
    }).immediate();

    const createdCustomer = CustomerModel.getById(customerId, db);

    logCRUD(ActionType.CUSTOMER_CREATE, 'Customer', customerId, `Created customer: ${customer_name}`, req.user!.id, {
      customer_code: newCustomerCode, customer_name, credit_limit: req.body.credit_limit
    });
    req.activityLogged = true;

    res.status(201).json({ success: true, data: createdCustomer, message: 'Customer created successfully' });
  } catch (error) {
    logger.error('Error creating customer:', error);
    res.status(500).json({ success: false, error: 'Failed to create customer' });
  }
}

function updateCustomer(req: AuthRequest, res: Response): void {
  try {
    const id = getRouteParam(req.params.id);
    const existingCustomer = CustomerModel.getById(id, db);
    if (!existingCustomer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    CustomerModel.update(id, req.body, db);
    const updatedCustomer = CustomerModel.getById(id, db);

    logCRUD(ActionType.CUSTOMER_UPDATE, 'Customer', parseInt(id, 10), `Updated customer: ${req.body.customer_name || existingCustomer.customer_name}`, req.user!.id, {
      changes: Object.keys(req.body).filter(k => req.body[k as keyof typeof req.body] !== undefined)
    });
    req.activityLogged = true;

    res.json({ success: true, data: updatedCustomer, message: 'Customer updated successfully' });
  } catch (error) {
    logger.error('Error updating customer:', error);
    res.status(500).json({ success: false, error: 'Failed to update customer' });
  }
}

function deleteCustomer(req: AuthRequest, res: Response): void {
  try {
    const id = getRouteParam(req.params.id);
    const existingCustomer = CustomerModel.getById(id, db);
    if (!existingCustomer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    const invoiceCount = CustomerModel.countInvoices(id, db);
    const paymentCount = CustomerModel.countPayments(id, db);

    if (invoiceCount > 0 || paymentCount > 0) {
      res.status(400).json({ success: false, error: 'Cannot delete customer with existing transactions' });
      return;
    }

    CustomerModel.deactivate(id, db);

    logCRUD(ActionType.CUSTOMER_DELETE, 'Customer', parseInt(id, 10), `Deactivated customer: ${existingCustomer.customer_name}`, req.user!.id, {
      customer_code: existingCustomer.customer_code
    });
    req.activityLogged = true;

    res.json({ success: true, message: 'Customer deactivated successfully' });
  } catch (error) {
    logger.error('Error deleting customer:', error);
    res.status(500).json({ success: false, error: 'Failed to delete customer' });
  }
}

function getCustomerLedger(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const sortByParam = getQueryParam(req.query.sortBy);
    const sortOrderParam = getQueryParam(req.query.sortOrder);
    const sortBy = (sortByParam as string) || 'transaction_date';
    const sortOrder = (sortOrderParam as string) || 'DESC';

    const sortParams = sanitizeSortParams(sortBy, sortOrder, LEDGER_SORT_COLUMNS as unknown as string[], 'transaction_date', 'DESC');

    const customer = CustomerModel.getById(id, db);
    if (!customer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    const ledgerEntries = CustomerModel.getLedger(id, sortParams.column, sortParams.order, db);
    res.json({ success: true, data: ledgerEntries });
  } catch (error) {
    logger.error('Error fetching customer ledger:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customer ledger' });
  }
}

function getCustomerStatement(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const fromDateParam = getQueryParam(req.query.fromDate);
    const toDateParam = getQueryParam(req.query.toDate);
    const fromDate = fromDateParam as string;
    const toDate = toDateParam as string;

    const customer = CustomerModel.getById(id, db);
    if (!customer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    const { transactions, openingBalance } = CustomerModel.getStatement(id, fromDate, toDate, db);

    let runningBalance = parseFloat(String(openingBalance));
    for (const entry of transactions) {
      runningBalance += parseFloat(String(entry.debit || 0)) - parseFloat(String(entry.credit || 0));
    }
    const closingBalance = runningBalance;

    res.json({
      success: true,
      data: {
        customer: { id: customer.id, customer_name: customer.customer_name },
        period: { fromDate: fromDate || null, toDate: toDate || null },
        openingBalance: parseFloat(String(openingBalance)),
        closingBalance: parseFloat(String(closingBalance)),
        transactions
      }
    });
  } catch (error) {
    logger.error('Error fetching customer statement:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customer statement' });
  }
}

function getCustomerBalance(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const customer = CustomerModel.getBalance(id, db);
    if (!customer) {
      res.status(404).json({ success: false, error: 'Customer not found' });
      return;
    }

    res.json({
      success: true,
      data: {
        customerId: customer.id,
        customerName: customer.customer_name,
        currentBalance: parseFloat(String(customer.current_balance))
      }
    });
  } catch (error) {
    logger.error('Error fetching customer balance:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch customer balance' });
  }
}

function recalculateAllBalances(req: AuthRequest, res: Response): void {
  try {
    const customerIds = CustomerModel.getAllIds(db);
    const recalculateAll = db.transaction(() => {
      for (const id of customerIds) {
        CustomerModel.recalculateBalance(id, db);
      }
    });
    recalculateAll();
    res.json({ success: true, message: `Recalculated balances for ${customerIds.length} customers` });
  } catch (error) {
    logger.error('Error recalculating balances:', error);
    res.status(500).json({ success: false, error: 'Failed to recalculate balances' });
  }
}

export default {
  getCustomers, getCustomer, createCustomer, updateCustomer, deleteCustomer,
  getCustomerLedger, getCustomerStatement, getCustomerBalance, recalculateAllBalances
};
