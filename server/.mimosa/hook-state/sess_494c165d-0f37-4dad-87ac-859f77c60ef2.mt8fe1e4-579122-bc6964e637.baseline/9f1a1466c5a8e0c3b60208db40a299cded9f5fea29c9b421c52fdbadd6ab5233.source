import db from '../config/database';
import SupplierLedgerModel from '../models/SupplierLedger';
import { parseCurrency, subtractCurrency, addCurrency } from './currency';
import { todayLocal } from './reportSql';

/**
 * Create a ledger entry for a customer.
 * ACC-12: carries the caller's real document date (invoice_date,
 * payment_date, …) — never the server clock — so the running-balance
 * chain follows (transaction_date, id) order over non-voided rows.
 * Wrapped in a transaction to prevent race conditions on running balance.
 * Uses currency utilities for safe arithmetic.
 */
function createLedgerEntry(
  customerId: number,
  transactionDate: string,
  type: string,
  referenceNo: string,
  debit: number,
  credit: number,
  description: string
): number {
  const insertEntry = db.transaction(() => {
    // ACC-12: the prior balance for a (possibly backdated) insert is the
    // latest row at or BEFORE the new row's position in
    // (transaction_date, id) order — never simply the newest row.
    const priorResult = db.prepare(`
      SELECT balance FROM customer_ledger
      WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL AND transaction_date <= ?
      ORDER BY transaction_date DESC, id DESC
      LIMIT 1
    `).get(customerId, transactionDate) as { balance: number } | undefined;

    const lastBalance = parseCurrency(priorResult?.balance);
    const safeDebit = parseCurrency(debit);
    const safeCredit = parseCurrency(credit);
    const newBalance = subtractCurrency(addCurrency(lastBalance, safeDebit), safeCredit);

    const result = db.prepare(`
      INSERT INTO customer_ledger (
        customer_id, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      customerId,
      transactionDate,
      type,
      referenceNo,
      safeDebit,
      safeCredit,
      newBalance,
      description
    );
    const newRowId = result.lastInsertRowid as number;

    // Rows positioned after the insert are stale; rebuild the whole chain
    // in date order so every stored balance stays consistent.
    rebuildLedgerBalances(customerId);

    return newRowId;
  });

  return insertEntry();
}

/**
 * Append-only correction (ACC-14 / ACC-20): never delete a ledger row.
 * Insert an equal-and-opposite REVERSAL row referencing the original via
 * reversed_by, mark the original voided = 1, and rebuild the counterparty's
 * stored chain. Works for both customer_ledger and supplier_ledger.
 */
function reverseLedgerEntry(
  table: 'customer_ledger' | 'supplier_ledger',
  rowId: number,
  reason: string
): number {
  if (table !== 'customer_ledger' && table !== 'supplier_ledger') {
    throw new Error(`Invalid ledger table: ${table}`);
  }

  return db.transaction(() => {
    const original = db.prepare(
      `SELECT * FROM ${table} WHERE id = ?`
    ).get(rowId) as Record<string, unknown> | undefined;
    if (!original) throw new Error(`Ledger row ${rowId} not found in ${table}`);
    if (Number(original.voided) === 1) {
      throw new Error(`Ledger row ${rowId} is already voided`);
    }

    const counterpartyKey = table === 'customer_ledger' ? 'customer_id' : 'supplier_id';
    const counterpartyId = original[counterpartyKey] as number;
    const debit = parseCurrency(original.debit as number);
    const credit = parseCurrency(original.credit as number);
    const originalType = String(original.transaction_type || '');

    // The reversal is positioned where the original sat in the chain —
    // same transaction_date — so the rebuilt running balances treat the
    // pair as a net-zero event at that point, not as an end-of-chain one.
    const reversalDate = String(original.transaction_date || todayLocal());

    // Latest non-voided balance for the counterparty.
    const lastRow = db.prepare(
      `SELECT balance FROM ${table}
       WHERE ${counterpartyKey} = ? AND voided = 0
       ORDER BY transaction_date DESC, id DESC LIMIT 1`
    ).get(counterpartyId) as { balance: number } | undefined;
    const lastBalance = parseCurrency(lastRow?.balance);
    const reversalBalance = subtractCurrency(addCurrency(lastBalance, credit), debit);

    const result = db.prepare(`
      INSERT INTO ${table} (
        ${counterpartyKey}, transaction_date, transaction_type, reference_no,
        debit, credit, balance, description, reversed_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      counterpartyId,
      reversalDate,
      `REVERSAL:${originalType}`,
      original.reference_no ?? null,
      credit,   // swapped legs
      debit,
      reversalBalance,
      `Reversal of ledger#${rowId}: ${reason}`,
      rowId
    );
    const reversalId = result.lastInsertRowid as number;

    db.prepare(`UPDATE ${table} SET voided = 1 WHERE id = ?`).run(rowId);

    // Refresh stored balances for this counterparty in date order.
    if (table === 'customer_ledger') {
      rebuildLedgerBalances(counterpartyId);
    } else {
      SupplierLedgerModel.rebuildBalances(counterpartyId, db);
    }

    return reversalId;
  })();
}



function calculateInvoiceBalance(invoiceId: number): number {
  const invoice = db.prepare('SELECT total_amount, returned_amount, return_fee FROM invoices WHERE id = ?').get(invoiceId) as { total_amount: number; returned_amount?: number; return_fee?: number } | undefined;

  if (!invoice) {
    throw new Error(`Invoice ${invoiceId} not found`);
  }

  const paidResult = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) as total_paid
    FROM payment_allocations
    WHERE invoice_id = ?
  `).get(invoiceId) as { total_paid: number };

  const totalPaid = parseCurrency(paidResult?.total_paid);
  const totalAmount = parseCurrency(invoice.total_amount);
  const returnedAmount = parseCurrency(invoice.returned_amount || 0);
  const returnFee = parseCurrency(invoice.return_fee || 0);
  // Balance = total owed minus paid minus (returned minus fee)
  // Equivalent to: total - paid - returned + return_fee
  const netReturnReduction = subtractCurrency(returnedAmount, returnFee);
  const newBalance = subtractCurrency(subtractCurrency(totalAmount, totalPaid), netReturnReduction);

  db.prepare('UPDATE invoices SET paid_amount = ?, balance_amount = ? WHERE id = ?')
    .run(totalPaid, newBalance, invoiceId);

  return newBalance;
}

function updateInvoiceStatus(invoiceId: number): string {
  const invoice = db.prepare('SELECT balance_amount, total_amount, paid_amount, due_date, returned_amount, status FROM invoices WHERE id = ?')
    .get(invoiceId) as { balance_amount: number; total_amount: number; paid_amount: number; due_date: string | null; returned_amount?: number; status?: string } | undefined;

  if (!invoice) {
    throw new Error(`Invoice ${invoiceId} not found`);
  }

  const balance = parseCurrency(invoice.balance_amount);
  const total = parseCurrency(invoice.total_amount);
  const returned = parseCurrency(invoice.returned_amount || 0);
  const currentStatus = String(invoice.status || '');

  let newStatus = 'Unpaid';

  if (currentStatus === 'Cancelled') {
    newStatus = 'Cancelled';
  } else if (returned >= total && total > 0) {
    // All items returned
    newStatus = 'Returned';
  } else if (returned > 0 && total > 0) {
    // Some items returned, some remain
    newStatus = 'Partially Returned';
  } else if (balance <= 0 && total > 0) {
    newStatus = 'Paid';
  } else if (balance < total && balance > 0) {
    newStatus = 'Partially Paid';
  } else if (balance >= total && total > 0) {
    newStatus = 'Unpaid';
  }

  if (newStatus !== 'Paid' && newStatus !== 'Returned' && newStatus !== 'Partially Returned' && invoice.due_date && new Date(invoice.due_date) < new Date()) {
    newStatus = 'Overdue';
  }

  db.prepare('UPDATE invoices SET status = ? WHERE id = ?').run(newStatus, invoiceId);

  return newStatus;
}

function rebuildLedgerBalances(customerId: number): void {
  db.transaction(() => {
    // ACC-14: voided rows are out; a REVERSAL row (reversed_by set) is
    // also excluded — its voided original is already gone, so keeping the
    // active half of the pair would double-count the correction.
    const entries = db.prepare(`
      SELECT id, debit, credit FROM customer_ledger
      WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
      ORDER BY transaction_date ASC, id ASC
    `).all(customerId) as Array<{ id: number; debit: number; credit: number }>;

    let runningBalance = 0;
    const updateStmt = db.prepare('UPDATE customer_ledger SET balance = ? WHERE id = ?');

    for (const entry of entries) {
      runningBalance = addCurrency(subtractCurrency(runningBalance, entry.credit), entry.debit);
      updateStmt.run(runningBalance, entry.id);
    }
  })();
}

/**
 * Task 8.2 (PERF-02): incremental running-balance update. Recomputes the
 * balance seed from everything BEFORE `fromEntryId`, then walks forward
 * only over the affected tail (uses idx_customer_ledger_cust_date).
 */
function updateBalancesFrom(customerId: number, fromEntryId: number): void {
  db.transaction(() => {
    const anchorRow = db.prepare(
      'SELECT transaction_date, id FROM customer_ledger WHERE id = ?'
    ).get(fromEntryId) as { transaction_date: string; id: number } | undefined;
    if (!anchorRow) {
      rebuildLedgerBalances(customerId);
      return;
    }

    // Seed: net of all active rows strictly before the changed row's position
    const seedRow = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
      FROM customer_ledger
      WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
        AND (transaction_date < ? OR (transaction_date = ? AND id < ?))
    `).get(customerId, anchorRow.transaction_date, anchorRow.transaction_date, fromEntryId) as { net: number };

    const tail = db.prepare(`
      SELECT id, debit, credit FROM customer_ledger
      WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
        AND (transaction_date > ? OR (transaction_date = ? AND id >= ?))
      ORDER BY transaction_date ASC, id ASC
    `).all(customerId, anchorRow.transaction_date, anchorRow.transaction_date, fromEntryId) as Array<{ id: number; debit: number; credit: number }>;

    let running = parseCurrency(seedRow.net);
    const updateStmt = db.prepare('UPDATE customer_ledger SET balance = ? WHERE id = ?');
    for (const entry of tail) {
      running = addCurrency(subtractCurrency(running, entry.credit), entry.debit);
      updateStmt.run(running, entry.id);
    }
  })();
}

/**
 * Single authoritative customer-balance writer (ACC-13): the ledger sum
 * over non-voided rows, not an open-invoice status heuristic.
 */
function recalcCustomerBalanceFromLedger(customerId: number): number {
  return db.transaction(() => {
    const row = db.prepare(`
      SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS net
      FROM customer_ledger
      WHERE customer_id = ? AND voided = 0 AND reversed_by IS NULL
    `).get(customerId) as { net: number };

    const newBalance = parseCurrency(row.net);
    db.prepare('UPDATE customers SET current_balance = ? WHERE id = ?').run(newBalance, customerId);
    return newBalance;
  })();
}

export default {
  createLedgerEntry,
  reverseLedgerEntry,
  recalcCustomerBalanceFromLedger,
  calculateInvoiceBalance,
  updateInvoiceStatus,
  rebuildLedgerBalances,
  updateBalancesFrom
};
