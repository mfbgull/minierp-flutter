import { Request, Response } from 'express';
import { AuthRequest, SellableStockUnavailableError } from '../types';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import logger from '../utils/logger';
import WarehouseModel from '../models/Warehouse';
import MobileInvoiceModel from '../models/MobileInvoice';
import { ActionType, newCorrelationId, logCRUD } from '../services/activityLogger';
import { computeInvoiceGrandTotal, parseCurrency } from '../utils/currency';
import {
  InvoiceCreationCreditError,
  InvoiceCreationIdempotencyError,
  InvoiceCreationOffsetError,
  InvoiceCreationPaymentMethodError,
  InvoiceCreationService,
  InvoiceCreationTotalMismatchError,
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
    'SELECT invoice_no, total_amount, customer_name, invoice_date, discount_scope, discount_type, discount_value FROM invoices WHERE id = ? AND source_type = ?'
  ).get(invoiceId, 'POS') as { invoice_no: string; total_amount: number; customer_name: string | null; invoice_date: string; discount_scope: string | null; discount_type: string | null; discount_value: number | null } | undefined;
  if (!inv) return undefined;

  // line_total is the STORED amount, not quantity * unit_price: a
  // discounted or taxed line stores something else, and a replay that
  // recomputed it would disagree with the invoice it is replaying.
  const itemDetails = db.prepare(`
    SELECT ? AS sale_id, ? AS sale_no, ii.item_id, i.item_code, i.item_name, i.unit_of_measure,
           ii.quantity, ii.unit_price, ii.amount AS line_total
    FROM invoice_items ii
    JOIN items i ON i.id = ii.item_id
    WHERE ii.invoice_id = ?
    ORDER BY ii.id
  `).all(invoiceId, inv.invoice_no, invoiceId) as Array<Record<string, unknown>>;
  if (itemDetails.length === 0) return undefined;

  // Legs are read back from the payments this sale actually recorded, so
  // the replay is server-authoritative rather than an echo of the request.
  const storedLegs = db.prepare(`
    SELECT p.payment_method, p.amount
    FROM payment_allocations pa
    JOIN payments p ON p.id = pa.payment_id
    WHERE pa.invoice_id = ? AND p.voided_at IS NULL
    ORDER BY p.id
  `).all(invoiceId) as Array<{ payment_method: string; amount: number }>;

  const total = Number(inv.total_amount);
  const usesLegs = Array.isArray(reqBody.payments);
  const warehouse = WarehouseModel.getById(db, Number(reqBody.warehouse_id));

  const cashLeg = storedLegs
    .filter((leg) => leg.payment_method.toLowerCase() === 'cash')
    .reduce((sum, leg) => sum + Number(leg.amount), 0);
  const cashReceived = usesLegs
    ? cashLeg
    : parseFloat(String(reqBody.cash_received ?? '')) || total;

  return {
    transaction_no: inv.invoice_no,
    sale_date: inv.invoice_date,
    warehouse_id: reqBody.warehouse_id,
    warehouse_name: warehouse?.warehouse_name,
    customer_id: reqBody.customer_id,
    customer_name: inv.customer_name || customerNameOrDefault(reqBody.customer_name),
    items: itemDetails,
    discount_scope: inv.discount_scope,
    discount_type: inv.discount_type,
    discount_value: Number(inv.discount_value ?? 0),
    payments: storedLegs,
    subtotal: total,
    total,
    cash_received: cashReceived,
    change: Math.max(0, cashReceived - cashLeg),
    items_count: itemDetails.length,
    sale_ids: [invoiceId],
  };
}

function customerNameOrDefault(raw: unknown): string {
  const name = typeof raw === 'string' ? raw.trim() : '';
  return name || 'Walk-in Customer';
}


type PosSaleItem = {
  item_id: number;
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: 'none' | 'percentage' | 'flat';
  discount_value?: number;
};

type PosPaymentLeg = {
  amount: number;
  payment_method: string;
  payment_date?: string;
};

