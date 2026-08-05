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
    const { customer_id, supplier_id, payment_date, amount, payment_method, reference_no, notes, invoice_allocations, po_allocations } = req.body;

    if ((!customer_id && !supplier_id) || !payment_date || !amount || amount <= 0) {
      res.status(400).json({ success: false, error: 'Customer ID or Supplier ID, payment date, and amount are required' });
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
      if (!po_allocations || !Array.isArray(po_allocations) || po_allocations.length === 0) {
        res.status(400).json({ success: false, error: 'At least one PO allocation is required for supplier payments' });
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
        po_allocations,
        userId: req.user!.id,
      });

      const supplier = SupplierModel.getById(parsedSupplierId, db);
      logCRUD(ActionType.PAYMENT_CREATE, 'Payment', paymentId, `Created supplier payment - $${parsedAmount} to ${supplier?.supplier_name || 'Unknown'}`, req.user!.id, { supplier_id: parsedSupplierId, amount: parsedAmount, payment_method, po_allocations: po_allocations.length });
      req.activityLogged = true;

      res.status(201).json({ success: true, data: PaymentModel.getById(db, paymentId) });
      return;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    logger.error('Error creating payment:', error);
    res.status(500).json({ success: false, error: message || 'Failed to create payment' });
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
      previousBalance = parseCurrency(currentBalance + parseCurrency(payment.amount));

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
      previousBalance = parseCurrency(currentBalance + parseCurrency(payment.amount));

      allocations = db.prepare(`
        SELECT pa.po_id as invoice_id, po.po_no as invoice_no, pa.amount
        FROM po_allocations pa
        LEFT JOIN purchase_orders po ON pa.po_id = po.id
        WHERE pa.payment_id = ?
        ORDER BY pa.id
      `).all(id) as { invoice_id: number; invoice_no: string; amount: number }[];
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

function allocatePaymentToInvoice(req: Request, res: Response): void {
  res.status(501).json({ success: false, error: 'Manual allocation endpoint not implemented - use createPayment with allocations instead' });
}

export default {
  getPayments, getPayment, createPayment, updatePayment, deletePayment, getPaymentReceipt, allocatePaymentToInvoice,
};

