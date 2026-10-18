import type Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { afterAll, beforeEach, test, expect, jest } from '@jest/globals';
import { UnappliedCashService } from '../services/unappliedCashService';
import AccountingService from '../services/accountingService';
import Payment from '../models/Payment';
import Invoice from '../models/Invoice';
import { PaymentRecordingService } from '../services/PaymentRecordingService';
import { createFixtureDb, cleanupFixtureDbs, seedCustomers } from './helpers/productionSchema';
import { expectAllInvariantsHold, unappliedLiabilityImbalances, creditSourceConsumptionImbalances, creditSourceBoundsImbalances, receiptAllocationImbalances, historicalCreditSourceBaseline } from './helpers/accountingInvariants';

afterAll(cleanupFixtureDbs);

let db: Database.Database;
let service: UnappliedCashService;
beforeEach(() => {
  db = createFixtureDb({ reference: true });
  seedCustomers(db);
  service = new UnappliedCashService(db);
});

function receive(amount = 500, customerId = 1, date = '2026-10-01') {
  return service.receive({ customerId, amount, date, paymentMethod: 'Cash' });
}

function invoice(amount = 1000, customerId = 1): number {
  const result = db.prepare(`INSERT INTO invoices
    (invoice_no, customer_id, invoice_date, total_amount, balance_amount, paid_amount)
    VALUES (?, ?, '2026-10-01', ?, ?, 0)`).run(`INV-${customerId}-${amount}`, customerId, amount, amount);
  db.prepare(`INSERT INTO customer_ledger
    (customer_id,transaction_date,transaction_type,reference_no,debit,credit,balance)
    VALUES (?,'2026-10-01','INVOICE',?, ?,0,?)`).run(customerId, `INV-${customerId}-${amount}`, amount, amount);
  db.prepare('UPDATE customers SET current_balance=current_balance+? WHERE id=?').run(amount, customerId);
  const debit = AccountingService.getAccountByCode(db, '1100');
  const credit = AccountingService.getAccountByCode(db, '4000');
  if (!debit || !credit) throw new Error('Missing fixture accounts');
  AccountingService.postEntry(db, { entry_date: '2026-10-01', description: 'Invoice', reference_type: 'INVOICE', reference_id: Number(result.lastInsertRowid),
    lines: [{ account_id: debit.id, debit: amount }, { account_id: credit.id, credit: amount }] });
  return Number(result.lastInsertRowid);
}

function source() {
  return db.prepare<[], { consumed_amount: number; refunded_amount: number; remaining_amount: number; refundable_cash_amount: number; voided_at: string | null }>(
    'SELECT consumed_amount,refunded_amount,remaining_amount,refundable_cash_amount,voided_at FROM customer_credit_sources ORDER BY id LIMIT 1').get();
}

function liability(): number {
  return db.prepare<[], { amount: number }>(`SELECT COALESCE(SUM(credit-debit),0) amount
    FROM journal_lines WHERE voided=0 AND account_id=(SELECT id FROM chart_of_accounts WHERE code='2110')`).get()?.amount ?? NaN;
}

test('receive holds cash without changing customer AR or return credit', () => {
  const receipt = receive();
  expect(receipt.paymentId).toBeGreaterThan(0);
  expect(source()).toMatchObject({ remaining_amount: 500, refundable_cash_amount: 500 });
  expect(liability()).toBe(500);
  expect(db.prepare('SELECT current_balance,credit_balance FROM customers WHERE id=1').get()).toEqual({ current_balance: 0, credit_balance: 0 });
  expect(db.prepare('SELECT COUNT(*) count FROM customer_ledger').get()).toEqual({ count: 0 });
});

test.each([0, -1, NaN, Infinity, 0.001])('rejects invalid amount %s without writes', amount => {
  expect(() => receive(amount)).toThrow();
  expect(source()).toBeUndefined();
});

