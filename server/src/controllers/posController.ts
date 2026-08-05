import { Request, Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import { getNextSequenceNumber } from '../utils/sequence';
import InvoiceModel from '../models/Invoice';
import StockMovementModel from '../models/StockMovement';
import WarehouseModel from '../models/Warehouse';

function generatePOSTransactionNo(): string {
  const year = new Date().getFullYear();
  const settingKey = `POS_last_no_${year}`;
  const nextNo = getNextSequenceNumber(db, settingKey);
  return `POS-${year}-${nextNo.toString().padStart(6, '0')}`;
}

/**
 * Find or create the "Walk-in Customer" record for POS transactions.
 */
function ensureWalkinCustomer(): number {
  const existing = db.prepare(`
    SELECT id FROM customers WHERE customer_code = 'WALK-IN' LIMIT 1
  `).get() as { id: number } | undefined;

  if (existing) return existing.id;

  const result = db.prepare(`
    INSERT INTO customers (customer_code, customer_name, is_active)
    VALUES ('WALK-IN', 'Walk-in Customer', 1)
  `).run();

  const walkinId = result.lastInsertRowid as number;
  logger.info(`Created Walk-in Customer with id=${walkinId}`);
  return walkinId;
}

function createPOSSale(req: AuthRequest, res: Response): void {
  try {
    const { warehouse_id, sale_date, items, cash_received, customer_name } = req.body;
    const userId = req.user!.id;

    if (!warehouse_id) {
      res.status(400).json({ error: 'Warehouse is required' });
      return;
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: 'At least one item is required' });
      return;
    }

    if (!sale_date) {
      res.status(400).json({ error: 'Sale date is required' });
      return;
    }

    const warehouse = WarehouseModel.getById(db, warehouse_id);
    if (!warehouse) {
      res.status(400).json({ error: 'Warehouse not found' });
      return;
    }

    let total = 0;
    for (const item of items) {
      if (!item.item_id || !item.quantity || item.quantity <= 0) {
        res.status(400).json({ error: 'Each item must have item_id and quantity > 0' });
        return;
      }
      if (item.unit_price === undefined || item.unit_price < 0) {
        res.status(400).json({ error: 'Each item must have a valid unit_price' });
        return;
      }
      total += item.quantity * item.unit_price;
    }

    const cashAmount = parseFloat(cash_received) || total;
    if (cashAmount < total) {
      res.status(400).json({
        error: `Insufficient cash. Total: ${total.toFixed(2)}, Received: ${cashAmount.toFixed(2)}`
      });
      return;
    }

    const customerName = customer_name || 'Walk-in Customer';

    // Stock validation — check all items have sufficient stock before proceeding
    for (const item of items) {
      const stockBalance = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?').get(item.item_id, warehouse_id) as { quantity: number } | undefined;
      const availableStock = stockBalance ? Number(stockBalance.quantity) : 0;
      if (availableStock < item.quantity) {
        const itemRecord = db.prepare('SELECT item_name FROM items WHERE id = ?').get(item.item_id) as { item_name: string } | undefined;
        res.status(400).json({
          error: `Insufficient stock for ${itemRecord?.item_name || 'item ' + item.item_id}. Available: ${availableStock}, Required: ${item.quantity}`
        });
        return;
      }
    }

    // === Create invoice inside a transaction ===
    const transaction = db.transaction(() => {
      const walkinCustomerId = ensureWalkinCustomer();
      const transactionNo = generatePOSTransactionNo();

      // Create the invoice with status='Paid' since POS collects payment immediately
      const invoiceResult = db.prepare(`
        INSERT INTO invoices (
          invoice_no, customer_id, customer_name, invoice_date, due_date, status,
          total_amount, paid_amount, balance_amount, notes, created_by,
          source_type
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        transactionNo,
        walkinCustomerId,
        customerName,
        sale_date,
        sale_date, // due_date = sale_date (immediate payment)
        'Paid',
        total,
        cashAmount,
        Math.max(0, total - cashAmount),
        `POS Transaction: ${transactionNo}`,
        userId,
        'POS'
      );

      const invoiceId = invoiceResult.lastInsertRowid as number;

      // Create invoice_items and stock movements for each cart item
      const itemDetails: Array<{
        sale_id: number;
        sale_no: string;
        item_id: number;
        item_code: string;
        item_name: string;
        unit_of_measure: string;
        quantity: number;
        unit_price: number;
        line_total: number;
      }> = [];

      for (const item of items) {
        const itemRecord = db.prepare('SELECT id, item_code, item_name, unit_of_measure FROM items WHERE id = ?').get(item.item_id) as {
          id: number; item_code: string; item_name: string; unit_of_measure: string;
        } | undefined;

        if (!itemRecord) {
          throw new Error(`Item with ID ${item.item_id} not found`);
        }

        const lineTotal = item.quantity * item.unit_price;

        // Create invoice item
        InvoiceModel.createInvoiceItem(db, invoiceId, {
          item_id: item.item_id,
          quantity: item.quantity,
          unit_price: item.unit_price,
        });

        // Deduct stock
        StockMovementModel.recordMovement({
          item_id: item.item_id,
          warehouse_id: warehouse_id,
          quantity: -item.quantity,
          movement_type: 'SALE',
          unit_cost: item.unit_price,
          reference_doctype: 'POS',
          reference_docno: transactionNo,
          movement_date: sale_date,
          remarks: `POS Sale: ${transactionNo} - ${itemRecord.item_name}`
        }, userId, db);

        itemDetails.push({
          sale_id: invoiceId,
          sale_no: transactionNo,
          item_id: item.item_id,
          item_code: itemRecord.item_code,
          item_name: itemRecord.item_name,
          unit_of_measure: itemRecord.unit_of_measure,
          quantity: item.quantity,
          unit_price: item.unit_price,
          line_total: lineTotal
        });
      }

      // Record payment
      if (cashAmount > 0) {
        const paymentNo = InvoiceModel.generatePaymentNoAtomic(db);
        const paymentId = InvoiceModel.createPayment(db, paymentNo, walkinCustomerId, sale_date, cashAmount, 'Cash', null, `POS Transaction ${transactionNo}`);
        InvoiceModel.createPaymentAllocation(db, paymentId, invoiceId, cashAmount);
        // Create ledger entry for payment
        InvoiceModel.createLedgerEntry(db, walkinCustomerId, 'PAYMENT', paymentNo, 0, cashAmount, `Payment ${paymentNo} for POS ${transactionNo}`);
      }

      // Create ledger entry for the sale
      InvoiceModel.createLedgerEntry(db, walkinCustomerId, 'INVOICE', transactionNo, total, 0, `POS Sale ${transactionNo}`);

      // Activity log
      db.prepare('INSERT INTO activity_log (user_id, action, entity_type, entity_id, description) VALUES (?, ?, ?, ?, ?)').run(
        userId, 'CREATE', 'POS', invoiceId, `POS Transaction ${transactionNo}: ${items.length} items`
      );

      return {
        transaction_no: transactionNo,
        sale_date,
        warehouse_id,
        warehouse_name: warehouse.warehouse_name,
        customer_name: customerName,
        items: itemDetails,
        subtotal: total,
        total,
        cash_received: cashAmount,
        change: cashAmount - total,
        items_count: items.length,
        sale_ids: [invoiceId]
      };
    });

    const result = transaction();

    res.status(201).json({
      success: true,
      message: 'POS sale completed successfully',
      data: result
    });

  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to process POS sale';
    logger.error('POS Sale Error:', error);
    res.status(500).json({ error: message });
  }
}

function getPOSTransactions(req: Request, res: Response): void {
  try {
    const startDate = req.query.start_date as string | undefined;
    const endDate = req.query.end_date as string | undefined;
    const limitParam = parseInt(req.query.limit as string) || 50;

    let query = `
      SELECT
        i.invoice_no as transaction_no,
        i.invoice_date as sale_date,
        COALESCE(i.customer_name, c.customer_name) as customer_name,
        w.warehouse_name,
        COUNT(ii.id) as items_count,
        i.total_amount as total,
        i.paid_amount,
        i.balance_amount
      FROM invoices i
      JOIN customers c ON i.customer_id = c.id
      JOIN invoice_items ii ON ii.invoice_id = i.id
      LEFT JOIN (
        SELECT reference_docno, w2.warehouse_name
        FROM stock_movements sm
        JOIN warehouses w2 ON sm.warehouse_id = w2.id
        WHERE sm.reference_doctype = 'POS'
        GROUP BY sm.reference_docno, w2.warehouse_name
      ) w ON w.reference_docno = i.invoice_no
      WHERE i.source_type = 'POS'
    `;

    const params: (string | number)[] = [];

    if (startDate) {
      query += ' AND i.invoice_date >= ?';
      params.push(startDate);
    }
    if (endDate) {
      query += ' AND i.invoice_date <= ?';
      params.push(endDate);
    }

    query += ` GROUP BY i.id ORDER BY i.created_at DESC LIMIT ?`;
    params.push(limitParam);

    const transactions = db.prepare(query).all(...params);

    res.json({
      success: true,
      data: transactions
    });

  } catch (error) {
    logger.error('Get POS Transactions Error:', error);
    res.status(500).json({ error: 'Failed to fetch POS transactions' });
  }
}

export default {
  createPOSSale,
  getPOSTransactions
};
