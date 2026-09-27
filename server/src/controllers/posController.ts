import { Request, Response } from 'express';
import { AuthRequest, SellableStockUnavailableError } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import WarehouseModel from '../models/Warehouse';
import { ActionType, newCorrelationId, logCRUD } from '../services/activityLogger';
import { computeInvoiceTotal } from '../utils/currency';
import {
  InvoiceCreationIdempotencyError,
  InvoiceCreationPaymentMethodError,
  InvoiceCreationService,
} from '../services/InvoiceCreationService';
import {
  IDEMPOTENCY_KEY_HEADER,
  POS_SALE_SCOPE,
  normalizeIdempotencyKey,
  hashRequestPayload,
} from '../utils/idempotency';

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

/**
 * P11: rebuild the POS sale result for an idempotent replay. The retried
 * request body is hash-verified identical to the original, so every
 * client-supplied field (warehouse, sale date, cash received, customer
 * name) is taken from it and only the server-derived fields (transaction
 * no, invoice id, item details, totals) are read back from the stored
 * invoice — the response is byte-equivalent to the original.
 */
function replayPosSaleResult(invoiceId: number, reqBody: Record<string, unknown>): Record<string, unknown> | undefined {
  const inv = db.prepare(
    'SELECT invoice_no, total_amount, customer_name, invoice_date FROM invoices WHERE id = ? AND source_type = ?'
  ).get(invoiceId, 'POS') as { invoice_no: string; total_amount: number; customer_name: string | null; invoice_date: string } | undefined;
  if (!inv) return undefined;

  const itemDetails = db.prepare(`
    SELECT ? AS sale_id, ? AS sale_no, ii.item_id, i.item_code, i.item_name, i.unit_of_measure,
           ii.quantity, ii.unit_price, ii.quantity * ii.unit_price AS line_total
    FROM invoice_items ii
    JOIN items i ON i.id = ii.item_id
    WHERE ii.invoice_id = ?
    ORDER BY ii.id
  `).all(invoiceId, inv.invoice_no, invoiceId) as Array<Record<string, unknown>>;
  if (itemDetails.length === 0) return undefined;

  const total = Number(inv.total_amount);
  const cashReceived = parseFloat(String(reqBody.cash_received ?? '')) || total;
  const warehouse = WarehouseModel.getById(db, Number(reqBody.warehouse_id));

  return {
    transaction_no: inv.invoice_no,
    sale_date: inv.invoice_date,
    warehouse_id: reqBody.warehouse_id,
    warehouse_name: warehouse?.warehouse_name,
    customer_name: inv.customer_name || customerNameOrDefault(reqBody.customer_name),
    items: itemDetails,
    subtotal: total,
    total,
    cash_received: cashReceived,
    change: cashReceived - total,
    items_count: itemDetails.length,
    sale_ids: [invoiceId],
  };
}

function customerNameOrDefault(raw: unknown): string {
  const name = typeof raw === 'string' ? raw.trim() : '';
  return name || 'Walk-in Customer';
}


function createPOSSale(req: AuthRequest, res: Response): void {
  if (!req.user) {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }

  try {
    const body = req.body as {
      warehouse_id: number;
      sale_date: string;
      items: Array<{ item_id: number; quantity: number; unit_price: number }>;
      cash_received: number;
      customer_name?: string;
    };
    if (!body.warehouse_id) {
      res.status(400).json({ error: 'Warehouse is required' });
      return;
    }
    if (!body.sale_date) {
      res.status(400).json({ error: 'Sale date is required' });
      return;
    }
    if (!Array.isArray(body.items) || body.items.length === 0) {
      res.status(400).json({ error: 'At least one item is required' });
      return;
    }
    const warehouse = WarehouseModel.getById(db, body.warehouse_id);
    if (!warehouse) {
      res.status(400).json({ error: 'Warehouse not found' });
      return;
    }

    const total = computeInvoiceTotal(body.items);
    const cashReceived = parseFloat(String(body.cash_received)) || total;
    if (cashReceived < total) {
      res.status(400).json({ error: `Insufficient cash. Total: ${total.toFixed(2)}, Received: ${cashReceived.toFixed(2)}` });
      return;
    }

    let idemKey: string | null;
    try {
      idemKey = normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]);
    } catch (keyError) {
      res.status(400).json({ error: (keyError as Error).message });
      return;
    }

    const walkinCustomerId = ensureWalkinCustomer();
    const service = new InvoiceCreationService(db);
    const result = service.create({
      source: 'POS',
      userId: req.user.id,
      customerId: walkinCustomerId,
      customerName: body.customer_name || 'Walk-in Customer',
      invoiceDate: body.sale_date,
      dueDate: body.sale_date,
      status: 'Paid',
      notes: 'POS sale',
      warehouseId: body.warehouse_id,
      items: body.items,
      totalAmount: total,
      recordPayment: cashReceived > 0,
      payment: { amount: Math.min(cashReceived, total), payment_date: body.sale_date, payment_method: 'Cash' },
      idempotency: idemKey
        ? { scope: POS_SALE_SCOPE, key: idemKey, hash: hashRequestPayload(req.body) }
        : undefined,
    });

    if (result.replayed) res.set('X-Idempotent-Replay', 'true');
    const replayed = replayPosSaleResult(result.invoiceId, req.body as Record<string, unknown>);
    if (!replayed) {
      res.status(500).json({ error: 'POS sale result could not be rebuilt' });
      return;
    }
    logCRUD(ActionType.INVOICE_CREATE, 'Invoice', result.invoiceId, `POS sale ${result.invoiceNo}`, req.user.id, { total_amount: total }, { correlationId: newCorrelationId() });
    res.status(201).json({ success: true, message: 'POS sale completed successfully', data: replayed });
  } catch (error: unknown) {
    if (error instanceof SellableStockUnavailableError) {
      res.status(400).json({ error: error.message });
      return;
    }
    if (error instanceof InvoiceCreationPaymentMethodError) {
      res.status(400).json({ error: error.message });
      return;
    }
    if (error instanceof InvoiceCreationIdempotencyError) {
      res.status(409).json({ error: error.message });
      return;
    }
    const message = error instanceof Error ? error.message : 'Failed to process POS sale';
    logger.error('POS Sale Error:', { error: message });
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