test('rejects missing customer, existing credit and invalid calendar dates', () => {
  expect(() => receive(500, 999)).toThrow();
  db.prepare('UPDATE customers SET current_balance=-1 WHERE id=1').run();
  expect(() => receive()).toThrow();
  expect(() => receive(500, 2, '2026-02-30')).toThrow();
  expect(source()).toBeUndefined();
});

test('apply then refund consumes only the remaining cash, without another receipt', () => {
  receive();
  const invoiceId = invoice();
  const input = { customerId: 1, date: '2026-10-02', applicationKey: 'apply-0001', allocations: [{ invoiceId, amount: 400 }] };
  const applied = service.apply(input);
  expect(service.apply(input)).toEqual(applied);
  expect(() => service.apply({ ...input, allocations: [{ invoiceId, amount: 401 }] })).toThrow();
  expect(source()).toMatchObject({ consumed_amount: 400, remaining_amount: 100, refundable_cash_amount: 100 });
  expect(db.prepare('SELECT paid_amount,balance_amount FROM invoices WHERE id=?').get(invoiceId)).toEqual({ paid_amount: 400, balance_amount: 600 });
  expect(db.prepare('SELECT current_balance FROM customers WHERE id=1').get()).toEqual({ current_balance: 600 });
  const refund = { customerId: 1, amount: 100, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'refund-001' };
  const refunded = service.refund(refund);
  expect(service.refund(refund)).toEqual(refunded);
  expect(source()).toMatchObject({ refunded_amount: 100, remaining_amount: 0, refundable_cash_amount: 0 });
  expect(liability()).toBe(0);
  expect(db.prepare('SELECT amount,payment_kind FROM payments ORDER BY id').all()).toEqual([
    { amount: 500, payment_kind: 'UNAPPLIED_RECEIPT' }, { amount: -100, payment_kind: 'REFUND' },
  ]);
});

test('normalizes duplicate allocations before checking invoice capacity', () => {
  receive();
  const invoiceId = invoice(300);
  expect(() => service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'duplicate1', allocations: [{ invoiceId, amount: 200 }, { invoiceId, amount: 200 }] })).toThrow();
  expect(source()?.consumed_amount).toBe(0);
});

