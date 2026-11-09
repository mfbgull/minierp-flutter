import Database from 'better-sqlite3';
import ledgerUtils from '../utils/ledgerUtils';
import { computePosition } from '../services/returnMath';
import { computeARAging } from '../models/arAging';
import { assertNoPartyAdjustment } from '../utils/partyAdjustmentBalances';
import PaymentModel from '../models/Payment';
import Reports from '../models/Reports';

describe('noncash party adjustment balances', () => {
  let db: Database.Database;
  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE invoices (id INTEGER PRIMARY KEY, total_amount REAL, returned_amount REAL DEFAULT 0,
        return_fee REAL DEFAULT 0, credit_offset REAL DEFAULT 0, paid_amount REAL DEFAULT 0,
        adjusted_amount REAL DEFAULT 0, balance_amount REAL, due_date TEXT, status TEXT,
        payment_status TEXT, return_status TEXT, customer_id INTEGER DEFAULT 1,
        invoice_date TEXT DEFAULT '2026-10-01', deleted_at TEXT);
      CREATE TABLE customers (id INTEGER PRIMARY KEY, customer_name TEXT, customer_code TEXT);
      INSERT INTO customers VALUES (1,'Dual role','DUAL');
      CREATE TABLE payments (id INTEGER PRIMARY KEY, payment_kind TEXT, payment_date TEXT, voided_at TEXT);
      CREATE TABLE payment_allocations (invoice_id INTEGER, amount REAL, voided_at TEXT, payment_id INTEGER);
      CREATE TABLE party_adjustments (id INTEGER PRIMARY KEY, status TEXT, adjustment_date TEXT, reversal_date TEXT);
      CREATE TABLE party_adjustment_receivables (adjustment_id INTEGER, invoice_id INTEGER, amount REAL);
      CREATE TABLE party_adjustment_payables (adjustment_id INTEGER, purchase_id INTEGER, purchase_order_id INTEGER, bill_id INTEGER, amount REAL);
      CREATE TABLE credit_source_consumptions (invoice_id INTEGER, amount REAL, application_id INTEGER, source_id INTEGER, kind TEXT, voided_at TEXT);
      CREATE TABLE credit_applications (id INTEGER, operation_date TEXT);
      CREATE TABLE customer_credit_sources (id INTEGER, kind TEXT, voided_at TEXT);
      CREATE TABLE invoice_returns (invoice_id INTEGER, returned_amount REAL, fee_amount REAL, return_date TEXT, voided_at TEXT, status TEXT);
      CREATE TABLE suppliers (id INTEGER PRIMARY KEY, supplier_name TEXT, supplier_code TEXT);
      CREATE TABLE supplier_ledger (id INTEGER PRIMARY KEY, supplier_id INTEGER, transaction_date TEXT,
        transaction_type TEXT, reference_no TEXT, debit REAL DEFAULT 0, credit REAL DEFAULT 0,
        voided INTEGER DEFAULT 0, reversed_by INTEGER);
      CREATE TABLE purchases (id INTEGER PRIMARY KEY, purchase_no TEXT, supplier_id INTEGER);
      CREATE TABLE goods_receipts (id INTEGER PRIMARY KEY, receipt_no TEXT, po_id INTEGER);
      CREATE TABLE supplier_bills (id INTEGER PRIMARY KEY, bill_no TEXT, supplier_id INTEGER);
      INSERT INTO invoices (id,total_amount,balance_amount,status) VALUES (1,2000,2000,'Unpaid');
      INSERT INTO party_adjustments VALUES (1,'posted','2026-11-01',NULL);
      INSERT INTO party_adjustment_receivables VALUES (1,1,1000);
    `);
  });
  afterEach(() => db.close());

  it('reduces invoice debt without increasing collected cash', () => {
    const balance = ledgerUtils.calculateInvoiceBalance(1, db);
    expect(balance).toBe(1000);
    expect(db.prepare('SELECT paid_amount, adjusted_amount FROM invoices WHERE id = 1').get())
      .toEqual({ paid_amount: 0, adjusted_amount: 1000 });
  });

  it('clears the remaining debt with a real receipt', () => {
    db.exec('INSERT INTO payment_allocations (invoice_id,amount) VALUES (1,1000)');
    const balance = ledgerUtils.calculateInvoiceBalance(1, db);
    expect(balance).toBe(0);
    expect(db.prepare('SELECT paid_amount, adjusted_amount FROM invoices WHERE id = 1').get())
      .toEqual({ paid_amount: 1000, adjusted_amount: 1000 });
  });

  it('restores only the adjustment when it is reversed after a receipt', () => {
    db.exec("INSERT INTO payment_allocations (invoice_id,amount) VALUES (1,1000); UPDATE party_adjustments SET status='reversed', reversal_date='2026-11-02'");
    expect(ledgerUtils.calculateInvoiceBalance(1, db)).toBe(1000);
    expect(db.prepare('SELECT paid_amount, adjusted_amount FROM invoices WHERE id = 1').get())
      .toEqual({ paid_amount: 1000, adjusted_amount: 0 });
  });

  it('includes noncash settlement in return credit entitlement while retaining cash separately', () => {
    const input = { originalTotal: 2000, totalReturned: 1500, totalFees: 0,
      totalPaid: 0, totalAdjusted: 1000, totalSettled: 0 };
    const position = computePosition(input);
    expect(position.balanceDue).toBe(0);
    expect(position.refundCreditDue).toBe(500);
    expect(position.totalPaid).toBe(0);
  });

  it('does not make noncash adjustment refundable as cash', () => {
    ledgerUtils.calculateInvoiceBalance(1, db);
    expect(PaymentModel.refundableOnInvoice(db, 1)).toBe(0);
  });

  it('reconstructs debt before posting, during settlement, and after reversal', () => {
    db.exec("UPDATE party_adjustments SET status='reversed', reversal_date='2026-11-10'");
    expect(computeARAging('2026-10-31', db).summary.totalReceivables).toBe(2000);
    expect(computeARAging('2026-11-01', db).summary.totalReceivables).toBe(1000);
    expect(computeARAging('2026-11-09', db).summary.totalReceivables).toBe(1000);
    expect(computeARAging('2026-11-10', db).summary.totalReceivables).toBe(2000);
    expect(Reports.getReceivablesSummary(db, '2026-10-31').total_outstanding).toBe(2000);
    expect(Reports.getReceivablesSummary(db, '2026-11-01').total_outstanding).toBe(1000);
    expect(Reports.getReceivablesSummary(db, '2026-11-10').total_outstanding).toBe(2000);
    expect(Reports.getTopDebtors(db, 10, '2026-11-01')).toEqual([
      expect.objectContaining({ total_outstanding: 1000 }),
    ]);
  });

  it('blocks source changes until the adjustment is reversed', () => {
    expect(() => assertNoPartyAdjustment(db, 'invoice', 1)).toThrow();
    db.exec("UPDATE party_adjustments SET status='reversed', reversal_date='2026-11-02'");
    expect(() => assertNoPartyAdjustment(db, 'invoice', 1)).not.toThrow();
  });

  it.each(['purchase', 'purchase_order', 'supplier_bill'] as const)('blocks an adjusted %s source', (kind) => {
    db.prepare('INSERT INTO party_adjustment_payables VALUES (1,?,?,?,1000)')
      .run(kind === 'purchase' ? 1 : null, kind === 'purchase_order' ? 1 : null, kind === 'supplier_bill' ? 1 : null);
    expect(() => assertNoPartyAdjustment(db, kind, 1)).toThrow();
    expect(() => assertNoPartyAdjustment(db, kind, 2)).not.toThrow();
  });

  it('ages the unpaid older bill when the adjustment targets the newer bill', () => {
    db.exec(`INSERT INTO suppliers VALUES (1,'Dual role','DUAL');
      INSERT INTO supplier_bills VALUES (1,'OLD',1),(2,'NEW',1);
      INSERT INTO supplier_ledger (id,supplier_id,transaction_date,transaction_type,reference_no,debit)
        VALUES (1,1,'2026-07-01','SUPPLIER_BILL','BILL-1',1000),
          (2,1,'2026-11-01','SUPPLIER_BILL','BILL-2',1000);
      INSERT INTO party_adjustment_payables VALUES (1,NULL,NULL,2,1000);`);
    const report = Reports.getAPAgingReport('2026-11-01', db);
    expect(report.agingBuckets).toEqual([expect.objectContaining({
      total_outstanding: 1000, days_over_90: 1000, current_amount: 0,
    })]);
    db.exec("UPDATE party_adjustments SET status='reversed', reversal_date='2026-11-10'");
    expect(Reports.getAPAgingReport('2026-11-01', db).summary.totalPayables).toBe(1000);
    expect(Reports.getAPAgingReport('2026-11-10', db).summary.totalPayables).toBe(2000);
  });
});
