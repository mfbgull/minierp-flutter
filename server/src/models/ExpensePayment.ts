import type Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { BusinessRuleError } from '../utils/businessRuleError';
import { isValidPaymentMethod } from '../services/cashService';
import { roundCurrency } from '../utils/currency';
import { claimIdempotencyKey, hashRequestPayload, startIdempotentRequest } from '../utils/idempotency';

interface PaymentInput {
  amount: number;
  payment_date: string;
  payment_method: string;
  reference_no?: string;
}
interface ExpensePayment {
  id: number;
  expense_id: number;
  amount: number;
  payment_date: string;
  payment_method: string;
  voided_at: string | null;
}
interface CreditExpense {
  id: number;
  expense_no: string;
  amount: number;
  expense_date: string;
  payment_method: string | null;
  status: string;
}

export function listExpensePayments(db: Database.Database, expenseId: number): ExpensePayment[] {
  return db.prepare('SELECT * FROM expense_payments WHERE expense_id = ? ORDER BY payment_date, id').all(expenseId) as ExpensePayment[];
}

export function payCreditExpense(db: Database.Database, expenseId: number, input: PaymentInput, userId: number, headers: Record<string, string | string[] | undefined>): ExpensePayment {
  return db.transaction(() => {
    const hash = hashRequestPayload({ expenseId, ...input });
    const start = startIdempotentRequest(db, headers, 'expenses.payment', hash);
    if (start.kind === 'error') throw new BusinessRuleError(start.status, start.message);
    if (start.kind === 'replay') {
      const replay = db.prepare('SELECT * FROM expense_payments WHERE id = ?').get(start.resourceId) as ExpensePayment | undefined;
      if (!replay) throw new BusinessRuleError(409, 'Expense payment retry requires review');
      return replay;
    }
    const expense = db.prepare('SELECT * FROM expenses WHERE id = ?').get(expenseId) as CreditExpense | undefined;
    if (!expense) throw new BusinessRuleError(404, 'Expense not found');
    if (expense.status !== 'Recorded' || expense.payment_method !== 'Credit') throw new BusinessRuleError(409, 'Only recorded credit expenses accept payments');
    const amount = roundCurrency(input.amount);
    if (!Number.isFinite(amount) || amount <= 0 || !isValidPaymentMethod(input.payment_method)) throw new BusinessRuleError(400, 'Invalid expense payment amount or method');
    const paid = listExpensePayments(db, expenseId).filter(p => !p.voided_at).reduce((sum, p) => roundCurrency(sum + p.amount), 0);
    if (amount > roundCurrency(expense.amount - paid)) throw new BusinessRuleError(400, 'Payment exceeds the outstanding expense');
    if (input.payment_date < expense.expense_date) throw new BusinessRuleError(400, 'Payment cannot precede the expense');
    AccountingService.assertPeriodNotClosed(db, input.payment_date, 'Expense payment');
    const cash = AccountingService.getAccountByCode(db, AccountingService._cashOrBankAccountCode(input.payment_method));
    const payable = AccountingService.getAccountByCode(db, '2115');
    if (!cash || !payable) throw new Error('Expense payment accounts are missing');
    AccountingService.assertSufficientFunds(db, { accountId: cash.id, amount, asOfDate: input.payment_date, label: expense.expense_no });
    const result = db.prepare('INSERT INTO expense_payments (expense_id, amount, payment_date, payment_method, reference_no, created_by) VALUES (?, ?, ?, ?, ?, ?)')
      .run(expenseId, amount, input.payment_date, input.payment_method, input.reference_no ?? null, userId);
    const id = Number(result.lastInsertRowid);
    AccountingService.postEntry(db, {
      entry_date: input.payment_date, reference_type: 'EXPENSE_PAYMENT', reference_id: id,
      description: `Settlement of ${expense.expense_no}`, created_by: userId,
      lines: [{ account_id: payable.id, debit: amount }, { account_id: cash.id, credit: amount }],
    });
    if (start.key) claimIdempotencyKey(db, 'expenses.payment', start.key, hash, id);
    return db.prepare('SELECT * FROM expense_payments WHERE id = ?').get(id) as ExpensePayment;
  })();
}

export function voidExpensePayment(db: Database.Database, expenseId: number, paymentId: number, userId: number, reason: string): ExpensePayment {
  return db.transaction(() => {
    const payment = db.prepare('SELECT * FROM expense_payments WHERE id = ? AND expense_id = ?').get(paymentId, expenseId) as ExpensePayment | undefined;
    if (!payment) throw new BusinessRuleError(404, 'Expense payment not found');
    if (payment.voided_at) return payment;
    AccountingService.assertPeriodNotClosed(db, payment.payment_date, 'Expense payment');
    AccountingService.voidJournalLinesByReference(db, 'EXPENSE_PAYMENT', paymentId, { voidedBy: userId, voidReason: reason });
    db.prepare('UPDATE expense_payments SET voided_at = CURRENT_TIMESTAMP, voided_by = ?, void_reason = ? WHERE id = ?').run(userId, reason, paymentId);
    return db.prepare('SELECT * FROM expense_payments WHERE id = ?').get(paymentId) as ExpensePayment;
  })();
}