test('refund cannot exceed available held cash and full refund is supported', () => {
  receive(300);
  expect(() => service.refund({ customerId: 1, amount: 301, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-big' })).toThrow();
  service.refund({ customerId: 1, amount: 300, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-all' });
  expect(liability()).toBe(0);
});

test('reverse unused receipt retires source and prevents spending', () => {
  const receipt = receive();
  service.reverse(receipt.paymentId, { voidReason: 'mistake' });
  expect(source()?.voided_at).not.toBeNull();
  expect(liability()).toBe(0);
  expect(() => service.refund({ customerId: 1, amount: 1, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-void' })).toThrow();
  expect(() => service.reverse(receipt.paymentId)).toThrow();
});

test('applied receipt cannot reverse or enter legacy mutation paths', () => {
  const receipt = receive();
  const invoiceId = invoice();
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-guard', allocations: [{ invoiceId, amount: 50 }] });
  expect(() => service.reverse(receipt.paymentId)).toThrow(expect.objectContaining({ status: 409, code: 'UNAPPLIED_ALREADY_APPLIED' }));
  expect(() => Payment.delete(db, receipt.paymentId)).toThrow();
  expect(() => Payment.update(db, receipt.paymentId, { payment_method: 'Bank' })).toThrow();
  expect(() => Payment.deleteAllocationsByPaymentId(db, receipt.paymentId)).toThrow();
  expect(() => Payment.deleteAllocationsByInvoiceId(db, invoiceId)).toThrow();
  expect(() => new PaymentRecordingService(db).allocateExistingPayment({ paymentId: receipt.paymentId, customerId: 1, allocations: [{ invoiceId, amount: 450 }] })).toThrow();
  expect(source()?.consumed_amount).toBe(50);
});

test('posting failure rolls back receipt, sources and payment numbering', () => {
  const failure = jest.spyOn(AccountingService, 'postEntry').mockImplementationOnce(() => { throw new Error('injected posting failure'); });
  expect(() => receive()).toThrow('injected posting failure');
  failure.mockRestore();
  expect(source()).toBeUndefined();
  expect(db.prepare('SELECT COUNT(*) count FROM payments').get()).toEqual({ count: 0 });
});

test('A-J signatures stay green through receive, multi-source apply and refund', () => {
  expectAllInvariantsHold('before', db);
  receive(200);
  receive(300);
  const invoiceId = invoice();
  expectAllInvariantsHold('received', db);
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-fifo', allocations: [{ invoiceId, amount: 400 }] });
  expect(db.prepare('SELECT consumed_amount FROM customer_credit_sources ORDER BY id').all()).toEqual([{ consumed_amount: 200 }, { consumed_amount: 200 }]);
  expectAllInvariantsHold('applied', db);
  service.refund({ customerId: 1, amount: 100, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'refund-fifo' });
  expectAllInvariantsHold('refunded', db);
  expect(unappliedLiabilityImbalances(db)).toEqual([]);
  expect(creditSourceConsumptionImbalances(db)).toEqual([]);
  expect(creditSourceBoundsImbalances(db)).toEqual([]);
  expect(receiptAllocationImbalances(db)).toEqual([]);
});

test('K reports missing account and planted liability drift', () => {
  receive();
  db.transaction(() => {
    db.prepare("UPDATE journal_lines SET credit=499 WHERE reference_type='UNAPPLIED_RECEIPT' AND credit>0").run();
    db.prepare("UPDATE journal_lines SET debit=499 WHERE reference_type='UNAPPLIED_RECEIPT' AND debit>0").run();
  })();
  expect(unappliedLiabilityImbalances(db)).toHaveLength(1);
  db.prepare("UPDATE chart_of_accounts SET code='2111' WHERE code='2110'").run();
  expect(() => unappliedLiabilityImbalances(db)).toThrow();
});

test('L detects offsetting per-source counter corruption and missing draw records', () => {
  receive();
  receive();
  const invoiceId = invoice();
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-drift', allocations: [{ invoiceId, amount: 600 }] });
  db.exec(`UPDATE customer_credit_sources SET consumed_amount=consumed_amount-10,refundable_cash_amount=refundable_cash_amount+10 WHERE id=1;
    UPDATE customer_credit_sources SET consumed_amount=consumed_amount+10,refundable_cash_amount=refundable_cash_amount-10 WHERE id=2`);
  expect(creditSourceConsumptionImbalances(db)).toHaveLength(2);
  db.prepare('DELETE FROM credit_source_consumptions').run();
  expect(creditSourceConsumptionImbalances(db)).toHaveLength(2);
});

test('M detects bounds and N compares only positive receipt allocations', () => {
  const receipt = receive();
  const invoiceId = invoice();
  db.prepare('INSERT INTO payment_allocations (payment_id,invoice_id,amount) VALUES (?,?,501)').run(receipt.paymentId, invoiceId);
  expect(receiptAllocationImbalances(db)).toHaveLength(1);
  db.exec('PRAGMA ignore_check_constraints=ON');
  db.exec('UPDATE customer_credit_sources SET refunded_amount=501,refundable_cash_amount=-1');
  expect(creditSourceBoundsImbalances(db)).toHaveLength(1);
  db.exec('PRAGMA ignore_check_constraints=OFF');
});

test('historical provenance is reported separately and never funds new payouts', () => {
  db.prepare(`INSERT INTO customer_credit_sources (customer_id,kind,credited_amount,consumed_amount,refundable_cash_amount)
    VALUES (1,'RETURN_CREDIT',100,25,0)`).run();
  expect(historicalCreditSourceBaseline(db)).toEqual([{ sourceId: 1, consumed: 25, refunded: 0 }]);
  expect(creditSourceConsumptionImbalances(db)).toEqual([]);
  expect(() => service.refund({ customerId: 1, amount: 1, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-old' })).toThrow();
});

test('fractional currency can be applied and refunded without floating point constraint failures', () => {
  receive(0.30);
  const invoiceId = invoice(1);
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-cents', allocations: [{ invoiceId, amount: 0.10 }] });
  service.refund({ customerId: 1, amount: 0.20, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'refund-cents' });
  expect(source()?.remaining_amount).toBeCloseTo(0, 8);
});

test('closed operation periods reject receive, apply, refund and original-date reversal', () => {
  const receipt = receive();
  const invoiceId = invoice();
  db.prepare("UPDATE accounting_periods SET status='closed' WHERE period_name='2026-10'").run();
  expect(() => receive()).toThrow(expect.objectContaining({ code: 'PERIOD_CLOSED' }));
  expect(() => service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-closed', allocations: [{ invoiceId, amount: 1 }] })).toThrow(expect.objectContaining({ code: 'PERIOD_CLOSED' }));
  expect(() => service.refund({ customerId: 1, amount: 1, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-closed' })).toThrow(expect.objectContaining({ code: 'PERIOD_CLOSED' }));
  expect(() => service.reverse(receipt.paymentId)).toThrow(expect.objectContaining({ code: 'PERIOD_CLOSED' }));
  service.apply({ customerId: 1, date: '2026-11-01', applicationKey: 'apply-new-period', allocations: [{ invoiceId, amount: 1 }] });
  expect(source()?.consumed_amount).toBe(1);
});

test('rejects another customer invoice and source overdraw without partial draws', () => {
  receive();
  const foreign = invoice(100, 2);
  expect(() => service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-foreign', allocations: [{ invoiceId: foreign, amount: 50 }] })).toThrow();
  const own = invoice();
  expect(() => service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-overdraw', allocations: [{ invoiceId: own, amount: 600 }] })).toThrow();
  expect(source()?.consumed_amount).toBe(0);
  expect(db.prepare('SELECT COUNT(*) count FROM credit_applications').get()).toEqual({ count: 0 });
});

test('repeat draws and refunds enforce the receipt original cash ceiling', () => {
  const receipt = receive();
  const invoiceId = invoice(2000);
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-first', allocations: [{ invoiceId, amount: 400 }] });
  expect(() => service.apply({ customerId: 1, date: '2026-10-03', applicationKey: 'apply-second', allocations: [{ invoiceId, amount: 400 }] })).toThrow();
  expect(() => service.refund({ customerId: 1, amount: 400, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'refund-second' })).toThrow();
  db.prepare('INSERT INTO payment_allocations (payment_id,invoice_id,amount) VALUES (?,?,100)').run(receipt.paymentId, invoiceId);
  expect(() => service.apply({ customerId: 1, date: '2026-10-03', applicationKey: 'apply-ceiling', allocations: [{ invoiceId, amount: 1 }] })).toThrow();
  expect(source()?.consumed_amount).toBe(400);
});

test('failure after source draws rolls back application, refund and GL', () => {
  receive();
  const invoiceId = invoice();
  const failure = jest.spyOn(AccountingService, 'postEntry').mockImplementationOnce(() => { throw new Error('apply failure'); });
  expect(() => service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'apply-rollback', allocations: [{ invoiceId, amount: 400 }] })).toThrow('apply failure');
  failure.mockImplementationOnce(() => { throw new Error('refund failure'); });
  expect(() => service.refund({ customerId: 1, amount: 300, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-rollback' })).toThrow('refund failure');
  failure.mockRestore();
  expect(source()).toMatchObject({ consumed_amount: 0, refunded_amount: 0, remaining_amount: 500 });
  expect(db.prepare('SELECT COUNT(*) count FROM credit_applications').get()).toEqual({ count: 0 });
  expectAllInvariantsHold('rollback', db);
});

test('refunded receipts and refund payment cannot be reversed through generic payment void', () => {
  const receipt = receive(300);
  const refunded = service.refund({ customerId: 1, amount: 300, date: '2026-10-02', paymentMethod: 'Cash', applicationKey: 'refund-block' });
  expect(() => service.reverse(receipt.paymentId)).toThrow(expect.objectContaining({ code: 'UNAPPLIED_ALREADY_APPLIED' }));
  if (refunded.paymentId === null) throw new Error('Missing refund payment');
  const refundPaymentId = refunded.paymentId;
  expect(() => Payment.delete(db, refundPaymentId)).toThrow();
  expect(receiptAllocationImbalances(db)).toEqual([]);
});

test('missing accounts roll back receive and cash timeline prevents unfunded refunds', () => {
  db.prepare("UPDATE chart_of_accounts SET is_active=0 WHERE code='2110'").run();
  expect(() => receive()).toThrow(expect.objectContaining({ code: 'MISSING_ACCOUNT' }));
  expect(source()).toBeUndefined();
  db.prepare("UPDATE chart_of_accounts SET is_active=1 WHERE code='2110'").run();
  receive();
  expect(() => service.refund({ customerId: 1, amount: 100, date: '2026-10-02', paymentMethod: 'Bank', applicationKey: 'refund-unfunded' })).toThrow(expect.objectContaining({ code: 'INSUFFICIENT_CASH' }));
  expect(source()?.refunded_amount).toBe(0);
});

test('reversal cannot remove cash already needed by later spending', () => {
  const receipt = receive();
  const cash = AccountingService.getAccountByCode(db, '1000');
  const offset = AccountingService.getAccountByCode(db, '4000');
  if (!cash || !offset) throw new Error('Missing fixture accounts');
  AccountingService.postEntry(db, { entry_date: '2026-10-03', description: 'Later cash spending', reference_type: 'MANUAL_JOURNAL', reference_id: 999,
    lines: [{ account_id: offset.id, debit: 400 }, { account_id: cash.id, credit: 400 }] });
  expect(() => service.reverse(receipt.paymentId)).toThrow(expect.objectContaining({ code: 'INSUFFICIENT_CASH' }));
  expect(source()?.voided_at).toBeNull();
  expect(liability()).toBe(500);
  expect(db.prepare('SELECT voided_at FROM payments WHERE id=?').get(receipt.paymentId)).toEqual({ voided_at: null });
});

test('permanent application replay survives idempotency pruning and rejects changed payloads', () => {
  receive();
  const invoiceId = invoice();
  const input = { customerId: 1, date: '2026-10-02', applicationKey: 'durable-key', allocations: [{ invoiceId, amount: 100 }] };
  const applied = service.apply(input);
  db.prepare('DELETE FROM idempotency_keys').run();
  expect(service.apply(input)).toEqual(applied);
  expect(() => service.apply({ ...input, allocations: [{ invoiceId, amount: 200 }] })).toThrow(expect.objectContaining({ code: 'IDEMPOTENCY_CONFLICT' }));
});

test('application keys are independent per customer and operation', () => {
  receive();
  receive(500, 2);
  const firstInvoice = invoice();
  const secondInvoice = invoice(1000, 2);
  const first = { customerId: 1, date: '2026-10-02', applicationKey: 'shared-key', allocations: [{ invoiceId: firstInvoice, amount: 100 }] };
  const second = { ...first, customerId: 2, allocations: [{ invoiceId: secondInvoice, amount: 100 }] };
  const appliedFirst = service.apply(first);
  const appliedSecond = service.apply(second);
  expect(appliedFirst.applicationId).not.toBe(appliedSecond.applicationId);
  expect(service.apply(first)).toEqual(appliedFirst);
  expect(service.apply(second)).toEqual(appliedSecond);
  service.refund({ customerId: 1, date: '2026-10-03', applicationKey: 'shared-key', amount: 100, paymentMethod: 'Cash' });
  expectAllInvariantsHold('independent keys', db);
});

test('currency migration preserves source IDs, live draws, replay records and foreign keys', () => {
  receive();
  const invoiceId = invoice();
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'migrate-apply', allocations: [{ invoiceId, amount: 400 }] });
  service.refund({ customerId: 1, amount: 100, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'migrate-refund' });
  const sources = db.prepare('SELECT * FROM customer_credit_sources ORDER BY id').all();
  const draws = db.prepare('SELECT * FROM credit_source_consumptions ORDER BY id').all();
  const headers = db.prepare('SELECT * FROM credit_applications ORDER BY id').all();
  const migration = fs.readFileSync(path.join(__dirname, '../migrations/110_unapplied_currency_precision.sql'), 'utf8');
  db.transaction(() => db.exec(migration))();
  expect(db.prepare('SELECT * FROM customer_credit_sources ORDER BY id').all()).toEqual(sources);
  expect(db.prepare('SELECT * FROM credit_source_consumptions ORDER BY id').all()).toEqual(draws);
  expect(db.prepare('SELECT * FROM credit_applications ORDER BY id').all()).toEqual(headers);
  expect(db.pragma('foreign_key_check')).toEqual([]);
  expectAllInvariantsHold('after currency migration', db);
});

test('all three posting groups use their numeric resource IDs and shared void helper', () => {
  const receipt = receive();
  const invoiceId = invoice();
  const applied = service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'group-apply', allocations: [{ invoiceId, amount: 400 }] });
  const refunded = service.refund({ customerId: 1, amount: 100, date: '2026-10-03', paymentMethod: 'Cash', applicationKey: 'group-refund' });
  const groups = [
    { type: 'UNAPPLIED_RECEIPT', id: receipt.paymentId },
    { type: 'UNAPPLIED_APPLY', id: applied.applicationId },
    { type: 'UNAPPLIED_REFUND', id: refunded.paymentId },
  ];
  for (const group of groups) {
    if (group.id === null) throw new Error('Missing journal reference ID');
    const resourceId = group.id;
    const transaction = db.transaction(() => {
      expect(AccountingService.voidJournalLinesByReference(db, group.type, resourceId)).toBe(2);
      expect(db.prepare('SELECT COUNT(*) count FROM journal_lines WHERE reference_type=? AND reference_id=? AND voided=0').get(group.type, resourceId)).toEqual({ count: 0 });
    });
    transaction();
  }
});

test('invoice cancellation rechecks live consumptions even with a stale unpaid invoice snapshot', () => {
  db.prepare(`INSERT INTO users (id,username,email,password_hash,full_name,role,is_active)
    VALUES (1,'stage-d-actor','stage-d@example.test','unused','Stage D actor','admin',1)`).run();
  receive();
  const invoiceId = invoice();
  const stale = Invoice.getById(invoiceId, db);
  if (!stale) throw new Error('Missing fixture invoice');
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'stale-cancel', allocations: [{ invoiceId, amount: 50 }] });
  expect(() => db.transaction(() => Invoice.cancelInvoiceInternal(db, stale, 1))()).toThrow(expect.objectContaining({ code: 'UNAPPLIED_ALREADY_APPLIED', status: 409 }));
  expect(source()?.consumed_amount).toBe(50);
  expect(db.prepare('SELECT paid_amount FROM invoices WHERE id=?').get(invoiceId)).toEqual({ paid_amount: 50 });
});

test('an invoice with held cash applications cannot be reassigned to another customer', () => {
  receive();
  const invoiceId = invoice();
  service.apply({ customerId: 1, date: '2026-10-02', applicationKey: 'owner-change', allocations: [{ invoiceId, amount: 50 }] });
  const existing = Invoice.getById(invoiceId, db);
  if (!existing) throw new Error('Missing fixture invoice');
  expect(() => Invoice.updateInvoice(db, invoiceId, { ...existing, customer_id: 2 })).toThrow(expect.objectContaining({ code: 'UNAPPLIED_ALREADY_APPLIED', status: 409 }));
  expect(db.prepare('SELECT customer_id FROM invoices WHERE id=?').get(invoiceId)).toEqual({ customer_id: 1 });
});
