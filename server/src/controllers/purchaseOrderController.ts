import { Request, Response } from 'express';
import { getQueryInteger, getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import PurchaseOrderModel from '../models/PurchaseOrder';
import SupplierLedgerModel from '../models/SupplierLedger';
import db from '../config/database';
import logger from '../utils/logger';

function createPurchaseOrder(req: AuthRequest, res: Response): void {
  try {
    const {
      supplier_id,
      po_date,
      items
    } = req.body;

    // Validation
    if (!supplier_id || !po_date) {
      res.status(400).json({
        error: 'Supplier and PO date are required'
      });
      return;
    }

    if (!items || items.length === 0) {
      res.status(400).json({
        error: 'At least one item is required'
      });
      return;
    }

    // Validate items
    for (const item of items) {
      if (!item.item_id || !item.quantity || !item.unit_price) {
        res.status(400).json({
          error: 'Each item must have item_id, quantity, and unit_price'
        });
        return;
      }

      if (item.quantity <= 0) {
        res.status(400).json({
          error: 'Item quantity must be positive'
        });
        return;
      }

      if (item.unit_price <= 0) {
        res.status(400).json({
          error: 'Item unit price must be positive'
        });
        return;
      }
    }

    const po = PurchaseOrderModel.create(req.body, req.user!.id, db);

    res.status(201).json(po);
  } catch (error: any) {
    logger.error('Create PO error:', error);
    res.status(500).json({ error: error.message || 'Failed to create purchase order' });
  }
}

function getPurchaseOrders(req: Request, res: Response): void {
  try {
    const page = getQueryInteger(req.query.page, 1);
    const limit = getQueryInteger(req.query.limit, 10);
    const supplierIdParam = getQueryParam(req.query.supplier_id);
    const statusParam = getQueryParam(req.query.status);
    const search = getQueryParam(req.query.search);
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const sortBy = getQueryParam(req.query.sortBy);
    const sortOrder = getQueryParam(req.query.sortOrder);

    const filters = {
      supplier_id: supplierIdParam ? Number(supplierIdParam) : undefined,
      status: statusParam as string | undefined,
      search: search || undefined,
      start_date: startDateParam as string | undefined,
      end_date: endDateParam as string | undefined,
      sortBy: sortBy || undefined,
      sortOrder: sortOrder || undefined,
      page,
      limit
    };

    const { rows, total, pageNum, limitNum } = PurchaseOrderModel.getAll(filters, db);

    // Flat envelope (data = list, pagination a sibling) — the shape the
    // client's `getPaged` helper parses.
    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: pageNum,
        totalPages: Math.ceil(total / limitNum),
        totalItems: total,
        hasNext: pageNum < Math.ceil(total / limitNum),
        hasPrev: pageNum > 1
      }
    });
  } catch (error) {
    logger.error('Get POs error:', error);
    res.status(500).json({ error: 'Failed to get purchase orders' });
  }
}

function getPurchaseOrder(req: Request, res: Response): void {
  try {
    const po = PurchaseOrderModel.getById(Number(req.params.id), db);

    if (!po) {
      res.status(404).json({ error: 'Purchase order not found' });
      return;
    }

    // Get items
    const items = PurchaseOrderModel.getItems(po.id, db);

    res.json({ ...po, items });
  } catch (error) {
    logger.error('Get PO error:', error);
    res.status(500).json({ error: 'Failed to get purchase order' });
  }
}

function updatePurchaseOrder(req: AuthRequest, res: Response): void {
  try {
    const {
      supplier_id,
      po_date,
      expected_delivery_date,
      notes,
      warehouse_id
    } = req.body;

    const po = PurchaseOrderModel.update(
      Number(req.params.id),
      {
        supplier_id,
        po_date,
        expected_delivery_date,
        notes,
        warehouse_id
      },
      req.user!.id,
      db
    );

    res.json(po);
  } catch (error: any) {
    logger.error('Update PO error:', error);
    res.status(500).json({ error: error.message || 'Failed to update purchase order' });
  }
}

