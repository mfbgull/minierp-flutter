import { listPagination, rawListPageQuery } from '../utils/controllerPagination';
import { Request, Response } from 'express';
import type Database from 'better-sqlite3';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import AccountingService from '../services/accountingService';
import { PaymentRecordingService } from '../services/PaymentRecordingService';
import db from '../config/database';
import { getRouteParam } from '../utils/queryUtils';
import { PAYMENT_SORT_COLUMNS } from '../utils/sqlSanitizer';
import logger from '../utils/logger';
import { parseCurrency } from '../utils/currency';
import PaymentModel from '../models/Payment';
import CustomerModel from '../models/Customer';
import InvoiceModel from '../models/Invoice';
import SupplierModel from '../models/Supplier';
import { handleBusinessError } from '../utils/businessRuleError';
import {
  IDEMPOTENCY_KEY_HEADER,
  IDEMPOTENCY_SCOPES,
  IdempotencyConflictError,
  beginIdempotentWrite,
  claimIdempotencyKey,
  hashRequestPayload,
  normalizeIdempotencyKey,
} from '../utils/idempotency';

/**
 * audit-3 task 08: read the retry key, or 400 on a malformed one.
 * Returns null when the client sent no key, which leaves the write unguarded
 * exactly as before.
 */
function readIdempotencyKey(req: AuthRequest, res: Response): string | null | undefined {
  try {
    return normalizeIdempotencyKey(req.headers[IDEMPOTENCY_KEY_HEADER]);
  } catch (err) {
    res.status(400).json({ success: false, error: (err as Error).message });
    return undefined;
  }
}

import { formatCurrency, getCurrencySymbol } from '../utils/displayCurrency';

function getPayments(req: Request, res: Response): void {
  try {
    const { pageParam, limitParam, searchParam } = rawListPageQuery(req.query);
    const customerIdParam = getQueryParam(req.query.customerId);
    const supplierIdParam = getQueryParam(req.query.supplierId);
    const fromDateParam = getQueryParam(req.query.fromDate);
    const toDateParam = getQueryParam(req.query.toDate);
    const sortByParam = getQueryParam(req.query.sortBy);
    const sortOrderParam = getQueryParam(req.query.sortOrder);

    const filters = {
      page: parseInt(pageParam as string) || 1,
      limit: parseInt(limitParam as string) || 10,
      search: searchParam as string,
      customerId: customerIdParam as string,
      supplierId: supplierIdParam as string,
      fromDate: fromDateParam as string,
      toDate: toDateParam as string,
      sortBy: sortByParam as string,
      sortOrder: sortOrderParam as string,
    };

    const { payments, total, pageNum, limitNum } = PaymentModel.getAll(db, filters, [...PAYMENT_SORT_COLUMNS], 'payment_date', 'DESC');

    res.json({
      success: true, data: payments,
      pagination: listPagination(total, pageNum, limitNum)
    });
  } catch (error) {
    logger.error('Error fetching payments:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch payments' });
  }
}

function getUnifiedPayments(req: Request, res: Response): void {
  try {
    const filters = {
      page: parseInt(getQueryParam(req.query.page) as string) || 1,
      limit: parseInt(getQueryParam(req.query.limit) as string) || 10,
      search: getQueryParam(req.query.search) as string,
      type: getQueryParam(req.query.type) as string,
      fromDate: getQueryParam(req.query.fromDate) as string,
      toDate: getQueryParam(req.query.toDate) as string,
      sortBy: getQueryParam(req.query.sortBy) as string,
      sortOrder: getQueryParam(req.query.sortOrder) as string,
    };

    const { payments, total, pageNum, limitNum } = PaymentModel.getUnifiedPayments(db, filters);

    res.json({
      success: true, data: payments,
      pagination: listPagination(total, pageNum, limitNum)
    });
  } catch (error) {
    logger.error('Error fetching unified payments:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch unified payments' });
  }
}

function getPayment(req: Request, res: Response): void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const payment = PaymentModel.getById(db, id);
    if (!payment) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }
    res.json({ success: true, data: payment });
  } catch (error) {
    logger.error('Error fetching payment:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch payment' });
  }
}

