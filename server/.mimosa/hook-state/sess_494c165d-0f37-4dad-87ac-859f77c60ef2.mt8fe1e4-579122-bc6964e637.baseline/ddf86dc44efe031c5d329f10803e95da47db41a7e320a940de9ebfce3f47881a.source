import { Response } from 'express';
import { AuthRequest } from '../types';
import db from '../config/database';
import { getRouteParam } from '../utils/queryUtils';
import logger from '../utils/logger';
import MobileInvoiceModel from '../models/MobileInvoice';
import { getQueryParam } from '../utils/queryUtils';

export async function createDraft(req: AuthRequest, res: Response) {
  try {
    const { session_id, customer_id, invoice_date, due_date, terms, notes, items_data } = req.body;
    const { randomUUID } = await import('crypto');
    const finalSessionId = session_id || `mobile_${Date.now()}_${randomUUID().replace(/-/g, '').slice(0, 9)}`;

    const existingDraft = MobileInvoiceModel.getDraftBySession(db, finalSessionId);

    if (existingDraft) {
      MobileInvoiceModel.updateDraft(db, existingDraft.id, { customer_id, invoice_date, due_date, terms, notes, items_data });
      return res.json({ success: true, data: { id: existingDraft.id, session_id: finalSessionId }, message: 'Draft updated successfully' });
    }

    const id = MobileInvoiceModel.createDraft(db, { customer_id, invoice_date, due_date, terms, notes, items_data }, finalSessionId);
    res.status(201).json({ success: true, data: { id, session_id: finalSessionId }, message: 'Draft created successfully' });
  } catch (error) {
    logger.error('Create draft error:', error);
    res.status(500).json({ error: 'Failed to create draft' });
  }
}

export async function updateDraft(req: AuthRequest, res: Response) {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const { customer_id, invoice_date, due_date, terms, notes, items_data, status } = req.body;

    const draft = MobileInvoiceModel.getDraftById(db, id);
    if (!draft) { return res.status(404).json({ error: 'Draft not found' }); }

    if (new Date(draft.expires_at) < new Date()) { return res.status(410).json({ error: 'Draft has expired' }); }

    MobileInvoiceModel.updateDraft(db, id, { customer_id, invoice_date, due_date, terms, notes, items_data, status });
    res.json({ success: true, message: 'Draft updated successfully' });
  } catch (error) {
    logger.error('Update draft error:', error);
    res.status(500).json({ error: 'Failed to update draft' });
  }
}

export async function getDraft(req: AuthRequest, res: Response) {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const draft = MobileInvoiceModel.getDraftById(db, id);
    if (!draft) { return res.status(404).json({ error: 'Draft not found' }); }
    if (new Date(draft.expires_at) < new Date()) { return res.status(410).json({ error: 'Draft has expired' }); }

    const parsedDraft = { ...draft, items_data: draft.items_data ? JSON.parse(draft.items_data) : [] };
    res.json({ success: true, data: parsedDraft });
  } catch (error) {
    logger.error('Get draft error:', error);
    res.status(500).json({ error: 'Failed to get draft' });
  }
}

export async function deleteDraft(req: AuthRequest, res: Response) {
  try {
    const id = parseInt(getRouteParam(req.params.id), 10);
    const deleted = MobileInvoiceModel.deleteDraft(db, id);
    if (!deleted) { return res.status(404).json({ error: 'Draft not found' }); }
    res.json({ success: true, message: 'Draft deleted successfully' });
  } catch (error) {
    logger.error('Delete draft error:', error);
    res.status(500).json({ error: 'Failed to delete draft' });
  }
}

export async function searchItems(req: AuthRequest, res: Response) {
  try {
    const qParam = getQueryParam(req.query.q);
    const limitParam = getQueryParam(req.query.limit);
    const q = qParam || '';
    const limit = parseInt(limitParam as string || '20', 10);

    const items = MobileInvoiceModel.searchItems(db, q as string, limit);
    res.json({ success: true, data: items, count: (items as []).length });
  } catch (error) {
    logger.error('Search items error:', error);
    res.status(500).json({ error: 'Failed to search items' });
  }
}

export async function searchCustomers(req: AuthRequest, res: Response) {
  try {
    const qParam = getQueryParam(req.query.q);
    const limitParam = getQueryParam(req.query.limit);
    const q = qParam || '';
    const limit = parseInt(limitParam as string || '20', 10);

    const customers = MobileInvoiceModel.searchCustomers(db, q as string, limit);
    res.json({ success: true, data: customers, count: (customers as []).length });
  } catch (error) {
    logger.error('Search customers error:', error);
    res.status(500).json({ error: 'Failed to search customers' });
  }
}

export async function getTaxRates(req: AuthRequest, res: Response) {
  try {
    const taxRates = MobileInvoiceModel.getTaxRates(db);
    res.json({ success: true, data: taxRates });
  } catch (error) {
    logger.error('Get tax rates error:', error);
    res.status(500).json({ error: 'Failed to get tax rates' });
  }
}

export async function getPaymentTerms(req: AuthRequest, res: Response) {
  try {
    const paymentTerms = MobileInvoiceModel.getPaymentTerms(db);
    res.json({ success: true, data: paymentTerms });
  } catch (error) {
    logger.error('Get payment terms error:', error);
    res.status(500).json({ error: 'Failed to get payment terms' });
  }
}

export async function submitInvoice(req: AuthRequest, res: Response) {
  try {
    const { draft_id, invoice_no, customer_id, invoice_date, due_date, status, terms, notes, items, record_payment, payment } = req.body;

    if (!customer_id) { return res.status(400).json({ error: 'Customer is required', field: 'customer_id' }); }
    if (!invoice_date) { return res.status(400).json({ error: 'Invoice date is required', field: 'invoice_date' }); }
    if (!items || items.length === 0) { return res.status(400).json({ error: 'At least one item is required', field: 'items' }); }

    const invoiceId = MobileInvoiceModel.submitInvoice(db, {
      draft_id: draft_id ? parseInt(draft_id, 10) : undefined,
      invoice_no, customer_id, invoice_date, due_date, status, terms, notes, items, record_payment, payment,
      userId: req.user!.id,
    });

    const createdInvoice = MobileInvoiceModel.getInvoiceWithCustomer(db, invoiceId);
    res.status(201).json({ success: true, data: createdInvoice, message: 'Invoice created successfully' });
  } catch (error) {
    logger.error('Submit invoice error:', error);
    res.status(500).json({ success: false, error: 'Failed to create invoice' });
  }
}

export default {
  createDraft,
  updateDraft,
  getDraft,
  deleteDraft,
  searchItems,
  searchCustomers,
  getTaxRates,
  getPaymentTerms,
  submitInvoice,
};
