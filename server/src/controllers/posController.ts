import { Request, Response } from 'express';
import { AuthRequest, SellableStockUnavailableError } from '../types';
import db from '../config/database';
import logger from '../utils/logger';
import { generateDocNo } from '../utils/sequence';
import InvoiceModel from '../models/Invoice';
import StockMovementModel from '../models/StockMovement';
import WarehouseModel from '../models/Warehouse';
import AccountingService from '../services/accountingService';
import { ActionType, newCorrelationId, logActivityInTx } from '../services/activityLogger';
import { parseCurrency, addCurrency, multiplyCurrency } from '../utils/currency';
import { roundQty } from '../utils/quantity';
import {
  IDEMPOTENCY_KEY_HEADER,
  POS_SALE_SCOPE,
  normalizeIdempotencyKey,
  hashRequestPayload,
  findIdempotencyRecord,
  claimIdempotencyKey,
} from '../utils/idempotency';

function generatePOSTransactionNo(): string {
  return generateDocNo(db, 'POS', 5);
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

    // P11: idempotent POS sale. A retry after a client-side timeout must
    // replay the original sale, never double-create (stock/GL/ledger).
    // Requests without the header keep the legacy (unguarded) behavior.
    let idemKey: string | null;
    try {
      idemKey = normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]);
    } catch (keyError) {
      res.status(400).json({ error: (keyError as Error).message });
      return;
    }
    const idemHash = idemKey ? hashRequestPayload(req.body) : '';
    if (idemKey) {
      const existing = findIdempotencyRecord(db, POS_SALE_SCOPE, idemKey);
      if (existing) {
        if (existing.request_hash !== idemHash) {
          res.status(409).json({
            error: 'Idempotency-Key was already used with a different request payload',
          });
          return;
        }
        if (existing.resource_id != null) {
          const replayed = replayPosSaleResult(existing.resource_id, req.body);
          if (replayed) {
            res.set('X-Idempotent-Replay', 'true');
            res.status(201).json({ success: true, message: 'POS sale completed successfully', data: replayed });
            return;
          }
        }
      }
    }


    // ACC-18 interim: the server computes each line (rounded) and sums.
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
      total = addCurrency(total, multiplyCurrency(item.quantity, item.unit_price));
    }

    const cashAmount = parseFloat(cash_received) || total;
    if (cashAmount < total) {
      res.status(400).json({
        error: `Insufficient cash. Total: ${total.toFixed(2)}, Received: ${cashAmount.toFixed(2)}`
      });
      return;
    }

    const customerName = customer_name || 'Walk-in Customer';

    // The actual amount applied to the invoice is min(cash, total).
    // Any overpayment is change returned to the customer — it must not
    // appear in the customer ledger or invoice paid_amount.
    const paymentAmount = Math.min(cashAmount, total);

    // Stock validation — all items must be covered by SELLABLE stock
    // (non-expired, non-halted, ACTIVE-location batches) at the POS
    // warehouse before proceeding. stock_balances.quantity counts
    // expired stock, so it must not gate POS sales.
    for (const item of items) {
      const sellable = StockMovementModel.getSellableAvailability(item.item_id, warehouse_id, db)[0];
      const availableStock = roundQty(sellable ? sellable.sellable_qty : 0);
      const requiredQty = roundQty(item.quantity);
      if (availableStock < requiredQty) {
        const itemRecord = db.prepare('SELECT item_name FROM items WHERE id = ?').get(item.item_id) as { item_name: string } | undefined;
        res.status(400).json({
          error: new SellableStockUnavailableError(itemRecord?.item_name || `item ${item.item_id}`, requiredQty, availableStock).message
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
        paymentAmount,
        total - paymentAmount,
        `POS Transaction: ${transactionNo}`,
        userId,
        'POS'
      );

      const invoiceId = invoiceResult.lastInsertRowid as number;
      // P11: claim the idempotency key inside this transaction — the
      // (key → invoice) row persists if and only if the sale commits,
      // so a rolled-back attempt leaves no trace and the retry runs
      // normally, while a post-commit client timeout replays this sale.
      if (idemKey) {
        claimIdempotencyKey(db, POS_SALE_SCOPE, idemKey, idemHash, invoiceId);
      }


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

        // Deduct stock via FIFO batch consumption
        const consumption = InvoiceModel.consumeFromOldestBatches(
          item.item_id, warehouse_id, item.quantity, db
        );
        for (const entry of consumption) {
          const batchLabel = entry.batchId ? `(batch ${entry.batchId})` : '(legacy stock)';
          StockMovementModel.recordMovement({
            item_id: item.item_id,
            warehouse_id: warehouse_id,
            quantity: -entry.consumed,
            movement_type: 'SALE',
            unit_cost: entry.unitCost,
            reference_doctype: 'POS',
            reference_docno: transactionNo,
            movement_date: sale_date,
            remarks: `POS Sale: ${transactionNo} - ${itemRecord.item_name} ${batchLabel}`,
            batch_id: entry.batchId ?? undefined,
          }, userId, db);
        }

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

      // Record payment — only the invoice total, not the full cash
      // received. Any overpayment (change) is returned to the customer
      // and must NOT be recorded in the customer ledger, otherwise the
      // walk-in accumulates a spurious Cr balance.
      let paymentId: number | null = null;
      let paymentNo: string | null = null;
      if (paymentAmount > 0) {
        paymentNo = InvoiceModel.generatePaymentNoAtomic(db);
        paymentId = InvoiceModel.createPayment(db, paymentNo, walkinCustomerId, sale_date, paymentAmount, 'Cash', null, `POS Transaction ${transactionNo}`);
        InvoiceModel.createPaymentAllocation(db, paymentId, invoiceId, paymentAmount);
        // Create ledger entry for payment
        InvoiceModel.createLedgerEntry(db, walkinCustomerId, 'PAYMENT', paymentNo, sale_date, 0, paymentAmount, `Payment ${paymentNo} for POS ${transactionNo}`);
      }

      // Create ledger entry for the sale
      InvoiceModel.createLedgerEntry(db, walkinCustomerId, 'INVOICE', transactionNo, sale_date, total, 0, `POS Sale ${transactionNo}`);

      // GL postings (ACC-05): POS sales previously posted nothing to the
      // journal. Route them through the same sequence as the standard
      // invoice path — revenue entry, COGS entry (actual FIFO cost), and
      // the cash payment entry. Any failure rethrows and rolls back the
      // whole sale (salary-payment reference pattern).
      let posCogsTotal = 0;
      for (const detail of itemDetails) {
        const cogsRows = db.prepare(`
          SELECT sm.quantity * sm.unit_cost AS line_cogs
          FROM stock_movements sm
          WHERE sm.reference_doctype = 'POS' AND sm.reference_docno = ?
            AND sm.item_id = ? AND sm.movement_type = 'SALE'
        `).all(transactionNo, detail.item_id) as Array<{ line_cogs: number }>;
        posCogsTotal += cogsRows.reduce((s, r) => s + Math.abs(Number(r.line_cogs)), 0);
      }

      // H3: posted tax must equal the stored invoice tax. POS carts carry
      // no tax_rate today (ACC-19 scope), so this reads 0 — but reading
      // the stored rows keeps it correct the moment POS gains tax rates.
      const computedPosTax = InvoiceModel.getInvoiceTaxTotal(db, invoiceId);
      AccountingService.postInvoiceEntry(db, {
        invoiceId,
        invoiceNo: transactionNo,
        totalAmount: total,
        invoiceDate: sale_date,
        userId,
        taxAmount: computedPosTax,
      });

      if (posCogsTotal > 0) {
        AccountingService.postCOGSEntry(db, {
          invoiceId,
          invoiceNo: transactionNo,
          cogsAmount: parseCurrency(posCogsTotal),
          invoiceDate: sale_date,
          userId,
        });
      }

      if (paymentAmount > 0) {
        if (paymentId === null || paymentNo === null) throw new Error('POS payment was not recorded');
        AccountingService.postPaymentEntry(db, {
          paymentId,
          paymentNo,
          amount: paymentAmount,
          paymentDate: sale_date,
          paymentMethod: 'cash',
          customerId: walkinCustomerId,
          userId,
        });
      }

      // Activity log — task 4.5: attribute POS sales to the INVOICE entity,
      // written transactionally via the shared helper.
      logActivityInTx(db, {
        userId,
        action: ActionType.INVOICE_CREATE,
        entityType: 'Invoice',
        entityId: invoiceId,
        description: `POS Transaction ${transactionNo}: ${items.length} items`,
        newValue: { transaction_no: transactionNo, total, items: items.length },
        correlationId: newCorrelationId()
      });

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
    if (error instanceof SellableStockUnavailableError) {
      logger.warn('POS sale rejected:', { error: error.message });
      res.status(400).json({ error: error.message });
      return;
    }
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
