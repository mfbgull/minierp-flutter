"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const Customer_1 = __importDefault(require("../models/Customer"));
const queryUtils_2 = require("../utils/queryUtils");
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const logger_1 = __importDefault(require("../utils/logger"));
const paginate_1 = require("../utils/paginate");
const sequence_1 = require("../utils/sequence");
function getCustomers(req, res) {
    try {
        const pageParam = (0, queryUtils_1.getQueryParam)(req.query.page);
        const limitParam = (0, queryUtils_1.getQueryParam)(req.query.limit);
        const searchParam = (0, queryUtils_1.getQueryParam)(req.query.search);
        const sortByParam = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrderParam = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const statusParam = (0, queryUtils_1.getQueryParam)(req.query.status);
        const page = Number(pageParam) || 1;
        const limit = Number(limitParam) || 10;
        const search = searchParam || '';
        const sortBy = sortByParam || 'customer_name';
        const sortOrder = sortOrderParam || 'ASC';
        const status = statusParam;
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)(sortBy, sortOrder, sqlSanitizer_1.CUSTOMER_SORT_COLUMNS, 'customer_name');
        const { data: customers, total } = Customer_1.default.getAll({ search, status }, sortParams.column, sortParams.order, page, limit, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Error fetching customers:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customers' });
    }
}
function getCustomer(req, res) {
    try {
        const { id } = req.params;
        const customer = Customer_1.default.getById(id, database_1.default);
        if (!customer) {
            res.status(404).json({ success: false, error: 'Customer not found' });
            return;
        }
        res.json({ success: true, data: customer });
    }
    catch (error) {
        logger_1.default.error('Error fetching customer:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customer' });
    }
}
function createCustomer(req, res) {
    try {
        const { customer_name, phone, opening_balance } = req.body;
        if (!customer_name || !phone) {
            res.status(400).json({ success: false, error: 'Customer name and phone are required' });
            return;
        }
        (0, sequence_1.initializeSequenceFromMax)(database_1.default, 'CUST_last_no', 'customers', 'customer_code', 'CUST');
        const nextCustomerNo = (0, sequence_1.getNextSequenceNumber)(database_1.default, 'CUST_last_no');
        const newCustomerCode = `CUST${String(nextCustomerNo).padStart(3, '0')}`;
        const customerId = database_1.default.transaction(() => {
            const cid = Customer_1.default.create({ ...req.body, opening_balance: opening_balance || 0 }, database_1.default);
            Customer_1.default.updateCode(cid, newCustomerCode, database_1.default);
            if (opening_balance && parseFloat(opening_balance) !== 0) {
                Customer_1.default.addOpeningBalanceLedger(cid, newCustomerCode, parseFloat(opening_balance), database_1.default);
            }
            return cid;
        }).immediate();
        const createdCustomer = Customer_1.default.getById(customerId, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.CUSTOMER_CREATE, 'Customer', customerId, `Created customer: ${customer_name}`, req.user.id, {
            customer_code: newCustomerCode, customer_name, credit_limit: req.body.credit_limit
        });
        req.activityLogged = true;
        res.status(201).json({ success: true, data: createdCustomer, message: 'Customer created successfully' });
    }
    catch (error) {
        logger_1.default.error('Error creating customer:', error);
        res.status(500).json({ success: false, error: 'Failed to create customer' });
    }
}
function updateCustomer(req, res) {
    try {
        const id = (0, queryUtils_2.getRouteParam)(req.params.id);
        const existingCustomer = Customer_1.default.getById(id, database_1.default);
        if (!existingCustomer) {
            res.status(404).json({ success: false, error: 'Customer not found' });
            return;
        }
        Customer_1.default.update(id, req.body, database_1.default);
        const updatedCustomer = Customer_1.default.getById(id, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.CUSTOMER_UPDATE, 'Customer', parseInt(id, 10), `Updated customer: ${req.body.customer_name || existingCustomer.customer_name}`, req.user.id, {
            changes: Object.keys(req.body).filter(k => req.body[k] !== undefined)
        });
        req.activityLogged = true;
        res.json({ success: true, data: updatedCustomer, message: 'Customer updated successfully' });
    }
    catch (error) {
        logger_1.default.error('Error updating customer:', error);
        res.status(500).json({ success: false, error: 'Failed to update customer' });
    }
}
function deleteCustomer(req, res) {
    try {
        const id = (0, queryUtils_2.getRouteParam)(req.params.id);
        const existingCustomer = Customer_1.default.getById(id, database_1.default);
        if (!existingCustomer) {
            res.status(404).json({ success: false, error: 'Customer not found' });
            return;
        }
        const invoiceCount = Customer_1.default.countInvoices(id, database_1.default);
        const paymentCount = Customer_1.default.countPayments(id, database_1.default);
        if (invoiceCount > 0 || paymentCount > 0) {
            res.status(400).json({ success: false, error: 'Cannot delete customer with existing transactions' });
            return;
        }
        Customer_1.default.deactivate(id, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.CUSTOMER_DELETE, 'Customer', parseInt(id, 10), `Deactivated customer: ${existingCustomer.customer_name}`, req.user.id, {
            customer_code: existingCustomer.customer_code
        });
        req.activityLogged = true;
        res.json({ success: true, message: 'Customer deactivated successfully' });
    }
    catch (error) {
        logger_1.default.error('Error deleting customer:', error);
        res.status(500).json({ success: false, error: 'Failed to delete customer' });
    }
}
function getCustomerLedger(req, res) {
    try {
        const { id } = req.params;
        const sortByParam = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrderParam = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const sortBy = sortByParam || 'transaction_date';
        const sortOrder = sortOrderParam || 'DESC';
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)(sortBy, sortOrder, sqlSanitizer_1.LEDGER_SORT_COLUMNS, 'transaction_date', 'DESC');
        const customer = Customer_1.default.getById(id, database_1.default);
        if (!customer) {
            res.status(404).json({ success: false, error: 'Customer not found' });
            return;
        }
        // Task 8.7: bounded ledger listing with a pagination envelope.
        const pageParams = (0, paginate_1.parsePageParams)(req);
        const { rows, total } = Customer_1.default.getLedger(id, sortParams.column, sortParams.order, database_1.default, pageParams.page, pageParams.limit);
        res.json({ success: true, data: rows, pagination: (0, paginate_1.envelope)(total, pageParams) });
    }
    catch (error) {
        logger_1.default.error('Error fetching customer ledger:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customer ledger' });
    }
}
function getCustomerStatement(req, res) {
    try {
        const { id } = req.params;
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.fromDate);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.toDate);
        const fromDate = fromDateParam;
        const toDate = toDateParam;
        const customer = Customer_1.default.getById(id, database_1.default);
        if (!customer) {
            res.status(404).json({ success: false, error: 'Customer not found' });
            return;
        }
        const { transactions, openingBalance } = Customer_1.default.getStatement(id, fromDate, toDate, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Error fetching customer statement:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customer statement' });
    }
}
function getCustomerBalance(req, res) {
    try {
        const { id } = req.params;
        const customer = Customer_1.default.getBalance(id, database_1.default);
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
    }
    catch (error) {
        logger_1.default.error('Error fetching customer balance:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch customer balance' });
    }
}
function recalculateAllBalances(req, res) {
    try {
        const customerIds = Customer_1.default.getAllIds(database_1.default);
        const recalculateAll = database_1.default.transaction(() => {
            for (const id of customerIds) {
                Customer_1.default.recalculateBalance(id, database_1.default);
            }
        });
        recalculateAll();
        res.json({ success: true, message: `Recalculated balances for ${customerIds.length} customers` });
    }
    catch (error) {
        logger_1.default.error('Error recalculating balances:', error);
        res.status(500).json({ success: false, error: 'Failed to recalculate balances' });
    }
}
exports.default = {
    getCustomers, getCustomer, createCustomer, updateCustomer, deleteCustomer,
    getCustomerLedger, getCustomerStatement, getCustomerBalance, recalculateAllBalances
};