function deletePurchaseOrder(req: AuthRequest, res: Response): void {
  try {
    PurchaseOrderModel.delete(Number(req.params.id), req.user!.id, db);

    res.json({ success: true, message: 'Purchase order deleted successfully' });
  } catch (error: any) {
    logger.error('Delete PO error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete purchase order' });
  }
}

function addLineItem(req: AuthRequest, res: Response): void {
  try {
    const { item_id, quantity, unit_price } = req.body;

    if (!item_id || !quantity || !unit_price) {
      res.status(400).json({
        error: 'Item, quantity, and unit price are required'
      });
      return;
    }

    if (quantity <= 0) {
      res.status(400).json({ error: 'Quantity must be positive' });
      return;
    }

    if (unit_price <= 0) {
      res.status(400).json({ error: 'Unit price must be positive' });
      return;
    }

    const item = PurchaseOrderModel.addItem(
      Number(req.params.id),
      { item_id, quantity, unit_price },
      db
    );

    res.status(201).json(item);
  } catch (error: any) {
    logger.error('Add PO item error:', error);
    res.status(500).json({ error: error.message || 'Failed to add line item' });
  }
}

function updateLineItem(req: Request, res: Response): void {
  try {
    const { quantity, unit_price } = req.body;

    if (!quantity || !unit_price) {
      res.status(400).json({
        error: 'Quantity and unit price are required'
      });
      return;
    }

    if (quantity <= 0) {
      res.status(400).json({ error: 'Quantity must be positive' });
      return;
    }

    if (unit_price <= 0) {
      res.status(400).json({ error: 'Unit price must be positive' });
      return;
    }

    const item = PurchaseOrderModel.updateItem(
      Number(req.params.itemId),
      { quantity, unit_price },
      db
    );

    res.json(item);
  } catch (error: any) {
    logger.error('Update PO item error:', error);
    res.status(500).json({ error: error.message || 'Failed to update line item' });
  }
}

function deleteLineItem(req: Request, res: Response): void {
  try {
    PurchaseOrderModel.removeItem(Number(req.params.itemId), db);

    res.json({ success: true, message: 'Line item deleted successfully' });
  } catch (error: any) {
    logger.error('Delete PO item error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete line item' });
  }
}

function updateStatus(req: AuthRequest, res: Response): void {
  try {
    const { status } = req.body;

    if (!status) {
      res.status(400).json({ error: 'Status is required' });
      return;
    }

    const validStatuses = ['Draft', 'Submitted', 'Partially Received', 'Completed', 'Cancelled'];
    if (!validStatuses.includes(status)) {
      res.status(400).json({ error: `Invalid status. Valid statuses: ${validStatuses.join(', ')}` });
      return;
    }

    const po = PurchaseOrderModel.updateStatus(Number(req.params.id), status, req.user!.id, db);

    res.json(po);
  } catch (error: any) {
    logger.error('Update PO status error:', error);
    res.status(500).json({ error: error.message || 'Failed to update purchase order status' });
  }
}

function getPurchaseOrderPayments(req: Request, res: Response): void {
  try {
    const payments = PurchaseOrderModel.getPayments(Number(req.params.id), db);
    res.json({ success: true, data: payments });
  } catch (error) {
    logger.error('Get PO payments error:', error);
    res.status(500).json({ error: 'Failed to get purchase order payments' });
  }
}

function getGoodsReceipts(req: Request, res: Response): void {
  try {
    const receipts = PurchaseOrderModel.getReceipts(Number(req.params.id), db);

    res.json(receipts);
  } catch (error) {
    logger.error('Get goods receipts error:', error);
    res.status(500).json({ error: 'Failed to get goods receipts' });
  }
}