/**
 * Validate a customer payment's invoice allocations: each allocation must
 * name an existing invoice that belongs to this customer, carry a positive
 * amount that does not exceed the invoice's remaining balance, and the
 * allocations must add up to the payment amount.
 */
function validateCustomerInvoiceAllocations(
  db: Database.Database,
  invoiceAllocations: Array<{ invoice_id: number | string; amount: number | string }>,
  parsedCustomerId: number,
  parsedAmount: number
): { status: number; error: string } | null {
  for (const alloc of invoiceAllocations) {
    const parsedInvoiceId = parseInt(String(alloc.invoice_id), 10);
    if (isNaN(parsedInvoiceId)) {
      return { status: 400, error: `Invalid invoice ID: ${alloc.invoice_id}` };
    }

    const invoice = InvoiceModel.getById(parsedInvoiceId, db);
    if (!invoice) {
      return { status: 404, error: `Invoice ${parsedInvoiceId} not found` };
    }

    if (Number(invoice.customer_id) !== Number(parsedCustomerId)) {
      return { status: 400, error: `Invoice ${parsedInvoiceId} does not belong to customer ${parsedCustomerId}` };
    }

    if (parseCurrency(alloc.amount) <= 0) {
      return { status: 400, error: `Allocation amount for invoice ${alloc.invoice_id} must be greater than 0` };
    }

    if (parseCurrency(alloc.amount) > parseCurrency(invoice.balance_amount)) {
      return {
        status: 400,
        error: `Allocation amount (${parseCurrency(alloc.amount).toFixed(2)}) for invoice ${alloc.invoice_id} exceeds the remaining balance (${parseCurrency(invoice.balance_amount).toFixed(2)})`,
      };
    }
  }

  const totalAllocated = invoiceAllocations.reduce(
    (sum: number, alloc: { amount: number | string }) => sum + parseCurrency(alloc.amount),
    0
  );
  if (Math.abs(totalAllocated - parsedAmount) > 0.01) {
    return {
      status: 400,
      error: `Payment amount (${parsedAmount.toFixed(2)}) does not match total allocated amount (${totalAllocated.toFixed(2)})`,
    };
  }

  return null;
}

interface CustomerPaymentParams {
  customerId: number;
  paymentDate: string;
  amount: number;
  paymentMethod: string;
  referenceNo: string | undefined;
  notes: string | undefined;
  invoiceAllocations: Array<{ invoice_id: string; amount: number }> | undefined;
  idemKey: string | null;
  currency: string;
}

interface SupplierPaymentParams {
  supplierId: number;
  paymentDate: string;
  amount: number;
  paymentMethod: string;
  referenceNo: string | undefined;
  notes: string | undefined;
  poAllocations: Array<{ po_id: string; amount: number }> | undefined;
  purchaseAllocations: Array<{ purchase_id: string; amount: number }> | undefined;
  idemKey: string | null;
  currency: string;
}

