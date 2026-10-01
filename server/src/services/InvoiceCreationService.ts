import Database from 'better-sqlite3';
import AccountingService from './accountingService';
import InvoiceModel from '../models/Invoice';
import StockMovementModel from '../models/StockMovement';
import ledgerUtils from '../utils/ledgerUtils';
import { PaymentRecordingService } from './PaymentRecordingService';
import { addCurrency, computeInvoiceGrandTotal, parseCurrency, subtractCurrency } from '../utils/currency';
import { isValidPaymentMethod } from './cashService';
import { claimIdempotencyKey, findIdempotencyRecord } from '../utils/idempotency';
import { generateDocNo } from '../utils/sequence';
import type {
  InvoiceCreationInput,
  InvoiceCreationItemResult,
  InvoiceCreationPayment,
  InvoiceCreationResult,
} from './invoiceCreationTypes';

export class InvoiceCreationTotalMismatchError extends Error {
  constructor(clientTotal: number, computedTotal: number) {
    super(`total_amount disagrees with line items (client ${clientTotal.toFixed(2)} vs computed ${computedTotal.toFixed(2)})`);
    this.name = 'InvoiceCreationTotalMismatchError';
  }
}

export class InvoiceCreationPaymentMethodError extends Error {
  constructor(method?: string) {
    super(`Invalid payment_method "${method ?? ''}" — use Cash, Bank, Easypaisa, JazzCash or Upaisa`);
    this.name = 'InvoiceCreationPaymentMethodError';
  }
}

export class InvoiceCreationCreditError extends Error {
  constructor(offset: number, available: number) {
    super(`Credit offset (${offset.toFixed(2)}) exceeds available credit balance (${available.toFixed(2)})`);
    this.name = 'InvoiceCreationCreditError';
  }
}

export class InvoiceCreationOffsetError extends Error {
  constructor(applied: number, total: number) {
    super(`Payment + credit offset (${applied.toFixed(2)}) exceeds invoice total (${total.toFixed(2)})`);
    this.name = 'InvoiceCreationOffsetError';
  }
}

export class InvoiceCreationIdempotencyError extends Error {
  constructor() {
    super('Idempotency-Key was already used with a different request payload');
    this.name = 'InvoiceCreationIdempotencyError';
  }
}

type ExistingInvoiceRow = {
  id: number;
  invoice_no: string;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
};

