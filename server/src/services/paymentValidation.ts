/**
 * TASK 33 — payment validation shared by every payment path.
 *
 * Pure checks only: no writes. The service runs them inside its own
 * transaction, before the first INSERT, so a rejected payment changes
 * nothing (the H7 invariant).
 */
import type Database from 'better-sqlite3';
import { parseCurrency } from '../utils/currency';
import type {
  CustomerPaymentInput,
  SupplierPaymentAllocation,
  SupplierPaymentInput,
} from './paymentRecordingTypes';

export const PAYMENT_METHODS_HINT =
  'use Cash, Bank, Easypaisa, JazzCash or Upaisa';

export function assertPaymentShape(args: {
  paymentDate: string;
  amount: number;
  paymentMethod: string | undefined;
  what: string;
}): void {
  if (!args.paymentDate) throw new Error(`${args.what} date is required`);
  if (!(args.amount > 0)) throw new Error(`${args.what} amount must be greater than 0`);
}

type AllocationCeiling = { readonly amount: number } | null;

function allocationCeiling(
  mode: CustomerPaymentInput['mode'],
  invoice: { total_amount: number; returned_amount: number | null; balance_amount: number },
): AllocationCeiling {
  // A refund is a correction against an already-settled invoice, so nothing
  // about it is bounded by what is still owed.
  if (mode === 'REFUND') return null;
  if (mode === 'INVOICE_SETTLEMENT') {
    return { amount: parseCurrency(invoice.total_amount) - parseCurrency(invoice.returned_amount) };
  }
  return { amount: parseCurrency(invoice.balance_amount) };
}

export function validateCustomerPayment(
  db: Database.Database,
  input: CustomerPaymentInput,
): void {
  assertPaymentShape({
    paymentDate: input.paymentDate,
    amount: input.amount,
    paymentMethod: input.paymentMethod,
    what: 'Payment',
  });

  if (input.customerId <= 0) throw new Error('Valid customer_id is required');
  if (input.allocations.length === 0) {
    throw new Error('At least one invoice allocation is required');
  }

  const customer = db.prepare('SELECT id FROM customers WHERE id = ?').get(input.customerId);
  if (!customer) throw new Error(`Customer ${input.customerId} not found`);

  for (const alloc of input.allocations) {
    const invoice = db.prepare(
      'SELECT id, customer_id, total_amount, returned_amount, balance_amount FROM invoices WHERE id = ?',
    ).get(alloc.invoiceId) as {
      id: number; customer_id: number; total_amount: number;
      returned_amount: number | null; balance_amount: number;
    } | undefined;
    if (!invoice) throw new Error(`Invoice ${alloc.invoiceId} not found`);
    if (Number(invoice.customer_id) !== Number(input.customerId)) {
      throw new Error(`Invoice ${alloc.invoiceId} does not belong to customer ${input.customerId}`);
    }
    const amount = parseCurrency(alloc.amount);
    if (!(amount > 0)) {
      throw new Error(`Allocation amount for invoice ${alloc.invoiceId} must be greater than 0`);
    }
    const ceiling = allocationCeiling(input.mode, invoice);
    if (ceiling && amount > ceiling.amount + 0.01) {
      throw new Error(
        `Allocation amount (${amount.toFixed(2)}) for invoice ${alloc.invoiceId} exceeds the remaining balance (${ceiling.amount.toFixed(2)})`,
      );
    }
  }
}

type PurchaseOrderRow = { id: number; supplier_id: number; total_amount: number; paid_amount: number };
type PurchaseRow = { id: number; supplier_id: number | null; total_cost: number; paid_amount: number };

export function validateSupplierPayment(
  db: Database.Database,
  input: SupplierPaymentInput,
): void {
  assertPaymentShape({
    paymentDate: input.paymentDate,
    amount: input.amount,
    paymentMethod: input.paymentMethod,
    what: 'Payment',
  });

  if (input.supplierId <= 0) throw new Error('Valid supplier_id is required');
  if (input.allocations.length === 0) {
    throw new Error('At least one PO or purchase allocation is required');
  }
  if (!db.prepare('SELECT id FROM suppliers WHERE id = ?').get(input.supplierId)) {
    throw new Error(`Supplier ${input.supplierId} not found`);
  }

  for (const alloc of input.allocations) {
    if (alloc.kind === 'purchase_order') {
      const po = readPurchaseOrder(db, alloc.id);
      if (!po) throw new Error(`Purchase order ${alloc.id} not found`);
      if (po.supplier_id !== input.supplierId) {
        throw new Error(`PO ${alloc.id} does not belong to supplier ${input.supplierId}`);
      }
      assertWithinBalance(`PO ${alloc.id}`, alloc, po.total_amount, po.paid_amount);
      continue;
    }
    const purchase = readPurchase(db, alloc.id);
    if (!purchase) throw new Error(`Purchase ${alloc.id} not found`);
    if (!purchase.supplier_id || purchase.supplier_id !== input.supplierId) {
      throw new Error(`Purchase ${alloc.id} does not belong to supplier ${input.supplierId}`);
    }
    assertWithinBalance(`purchase ${alloc.id}`, alloc, purchase.total_cost, purchase.paid_amount);
  }

  // H7: there is no supplier-advance concept, so a supplier payment must be
  // fully allocated. Checked before the first INSERT.
  const allocatedTotal = input.allocations.reduce((sum, a) => sum + parseCurrency(a.amount), 0);
  const paymentTotal = parseCurrency(input.amount);
  if (Math.abs(allocatedTotal - paymentTotal) > 0.01) {
    throw new Error(
      `Allocation total (${allocatedTotal.toFixed(2)}) does not match the payment amount ` +
      `(${paymentTotal.toFixed(2)}) — the full payment amount is required to be allocated across ` +
      `the selected PO(s) / purchase(s); unallocated supplier payments are not supported`,
    );
  }
}

function readPurchaseOrder(db: Database.Database, poId: number): PurchaseOrderRow | undefined {
  return db.prepare(`
    SELECT po.id, po.supplier_id, po.total_amount, COALESCE(SUM(pa.amount), 0) as paid_amount
    FROM purchase_orders po
    LEFT JOIN po_allocations pa ON pa.po_id = po.id AND pa.voided_at IS NULL
    WHERE po.id = ? GROUP BY po.id
  `).get(poId) as PurchaseOrderRow | undefined;
}

function readPurchase(db: Database.Database, purchaseId: number): PurchaseRow | undefined {
  return db.prepare(`
    SELECT p.id, p.supplier_id, p.total_cost, COALESCE(SUM(pa.amount), 0) as paid_amount
    FROM purchases p
    LEFT JOIN purchase_allocations pa ON pa.purchase_id = p.id AND pa.voided_at IS NULL
    WHERE p.id = ? GROUP BY p.id
  `).get(purchaseId) as PurchaseRow | undefined;
}

function assertWithinBalance(
  label: string,
  alloc: SupplierPaymentAllocation,
  total: number,
  paid: number,
): void {
  const amount = parseCurrency(alloc.amount);
  if (!(amount > 0)) throw new Error(`Allocation amount for ${label} must be greater than 0`);
  const remaining = Math.max(0, parseCurrency(total) - parseCurrency(paid));
  if (amount > remaining) {
    throw new Error(
      `Allocation amount (${amount.toFixed(2)}) for ${label} exceeds the remaining balance (${remaining.toFixed(2)})`,
    );
  }
}