function createCustomerPayment(
  req: AuthRequest,
  res: Response,
  p: CustomerPaymentParams
): void {
  const { customerId, paymentDate, amount, paymentMethod, referenceNo, notes, invoiceAllocations, idemKey, currency } = p;

  if (!invoiceAllocations || !Array.isArray(invoiceAllocations) || invoiceAllocations.length === 0) {
    res.status(400).json({ success: false, error: 'At least one invoice allocation is required for customer payments' });
    return;
  }

  if (!CustomerModel.getById(customerId, db)) {
    res.status(404).json({ success: false, error: 'Customer not found' });
    return;
  }

  const allocationError = validateCustomerInvoiceAllocations(db, invoiceAllocations, customerId, amount);
  if (allocationError) {
    res.status(allocationError.status).json({ success: false, error: allocationError.error });
    return;
  }

  const hash = hashRequestPayload(req.body);
  const { replayId } = beginIdempotentWrite(db, IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER, idemKey, hash);
  if (replayId !== null) {
    if (idemKey) res.set('X-Idempotent-Replay', 'true');
    res.status(201).json({ success: true, data: PaymentModel.getById(db, replayId) });
    return;
  }

  const paymentId = db.transaction(() => {
    const id = PaymentModel.create(db, {
      customer_id: customerId, payment_date: paymentDate, amount, payment_method: paymentMethod, reference_no: referenceNo, notes, invoice_allocations: invoiceAllocations,
      userId: req.user!.id,
    });
    if (idemKey) {
      claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.PAYMENT_CUSTOMER, idemKey, hash, id);
    }
    return id;
  })();

  const customer = CustomerModel.getById(customerId, db);
  logCRUD(ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created payment - ${formatCurrency(amount, currency)} from ${customer?.customer_name || 'Unknown'}`, req.user!.id, { customer_id: customerId, amount, payment_method: paymentMethod, invoice_allocations: invoiceAllocations.length });
  req.activityLogged = true;

  res.status(201).json({ success: true, data: PaymentModel.getById(db, paymentId) });
}

function createSupplierPayment(
  req: AuthRequest,
  res: Response,
  p: SupplierPaymentParams
): void {
  const { supplierId, paymentDate, amount, paymentMethod, referenceNo, notes, poAllocations, purchaseAllocations, idemKey, currency } = p;

  const hasPoAllocs = poAllocations && Array.isArray(poAllocations) && poAllocations.length > 0;
  const hasPurchaseAllocs = purchaseAllocations && Array.isArray(purchaseAllocations) && purchaseAllocations.length > 0;
  if (!hasPoAllocs && !hasPurchaseAllocs) {
    res.status(400).json({ success: false, error: 'At least one PO or purchase allocation is required for supplier payments' });
    return;
  }

  if (!SupplierModel.getById(supplierId, db)) {
    res.status(404).json({ success: false, error: 'Supplier not found' });
    return;
  }

  const hash = hashRequestPayload(req.body);
  const { replayId } = beginIdempotentWrite(db, IDEMPOTENCY_SCOPES.PAYMENT_SUPPLIER, idemKey, hash);
  if (replayId !== null) {
    if (idemKey) res.set('X-Idempotent-Replay', 'true');
    res.status(201).json({ success: true, data: PaymentModel.getById(db, replayId) });
    return;
  }

  const paymentId = db.transaction(() => {
    const id = PaymentModel.createSupplierPayment(db, {
      supplier_id: supplierId,
      payment_date: paymentDate,
      amount,
      payment_method: paymentMethod,
      reference_no: referenceNo,
      notes,
      po_allocations: hasPoAllocs ? poAllocations : [],
      purchase_allocations: hasPurchaseAllocs ? purchaseAllocations : [],
      userId: req.user!.id,
    });
    if (idemKey) {
      claimIdempotencyKey(db, IDEMPOTENCY_SCOPES.PAYMENT_SUPPLIER, idemKey, hash, id);
    }
    return id;
  })();

  const supplier = SupplierModel.getById(supplierId, db);
  logCRUD(ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created supplier payment - ${formatCurrency(amount, currency)} to ${supplier?.supplier_name || 'Unknown'}`, req.user!.id, { supplier_id: supplierId, amount, payment_method: paymentMethod, allocation_count: (poAllocations || []).length + (purchaseAllocations || []).length });
  req.activityLogged = true;

  res.status(201).json({ success: true, data: PaymentModel.getById(db, paymentId) });
}

function createPayment(req: AuthRequest, res: Response): void {
  try {
    const { customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, invoice_allocations, po_allocations, purchase_allocations } = req.body;

    // PAY-09 (task 2.2): XOR — exactly one counterparty. The old `||` guard
    // admitted both ids and then silently discarded the supplier.
    if (!!customer_id === !!supplier_id) {
      res.status(400).json({ success: false, error: 'Exactly one of customer_id or supplier_id is required' });
      return;
    }
    if (!payment_date || !amount || amount <= 0) {
      res.status(400).json({ success: false, error: 'Payment date and a positive amount are required' });
      return;
    }

    const parsedAmount = parseCurrency(amount);

    const idemKey = readIdempotencyKey(req, res);
    if (idemKey === undefined) return;

    const currency = getCurrencySymbol(db);

    if (customer_id) {
      createCustomerPayment(req, res, {
        customerId: parseInt(customer_id, 10),
        paymentDate: payment_date,
        amount: parsedAmount,
        paymentMethod: payment_method,
        referenceNo: reference_no,
        notes,
        invoiceAllocations: invoice_allocations,
        idemKey,
        currency,
      });
      return;
    }

    if (supplier_id) {
      createSupplierPayment(req, res, {
        supplierId: parseInt(supplier_id, 10),
        paymentDate: payment_date,
        amount: parsedAmount,
        paymentMethod: payment_method,
        referenceNo: reference_no,
        notes,
        poAllocations: po_allocations,
        purchaseAllocations: purchase_allocations,
        idemKey,
        currency,
      });
      return;
    }
  } catch (error) {
    if (error instanceof IdempotencyConflictError) {
      res.status(409).json({ success: false, error: error.message });
      return;
    }
    handleBusinessError(res, error, 'Create payment', 'Failed to create payment', { success: true });
  }
}

