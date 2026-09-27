import Database from 'better-sqlite3';
import { MOBILE_INVOICE_CREATE_SCOPE } from '../utils/idempotency';
import { InvoiceCreationService } from '../services/InvoiceCreationService';

interface DraftRecord {
  id: number;
  session_id: string;
  customer_id: number | null;
  invoice_date: string | null;
  due_date: string | null;
  terms: string | null;
  notes: string | null;
  items_data: string | null;
  status: string;
  expires_at: string;
  created_at: string;
  updated_at: string;
}

interface DraftDTO {
  session_id?: string;
  customer_id?: number;
  invoice_date?: string;
  due_date?: string;
  terms?: string;
  notes?: string;
  items_data?: unknown;
  status?: string;
}

interface InvoiceItemDTO {
  item_id: number;
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: string;
  discount_value?: number;
  warehouse_id?: number;
}

interface PaymentDTO {
  amount: number;
  payment_date?: string;
  payment_method?: string;
  reference_no?: string;
  notes?: string;
}

interface SubmitInvoiceDTO {
  draft_id?: number;
  invoice_no?: string;
  customer_id: number;
  invoice_date: string;
  due_date?: string;
  status?: string;
  terms?: string;
  notes?: string;
  items: InvoiceItemDTO[];
  record_payment?: boolean;
  payment?: PaymentDTO;
  userId: number;
  /** P11: claim the key inside this transaction so the (key → invoice)
   * row persists if and only if the submit commits. */
  idempotency?: { key: string; hash: string };
}

function getDraftById(db: Database.Database, id: number): DraftRecord | undefined {
  return db.prepare('SELECT * FROM invoice_drafts WHERE id = ?').get(id) as DraftRecord | undefined;
}

function getDraftBySession(db: Database.Database, sessionId: string): DraftRecord | undefined {
  return db.prepare(`
    SELECT * FROM invoice_drafts
    WHERE session_id = ? AND status = 'draft' AND expires_at > datetime('now')
  `).get(sessionId) as DraftRecord | undefined;
}

function createDraft(db: Database.Database, data: DraftDTO, sessionId: string): number {
  const result = db.prepare(`
    INSERT INTO invoice_drafts (
      session_id, customer_id, invoice_date, due_date,
      terms, notes, items_data, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'draft')
  `).run(
    sessionId,
    data.customer_id || null,
    data.invoice_date || null,
    data.due_date || null,
    data.terms || null,
    data.notes || null,
    data.items_data ? JSON.stringify(data.items_data) : null
  );
  return result.lastInsertRowid as number;
}

function updateDraft(db: Database.Database, id: number, data: DraftDTO): void {
  db.prepare(`
    UPDATE invoice_drafts
    SET customer_id = ?, invoice_date = ?, due_date = ?,
        terms = ?, notes = ?, items_data = ?, status = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `).run(
    data.customer_id || null,
    data.invoice_date || null,
    data.due_date || null,
    data.terms || null,
    data.notes || null,
    data.items_data ? JSON.stringify(data.items_data) : null,
    data.status || 'draft',
    id
  );
}

function deleteDraft(db: Database.Database, id: number): boolean {
  const result = db.prepare('DELETE FROM invoice_drafts WHERE id = ?').run(id);
  return (result.changes as number) > 0;
}

function searchItems(db: Database.Database, q: string, limit: number) {
  let query = `
    SELECT id, item_code, item_name, description, category, unit_of_measure,
           current_stock, standard_selling_price as price, standard_cost as cost,
           is_raw_material, is_finished_good, is_purchased
    FROM items WHERE is_active = 1
  `;
  const params: (string | number)[] = [];

  if (q && q.trim().length > 0) {
    const term = `%${q.trim()}%`;
    query += ` AND (item_name LIKE ? OR item_code LIKE ? OR description LIKE ?)`;
    params.push(term, term, term);
  }

  query += ` AND (is_finished_good = 1 OR is_purchased = 1) AND is_raw_material = 0`;
  query += ` ORDER BY item_name ASC LIMIT ?`;
  params.push(limit);

  return db.prepare(query).all(...params);
}

function searchCustomers(db: Database.Database, q: string, limit: number) {
  let query = `
    SELECT id, customer_code, customer_name, contact_person, email, phone,
           billing_address, payment_terms, is_active
    FROM customers WHERE is_active = 1
  `;
  const params: (string | number)[] = [];

  if (q && q.trim().length > 0) {
    const term = `%${q.trim()}%`;
    query += ` AND (customer_name LIKE ? OR customer_code LIKE ? OR phone LIKE ? OR email LIKE ?)`;
    params.push(term, term, term, term);
  }

  query += ` ORDER BY customer_name ASC LIMIT ?`;
  params.push(limit);

  return db.prepare(query).all(...params);
}

function getTaxRates(db: Database.Database) {
  return db.prepare(`
    SELECT id, name, rate, is_default FROM tax_rates WHERE is_active = 1 ORDER BY rate ASC
  `).all();
}

function getPaymentTerms(db: Database.Database) {
  return db.prepare(`
    SELECT id, name, days, is_default FROM payment_terms WHERE is_active = 1 ORDER BY days ASC
  `).all();
}

function toInvoiceStatus(value: string | undefined): 'Draft' | 'Sent' | 'Unpaid' | 'Partially Paid' | 'Paid' | 'Overdue' | 'Cancelled' | 'Returned' | 'Partially Returned' | undefined {
  switch (value) {
    case 'Draft':
    case 'Sent':
    case 'Unpaid':
    case 'Partially Paid':
    case 'Paid':
    case 'Overdue':
    case 'Cancelled':
    case 'Returned':
    case 'Partially Returned':
      return value;
    default:
      return undefined;
  }
}

function submitInvoice(db: Database.Database, data: SubmitInvoiceDTO): number {
  const service = new InvoiceCreationService(db);
  const result = service.create({
    source: 'MOBILE',
    userId: data.userId,
    customerId: data.customer_id,
    invoiceNo: data.invoice_no,
    invoiceDate: data.invoice_date,
    dueDate: data.due_date,
    status: toInvoiceStatus(data.status),
    notes: data.notes,
    terms: data.terms,
    items: data.items.map((item) => ({
      item_id: item.item_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      tax_rate: item.tax_rate,
      discount_type: item.discount_type === 'flat' ? 'flat' : item.discount_type === 'percentage' ? 'percentage' : 'none',
      discount_value: item.discount_value,
      warehouse_id: item.warehouse_id,
    })),
    recordPayment: data.record_payment,
    payment: data.payment,
    draftId: data.draft_id,
    idempotency: data.idempotency
      ? { scope: MOBILE_INVOICE_CREATE_SCOPE, key: data.idempotency.key, hash: data.idempotency.hash }
      : undefined,
  });
  return result.invoiceId;
}

function getInvoiceWithCustomer(db: Database.Database, invoiceId: number) {
  return db.prepare(`
    SELECT i.*, c.customer_name, c.email as customer_email,
           c.phone as customer_phone, c.billing_address as customer_address
    FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id
    WHERE i.id = ?
  `).get(invoiceId);
}


export default {
  getDraftById,
  getDraftBySession,
  createDraft,
  updateDraft,
  deleteDraft,
  searchItems,
  searchCustomers,
  getTaxRates,
  getPaymentTerms,
  submitInvoice,
  getInvoiceWithCustomer,
};
