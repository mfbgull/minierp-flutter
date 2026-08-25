"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const queryUtils_1 = require("../utils/queryUtils");
const activityLogger_1 = require("../services/activityLogger");
const database_1 = __importDefault(require("../config/database"));
const Supplier_1 = __importDefault(require("../models/Supplier"));
const sqlSanitizer_1 = require("../utils/sqlSanitizer");
const logger_1 = __importDefault(require("../utils/logger"));
const paginate_1 = require("../utils/paginate");
const sequence_1 = require("../utils/sequence");
function getSuppliers(req, res) {
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
        const sortBy = sortByParam || 'supplier_name';
        const sortOrder = sortOrderParam || 'ASC';
        const status = statusParam;
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)(sortBy, sortOrder, sqlSanitizer_1.SUPPLIER_SORT_COLUMNS, 'supplier_name');
        const { data: suppliers, total } = Supplier_1.default.getAll({ search, status }, sortParams.column, sortParams.order, page, limit, database_1.default);
        res.json({
            success: true,
            data: suppliers,
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
        logger_1.default.error('Error fetching suppliers:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch suppliers' });
    }
}
function getSupplier(req, res) {
    try {
        const { id } = req.params;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const supplier = Supplier_1.default.getById(supplierId, database_1.default);
        if (!supplier) {
            res.status(404).json({ success: false, error: 'Supplier not found' });
            return;
        }
        res.json({ success: true, data: supplier });
    }
    catch (error) {
        logger_1.default.error('Error fetching supplier:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch supplier' });
    }
}
function createSupplier(req, res) {
    try {
        const { supplier_code, supplier_name, contact_person, email, phone, address, payment_terms } = req.body;
        if (!supplier_code || !supplier_name) {
            res.status(400).json({
                success: false,
                error: 'Supplier code and name are required'
            });
            return;
        }
        const id = Supplier_1.default.create({
            supplier_code,
            supplier_name,
            contact_person,
            email,
            phone,
            address,
            payment_terms
        }, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SUPPLIER_CREATE, 'Supplier', id, `Created supplier: ${supplier_name} (${supplier_code})`, req.user?.id);
        req.activityLogged = true;
        res.status(201).json({
            success: true,
            data: {
                id,
                supplier_code,
                supplier_name,
                contact_person,
                email,
                phone,
                address,
                payment_terms
            }
        });
    }
    catch (error) {
        logger_1.default.error('Error creating supplier:', error);
        if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
            res.status(400).json({
                success: false,
                error: 'Supplier code already exists'
            });
        }
        else {
            res.status(500).json({
                success: false,
                error: 'Failed to create supplier'
            });
        }
    }
}
function updateSupplier(req, res) {
    try {
        const { id } = req.params;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const { supplier_name, contact_person, email, phone, address, payment_terms, is_active } = req.body;
        const result = Supplier_1.default.update(supplierId, {
            supplier_name,
            contact_person,
            email,
            phone,
            address,
            payment_terms,
            is_active
        }, database_1.default);
        if (result.changes === 0) {
            res.status(404).json({
                success: false,
                error: 'Supplier not found'
            });
            return;
        }
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SUPPLIER_UPDATE, 'Supplier', supplierId, `Updated supplier: ${supplier_name}`, req.user?.id);
        req.activityLogged = true;
        res.json({
            success: true,
            data: {
                id: supplierId,
                supplier_name,
                contact_person,
                email,
                phone,
                address,
                payment_terms,
                is_active: is_active !== undefined ? (is_active ? 1 : 0) : 1
            }
        });
    }
    catch (error) {
        logger_1.default.error('Error updating supplier:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to update supplier'
        });
    }
}
function deleteSupplier(req, res) {
    try {
        const { id } = req.params;
        const deleteId = Array.isArray(id) ? id[0] : id;
        const supplierId = parseInt(deleteId, 10);
        const poCount = Supplier_1.default.countPurchaseOrders(supplierId, database_1.default);
        if (poCount.count > 0) {
            res.status(400).json({
                success: false,
                error: 'Cannot delete supplier with existing purchase orders'
            });
            return;
        }
        const existingSupplier = Supplier_1.default.getById(supplierId, database_1.default);
        Supplier_1.default.delete(supplierId, database_1.default);
        (0, activityLogger_1.logCRUD)(activityLogger_1.ActionType.SUPPLIER_DELETE, 'Supplier', supplierId, `Deleted supplier: ${existingSupplier?.supplier_name || 'Unknown'} (${existingSupplier?.supplier_code || 'N/A'})`, req.user?.id);
        req.activityLogged = true;
        res.json({
            success: true,
            message: 'Supplier deleted successfully'
        });
    }
    catch (error) {
        logger_1.default.error('Error deleting supplier:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to delete supplier'
        });
    }
}
function getSupplierById(req, res) {
    try {
        const { id } = req.params;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const supplier = Supplier_1.default.getById(supplierId, database_1.default);
        if (!supplier) {
            res.status(404).json({ success: false, error: 'Supplier not found' });
            return;
        }
        res.json({ success: true, data: supplier });
    }
    catch {
        res.status(500).json({ success: false, error: 'Failed to fetch supplier' });
    }
}
function getNextSupplierCode(req, res) {
    try {
        (0, sequence_1.initializeSequenceFromMax)(database_1.default, 'SUP_last_no', 'suppliers', 'supplier_code', 'SUP-');
        const nextNumber = (0, sequence_1.getNextSequenceNumber)(database_1.default, 'SUP_last_no');
        const code = `SUP-${String(nextNumber).padStart(3, '0')}`;
        res.json({ success: true, data: { code } });
    }
    catch (error) {
        logger_1.default.error('Error generating supplier code:', error);
        const code = 'SUP-001';
        res.json({ success: true, data: { code } });
    }
}
function getSupplierLedger(req, res) {
    try {
        const { id } = req.params;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const sortByParam = (0, queryUtils_1.getQueryParam)(req.query.sortBy);
        const sortOrderParam = (0, queryUtils_1.getQueryParam)(req.query.sortOrder);
        const sortBy = sortByParam || 'transaction_date';
        const sortOrder = sortOrderParam || 'DESC';
        const sortParams = (0, sqlSanitizer_1.sanitizeSortParams)(sortBy, sortOrder, sqlSanitizer_1.LEDGER_SORT_COLUMNS, 'transaction_date', 'DESC');
        const supplier = Supplier_1.default.getById(supplierId, database_1.default);
        if (!supplier) {
            res.status(404).json({ success: false, error: 'Supplier not found' });
            return;
        }
        // Task 8.7: bounded ledger listing with a pagination envelope.
        const pageParams = (0, paginate_1.parsePageParams)(req);
        const { rows, total } = Supplier_1.default.getLedger(supplierId, sortParams.column, sortParams.order, database_1.default, pageParams.page, pageParams.limit);
        res.json({ success: true, data: rows, pagination: (0, paginate_1.envelope)(total, pageParams) });
    }
    catch (error) {
        logger_1.default.error('Error fetching supplier ledger:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch supplier ledger' });
    }
}
function getSupplierStatement(req, res) {
    try {
        const { id } = req.params;
        const fromDateParam = (0, queryUtils_1.getQueryParam)(req.query.fromDate);
        const toDateParam = (0, queryUtils_1.getQueryParam)(req.query.toDate);
        const fromDate = fromDateParam;
        const toDate = toDateParam;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const supplier = Supplier_1.default.getById(supplierId, database_1.default);
        if (!supplier) {
            res.status(404).json({ success: false, error: 'Supplier not found' });
            return;
        }
        const { transactions, openingBalance } = Supplier_1.default.getStatement(supplierId, fromDate, toDate, database_1.default);
        let runningBalance = parseFloat(String(openingBalance));
        for (const entry of transactions) {
            runningBalance += parseFloat(String(entry.debit || 0)) - parseFloat(String(entry.credit || 0));
        }
        const closingBalance = runningBalance;
        res.json({
            success: true,
            data: {
                supplier: { id: supplier.id, supplier_name: supplier.supplier_name },
                period: { fromDate: fromDate || null, toDate: toDate || null },
                openingBalance: parseFloat(String(openingBalance)),
                closingBalance: parseFloat(String(closingBalance)),
                transactions
            }
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching supplier statement:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch supplier statement' });
    }
}
function getSupplierBalance(req, res) {
    try {
        const { id } = req.params;
        const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
        const balanceData = Supplier_1.default.getBalance(supplierId, database_1.default);
        if (!balanceData) {
            res.status(404).json({ success: false, error: 'Supplier not found' });
            return;
        }
        res.json({
            success: true,
            data: {
                supplierId: balanceData.id,
                supplierName: balanceData.supplier_name,
                currentBalance: parseFloat(String(balanceData.current_balance))
            }
        });
    }
    catch (error) {
        logger_1.default.error('Error fetching supplier balance:', error);
        res.status(500).json({ success: false, error: 'Failed to fetch supplier balance' });
    }
}
function recalculateAllBalances(req, res) {
    try {
        const supplierIds = Supplier_1.default.getAllIds(database_1.default);
        const recalculateAll = database_1.default.transaction(() => {
            for (const id of supplierIds) {
                Supplier_1.default.recalculateBalance(id, database_1.default);
            }
        });
        recalculateAll();
        res.json({ success: true, message: `Recalculated balances for ${supplierIds.length} suppliers` });
    }
    catch (error) {
        logger_1.default.error('Error recalculating balances:', error);
        res.status(500).json({ success: false, error: 'Failed to recalculate balances' });
    }
}
exports.default = {
    getSuppliers, getSupplier, createSupplier, updateSupplier, deleteSupplier,
    getSupplierById, getNextSupplierCode, getSupplierLedger, getSupplierStatement,
    getSupplierBalance, recalculateAllBalances
};
