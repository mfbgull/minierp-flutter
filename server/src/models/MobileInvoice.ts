import Database from 'better-sqlite3';
import StockMovementModel from './StockMovement';
import { initializeSequenceFromMax, getNextSequenceNumber } from '../utils/sequence';
import ledgerUtils from '../utils/ledgerUtils';

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

function findWarehouseForItem(db: Database.Database, itemId: number, quantity: number): number {
  const balance = db.prepare(`
    SELECT warehouse_id, quantity FROM stock_balances
    WHERE item_id = ? AND quantity >= ? ORDER BY quantity DESC LIMIT 1
  `).get(itemId, quantity) as { warehouse_id: number; quantity: number } | undefined;

  if (balance?.warehouse_id) return balance.warehouse_id;

  const anyBalance = db.prepare(`
    SELECT warehouse_id, quantity FROM stock_balances
    WHERE item_id = ? AND quantity > 0 ORDER BY quantity DESC LIMIT 1
  `).get(itemId) as { warehouse_id: number; quantity: number } | undefined;

  if (anyBalance?.warehouse_id) return anyBalance.warehouse_id;

  const defaultWh = db.prepare(
    'SELECT id FROM warehouses WHERE warehouse_code = ? AND is_active = 1'
  ).get('WH-001') as { id: number } | undefined;

  return defaultWh?.id || 1;
}

function submitInvoice(db: Database.Database, data: SubmitInvoiceDTO): number {
  if (!data.customer_id || data.customer_id <= 0) throw new Error('Invalid customer_id');
  if (!data.invoice_date) throw new Error('invoice_date is required');
  if (!data.items || data.items.length === 0) throw new Error('At least one invoice item is required');
  for (const item of data.items) {
    if (!item.item_id || item.item_id <= 0) throw new Error('Invalid item_id in invoice items');
    if (!item.quantity || item.quantity <= 0) throw new Error('Invalid quantity in invoice items');
    if (item.unit_price === undefined || item.unit_price < 0) throw new Error('Invalid unit_price in invoice items');
  }

  return db.transaction(() => {
    const subtotal = data.items.reduce((sum, item) => sum + (item.quantity || 0) * (item.unit_price || 0), 0);
    const totalTax = data.items.reduce((sum, item) => {
      const itemSubtotal = (item.quantity || 0) * (item.unit_price || 0);
      return sum + itemSubtotal * ((item.tax_rate || 0) / 100);
    }, 0);
    const totalAmount = subtotal + totalTax;

    const invoiceResult = db.prepare(`
      INSERT INTO invoices (
        invoice_no, customer_id, invoice_date, due_date, status,
        total_amount, paid_amount, balance_amount, notes, terms, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      data.invoice_no || generateInvoiceNumber(),
      data.customer_id,
      data.invoice_date,
      data.due_date || data.invoice_date,
      data.status || 'Unpaid',
      totalAmount,
      0,
      totalAmount,
      data.notes || null,
      data.terms || null,
      data.userId
    );

    const invoiceId = invoiceResult.lastInsertRowid as number;
    const invoiceNo = data.invoice_no || (invoiceResult.lastInsertRowid ? `INV-${Date.now()}` : '');

    for (const item of data.items) {
      const amount = (item.quantity || 0) * (item.unit_price || 0);
      db.prepare(`
        INSERT INTO invoice_items (
          invoice_id, item_id, quantity, unit_price, amount, tax_rate, discount_type, discount_value
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, item.item_id, item.quantity, item.unit_price, amount, item.tax_rate || 0, item.discount_type || 'percentage', item.discount_value || 0);

      const warehouseId = item.warehouse_id || findWarehouseForItem(db, item.item_id, item.quantity);

      StockMovementModel.recordMovement({
        item_id: item.item_id,
        warehouse_id: warehouseId,
        movement_type: 'SALE',
        quantity: -item.quantity,
        unit_cost: item.unit_price,
        reference_doctype: 'INVOICE',
        reference_docno: String(invoiceId),
        remarks: `Sold via Invoice ${invoiceId}`,
        movement_date: data.invoice_date,
      }, data.userId, db);
    }

    if (data.record_payment && data.payment) {
      const paymentAmount = data.payment.amount || 0;
      initializeSequenceFromMax(db, 'PAY_last_no', 'payments', 'payment_no', 'PAY');
      const nextPaymentNo = getNextSequenceNumber(db, 'PAY_last_no');
      const paymentNo = `PAY${String(nextPaymentNo).padStart(3, '0')}`;

      const paymentResult = db.prepare(`
        INSERT INTO payments (
          payment_no, customer_id, invoice_id, payment_date,
          amount, payment_method, reference_no, notes, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        paymentNo,
        data.customer_id,
        invoiceId,
        data.payment.payment_date || data.invoice_date,
        paymentAmount,
        data.payment.payment_method || 'Cash',
        data.payment.reference_no || null,
        data.payment.notes || null,
        data.userId
      );

      const paymentId = paymentResult.lastInsertRowid as number;

      db.prepare('INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (?, ?, ?)').run(paymentId, invoiceId, paymentAmount);

      db.prepare(`
        UPDATE invoices SET paid_amount = ?, balance_amount = ?, status = ? WHERE id = ?
      `).run(paymentAmount, totalAmount - paymentAmount, paymentAmount >= totalAmount ? 'Paid' : 'Partially Paid', invoiceId);

      // Create ledger entry for payment (credit to reduce AR)
      ledgerUtils.createLedgerEntry(data.customer_id, 'PAYMENT', paymentNo, 0, paymentAmount, `Payment ${paymentNo} for Invoice ${invoiceId}`);
    }

    // Create customer ledger entry for the invoice (debit to increase AR)
    ledgerUtils.createLedgerEntry(data.customer_id, 'INVOICE', invoiceNo, totalAmount, 0, `Invoice ${invoiceNo}`);

    // Update customer balance
    ledgerUtils.updateCustomerBalance(data.customer_id);

    if (data.draft_id) {
      db.prepare('DELETE FROM invoice_drafts WHERE id = ?').run(data.draft_id);
    }

    return invoiceId;
  })();
}

function getInvoiceWithCustomer(db: Database.Database, invoiceId: number) {
  return db.prepare(`
    SELECT i.*, c.customer_name, c.email as customer_email,
           c.phone as customer_phone, c.billing_address as customer_address
    FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id
    WHERE i.id = ?
  `).get(invoiceId);
}

function generateInvoiceNumber(): string {
  const year = new Date().getFullYear();
  const timestamp = Date.now().toString().slice(-6);
  const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
  return `INV-${year}-${timestamp}${random}`;
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