function updatePayment(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const { payment_date, amount, payment_method, reference_no, notes } = req.body;

    const existing = PaymentModel.getById(db, id);
    if (!existing) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }

    AccountingService.assertPeriodNotClosed(db, existing.payment_date, `Payment ${existing.payment_no}`);

    PaymentModel.update(db, id, { payment_date, amount, payment_method, reference_no, notes }, { userId: req.user?.id ?? null });

    logCRUD(ActionType.PAYMENT_UPDATE, 'Payment', id, `Updated payment: ${existing.payment_no}`, req.user!.id, { payment_no: existing.payment_no, changes: Object.keys(req.body).filter(k => req.body[k] !== undefined) });
    req.activityLogged = true;

    res.json({ success: true, message: 'Payment updated successfully' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to update payment';
    if (message === 'Payment not found') { res.status(404).json({ success: false, error: message }); return; }
    // PAY-04 (task 2.1): amount edits are a client error — explain the policy.
    if (message.includes('Cannot change the amount')) { res.status(400).json({ success: false, error: message }); return; }
    // CASH-02 (task 1.4): bad method on edit is a client error too.
    if (message.includes('Invalid payment_method')) { res.status(400).json({ success: false, error: message }); return; }
    // Closed period guard: editing history is forbidden, not a server failure.
    if (message.includes('inside closed accounting period')) { res.status(409).json({ success: false, error: message }); return; }
    handleBusinessError(res, error, 'Update payment', 'Failed to update payment', { success: true });
  }
}

function deletePayment(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    if (isNaN(id)) { res.status(400).json({ success: false, error: 'Invalid payment ID' }); return; }

    const existing = PaymentModel.getById(db, id);
    if (!existing) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }

    AccountingService.assertPeriodNotClosed(db, existing.payment_date, `Payment ${existing.payment_no}`);

    // C6 (reversal-rules): void with attribution — payments are never
    // hard-deleted once they have moved money.
    PaymentModel.void(db, id, req.user?.id ?? null, `Payment voided: ${existing.payment_no}`);

    logCRUD(ActionType.PAYMENT_DELETE, 'Payment', id, `Voided payment: ${existing.payment_no} - ${formatCurrency(Number(existing.amount), getCurrencySymbol(db))}`, req.user!.id, { payment_no: existing.payment_no, amount: existing.amount });
    req.activityLogged = true;

    res.json({ success: true, message: 'Payment voided successfully' });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    // Double-fire / stale-UI guard: an already-voided payment is a state
    // conflict, not a server failure (Phase 5 / TASK 24).
    if (message === 'Payment is already voided') {
      res.status(409).json({ success: false, error: message });
      return;
    }
    // Closed period guard: voiding history is forbidden, not a server failure.
    if (message.includes('inside closed accounting period')) { res.status(409).json({ success: false, error: message }); return; }
    handleBusinessError(res, error, 'Delete payment', 'Failed to delete payment', { success: true });
  }
}

function receiptContact(entity: { entity_address: string; entity_phone: string; entity_email: string }) {
  return { entityAddress: entity.entity_address || '', entityPhone: entity.entity_phone || '', entityEmail: entity.entity_email || '' };
}

function receiptCompany() {
  const settingsRows = db.prepare("SELECT key, value FROM settings WHERE key IN ('company_name','company_address','company_phone','company_email','company_tax_id')").all() as { key: string; value: string }[];
  const company: Record<string, string> = {};
  for (const row of settingsRows) {
    company[row.key.replace('company_', '')] = row.value;
  }

  return {
    name: company.name || 'Mini ERP',
    address: company.address || '',
    phone: company.phone || '',
    email: company.email || '',
    tax_id: company.tax_id || '',
  };
}