function defaultDueDate(invoiceDate: string): string {
  const date = new Date(`${invoiceDate}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + 15);
  return date.toISOString().slice(0, 10);
}

function validateInput(input: InvoiceCreationInput): void {
  if (!input.customerId || input.customerId <= 0) throw new Error('Invalid customer_id');
  if (!input.invoiceDate) throw new Error('invoice_date is required');
  if (input.items.length === 0) throw new Error('At least one invoice item is required');
  for (const item of input.items) {
    if (!item.item_id || item.item_id <= 0) throw new Error('Invalid item_id in invoice items');
    if (!item.quantity || item.quantity <= 0) throw new Error('Invalid quantity in invoice items');
    if (item.unit_price === undefined || item.unit_price < 0) throw new Error('Invalid unit_price in invoice items');
  }
}

export class InvoiceCreationService {
  constructor(private readonly db: Database.Database) {}

  create(input: InvoiceCreationInput): InvoiceCreationResult {
    validateInput(input);

    const totalAmount = computeInvoiceGrandTotal([...input.items], {
      discount_scope: input.discountScope,
      discount_type: input.discountType,
      discount_value: input.discountValue,
    });
    if (input.totalAmount !== undefined && Math.abs(input.totalAmount - totalAmount) > 0.01) {
      throw new InvoiceCreationTotalMismatchError(input.totalAmount, totalAmount);
    }

    const legs: readonly InvoiceCreationPayment[] = input.payments !== undefined
      ? input.payments
      : input.recordPayment && input.payment
        ? [input.payment]
        : [];

    let legsTotal = 0;
    for (const leg of legs) {
      const legAmount = parseCurrency(leg.amount);
      if (legAmount < 0) throw new Error('Payment amounts must be non-negative');
      if (legAmount > 0 && !isValidPaymentMethod(leg.payment_method ?? 'Cash')) {
        throw new InvoiceCreationPaymentMethodError(leg.payment_method);
      }
      // addCurrency, not `+=`: summing several 2dp legs in floating point
      // can land a cent low and flip a fully-settled invoice to
      // 'Partially Paid'.
      legsTotal = addCurrency(legsTotal, legAmount);
    }

    const creditOffset = parseCurrency(input.creditOffset);
    if (creditOffset < 0) throw new Error('Credit offset must be non-negative');
    if (legsTotal + creditOffset > totalAmount + 0.01) {
      throw new InvoiceCreationOffsetError(legsTotal + creditOffset, totalAmount);
    }

    const paidAmount = addCurrency(legsTotal, creditOffset);
    const balanceAmount = subtractCurrency(totalAmount, paidAmount);
    const status = input.status ?? (paidAmount >= totalAmount ? 'Paid' : paidAmount > 0 ? 'Partially Paid' : 'Unpaid');
    const dueDate = input.dueDate === undefined ? defaultDueDate(input.invoiceDate) : input.dueDate;

    const transaction = this.db.transaction((): InvoiceCreationResult => {
      if (input.idempotency) {
        const existing = findIdempotencyRecord(this.db, input.idempotency.scope, input.idempotency.key);
        if (existing) {
          if (existing.request_hash !== input.idempotency.hash) throw new InvoiceCreationIdempotencyError();
          if (existing.resource_id !== null) return this.resultFromExisting(existing.resource_id, true);
        }
      }

      if (creditOffset > 0) {
        const customer = this.db.prepare(`
          SELECT current_balance, COALESCE(credit_balance, 0) AS credit_balance
          FROM customers WHERE id = ?
        `).get(input.customerId) as { current_balance: number; credit_balance: number } | undefined;
        const available = Math.max(0, customer?.credit_balance ?? 0) + Math.abs(Math.min(0, customer?.current_balance ?? 0));
        if (creditOffset > available + 0.005) throw new InvoiceCreationCreditError(creditOffset, available);
      }

      const invoiceNo = input.invoiceNo || generateDocNo(this.db, 'INV', 5);
      const invoiceId = InvoiceModel.createInvoice(this.db, {
        invoice_no: invoiceNo,
        customer_id: input.customerId,
        customer_name: input.customerName,
        so_id: input.soId,
        source_type: input.source,
        quotation_id: input.quotationId,
        invoice_date: input.invoiceDate,
        due_date: dueDate ?? undefined,
        status,
        total_amount: totalAmount,
        paid_amount: paidAmount,
        balance_amount: balanceAmount,
        credit_offset: creditOffset,
        notes: input.notes,
        terms: input.terms,
        discount_scope: input.discountScope,
        discount_type: input.discountType,
        discount_value: input.discountValue,
        items: input.items.map((item) => ({
          item_id: item.item_id,
          quantity: item.quantity,
          unit_price: item.unit_price,
          tax_rate: item.tax_rate,
          discount_type: item.discount_type,
          discount_value: item.discount_value,
          amount: item.amount,
        })),
      }, input.userId);

      if (input.idempotency) {
        claimIdempotencyKey(this.db, input.idempotency.scope, input.idempotency.key, input.idempotency.hash, invoiceId);
      }

      const itemResults: InvoiceCreationItemResult[] = [];
      const consumptions: Array<{ itemId: number; consumption: Array<{ batchId: number | null; consumed: number }> }> = [];
      let cogsAmount = 0;
      for (const item of input.items) {
        const warehouseId = item.warehouse_id || input.warehouseId || InvoiceModel.findWarehouseForItem(this.db, item.item_id, item.quantity);
        InvoiceModel.createInvoiceItem(this.db, invoiceId, {
          item_id: item.item_id,
          quantity: item.quantity,
          unit_price: item.unit_price,
          tax_rate: item.tax_rate,
          discount_type: item.discount_type,
          discount_value: item.discount_value,
          amount: item.amount,
        });
        const consumption = InvoiceModel.consumeFromOldestBatches(item.item_id, warehouseId, item.quantity, this.db);
        const batchIds: Array<number | null> = [];
        for (const entry of consumption) {
          StockMovementModel.recordMovement({
            item_id: item.item_id,
            warehouse_id: warehouseId,
            movement_type: 'SALE',
            quantity: -entry.consumed,
            unit_cost: entry.unitCost,
            reference_doctype: input.source === 'POS' ? 'POS' : 'INVOICE',
            reference_docno: invoiceNo,
            remarks: input.source === 'POS' ? `POS Sale: ${invoiceNo}` : `Sold via Invoice ${invoiceNo}`,
            movement_date: input.invoiceDate,
            batch_id: entry.batchId ?? undefined,
          }, input.userId, this.db);
          batchIds.push(entry.batchId);
          cogsAmount += entry.consumed * entry.unitCost;
        }
        consumptions.push({ itemId: item.item_id, consumption });
        itemResults.push({ itemId: item.item_id, quantity: item.quantity, unitPrice: item.unit_price, amount: parseCurrency(item.quantity * item.unit_price), warehouseId, batchIds });
      }
      InvoiceModel.denormalizeExpiryInfo(invoiceId, consumptions, this.db);
      InvoiceModel.createLedgerEntry(this.db, input.customerId, 'INVOICE', invoiceNo, input.invoiceDate, totalAmount, 0, `Invoice ${invoiceNo}`);
      AccountingService.postInvoiceEntry(this.db, { invoiceId, invoiceNo, totalAmount, invoiceDate: input.invoiceDate, userId: input.userId, taxAmount: InvoiceModel.getInvoiceTaxTotal(this.db, invoiceId) });
      if (cogsAmount > 0) AccountingService.postCOGSEntry(this.db, { invoiceId, invoiceNo, cogsAmount: parseCurrency(cogsAmount), invoiceDate: input.invoiceDate, userId: input.userId });

      let paymentId: number | null = null;
      let paymentNo: string | null = null;
      // One entry per leg, each through the single existing recording path
      // so the method whitelist, period guard, allocation, status refresh
      // and GL posting stay in one place.
      for (const leg of legs) {
        const legAmount = parseCurrency(leg.amount);
        if (legAmount <= 0) continue;
        const recorded = new PaymentRecordingService(this.db).recordCustomerPayment({
          mode: 'INVOICE_SETTLEMENT',
          customerId: input.customerId,
          paymentDate: leg.payment_date || input.invoiceDate,
          amount: legAmount,
          paymentMethod: leg.payment_method || 'Cash',
          referenceNo: leg.reference_no,
          notes: leg.notes,
          userId: input.userId,
          allocations: [{ invoiceId, amount: legAmount }],
        });
        paymentId = paymentId ?? recorded.paymentId;
        paymentNo = paymentNo ?? recorded.paymentNo;
      }
      if (creditOffset > 0) {
        AccountingService.postCreditOffsetEntry(this.db, { invoiceId, invoiceNo, amount: creditOffset, invoiceDate: input.invoiceDate, customerId: input.customerId, userId: input.userId });
        const customer = this.db.prepare('SELECT COALESCE(credit_balance, 0) AS credit_balance FROM customers WHERE id = ?').get(input.customerId) as { credit_balance: number };
        const poolApplied = Math.min(creditOffset, Math.max(0, customer.credit_balance));
        if (poolApplied > 0) {
          this.db.prepare('UPDATE customers SET credit_balance = MAX(0, credit_balance - ?) WHERE id = ?').run(poolApplied, input.customerId);
          InvoiceModel.createLedgerEntry(this.db, input.customerId, 'CREDIT', `CREDIT-${invoiceNo}`, input.invoiceDate, 0, poolApplied, `Store credit applied to Invoice ${invoiceNo}`);
        }
      }
      if (input.afterCreate) input.afterCreate(invoiceId, invoiceNo);
      ledgerUtils.rebuildLedgerBalances(input.customerId, this.db);
      ledgerUtils.recalcCustomerBalanceFromLedger(input.customerId, this.db);
      if (input.draftId) this.db.prepare('DELETE FROM invoice_drafts WHERE id = ?').run(input.draftId);
      return { invoiceId, invoiceNo, totalAmount, paidAmount, balanceAmount, taxAmount: InvoiceModel.getInvoiceTaxTotal(this.db, invoiceId), cogsAmount: parseCurrency(cogsAmount), paymentId, paymentNo, replayed: false, items: itemResults };
    });

    return transaction();
  }

  private resultFromExisting(invoiceId: number, replayed: boolean): InvoiceCreationResult {
    const row = this.db.prepare('SELECT id, invoice_no, total_amount, paid_amount, balance_amount FROM invoices WHERE id = ?').get(invoiceId) as ExistingInvoiceRow | undefined;
    if (!row) throw new Error(`Invoice ${invoiceId} not found for idempotency replay`);
    return { invoiceId: row.id, invoiceNo: row.invoice_no, totalAmount: numberValue(row.total_amount), paidAmount: numberValue(row.paid_amount), balanceAmount: numberValue(row.balance_amount), taxAmount: 0, cogsAmount: 0, paymentId: null, paymentNo: null, replayed, items: [] };
  }
}

function numberValue(value: number | null | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}
