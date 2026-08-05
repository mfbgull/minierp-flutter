import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import Purchase from '../models/Purchase';
import AccountingService from '../services/accountingService';
import db from '../config/database';
import logger from '../utils/logger';

function recordPurchase(req: AuthRequest, res: Response): void {
  try {
    const {
      item_id,
      warehouse_id,
      quantity,
      unit_cost,
      purchase_date,
    } = req.body;

    if (!item_id || !warehouse_id || !quantity || !unit_cost || !purchase_date) {
      res.status(400).json({
        error: 'Item, warehouse, quantity, unit cost, and purchase date are required'
      });
      return;
    }

    if (quantity <= 0) {
      res.status(400).json({ error: 'Quantity must be positive' });
      return;
    }

    if (unit_cost < 0) {
      res.status(400).json({ error: 'Unit cost cannot be negative' });
      return;
    }

    const purchase = Purchase.recordPurchase(req.body, req.user!.id, db);

    res.status(201).json(purchase);
  } catch (error: any) {
    logger.error('Record purchase error:', error);
    res.status(500).json({ error: error.message || 'Failed to record purchase' });
  }
}

function getPurchases(req: Request, res: Response): void {
  try {
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const itemIdParam = getQueryParam(req.query.item_id);
    const warehouseIdParam = getQueryParam(req.query.warehouse_id);
    const supplierNameParam = getQueryParam(req.query.supplier_name);
    const limitParam = getQueryParam(req.query.limit);

    const filters = {
      start_date: startDateParam as string | undefined,
      end_date: endDateParam as string | undefined,
      item_id: itemIdParam ? Number(itemIdParam) : undefined,
      warehouse_id: warehouseIdParam ? Number(warehouseIdParam) : undefined,
      supplier_name: supplierNameParam as string | undefined,
      limit: limitParam ? parseInt(String(limitParam)) : undefined
    };

    const purchases = Purchase.getAll(filters, db);

    res.json(purchases);
  } catch (error) {
    logger.error('Get purchases error:', error);
    res.status(500).json({ error: 'Failed to get purchases' });
  }
}

function getPurchase(req: Request, res: Response): void {
  try {
    const purchase = Purchase.getById(Number(req.params.id), db);

    if (!purchase) {
      res.status(404).json({ error: 'Purchase not found' });
      return;
    }

    res.json(purchase);
  } catch (error) {
    logger.error('Get purchase error:', error);
    res.status(500).json({ error: 'Failed to get purchase' });
  }
}

function getPurchaseSummaryByItem(req: Request, res: Response): void {
  try {
    const { item_id } = req.params;

    if (!item_id) {
      res.status(400).json({ error: 'Item ID is required' });
      return;
    }

    const summary = Purchase.getSummaryByItem(Number(item_id), db);

    res.json(summary);
  } catch (error) {
    logger.error('Get purchase summary error:', error);
    res.status(500).json({ error: 'Failed to get purchase summary' });
  }
}

function getPurchaseSummaryByDateRange(req: Request, res: Response): void {
  try {
    const { start_date, end_date } = req.query;

    if (!start_date || !end_date) {
      res.status(400).json({ error: 'Start date and end date are required' });
      return;
    }

    const summary = Purchase.getSummaryByDateRange(start_date as string, end_date as string, db);

    res.json(summary);
  } catch (error) {
    logger.error('Get purchase summary error:', error);
    res.status(500).json({ error: 'Failed to get purchase summary' });
  }
}

function getReturnHistory(req: Request, res: Response): void {
  try {
    const startDateParam = getQueryParam(req.query.start_date);
    const endDateParam = getQueryParam(req.query.end_date);
    const itemIdParam = getQueryParam(req.query.item_id);
    const limitParam = getQueryParam(req.query.limit);

    const filters = {
      start_date: startDateParam as string | undefined,
      end_date: endDateParam as string | undefined,
      item_id: itemIdParam ? Number(itemIdParam) : undefined,
      limit: limitParam ? parseInt(String(limitParam)) : undefined
    };

    const returns = Purchase.getReturnHistory(filters, db);
    res.json(returns);
  } catch (error) {
    logger.error('Get purchase return history error:', error);
    res.status(500).json({ error: 'Failed to get purchase return history' });
  }
}

function getTopSuppliers(req: Request, res: Response): void {
  try {
    const limitParam = getQueryParam(req.query.limit);
    const limit = limitParam ? parseInt(String(limitParam)) : 10;
    const suppliers = Purchase.getTopSuppliers(limit, db);

    res.json(suppliers);
  } catch (error) {
    logger.error('Get top suppliers error:', error);
    res.status(500).json({ error: 'Failed to get top suppliers' });
  }
}

function deletePurchase(req: AuthRequest, res: Response): void {
  try {
    Purchase.delete(Number(req.params.id), req.user!.id, db);

    res.json({ success: true, message: 'Purchase deleted successfully' });
  } catch (error: any) {
    logger.error('Delete purchase error:', error);
    res.status(500).json({ error: error.message || 'Failed to delete purchase' });
  }
}

function returnPurchaseItems(req: AuthRequest, res: Response): Response | void {
  try {
    const { id } = req.params;
    const purchaseId = parseInt(id as string, 10);
    const userId = req.user!.id;

    const { quantity, reason } = req.body as {
      quantity: number;
      reason?: string;
    };

    if (!quantity || quantity <= 0) {
      return res.status(400).json({ error: 'A positive return quantity is required' });
    }

    // Wrap everything in a transaction so GL posting is atomic with stock return
    let result: { returnedQuantity: number; totalCost: number };

    db.transaction(() => {
      // Fetch purchase first to get its number for the GL entry
      const purchase = Purchase.getById(purchaseId, db);
      if (!purchase) throw new Error('Purchase not found');

      // Return stock and get the cost for GL posting
      result = Purchase.returnPurchaseItems(db, purchaseId, quantity, userId, reason);

      // Post GL reversal — Dr AP, Cr Inventory
      AccountingService.postPurchaseReturnEntry(db, {
        purchaseId,
        purchaseNo: purchase.purchase_no,
        returnAmount: result.totalCost,
        returnDate: new Date().toISOString().split('T')[0],
        userId,
      });
    })();

    res.json({ success: true, message: 'Return processed successfully', data: result! });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('Return purchase items error:', { error: errorMessage });
    res.status(400).json({ error: errorMessage });
  }
}

export default {
  recordPurchase,
  getPurchases,
  getPurchase,
  getPurchaseSummaryByItem,
  getPurchaseSummaryByDateRange,
  getTopSuppliers,
  getReturnHistory,
  deletePurchase,
  returnPurchaseItems,
};
