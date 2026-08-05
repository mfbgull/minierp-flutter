import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import SupplierModel from '../models/Supplier';
import { getRouteParam } from '../utils/queryUtils';
import { sanitizeSortParams, SUPPLIER_SORT_COLUMNS, LEDGER_SORT_COLUMNS } from '../utils/sqlSanitizer';
import logger from '../utils/logger';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';

function getSuppliers(req: Request, res: Response): void {
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
    const sortBy = (sortByParam as string) || 'supplier_name';
    const sortOrder = (sortOrderParam as string) || 'ASC';
    const status = statusParam as string;

    const sortParams = sanitizeSortParams(sortBy, sortOrder, SUPPLIER_SORT_COLUMNS, 'supplier_name');
    const { data: suppliers, total } = SupplierModel.getAll(
      { search, status }, sortParams.column, sortParams.order, page, limit, db
    );

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
  } catch (error) {
    logger.error('Error fetching suppliers:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch suppliers' });
  }
}

function getSupplier(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const supplier = SupplierModel.getById(supplierId, db);

    if (!supplier) {
      res.status(404).json({ success: false, error: 'Supplier not found' });
      return;
    }

    res.json({ success: true, data: supplier });
  } catch (error) {
    logger.error('Error fetching supplier:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch supplier' });
  }
}

function createSupplier(req: Request, res: Response): void {
  try {
    const {
      supplier_code,
      supplier_name,
      contact_person,
      email,
      phone,
      address,
      payment_terms
    } = req.body;

    if (!supplier_code || !supplier_name) {
      res.status(400).json({
        success: false,
        error: 'Supplier code and name are required'
      });
      return;
    }

    const id = SupplierModel.create({
      supplier_code,
      supplier_name,
      contact_person,
      email,
      phone,
      address,
      payment_terms
    }, db);

    logCRUD(ActionType.SUPPLIER_CREATE, 'Supplier', id, `Created supplier: ${supplier_name} (${supplier_code})`, (req as AuthRequest).user?.id);
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
  } catch (error: any) {
    logger.error('Error creating supplier:', error);
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      res.status(400).json({
        success: false,
        error: 'Supplier code already exists'
      });
    } else {
      res.status(500).json({
        success: false,
        error: 'Failed to create supplier'
      });
    }
  }
}

function updateSupplier(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const {
      supplier_name,
      contact_person,
      email,
      phone,
      address,
      payment_terms,
      is_active
    } = req.body;

    const result = SupplierModel.update(supplierId, {
      supplier_name,
      contact_person,
      email,
      phone,
      address,
      payment_terms,
      is_active
    }, db);

    if (result.changes === 0) {
      res.status(404).json({
        success: false,
        error: 'Supplier not found'
      });
      return;
    }

    logCRUD(ActionType.SUPPLIER_UPDATE, 'Supplier', supplierId, `Updated supplier: ${supplier_name}`, (req as AuthRequest).user?.id);
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
  } catch (error) {
    logger.error('Error updating supplier:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update supplier'
    });
  }
}

function deleteSupplier(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const deleteId = Array.isArray(id) ? id[0] : id;
    const supplierId = parseInt(deleteId, 10);

    const poCount = SupplierModel.countPurchaseOrders(supplierId, db);

    if (poCount.count > 0) {
      res.status(400).json({
        success: false,
        error: 'Cannot delete supplier with existing purchase orders'
      });
      return;
    }

    const existingSupplier = SupplierModel.getById(supplierId, db);

    SupplierModel.delete(supplierId, db);

    logCRUD(ActionType.SUPPLIER_DELETE, 'Supplier', supplierId, `Deleted supplier: ${existingSupplier?.supplier_name || 'Unknown'} (${existingSupplier?.supplier_code || 'N/A'})`, (req as AuthRequest).user?.id);
    req.activityLogged = true;

    res.json({
      success: true,
      message: 'Supplier deleted successfully'
    });
  } catch (error) {
    logger.error('Error deleting supplier:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete supplier'
    });
  }
}

function getSupplierById(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const supplier = SupplierModel.getById(supplierId, db);
    if (!supplier) {
      res.status(404).json({ success: false, error: 'Supplier not found' });
      return;
    }
    res.json({ success: true, data: supplier });
  } catch {
    res.status(500).json({ success: false, error: 'Failed to fetch supplier' });
  }
}

function getNextSupplierCode(req: Request, res: Response): void {
  try {
    initializeSequenceFromMax(db, 'SUP_last_no', 'suppliers', 'supplier_code', 'SUP-');
    const nextNumber = getNextSequenceNumber(db, 'SUP_last_no');
    const code = `SUP-${String(nextNumber).padStart(3, '0')}`;
    res.json({ success: true, data: { code } });
  } catch (error) {
    logger.error('Error generating supplier code:', error);
    const code = 'SUP-001';
    res.json({ success: true, data: { code } });
  }
}

function getSupplierLedger(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const sortByParam = getQueryParam(req.query.sortBy);
    const sortOrderParam = getQueryParam(req.query.sortOrder);
    const sortBy = (sortByParam as string) || 'transaction_date';
    const sortOrder = (sortOrderParam as string) || 'DESC';

    const sortParams = sanitizeSortParams(sortBy, sortOrder, LEDGER_SORT_COLUMNS as unknown as string[], 'transaction_date', 'DESC');

    const supplier = SupplierModel.getById(supplierId, db);
    if (!supplier) {
      res.status(404).json({ success: false, error: 'Supplier not found' });
      return;
    }

    const ledgerEntries = SupplierModel.getLedger(supplierId, sortParams.column, sortParams.order, db);
    res.json({ success: true, data: ledgerEntries });
  } catch (error) {
    logger.error('Error fetching supplier ledger:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch supplier ledger' });
  }
}

function getSupplierStatement(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const fromDateParam = getQueryParam(req.query.fromDate);
    const toDateParam = getQueryParam(req.query.toDate);
    const fromDate = fromDateParam as string;
    const toDate = toDateParam as string;

    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const supplier = SupplierModel.getById(supplierId, db);
    if (!supplier) {
      res.status(404).json({ success: false, error: 'Supplier not found' });
      return;
    }

    const { transactions, openingBalance } = SupplierModel.getStatement(supplierId, fromDate, toDate, db);

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
  } catch (error) {
    logger.error('Error fetching supplier statement:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch supplier statement' });
  }
}

function getSupplierBalance(req: Request, res: Response): void {
  try {
    const { id } = req.params;
    const supplierId = parseInt(Array.isArray(id) ? id[0] : id, 10);
    const balanceData = SupplierModel.getBalance(supplierId, db);
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
  } catch (error) {
    logger.error('Error fetching supplier balance:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch supplier balance' });
  }
}

function recalculateAllBalances(req: AuthRequest, res: Response): void {
  try {
    const supplierIds = SupplierModel.getAllIds(db);
    const recalculateAll = db.transaction(() => {
      for (const id of supplierIds) {
        SupplierModel.recalculateBalance(id, db);
      }
    });
    recalculateAll();
    res.json({ success: true, message: `Recalculated balances for ${supplierIds.length} suppliers` });
  } catch (error) {
    logger.error('Error recalculating balances:', error);
    res.status(500).json({ success: false, error: 'Failed to recalculate balances' });
  }
}

export default {
  getSuppliers, getSupplier, createSupplier, updateSupplier, deleteSupplier,
  getSupplierById, getNextSupplierCode, getSupplierLedger, getSupplierStatement,
  getSupplierBalance, recalculateAllBalances
};
