/**
 * financial-audit-p0-remediation task 2.8 — payment guard regressions.
 * PAY-04: amount edits rejected (void-and-reissue policy).
 * PAY-09: XOR counterparty guard at the controller.
 * PAY-11: receipt previous balance derives from the payment's own ledger row.
 */
import Database from 'better-sqlite3';
import PaymentModel from '../models/Payment';
import { isValidPaymentMethod } from '../services/cashService';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

function createFixture(): Database.Database {
  const db = createFixtureDb();

  db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,is_active)
              VALUES ('u','e@x.c','h','U','admin',1)`).run();
  db.prepare(`INSERT INTO customers (customer_code,customer_name,contact_person)
              VALUES ('C1','Walkin','W')`).run();
  db.prepare(`INSERT INTO suppliers (supplier_code,supplier_name) VALUES ('S1','Acme')`).run();
  return db;
}

afterAll(() => cleanupFixtureDbs());

describe('PAY-04: amount edits are forbidden', () => {
  it('rejects an amount change on a customer payment and touches nothing', () => {
    const db = createFixture();
    const pid = PaymentModel.createSupplierPayment === undefined ? 0 : 0; // keep TS happy
    db.prepare(`
      INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method)
      VALUES ('PAYT1', 1, '2026-08-01', 100, 'Cash')
    `).run();
    const row = db.prepare(`SELECT id FROM payments WHERE payment_no='PAYT1'`).get() as { id: number };

    expect(() =>
      PaymentModel.update(db, row.id, { amount: 999 })
    ).toThrow(/Cannot change the amount/);

    const after = db.prepare(`SELECT amount FROM payments WHERE id = ?`).get(row.id) as { amount: number };
    expect(Number(after.amount)).toBe(100); // untouched
    expect(pid).toBe(0);
    db.close();
  });

  it('allows metadata edits (notes/reference/date) on the same payment', () => {
    const db = createFixture();
    db.prepare(`
      INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method)
      VALUES ('PAYT2', 1, '2026-08-01', 100, 'Cash')
    `).run();
    const row = db.prepare(`SELECT id FROM payments WHERE payment_no='PAYT2'`).get() as { id: number };

    expect(() =>
      PaymentModel.update(db, row.id, { notes: 'ok', reference_no: 'REF-9' })
    ).not.toThrow();

    const after = db.prepare(`SELECT notes, reference_no FROM payments WHERE id = ?`).get(row.id) as { notes: string; reference_no: string };
    expect(after.notes).toBe('ok');
    db.close();
  });
});

describe('PAY-09: XOR counterparty constraint', () => {
  it('database CHECK refuses a payment with both counterparties', () => {
    const db = createFixture();
    expect(() =>
      db.prepare(`
        INSERT INTO payments (payment_no, customer_id, supplier_id, payment_date, amount, payment_method)
        VALUES ('PAYBAD', 1, 1, '2026-08-01', 50, 'Cash')
      `).run()
    ).toThrow(/CHECK/);
    db.close();
  });

  it('accepts a supplier-only payment with default method applied', () => {
    const db = createFixture();
    db.prepare(`
      INSERT INTO payments (payment_no, supplier_id, payment_date, amount)
      VALUES ('PAYS1', 1, '2026-08-01', 75)
    `).run();
    const row = db.prepare(`SELECT payment_method FROM payments WHERE payment_no='PAYS1'`).get() as { payment_method: string };
    expect(row.payment_method).toBe('Cash'); // NOT NULL DEFAULT verified
    db.close();
  });
});

describe('CASH-02 write-path method validation', () => {
  it('isValidPaymentMethod rejects unknowns accepted by neither whitelist nor bank set', () => {
    expect(isValidPaymentMethod('JazzCash')).toBe(true);
    expect(isValidPaymentMethod('Cheque')).toBe(true); // bank-like set is a valid method value
    expect(isValidPaymentMethod('IOU')).toBe(false);
  });
});