type PosSaleBody = {
  warehouse_id: number;
  sale_date: string;
  items: PosSaleItem[];
  cash_received?: number;
  customer_id?: number;
  customer_name?: string;
  discount_scope?: string;
  discount_type?: string;
  discount_value?: number;
  total_amount?: number;
  payments?: PosPaymentLeg[];
};

function createPOSSale(req: AuthRequest, res: Response): void {
  if (!req.user) {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }

  try {
    const body = req.body as PosSaleBody;
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

    // Presence of `payments` — even as an empty array — selects the split
    // path. Its absence is the legacy payload, which keeps the cash guard
    // below so an old client cannot silently turn into a credit sale.
    const usesLegs = Array.isArray(body.payments);

    // The same function the service validates against, so a header discount
    // cannot make the client's total disagree with ours.
    const total = computeInvoiceGrandTotal(body.items, {
      discount_scope: body.discount_scope,
      discount_type: body.discount_type,
      discount_value: body.discount_value,
    });

    const legs: PosPaymentLeg[] = usesLegs
      ? body.payments!
      : [{ amount: 0, payment_method: 'Cash' }];

    if (!usesLegs) {
      const cashReceived = parseFloat(String(body.cash_received)) || total;
      if (cashReceived < total) {
        res.status(400).json({ error: `Insufficient cash. Total: ${total.toFixed(2)}, Received: ${cashReceived.toFixed(2)}` });
        return;
      }
      legs[0] = {
        amount: Math.min(cashReceived, total),
        payment_method: 'Cash',
        payment_date: body.sale_date,
      };
    } else {
      for (const leg of legs) {
        if (!leg.payment_date) leg.payment_date = body.sale_date;
      }
    }

    // H6: a closed period must not gain new money movements. A POS sale
    // posts a new AR entry dated sale_date, so refuse before any write
    // rather than letting the service's own period check surface it late.
    const closedPeriod = AccountingService.getClosedPeriodCovering(db, body.sale_date);
    if (closedPeriod) {
      res.status(409).json({
        error: `POS sale is dated ${body.sale_date} inside closed accounting period '${closedPeriod.period_name}' — edit/delete blocked`,
      });
      return;
    }

    let idemKey: string | null;
    try {
      idemKey = normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]);
    } catch (keyError) {
      res.status(400).json({ error: (keyError as Error).message });
      return;
    }

    const customerId = body.customer_id && body.customer_id > 0
      ? body.customer_id
      : ensureWalkinCustomer();
    const customerName = body.customer_id
      ? undefined
      : body.customer_name || 'Walk-in Customer';

    const service = new InvoiceCreationService(db);
    const result = service.create({
      source: 'POS',
      userId: req.user.id,
      customerId,
      customerName,
      invoiceDate: body.sale_date,
      dueDate: body.sale_date,
      notes: 'POS sale',
      warehouseId: body.warehouse_id,
      items: body.items,
      discountScope: body.discount_scope as 'item' | 'invoice' | undefined,
      discountType: body.discount_type as 'flat' | 'percentage' | undefined,
      discountValue: body.discount_value,
      totalAmount: body.total_amount === undefined ? undefined : parseCurrency(body.total_amount),
      payments: legs,
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
    if (error instanceof InvoiceCreationTotalMismatchError) {
      res.status(400).json({ error: error.message });
      return;
    }
    if (error instanceof InvoiceCreationOffsetError) {
      res.status(400).json({ error: error.message });
      return;
    }
    if (error instanceof InvoiceCreationCreditError) {
      res.status(400).json({ error: error.message });
      return;
    }
    const message = error instanceof Error ? error.message : 'Failed to process POS sale';
    if (message.includes('inside closed accounting period')) {
      res.status(409).json({ error: message });
      return;
    }
    logger.error('POS Sale Error:', { error: message });
    res.status(500).json({ error: message });
  }
}

function getPOSTaxRates(req: Request, res: Response): void {
  try {
    res.json({ success: true, data: MobileInvoiceModel.getTaxRates(db) });
  } catch (error) {
    logger.error('Get POS tax rates error:', error);
    res.status(500).json({ error: 'Failed to get tax rates' });
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
  getPOSTransactions,
  getPOSTaxRates
};