function createGoodsReceipt(req: AuthRequest, res: Response): void {
  try {
    const {
      receipt_date,
      warehouse_id,
      remarks,
      items
    } = req.body;

    // Validation
    if (!receipt_date || !warehouse_id) {
      res.status(400).json({
        error: 'Receipt date and warehouse are required'
      });
      return;
    }

    if (!items || items.length === 0) {
      res.status(400).json({
        error: 'At least one item must be received'
      });
      return;
    }

    // Validate receipt items
    for (const item of items) {
      if (!item.po_item_id || !item.received_quantity) {
        res.status(400).json({
          error: 'Each receipt item must have po_item_id and received_quantity'
        });
        return;
      }

      if (item.received_quantity <= 0) {
        res.status(400).json({
          error: 'Received quantity must be positive'
        });
        return;
      }
    }

    const receipt = PurchaseOrderModel.addReceipt(
      {
        po_id: Number(req.params.id),
        receipt_date,
        warehouse_id,
        remarks,
        items
      },
      req.user!.id,
      db
    );

    res.status(201).json(receipt);
  } catch (error: any) {
    logger.error('Create goods receipt error:', error);
    res.status(500).json({ error: error.message || 'Failed to create goods receipt' });
  }
}

function getPendingOrders(req: Request, res: Response): void {
  try {
    const pos = PurchaseOrderModel.getPendingOrders(db);

    res.json(pos);
  } catch (error) {
    logger.error('Get pending POs error:', error);
    res.status(500).json({ error: 'Failed to get pending purchase orders' });
  }
}

function getSummaryBySupplier(req: Request, res: Response): void {
  try {
    const { supplierId } = req.params;
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);

    if (!supplierId) {
      res.status(400).json({ error: 'Supplier ID is required' });
      return;
    }

    // Optional inclusive po_date bounds (unified detail date picker) — same
    // param names as the PO list endpoint (start_date/end_date).
    const summary = PurchaseOrderModel.getSummaryBySupplier(Number(supplierId), db, {
      startDate: (startDateParam as string) || undefined,
      endDate: (endDateParam as string) || undefined,
    });

    // Return default object if no purchase orders exist for this supplier
    res.json(summary || {
      total_pos: 0,
      draft_pos: 0,
      submitted_pos: 0,
      partially_received_pos: 0,
      completed_pos: 0,
      total_value: 0
    });
  } catch (error) {
    logger.error('Get PO summary error:', error);
    res.status(500).json({ error: 'Failed to get purchase order summary' });
  }
}

function getSupplierBalance(req: Request, res: Response): void {
  try {
    const { supplierId } = req.params;

    if (!supplierId) {
      res.status(400).json({ error: 'Supplier ID is required' });
      return;
    }

    const balance = SupplierLedgerModel.getBalance(Number(supplierId), db);

    // Ensure balance is always a number (0 if no ledger entries exist)
    res.json({ supplier_id: Number(supplierId), balance: balance || 0 });
  } catch (error) {
    logger.error('Get supplier balance error:', error);
    res.status(500).json({ error: 'Failed to get supplier balance' });
  }
}

function getSupplierTransactions(req: Request, res: Response): void {
  try {
    const { supplierId } = req.params;

    if (!supplierId) {
      res.status(400).json({ error: 'Supplier ID is required' });
      return;
    }

    const transactions = SupplierLedgerModel.getTransactions(Number(supplierId), db);

    res.json(transactions);
  } catch (error) {
    logger.error('Get supplier transactions error:', error);
    res.status(500).json({ error: 'Failed to get supplier transactions' });
  }
}

export default {
  createPurchaseOrder,
  getPurchaseOrders,
  getPurchaseOrder,
  updatePurchaseOrder,
  deletePurchaseOrder,
  addLineItem,
  updateLineItem,
  deleteLineItem,
  updateStatus,
  getPurchaseOrderPayments,
  getGoodsReceipts,
  createGoodsReceipt,
  getPendingOrders,
  getSummaryBySupplier,
  getSupplierBalance,
  getSupplierTransactions
};
