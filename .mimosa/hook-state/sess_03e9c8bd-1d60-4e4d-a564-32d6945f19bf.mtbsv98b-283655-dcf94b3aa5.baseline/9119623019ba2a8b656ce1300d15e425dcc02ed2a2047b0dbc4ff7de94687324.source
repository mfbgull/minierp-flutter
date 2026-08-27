import { Request, Response } from 'express';
import { getQueryParam } from '../utils/queryUtils';
import { AuthRequest } from '../types';
import { logCRUD, ActionType } from '../services/activityLogger';
import db from '../config/database';
import { getRouteParam } from '../utils/queryUtils';
import { PAYMENT_SORT_COLUMNS } from '../utils/sqlSanitizer';
import logger from '../utils/logger';
import { parseCurrency } from '../utils/currency';
import PaymentModel from '../models/Payment';
import CustomerModel from '../models/Customer';
import ledgerUtils from '../utils/ledgerUtils';
import InvoiceModel from '../models/Invoice';
import SupplierModel from '../models/Supplier';

function getPayments(req: Request, res: Response): void {
  try {
    const pageParam = getQueryParam(req.query.page);
    const limitParam = getQueryParam(req.query.limit);
    const searchParam = getQueryParam(req.query.search);
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
      pagination: { currentPage: pageNum, totalPages: Math.ceil(total / limitNum), totalItems: total, hasNext: pageNum < Math.ceil(total / limitNum), hasPrev: pageNum > 1 }
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
      pagination: { currentPage: pageNum, totalPages: Math.ceil(total / limitNum), totalItems: total, hasNext: pageNum < Math.ceil(total / limitNum), hasPrev: pageNum > 1 }
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

    if (customer_id) {
      const parsedCustomerId = parseInt(customer_id, 10);
      if (!invoice_allocations || !Array.isArray(invoice_allocations) || invoice_allocations.length === 0) {
        res.status(400).json({ success: false, error: 'At least one invoice allocation is required for customer payments' });
        return;
      }

      if (!CustomerModel.getById(parsedCustomerId, db)) {
        res.status(404).json({ success: false, error: 'Customer not found' });
        return;
      }

      for (const alloc of invoice_allocations) {
        const parsedInvoiceId = parseInt(alloc.invoice_id, 10);
        if (isNaN(parsedInvoiceId)) {
          res.status(400).json({ success: false, error: `Invalid invoice ID: ${alloc.invoice_id}` });
          return;
        }

        const invoice = InvoiceModel.getById(parsedInvoiceId, db);
        if (!invoice) {
          res.status(404).json({ success: false, error: `Invoice ${parsedInvoiceId} not found` });
          return;
        }

        if (Number(invoice.customer_id) !== Number(parsedCustomerId)) {
          res.status(400).json({ success: false, error: `Invoice ${parsedInvoiceId} does not belong to customer ${parsedCustomerId}` });
          return;
        }

        if (parseCurrency(alloc.amount) <= 0) {
          res.status(400).json({ success: false, error: `Allocation amount for invoice ${alloc.invoice_id} must be greater than 0` });
          return;
        }

        if (parseCurrency(alloc.amount) > parseCurrency(invoice.balance_amount)) {
          res.status(400).json({
            success: false,
            error: `Allocation amount (${parseCurrency(alloc.amount).toFixed(2)}) for invoice ${alloc.invoice_id} exceeds the remaining balance (${parseCurrency(invoice.balance_amount).toFixed(2)})`
          });
          return;
        }
      }

      const totalAllocated = invoice_allocations.reduce((sum: number, alloc: any) => sum + parseCurrency(alloc.amount), 0);
      if (Math.abs(totalAllocated - parsedAmount) > 0.01) {
        res.status(400).json({ success: false, error: `Payment amount (${parsedAmount.toFixed(2)}) does not match total allocated amount (${totalAllocated.toFixed(2)})` });
        return;
      }

      const paymentId = PaymentModel.create(db, {
        customer_id: parsedCustomerId, payment_date, amount: parsedAmount, payment_method, reference_no, notes, invoice_allocations,
        userId: req.user!.id,
      });

      const customer = CustomerModel.getById(parsedCustomerId, db);
      logCRUD(ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created payment - $${parsedAmount} from ${customer?.customer_name || 'Unknown'}`, req.user!.id, { customer_id: parsedCustomerId, amount: parsedAmount, payment_method, invoice_allocations: invoice_allocations.length });
      req.activityLogged = true;

      res.status(201).json({ success: true, data: PaymentModel.getById(db, paymentId) });
      return;
    }

    if (supplier_id) {
      const parsedSupplierId = parseInt(supplier_id, 10);
      const hasPoAllocs = po_allocations && Array.isArray(po_allocations) && po_allocations.length > 0;
      const hasPurchaseAllocs = purchase_allocations && Array.isArray(purchase_allocations) && purchase_allocations.length > 0;
      if (!hasPoAllocs && !hasPurchaseAllocs) {
        res.status(400).json({ success: false, error: 'At least one PO or purchase allocation is required for supplier payments' });
        return;
      }

      if (!SupplierModel.getById(parsedSupplierId, db)) {
        res.status(404).json({ success: false, error: 'Supplier not found' });
        return;
      }

      const paymentId = PaymentModel.createSupplierPayment(db, {
        supplier_id: parsedSupplierId,
        payment_date,
        amount: parsedAmount,
        payment_method,
        reference_no,
        notes,
        po_allocations: hasPoAllocs ? po_allocations : [],
        purchase_allocations: hasPurchaseAllocs ? purchase_allocations : [],
        userId: req.user!.id,
      });

      const supplier = SupplierModel.getById(parsedSupplierId, db);
      logCRUD(ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created supplier payment - $${parsedAmount} to ${supplier?.supplier_name || 'Unknown'}`, req.user!.id, { supplier_id: parsedSupplierId, amount: parsedAmount, payment_method, allocation_count: (po_allocations || []).length + (purchase_allocations || []).length });
      req.activityLogged = true;

      res.status(201).json({ success: true, data: PaymentModel.getById(db, paymentId) });
      return;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    logger.error('Error creating payment:', error);
    const isClientError = message.includes('not allowed') || message.includes('required') || message.includes('Invalid');
    res.status(isClientError ? 400 : 500).json({ success: false, error: message || 'Failed to create payment' });
  }
}

function updatePayment(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(Array.isArray(req.params.id) ? req.params.id[0] : req.params.id, 10);
    const { payment_date, amount, payment_method, reference_no, notes } = req.body;

    const existing = PaymentModel.getById(db, id);
    if (!existing) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }

    PaymentModel.update(db, id, { payment_date, amount, payment_method, reference_no, notes });

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
    logger.error('Error updating payment:', error);
    res.status(500).json({ success: false, error: 'Failed to update payment' });
  }
}

