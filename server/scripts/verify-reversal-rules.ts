/**
 * Phase 1 reversal-rules verification (C1, C3, C4, C2) — model level.
 *
 * Runs the exact transaction bodies the API endpoints call, against the
 * same kind of fresh temp-DB fixture the jest suite uses, and asserts
 * the accounting invariants from the audit's Section I cases 1-8
 * (cases 2/3/5a are guard paths; case 7 covers the PO state machine).
 */
import path from 'path';
import fs from 'fs';
import os from 'os';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'verify-script-secret';
process.env.DEFAULT_ADMIN_PASSWORD = 'verify-admin-pass';

const testDbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-verify-'));
process.env.DATABASE_PATH = testDbDir;

import db, { dbSeedReady } from '../src/config/database';
import InvoiceModel from '../src/models/Invoice';
import PurchaseOrderModel from '../src/models/PurchaseOrder';
import SalesOrderModel from '../src/models/SalesOrder';
import ProductionModel from '../src/models/Production';
import StockMovementModel from '../src/models/StockMovement';
import SupplierModel from '../src/models/Supplier';
import EmployeeModel from '../src/models/Employee';
import EmployeeLoanModel from '../src/models/EmployeeLoan';
import PaymentModel from '../src/models/Payment';
import AccountingService from '../src/services/accountingService';
import ledgerUtils from '../src/utils/ledgerUtils';
import { InvoiceCancellationGuardError } from '../src/models/Invoice';

let passed = 0;
let failed = 0;
function assert(cond: boolean, label: string): void {
  if (cond) { passed++; console.log(`  PASS  ${label}`); }
  else { failed++; console.log(`  FAIL  ${label}`); }
}
function assertClose(actual: number, expected: number, label: string): void {
  assert(Math.abs(actual - expected) < 0.005, `${label} (got ${actual.toFixed(2)}, want ${expected.toFixed(2)})`);
}
function activeLines(refType: string, refId: number): number {
  return (db.prepare(
    'SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0'
  ).get(refType, refId) as { c: number }).c;
}