function getPaymentReceipt(req: Request, res: Response): void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const payment = PaymentModel.getById(db, id);
    if (!payment) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }

    let entityName: string = '';
    let entityAddress = '';
    let entityPhone = '';
    let entityEmail = '';
    let currentBalance = 0;
    let previousBalance = 0;
    let allocations: Array<{ invoice_id: number; invoice_no: string; amount: number }> = [];
    let entityType: 'customer' | 'supplier' = 'customer';

    if (payment.customer_id) {
      entityType = 'customer';
      const customer = db.prepare(`
        SELECT id, customer_name, billing_address as entity_address, phone as entity_phone, email as entity_email, current_balance
        FROM customers WHERE id = ?
      `).get(payment.customer_id) as {
        id: number; customer_name: string; entity_address: string;
        entity_phone: string; entity_email: string; current_balance: number;
      } | undefined;

      if (!customer) { res.status(404).json({ success: false, error: 'Customer not found' }); return; }

      entityName = customer.customer_name;
      ({ entityAddress, entityPhone, entityEmail } = receiptContact(customer));
      currentBalance = parseCurrency(customer.current_balance);
      // PAY-11 (task 2.6): previous balance comes from the payment's own
      // ledger row — today's balance is polluted by everything since.
      const ownRow = db.prepare(`
        SELECT debit, credit, balance FROM customer_ledger
        WHERE reference_no = ? AND transaction_type = 'PAYMENT' AND customer_id = ? AND voided = 0
        ORDER BY id DESC LIMIT 1
      `).get(payment.payment_no, payment.customer_id) as { debit: number; credit: number; balance: number } | undefined;
      previousBalance = ownRow
        ? parseCurrency(parseCurrency(ownRow.balance) + parseCurrency(ownRow.credit) - parseCurrency(ownRow.debit))
        : parseCurrency(currentBalance + parseCurrency(payment.amount)); // legacy fallback

      allocations = db.prepare(`
        SELECT pa.invoice_id, i.invoice_no, pa.amount
        FROM payment_allocations pa
        LEFT JOIN invoices i ON pa.invoice_id = i.id
        WHERE pa.payment_id = ? AND pa.voided_at IS NULL
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
    } else if (payment.supplier_id) {
      entityType = 'supplier';
      const supplier = db.prepare(`
        SELECT id, supplier_name, address as entity_address, phone as entity_phone, email as entity_email, current_balance
        FROM suppliers WHERE id = ?
      `).get(payment.supplier_id) as {
        id: number; supplier_name: string; entity_address: string;
        entity_phone: string; entity_email: string; current_balance: number;
      } | undefined;

      if (!supplier) { res.status(404).json({ success: false, error: 'Supplier not found' }); return; }

      entityName = supplier.supplier_name;
      ({ entityAddress, entityPhone, entityEmail } = receiptContact(supplier));
      currentBalance = parseCurrency(supplier.current_balance);
      // PAY-11 (task 2.6): supplier sign convention — debit increases what
      // we owe, credit (a payment) decreases it.
      const supOwnRow = db.prepare(`
        SELECT debit, credit, balance FROM supplier_ledger
        WHERE reference_no = ? AND transaction_type = 'PAYMENT' AND supplier_id = ? AND voided = 0
        ORDER BY id DESC LIMIT 1
      `).get(payment.payment_no, payment.supplier_id) as { debit: number; credit: number; balance: number } | undefined;
      previousBalance = supOwnRow
        ? parseCurrency(parseCurrency(supOwnRow.balance) + parseCurrency(supOwnRow.debit) - parseCurrency(supOwnRow.credit))
        : parseCurrency(currentBalance + parseCurrency(payment.amount)); // legacy fallback

      const poRows = db.prepare(`
        SELECT pa.po_id as invoice_id, po.po_no as invoice_no, pa.amount
        FROM po_allocations pa
        LEFT JOIN purchase_orders po ON pa.po_id = po.id
        WHERE pa.payment_id = ? AND pa.voided_at IS NULL
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
      const purchaseRows = db.prepare(`
        SELECT pa.purchase_id as invoice_id, p.purchase_no as invoice_no, pa.amount
        FROM purchase_allocations pa
        LEFT JOIN purchases p ON pa.purchase_id = p.id
        WHERE pa.payment_id = ? AND pa.voided_at IS NULL
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
      allocations = [...poRows, ...purchaseRows];
    }

    const amount = parseCurrency(payment.amount);

    const company = receiptCompany();

    res.json({
      success: true,
      data: {
        payment: {
          id: payment.id,
          payment_no: payment.payment_no,
          payment_date: payment.payment_date,
          amount,
          payment_method: payment.payment_method,
          reference_no: payment.reference_no || '',
          notes: payment.notes || '',
          created_at: payment.created_at,
        },
        [entityType]: {
          name: entityName,
          address: entityAddress,
          phone: entityPhone,
          email: entityEmail,
        },
        balance: {
          previous_balance: previousBalance,
          payment_amount: amount,
          current_balance: currentBalance,
        },
        allocations,
        company,
      },
    });
  } catch (error) {
    logger.error('Error fetching payment receipt:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch receipt data' });
  }
}

function invalidAllocationInvoice(allocations: Array<{ invoice_id: number | string }>): string | null {
  for (const alloc of allocations) {
    if (isNaN(parseInt(alloc.invoice_id as string, 10))) return `Invalid invoice ID: ${alloc.invoice_id}`;
  }
  return null;
}

function allocatePaymentToInvoice(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    if (isNaN(id)) { res.status(400).json({ success: false, error: 'Invalid payment ID' }); return; }

    const { allocations } = req.body as { allocations?: Array<{ invoice_id: number | string; amount: number | string }> };
    if (!allocations || !Array.isArray(allocations) || allocations.length === 0) {
      res.status(400).json({ success: false, error: 'At least one allocation is required' });
      return;
    }

    const payment = PaymentModel.getById(db, id);
    if (!payment) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }
    if (!payment.customer_id) {
      res.status(400).json({ success: false, error: 'Manual invoice allocation applies to customer payments only' });
      return;
    }

    const allocationError = invalidAllocationInvoice(allocations);
    if (allocationError) { res.status(400).json({ success: false, error: allocationError }); return; }

    // TASK 33: the per-invoice ceiling, the remainder match and the
    // allocation writes belong to the single payment writer, so this path
    // validates identically to an up-front allocation.
    const allocatedTotal = parseCurrency(payment.amount) - parseCurrency(
      (db.prepare(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations WHERE payment_id = ? AND voided_at IS NULL'
      ).get(id) as { total: number }).total,
    );

    const idemKey = readIdempotencyKey(req, res);
    if (idemKey === undefined) return;
    const claim = idemKey
      ? { scope: IDEMPOTENCY_SCOPES.PAYMENT_ALLOCATE, key: idemKey, hash: hashRequestPayload({ id, allocations }) }
      : undefined;

    if (claim) {
      const { replayId } = beginIdempotentWrite(db, claim.scope, claim.key, claim.hash);
      if (replayId !== null) {
        res.set('X-Idempotent-Replay', 'true');
        res.json({
          success: true,
          message: 'Allocation recorded',
          data: PaymentModel.getById(db, replayId),
        });
        return;
      }
    }

    new PaymentRecordingService(db).allocateExistingPayment({
      paymentId: id,
      customerId: Number(payment.customer_id),
      allocations: allocations.map((alloc) => ({
        invoiceId: parseInt(alloc.invoice_id as string, 10),
        amount: parseCurrency(alloc.amount),
      })),
      idempotency: claim,
    });

    const newTotal = parseCurrency(payment.amount) - allocatedTotal;

    logCRUD(ActionType.PAYMENT_UPDATE, 'Payment', id, `Allocated ${newTotal.toFixed(2)} of ${payment.payment_no} across ${allocations.length} invoice(s)`, req.user!.id, { payment_no: payment.payment_no, allocated: newTotal });
    req.activityLogged = true;

    res.json({ success: true, message: 'Allocation recorded', data: PaymentModel.getById(db, id) });
  } catch (error) {
    if (error instanceof IdempotencyConflictError) {
      res.status(409).json({ success: false, error: error.message });
      return;
    }
    handleBusinessError(res, error, 'Allocate payment', 'Failed to allocate payment', { success: true });
  }
}

export default {
  getPayments, getUnifiedPayments, getPayment, createPayment, updatePayment, deletePayment, getPaymentReceipt, allocatePaymentToInvoice,
};
