/**
 * H7 — Supplier payment allocations must reconcile.
 *
 * A supplier payment of 1000 used to be accepted with a single 100
 * allocation: the supplier balance and the GL cash posting paid out the
 * full 1000 while the purchase balances only dropped by 100. The payment
 * is the single source of truth for "how much left the business", so for
 * a normal allocated supplier payment:
 *
 *     SUM(po_allocations + purchase_allocations) == payment amount
 *
 * There is no supplier-advance / unallocated-payment concept here —
 * advances exist only on the employee-salary side — so the match is
 * exact. The guard lives in PaymentModel.createSupplierPayment, inside
 * the transaction and before the first INSERT, so a rejected payment
 * changes nothing.
 */
import Database from 'better-sqlite3';
import PaymentModel from '../models/Payment';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());


function createFixture(): Database.Database {
  const db = createFixtureDb({ reference: true });
  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  // Seed opening capital in Cash so supplier payouts clear the funds guard
  // (same pattern as glPostingMatrix — Cash is read from journal_lines).
  OwnerCapitalModel.create(db, {
    capital_no: generateCapitalNo(db, '2026-01-01'),
    capital_date: '2026-01-01',
    amount: 1_000_000,
    payment_method: 'Cash',
    created_by: 1,
  });

  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name,is_active,current_balance)
              VALUES ('S1','Acme',1,0)`).run();
  db.prepare(`INSERT INTO items (item_code,item_name,unit_of_measure,standard_cost,is_purchased,is_active)
              VALUES ('IT-A','Widget','Nos',20,1,1)`).run();
  db.prepare(`INSERT INTO warehouses (warehouse_code,warehouse_name,is_active)
              VALUES ('W1','Main',1)`).run();
  return db;
}

/** Seed one open direct purchase owed to supplier 1. */
function seedPurchase(db: Database.Database, totalCost: number): number {
  db.prepare(`
    INSERT INTO purchases (purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
                           purchase_date, supplier_id, created_by)
    VALUES (?, 1, 1, 1, ?, ?, '2026-09-01', 1, 1)
  `).run(`PUR-${Math.floor(Math.random() * 1e6)}`, totalCost, totalCost);
  return (db.prepare('SELECT id FROM purchases ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
}

/** Seed one open purchase order owed to supplier 1. */
function seedPo(db: Database.Database, totalAmount: number): number {
  db.prepare(`
    INSERT INTO purchase_orders (po_no, supplier_id, po_date, total_amount, status)
    VALUES (?, 1, '2026-09-01', ?, 'approved')
  `).run(`PO-${Math.floor(Math.random() * 1e6)}`, totalAmount);
  return (db.prepare('SELECT id FROM purchase_orders ORDER BY id DESC LIMIT 1').get() as { id: number }).id;
}

function countPayments(db: Database.Database): number {
  return (db.prepare('SELECT COUNT(*) n FROM payments').get() as { n: number }).n;
}

describe('H7 — supplier payment allocations must reconcile with the payment amount', () => {
  it('an exact single allocation succeeds and settles the purchase', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 1000);

    const paymentId = PaymentModel.createSupplierPayment(db, {
      supplier_id: 1,
      payment_date: '2026-09-05',
      amount: 1000,
      payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: String(purchaseId), amount: 1000 }],
      userId: 1,
    });

    expect(paymentId).toBeGreaterThan(0);
    const paid = db.prepare(
      'SELECT COALESCE(SUM(amount),0) n FROM purchase_allocations WHERE purchase_id = ? AND voided_at IS NULL'
    ).get(purchaseId) as { n: number };
    expect(Number(paid.n)).toBe(1000);
    db.close();
  });

  it('UNDER-allocation is rejected (1000 payment, single 100 allocation)', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 1000);
    const before = countPayments(db);

    expect(() =>
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-05',
        amount: 1000,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: String(purchaseId), amount: 100 }],
        userId: 1,
      }),
    ).toThrow(/does not match the payment amount/);

    // Nothing was written — no payment row, no allocation, no ledger move.
    expect(countPayments(db)).toBe(before);
    const allocs = db.prepare('SELECT COUNT(*) n FROM purchase_allocations').get() as { n: number };
    expect(Number(allocs.n)).toBe(0);
    const ledger = db.prepare('SELECT COUNT(*) n FROM supplier_ledger').get() as { n: number };
    expect(Number(ledger.n)).toBe(0);
    db.close();
  });

  it('OVER-allocation is rejected (100 payment, allocations totalling 1000)', () => {
    const db = createFixture();
    const p1 = seedPurchase(db, 600);
    const p2 = seedPurchase(db, 400);
    const before = countPayments(db);

    expect(() =>
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-05',
        amount: 100,
        payment_method: 'Cash',
        purchase_allocations: [
          { purchase_id: String(p1), amount: 600 },
          { purchase_id: String(p2), amount: 400 },
        ],
        userId: 1,
      }),
    ).toThrow(/does not match the payment amount/);

    expect(countPayments(db)).toBe(before);
    const allocs = db.prepare('SELECT COUNT(*) n FROM purchase_allocations').get() as { n: number };
    expect(Number(allocs.n)).toBe(0);
    db.close();
  });

  it('a multi-document allocation succeeds when the total equals the payment', () => {
    const db = createFixture();
    const p1 = seedPurchase(db, 600);
    const p2 = seedPurchase(db, 400);

    const paymentId = PaymentModel.createSupplierPayment(db, {
      supplier_id: 1,
      payment_date: '2026-09-05',
      amount: 1000,
      payment_method: 'Cash',
      purchase_allocations: [
        { purchase_id: String(p1), amount: 600 },
        { purchase_id: String(p2), amount: 400 },
      ],
      userId: 1,
    });

    expect(paymentId).toBeGreaterThan(0);
    const total = db.prepare(
      'SELECT COALESCE(SUM(amount),0) n FROM purchase_allocations WHERE payment_id = ?'
    ).get(paymentId) as { n: number };
    expect(Number(total.n)).toBe(1000);
    db.close();
  });

  it('a mixed PO + purchase allocation succeeds when the total equals the payment', () => {
    const db = createFixture();
    const poId = seedPo(db, 300);
    const purchaseId = seedPurchase(db, 700);

    const paymentId = PaymentModel.createSupplierPayment(db, {
      supplier_id: 1,
      payment_date: '2026-09-05',
      amount: 1000,
      payment_method: 'Cash',
      po_allocations: [{ po_id: String(poId), amount: 300 }],
      purchase_allocations: [{ purchase_id: String(purchaseId), amount: 700 }],
      userId: 1,
    });

    expect(paymentId).toBeGreaterThan(0);
    const poTotal = db.prepare(
      'SELECT COALESCE(SUM(amount),0) n FROM po_allocations WHERE payment_id = ?'
    ).get(paymentId) as { n: number };
    const purTotal = db.prepare(
      'SELECT COALESCE(SUM(amount),0) n FROM purchase_allocations WHERE payment_id = ?'
    ).get(paymentId) as { n: number };
    expect(Number(poTotal.n)).toBe(300);
    expect(Number(purTotal.n)).toBe(700);
    db.close();
  });

  it('an allocation still cannot exceed the document balance', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 500);

    // The 1000 total matches the payment, but the single document is only
    // owed 500 — the per-document balance guard must fire first.
    expect(() =>
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-05',
        amount: 1000,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: String(purchaseId), amount: 1000 }],
        userId: 1,
      }),
    ).toThrow(/exceeds the remaining balance/);

    expect(countPayments(db)).toBe(0);
    db.close();
  });

  it('a rejected payment leaves the supplier balance, ledger and GL untouched', () => {
    const db = createFixture();
    const purchaseId = seedPurchase(db, 1000);

    // A first, correctly-allocated payment settles the purchase and moves
    // the supplier balance by the full amount.
    PaymentModel.createSupplierPayment(db, {
      supplier_id: 1,
      payment_date: '2026-09-05',
      amount: 1000,
      payment_method: 'Cash',
      purchase_allocations: [{ purchase_id: String(purchaseId), amount: 1000 }],
      userId: 1,
    });
    const supplierRow = () => db.prepare(
      'SELECT current_balance FROM suppliers WHERE id = 1'
    ).get() as { current_balance: number };
    const ledgerCount = () => (db.prepare(
      'SELECT COUNT(*) n FROM supplier_ledger'
    ).get() as { n: number }).n;
    const paymentCount = () => countPayments(db);

    expect(Number(supplierRow().current_balance)).toBeCloseTo(-1000, 2);
    const ledgerAfter = ledgerCount();
    const paymentsAfter = paymentCount();

    // A second payment under-allocates against a FRESH purchase (still owed
    // in full, so the per-document balance guard lets 100 through) — the H7
    // reconciliation guard must reject it and change nothing.
    const otherPurchaseId = seedPurchase(db, 500);
    expect(() =>
      PaymentModel.createSupplierPayment(db, {
        supplier_id: 1,
        payment_date: '2026-09-06',
        amount: 500,
        payment_method: 'Cash',
        purchase_allocations: [{ purchase_id: String(otherPurchaseId), amount: 100 }],
        userId: 1,
      }),
    ).toThrow(/does not match the payment amount/);

    expect(Number(supplierRow().current_balance)).toBeCloseTo(-1000, 2);
    expect(ledgerCount()).toBe(ledgerAfter);
    expect(paymentCount()).toBe(paymentsAfter);
    // Not even an allocation row leaked for the rejected payment.
    const otherAllocs = db.prepare(
      'SELECT COUNT(*) n FROM purchase_allocations WHERE purchase_id = ?'
    ).get(otherPurchaseId) as { n: number };
    expect(Number(otherAllocs.n)).toBe(0);
    db.close();
  });
});