async function main(): Promise<void> {
  // The admin seed hash is computed off the event loop — wait for the
  // row before any FK (created_by) references it.
  await dbSeedReady;

  console.log('Phase 1 reversal-rules verification (fresh temp DB)');

  // ---------- fixtures ----------
  const warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
  const item = db.prepare(
    'INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, current_stock) VALUES (?, ?, ?, ?, 0)'
  ).run(`VERIF-${Date.now()}`, 'Verify Item', 'pcs', 10);
  const itemId = Number(item.lastInsertRowid);

  const rawItem = db.prepare(
    'INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, current_stock) VALUES (?, ?, ?, ?, 0)'
  ).run(`VERIF-RAW-${Date.now()}`, 'Verify Raw', 'pcs', 5);
  const rawItemId = Number(rawItem.lastInsertRowid);

  const fgItem = db.prepare(
    'INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, current_stock) VALUES (?, ?, ?, ?, 0)'
  ).run(`VERIF-FG-${Date.now()}`, 'Verify FG', 'pcs', 0);
  const fgItemId = Number(fgItem.lastInsertRowid);

  const customerRes = db.prepare(
    'INSERT INTO customers (customer_code, customer_name, phone) VALUES (?, ?, ?)'
  ).run('VERIF-CUST-1', 'Verify Customer', '555-0001');
  const customerId = Number(customerRes.lastInsertRowid);
  const customerStartBalance = 0;

  // Stock via the purchase model path (FIFO batches + GL).
  StockMovementModel.recordMovement({
    item_id: itemId, warehouse_id: warehouseId, movement_type: 'PURCHASE',
    quantity: 50, unit_cost: 10, reference_doctype: 'Purchase',
    reference_docno: 'VERIF-PUR-1', movement_date: '2026-08-01',
  }, 1, db);
  StockMovementModel.recordMovement({
    item_id: rawItemId, warehouse_id: warehouseId, movement_type: 'PURCHASE',
    quantity: 20, unit_cost: 5, reference_doctype: 'Purchase',
    reference_docno: 'VERIF-PUR-2', movement_date: '2026-08-01',
  }, 1, db);

  const supplierId = SupplierModel.create({ supplier_code: `VERIF-SUP-${Date.now()}`, supplier_name: 'Verify Supplier' }, db);

  const stockOf = (id: number): number =>
    (db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = ?')
      .get(id, warehouseId) as { quantity: number }).quantity;

/**
 * Mirrors the createInvoice controller's transaction: model insert,
 * items + FIFO consumption, SALE movements, customer-ledger debit,
 * postInvoiceEntry + postCOGSEntry. This is the exact posting pipeline
 * the API endpoint runs, so the fixture reaches cancelInvoiceInternal
 * with the same GL state production would have.
 */
function createPostedInvoice(invoiceNo: string, qty: number, unitPrice: number): number {
  const total = qty * unitPrice;
  return db.transaction(() => {
    const invoiceId = InvoiceModel.createInvoice(db, {
      invoice_no: invoiceNo, customer_id: customerId, invoice_date: '2026-08-10',
      due_date: '2026-08-20', status: 'Unpaid', total_amount: total,
      paid_amount: 0, balance_amount: total,
      items: [{ item_id: itemId, quantity: qty, unit_price: unitPrice, warehouse_id: warehouseId }],
    } as never, 1);

    let cogsTotal = 0;
    const warehouseId2 = InvoiceModel.findWarehouseForItem(db, itemId, qty, warehouseId);
    InvoiceModel.createInvoiceItem(db, invoiceId, {
      item_id: itemId, quantity: qty, unit_price: unitPrice,
    } as never);
    const consumption = InvoiceModel.consumeFromOldestBatches(itemId, warehouseId2, qty, db);
    for (const entry of consumption) {
      StockMovementModel.recordMovement({
        item_id: itemId, warehouse_id: warehouseId2, movement_type: 'SALE',
        quantity: -entry.consumed, unit_cost: entry.unitCost,
        reference_doctype: 'INVOICE', reference_docno: invoiceNo,
        movement_date: '2026-08-10', batch_id: entry.batchId ?? undefined,
      }, 1, db);
      cogsTotal += entry.consumed * entry.unitCost;
    }

    InvoiceModel.createLedgerEntry(db, customerId, 'INVOICE', invoiceNo, '2026-08-10', total, 0, `Invoice ${invoiceNo}`);
    AccountingService.postInvoiceEntry(db, {
      invoiceId, invoiceNo, totalAmount: total, invoiceDate: '2026-08-10', userId: 1, taxAmount: 0,
    } as never);
    if (cogsTotal > 0) {
      AccountingService.postCOGSEntry(db, {
        invoiceId, invoiceNo, cogsAmount: cogsTotal, invoiceDate: '2026-08-10', userId: 1,
      } as never);
    }
    ledgerUtils.recalcCustomerBalanceFromLedger(customerId);
    return invoiceId;
  })();
}

  // ---------- C1 case 1: cancel unpaid invoice ----------
  console.log('C1 case 1 — cancel unpaid invoice');
  const inv1Id = createPostedInvoice('VERIF-INV-1', 2, 50);
  assert(activeLines('INVOICE', inv1Id) > 0, 'invoice posted GL lines');

  const stockBefore = stockOf(itemId);
  InvoiceModel.cancelInvoiceInternal(db, InvoiceModel.getById(inv1Id, db)!, 1);

  assert((db.prepare('SELECT status FROM invoices WHERE id = ?').get(inv1Id) as { status: string }).status === 'Cancelled', 'status Cancelled');
  assertClose(stockOf(itemId) - stockBefore, 2, 'stock restored +2');
  assert(activeLines('INVOICE', inv1Id) === 0, 'INVOICE GL lines voided');
  assert(activeLines('INVOICE_RETURN', inv1Id) === 0, 'INVOICE_RETURN GL voided');
  assert((db.prepare(
    'SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 1'
  ).get('INVOICE', inv1Id) as { c: number }).c > 0, 'voided lines retained for audit');
  const ledgerRows = db.prepare(
    'SELECT debit, credit FROM customer_ledger WHERE reference_no = ? AND voided = 0'
  ).all('VERIF-INV-1') as Array<{ debit: number; credit: number }>;
  assertClose(ledgerRows.reduce((s, r) => s + Number(r.debit), 0), 100, 'ledger debit 100');
  assertClose(ledgerRows.reduce((s, r) => s + Number(r.credit), 0), 100, 'ledger credit 100 (CANCELLATION)');
  assertClose(
    (db.prepare('SELECT current_balance FROM customers WHERE id = ?').get(customerId) as { current_balance: number }).current_balance,
    customerStartBalance, 'customer balance net 0');
  assert((db.prepare(
    "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = ?"
  ).get('VERIF-INV-1') as { c: number }).c > 0, 'INVOICE_CANCEL movement exists');

  // ---------- C1 case 3: partially-paid invoice blocked ----------
  console.log('C1 case 3 — partially-paid invoice blocked');
  const inv2Id = createPostedInvoice('VERIF-INV-2', 1, 100);
  db.prepare('UPDATE invoices SET paid_amount = 40 WHERE id = ?').run(inv2Id);
  const inv2Row = InvoiceModel.getById(inv2Id, db)!;
  let guardBlocked = false;
  try { InvoiceModel.cancelInvoiceInternal(db, inv2Row, 1); }
  catch (e) { guardBlocked = e instanceof InvoiceCancellationGuardError && /payments/.test(e.message); }
  assert(guardBlocked, 'guard threw InvoiceCancellationGuardError');
  assert((db.prepare('SELECT status FROM invoices WHERE id = ?').get(inv2Id) as { status: string }).status !== 'Cancelled', 'status unchanged');
  assert(activeLines('INVOICE', inv2Id) > 0, 'GL still active');
  assert((db.prepare(
    "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_doctype = 'INVOICE_CANCEL' AND reference_docno = ?"
  ).get('VERIF-INV-2') as { c: number }).c === 0, 'no reversal movement');

  // ---------- C4 case 5b: SO.cancel on invoiced + unpaid ----------
  console.log('C4 case 5b — SO.cancel on invoiced unpaid order');
  const so = SalesOrderModel.create({
    customer_id: customerId, so_date: '2026-08-10', delivery_date: '2026-08-15',
    status: 'Confirmed', warehouse_id: warehouseId,
    items: [{ item_id: itemId, quantity: 1, unit_price: 100, warehouse_id: warehouseId }],
  } as never, 1, db);
  const { invoiceId: soInvId } = SalesOrderModel.convertToInvoice(so.id, 1, db);
  const soStockBefore = stockOf(itemId);
  SalesOrderModel.cancel(so.id, 1, db);
  assert((db.prepare('SELECT status FROM sales_orders WHERE id = ?').get(so.id) as { status: string }).status === 'Cancelled', 'SO cancelled');
  assert((db.prepare('SELECT status FROM invoices WHERE id = ?').get(soInvId) as { status: string }).status === 'Cancelled', 'linked invoice cancelled');
  assert(activeLines('INVOICE', soInvId) === 0, 'linked invoice GL voided');
  assertClose(stockOf(itemId) - soStockBefore, 1, 'stock restored +1');
  assert((db.prepare(
    "SELECT credit FROM customer_ledger WHERE transaction_type = 'CANCELLATION' AND voided = 0"
  ).get() as { credit: number }) !== undefined, 'CANCELLATION ledger row exists');

  // ---------- C3 case 6: PO cancel reverses AP ----------
  console.log('C3 case 6 — PO cancel reverses AP debit');
  const po = PurchaseOrderModel.create({
    supplier_id: supplierId, po_date: '2026-08-10',
    items: [{ item_id: itemId, quantity: 5, unit_price: 20 }],
  } as never, 1, db);
  PurchaseOrderModel.updateStatus(po.id, 'Submitted', 1, db);
  const poNo = (db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(po.id) as { po_no: string }).po_no;
  const submitDebit = db.prepare(
    "SELECT debit FROM supplier_ledger WHERE reference_no = ? AND transaction_type = 'PURCHASE_ORDER' AND voided = 0"
  ).get(poNo) as { debit: number };
  assertClose(Number(submitDebit.debit), 100, 'submission posted AP debit 100');

  PurchaseOrderModel.updateStatus(po.id, 'Cancelled', 1, db);
  const poRows = db.prepare(
    'SELECT transaction_type, debit, credit FROM supplier_ledger WHERE reference_no = ? AND voided = 0 ORDER BY id'
  ).all(poNo) as Array<{ transaction_type: string; debit: number; credit: number }>;
  assert(poRows.length === 2, 'ledger has exactly 2 rows (debit + cancellation credit)');
  assert(poRows[1].transaction_type === 'PURCHASE_ORDER_CANCEL', 'second row is PURCHASE_ORDER_CANCEL');
  assertClose(Number(poRows[1].credit), 100, 'cancellation credit 100');
  assertClose(poRows.reduce((s, r) => s + Number(r.debit) - Number(r.credit), 0), 0, 'net AP effect 0');
  assertClose(
    (db.prepare('SELECT current_balance FROM suppliers WHERE id = ?').get(supplierId) as { current_balance: number }).current_balance,
    0, 'supplier balance back to 0');

  // ---------- C3 case 7: Cancelled → Submitted blocked ----------
  console.log('C3 case 7 — Cancelled → Submitted blocked');
  let resubmitBlocked = false;
  try { PurchaseOrderModel.updateStatus(po.id, 'Submitted', 1, db); }
  catch { resubmitBlocked = true; }
  assert(resubmitBlocked, 'state machine rejected Cancelled → Submitted');
  const activePoRows = db.prepare(
    "SELECT COUNT(*) AS c FROM supplier_ledger WHERE reference_no = ? AND transaction_type = 'PURCHASE_ORDER' AND voided = 0"
  ).get(poNo) as { c: number };
  assert(activePoRows.c === 1, 'exactly one active PURCHASE_ORDER row');

  // ---------- C2 case 8: production delete voids canonical GL ----------
  console.log('C2 case 8 — production delete voids canonical GL');
  const prod = ProductionModel.recordProduction({
    output_item_id: fgItemId, output_quantity: 4, warehouse_id: warehouseId,
    production_date: '2026-08-10', input_items: [{ item_id: rawItemId, quantity: 8 }],
    overhead_cost: 10,
  } as never, 1, db);
  const outputMovement = db.prepare(
    "SELECT id, journal_entry_id FROM stock_movements WHERE reference_docno = ? AND movement_type = 'PRODUCTION' AND quantity > 0"
  ).get(prod.production_no) as { id: number; journal_entry_id: number | null };
  const outputMovementId = outputMovement!.id;
  assert(Boolean(outputMovement?.journal_entry_id), 'output movement linked to legacy JE');
  const jeId = outputMovement!.journal_entry_id as number;
  const jeBefore = db.prepare('SELECT voided, amount FROM journal_entries WHERE id = ?').get(jeId) as { voided: number; amount: number };
  assert(Number(jeBefore.voided) === 0, 'JE active before delete');
  assertClose(Number(jeBefore.amount), 50, 'JE amount 50 (8×5 + 10)');

  const rawBefore = stockOf(rawItemId);
  const fgBefore = stockOf(fgItemId);
  ProductionModel.delete(prod.id, 1, db);
  const jeAfter = db.prepare('SELECT voided FROM journal_entries WHERE id = ?').get(jeId) as { voided: number };
  assert(Number(jeAfter.voided) === 1, 'JE voided after delete');
  const activeProdLines = db.prepare(`
    SELECT COUNT(*) AS c FROM journal_lines WHERE reference_type = ? AND reference_id = ? AND voided = 0
  `).get('production', outputMovementId) as { c: number };
  assert(activeProdLines.c === 0, 'canonical GL lines voided after delete');
  assertClose(stockOf(rawItemId) - rawBefore, 8, 'raw restored +8');
  assertClose(stockOf(fgItemId) - fgBefore, -4, 'output reversed -4');

  // ---------- C5 case 9: loan void keeps row, voids GL unconditionally ----------
  console.log('C5 case 9 — loan void keeps row + voids GL');
  const emp = db.prepare(
    'INSERT INTO employees (employee_code, first_name, last_name, salary) VALUES (?, ?, ?, ?)'
  ).run(`VERIF-EMP-${Date.now()}`, 'Verify', 'Employee', 50000);
  const empId = Number(emp.lastInsertRowid);

  const loanId = EmployeeLoanModel.create({
    employee_id: empId, amount: 1000, disbursement_date: '2026-08-01',
    payment_method: 'cash', created_by: 1,
  }, db);
  AccountingService.postLoanDisbursement(db, {
    loanId, employeeName: 'Verify Employee', employeeCode: 'VERIF-EMP',
    amount: 1000, disbursementDate: '2026-08-01', paymentMethod: 'cash', userId: 1,
  });
  // Simulate the legacy NULL-link state: clear journal_entry_id so the
  // void-by-reference is the only path that can find the GL lines.
  db.prepare('UPDATE employee_loans SET journal_entry_id = NULL WHERE id = ?').run(loanId);
  assert(activeLines('LOAN_DISBURSEMENT', loanId) === 2, 'loan GL lines active before void');

  const voidLoan = db.transaction(() => {
    AccountingService.voidJournalLinesByReference(db, 'LOAN_DISBURSEMENT', loanId, {
      voidedBy: 1, voidReason: 'Loan deleted',
    });
    EmployeeLoanModel.delete(loanId, db, 1, 'Loan deleted');
  });
  voidLoan();
  const loanRow = db.prepare('SELECT voided_at FROM employee_loans WHERE id = ?').get(loanId) as { voided_at: string | null };
  assert(Boolean(loanRow?.voided_at), 'loan row retained with voided_at set');
  assert(activeLines('LOAN_DISBURSEMENT', loanId) === 0, 'loan GL lines voided despite NULL link');

  // ---------- C5 case 10: repayment void keeps row, restores balance ----------
  console.log('C5 case 10 — repayment void keeps row + restores balance');
  const loanId2 = EmployeeLoanModel.create({
    employee_id: empId, amount: 1000, disbursement_date: '2026-08-01',
    payment_method: 'cash', created_by: 1,
  }, db);
  const repaymentId = EmployeeLoanModel.addRepayment({
    loan_id: loanId2, employee_id: empId, amount: 400,
    payment_date: '2026-08-10', payment_method: 'cash',
    repayment_type: 'direct', created_by: 1,
  }, db);
  EmployeeLoanModel.deductBalance(loanId2, 400, db);
  AccountingService.postLoanRepayment(db, {
    repaymentId, loanId: loanId2, employeeName: 'Verify Employee', employeeCode: 'VERIF-EMP',
    amount: 400, paymentDate: '2026-08-10', paymentMethod: 'cash', userId: 1,
  });
  db.prepare('UPDATE employee_loan_repayments SET journal_entry_id = NULL WHERE id = ?').run(repaymentId);
  assert(activeLines('LOAN_REPAYMENT', repaymentId) === 2, 'repayment GL lines active before void');

  const voidRepayment = db.transaction(() => {
    AccountingService.voidJournalLinesByReference(db, 'LOAN_REPAYMENT', repaymentId, {
      voidedBy: 1, voidReason: 'Repayment voided',
    });
    EmployeeLoanModel.restoreBalance(loanId2, 400, db);
    EmployeeLoanModel.deleteRepayment(repaymentId, db, 1, 'Repayment voided');
  });
  voidRepayment();
  const repayRow = db.prepare(
    'SELECT voided_at FROM employee_loan_repayments WHERE id = ?'
  ).get(repaymentId) as { voided_at: string | null };
  assert(Boolean(repayRow?.voided_at), 'repayment row retained with voided_at set');
  assert(activeLines('LOAN_REPAYMENT', repaymentId) === 0, 'repayment GL lines voided despite NULL link');
  assertClose(
    (db.prepare('SELECT balance FROM employee_loans WHERE id = ?').get(loanId2) as { balance: number }).balance,
    1000, 'loan balance restored to 1000');

  // ---------- C6 case 11: payment void keeps row + allocations ----------
  console.log('C6 case 11 — payment void keeps row + allocations');
  const payInvId = createPostedInvoice('VERIF-PAY-INV', 2, 50);
  const paymentId = PaymentModel.create(db, {
    customer_id: customerId, payment_date: '2026-08-11', amount: 100,
    payment_method: 'Cash',
    invoice_allocations: [{ invoice_id: String(payInvId), amount: 100 }],
    userId: 1,
  });
  assert(activeLines('PAYMENT', paymentId) === 2, 'payment GL lines active before void');
  const invPaidBefore = (db.prepare(
    'SELECT paid_amount FROM invoices WHERE id = ?'
  ).get(payInvId) as { paid_amount: number }).paid_amount;
  assertClose(Number(invPaidBefore), 100, 'invoice paid_amount 100 before void');

  PaymentModel.void(db, paymentId, 1, 'Verify void');
  const payRow = db.prepare(
    'SELECT voided_at, void_reason FROM payments WHERE id = ?'
  ).get(paymentId) as { voided_at: string | null; void_reason: string | null };
  assert(Boolean(payRow?.voided_at), 'payment row retained with voided_at set');
  assert(payRow?.void_reason === 'Verify void', 'void reason recorded');
  assert(activeLines('PAYMENT', paymentId) === 0, 'payment GL lines voided');
  const allocRow = db.prepare(
    'SELECT voided_at FROM payment_allocations WHERE payment_id = ?'
  ).get(paymentId) as { voided_at: string | null };
  assert(Boolean(allocRow?.voided_at), 'allocation row retained with voided_at set');
  const invPaidAfter = (db.prepare(
    'SELECT paid_amount FROM invoices WHERE id = ?'
  ).get(payInvId) as { paid_amount: number }).paid_amount;
  assertClose(Number(invPaidAfter), 0, 'invoice paid_amount back to 0 after void');
  const invStatus = (db.prepare(
    'SELECT status FROM invoices WHERE id = ?'
  ).get(payInvId) as { status: string }).status;
  assert(invStatus !== 'Paid', 'invoice no longer Paid after void');

  let doubleVoidBlocked = false;
  try { PaymentModel.void(db, paymentId, 1, 'Double void'); }
  catch { doubleVoidBlocked = true; }
  assert(doubleVoidBlocked, 'double void rejected');

  // ---------- C6 case 12: salary payment void keeps row + GL voided ----------
  console.log('C6 case 12 — salary payment void keeps row + GL voided');
  const salaryPaymentId = EmployeeModel.addSalaryPayment({
    employee_id: empId, amount: 50000, payment_date: '2026-08-05',
    payment_method: 'cash', paid_by: 1, payment_type: 'full',
  }, db);
  AccountingService.postSalaryEntry(db, {
    salaryPaymentId, employeeName: 'Verify Employee', employeeCode: 'VERIF-EMP',
    amount: 50000, paymentDate: '2026-08-05', paymentMethod: 'cash', userId: 1,
  });
  assert(activeLines('SALARY_PAYMENT', salaryPaymentId) === 2, 'salary GL lines active before void');

  const voidSalary = db.transaction(() => {
    AccountingService.voidJournalLinesByReference(db, 'SALARY_PAYMENT', salaryPaymentId, {
      voidedBy: 1, voidReason: 'Salary payment voided',
    });
    EmployeeModel.deleteSalaryPayment(salaryPaymentId, db, 1, 'Salary payment voided');
  });
  voidSalary();
  const salRow = db.prepare(
    'SELECT voided_at, status FROM salary_payments WHERE id = ?'
  ).get(salaryPaymentId) as { voided_at: string | null; status: string };
  assert(Boolean(salRow?.voided_at), 'salary row retained with voided_at set');
  assert(salRow?.status === 'cancelled', 'salary status cancelled');
  assert(activeLines('SALARY_PAYMENT', salaryPaymentId) === 0, 'salary GL lines voided');

  // ---------- C7 case 13: advance GL failure rolls back whole payment ----------
  console.log('C7 case 13 — advance GL failure rolls back everything');
  // Simulate: overpay the month so the auto-advance path fires, then make
  // the salary GL posting throw by removing the wage account mid-flow.
  db.prepare(
    "UPDATE salary_payments SET voided_at = NULL, status = 'paid' WHERE id = ?"
  ).run(salaryPaymentId);
  const advanceTx = db.transaction(() => {
    const advId = EmployeeModel.addSalaryPayment({
      employee_id: empId, amount: 5000, payment_date: '2026-09-01',
      payment_method: 'cash', reference_no: 'ADV-2026-08',
      paid_by: 1, payment_type: 'advance',
    }, db);
    // Wage account missing → postSalaryEntry must throw, and the whole
    // transaction (including the advance row) must roll back.
    db.prepare("DELETE FROM chart_of_accounts WHERE code = '6100'").run();
    AccountingService.postSalaryEntry(db, {
      salaryPaymentId: advId, employeeName: 'Verify Employee', employeeCode: 'VERIF-EMP',
      amount: 5000, paymentDate: '2026-09-01', paymentMethod: 'cash', userId: 1,
    });
    return advId;
  });
  let c7Threw = false;
  try { advanceTx(); }
  catch { c7Threw = true; }
  db.prepare(
    "INSERT OR IGNORE INTO chart_of_accounts (code, name, type, normal_balance, text_code) VALUES ('6100', 'Wages & Salaries', 'expense', 'debit', 'wages_salaries')"
  ).run();
  assert(c7Threw, 'advance GL failure threw');
  const advRow = db.prepare('SELECT COUNT(*) AS c FROM salary_payments WHERE payment_type = \'advance\' AND employee_id = ?').get(empId) as { c: number };
  assert(advRow.c === 0, 'advance row rolled back (not committed without GL)');

  console.log(`\nResult: ${passed} passed, ${failed} failed`);
  fs.rmSync(testDbDir, { recursive: true, force: true });
  process.exit(failed > 0 ? 1 : 0);
}

void main().catch((err) => {
  console.error('Verification crashed:', err);
  fs.rmSync(testDbDir, { recursive: true, force: true });
  process.exit(1);
});