function deletePayment(req: AuthRequest, res: Response): void {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    if (isNaN(id)) { res.status(400).json({ success: false, error: 'Invalid payment ID' }); return; }

    const existing = PaymentModel.getById(db, id);
    if (!existing) { res.status(404).json({ success: false, error: 'Payment not found' }); return; }

    PaymentModel.delete(db, id);

    logCRUD(ActionType.PAYMENT_DELETE, 'Payment', id, `Deleted payment: ${existing.payment_no} - $${existing.amount}`, req.user!.id, { payment_no: existing.payment_no, amount: existing.amount });
    req.activityLogged = true;

    res.json({ success: true, message: 'Payment deleted successfully' });
  } catch (error) {
    logger.error('Error deleting payment:', error);
    res.status(500).json({ success: false, error: 'Failed to delete payment' });
  }
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
      entityAddress = customer.entity_address || '';
      entityPhone = customer.entity_phone || '';
      entityEmail = customer.entity_email || '';
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
        WHERE pa.payment_id = ?
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
      entityAddress = supplier.entity_address || '';
      entityPhone = supplier.entity_phone || '';
      entityEmail = supplier.entity_email || '';
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
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
      const purchaseRows = db.prepare(`
        SELECT pa.purchase_id as invoice_id, p.purchase_no as invoice_no, pa.amount
        FROM purchase_allocations pa
        LEFT JOIN purchases p ON pa.purchase_id = p.id
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
      allocations = [...poRows, ...purchaseRows];
    }

    const amount = parseCurrency(payment.amount);

    const settingsRows = db.prepare("SELECT key, value FROM settings WHERE key IN ('company_name','company_address','company_phone','company_email','company_tax_id')").all() as { key: string; value: string }[];
    const company: Record<string, string> = {};
    for (const row of settingsRows) {
      company[row.key.replace('company_', '')] = row.value;
    }

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
        company: {
          name: company.name || 'Mini ERP',
          address: company.address || '',
          phone: company.phone || '',
          email: company.email || '',
          tax_id: company.tax_id || '',
        },
      },
    });
  } catch (error) {
    logger.error('Error fetching payment receipt:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch receipt data' });
  }
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

    const paymentAmount = parseCurrency(payment.amount);

    // Currently allocated total for THIS payment.
    const currentRows = db.prepare(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations WHERE payment_id = ?'
    ).get(id) as { total: number };
    const currentlyAllocated = parseCurrency(currentRows.total);
    const unallocated = paymentAmount - currentlyAllocated;

    let newTotal = 0;
    for (const alloc of allocations) {
      const parsedInvoiceId = parseInt(alloc.invoice_id as string, 10);
      if (isNaN(parsedInvoiceId)) {
        res.status(400).json({ success: false, error: `Invalid invoice ID: ${alloc.invoice_id}` });
        return;
      }
      const amount = parseCurrency(alloc.amount);
      if (amount <= 0) {
        res.status(400).json({ success: false, error: `Allocation amount for invoice ${parsedInvoiceId} must be greater than 0` });
        return;
      }
      const invoice = InvoiceModel.getById(parsedInvoiceId, db);
      if (!invoice) {
        res.status(404).json({ success: false, error: `Invoice ${parsedInvoiceId} not found` });
        return;
      }
      if (Number(invoice.customer_id) !== Number(payment.customer_id)) {
        res.status(400).json({ success: false, error: `Invoice ${parsedInvoiceId} does not belong to this payment's customer` });
        return;
      }
      if (amount > parseCurrency(invoice.balance_amount) + 0.01) {
        res.status(400).json({
          success: false,
          error: `Allocation (${amount.toFixed(2)}) exceeds invoice ${parsedInvoiceId} balance (${parseCurrency(invoice.balance_amount).toFixed(2)})`,
        });
        return;
      }
      newTotal += amount;
    }

    if (Math.abs(newTotal - unallocated) > 0.01) {
      res.status(400).json({
        success: false,
        error: `Allocations total (${newTotal.toFixed(2)}) must equal the unallocated remainder (${unallocated.toFixed(2)})`,
      });
      return;
    }

    db.transaction(() => {
      const insert = db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)');
      for (const alloc of allocations) {
        insert.run(id, parseInt(alloc.invoice_id as string, 10), parseCurrency(alloc.amount));
      }
      for (const alloc of allocations) {
        const invoiceId = parseInt(alloc.invoice_id as string, 10);
        ledgerUtils.calculateInvoiceBalance(invoiceId);
        ledgerUtils.updateInvoiceStatus(invoiceId);
      }
    })();

    logCRUD(ActionType.PAYMENT_UPDATE, 'Payment', id, `Allocated ${newTotal.toFixed(2)} of ${payment.payment_no} across ${allocations.length} invoice(s)`, req.user!.id, { payment_no: payment.payment_no, allocated: newTotal });
    req.activityLogged = true;

    res.json({ success: true, message: 'Allocation recorded', data: PaymentModel.getById(db, id) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to allocate payment';
    logger.error('Error allocating payment:', error);
    res.status(500).json({ success: false, error: message });
  }
}

export default {
  getPayments, getUnifiedPayments, getPayment, createPayment, updatePayment, deletePayment, getPaymentReceipt, allocatePaymentToInvoice,
};

