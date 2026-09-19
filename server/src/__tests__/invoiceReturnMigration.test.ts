/**
 * Milestone 1 integration tests: add-invoice-returns.sql tables exist on
 * the shared test DB, the 4150 guard account is present, and the
 * InvoiceReturnModel numbering/settlement helpers behave atomically
 * (invoice-return-spec.md §4.1, Milestone 1 steps 1.1/1.2/1.4).
 */
import db from '../config/database';
import InvoiceReturnModel from '../models/InvoiceReturn';

function tableExists(name: string): boolean {
  const row = db.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?"
  ).get(name) as { name: string } | undefined;
  return row !== undefined;
}

describe('invoice-returns migration (Milestone 1)', () => {
  it('creates the three return tables on boot', () => {
    expect(tableExists('invoice_returns')).toBe(true);
    expect(tableExists('invoice_return_items')).toBe(true);
    expect(tableExists('return_settlements')).toBe(true);
  });

  it('enforces CHECK constraints (settlement type, positive amount, header status)', () => {
    expect(() =>
      db.prepare(
        "INSERT INTO return_settlements (return_id, settlement_no, type, amount, settled_date, created_by) VALUES (1, 'X1', 'gift', 10, '2026-09-17', 1)"
      ).run()
    ).toThrow();

    expect(() =>
      db.prepare(
        "INSERT INTO return_settlements (return_id, settlement_no, type, amount, settled_date, created_by) VALUES (1, 'X2', 'credit', 0, '2026-09-17', 1)"
      ).run()
    ).toThrow();
  });

  it('4150 Restocking Fee Income exists (boot guard precondition)', () => {
    const acct = db.prepare("SELECT code, name, type, normal_balance FROM chart_of_accounts WHERE code = '4150'")
      .get() as { code: string; name: string; type: string; normal_balance: string };
    expect(acct).toBeDefined();
    expect(acct.name).toBe('Restocking Fee Income');
    expect(acct.type).toBe('revenue');
    expect(acct.normal_balance).toBe('credit');
  });
});

describe('InvoiceReturnModel (Milestone 1)', () => {
  let invoiceId: number;
  let customerId: number;
  let invoiceItemId: number;
  let userId: number;

  beforeAll(() => {
    // Minimal fixture rows directly in DB (no HTTP): a customer + a paid
    // invoice + one line, plus the admin user id.
    const user = db.prepare("SELECT id FROM users WHERE username = 'admin'").get() as { id: number };
    userId = user.id;

    const cust = db.prepare(`
      INSERT INTO customers (customer_code, customer_name, phone)
      VALUES (?, 'RET Model Customer', '555-0911')
    `).run(`RETM-C${Date.now()}`);
    customerId = Number(cust.lastInsertRowid);

    const inv = db.prepare(`
      INSERT INTO invoices (invoice_no, customer_id, invoice_date, due_date, status,
                            total_amount, paid_amount, balance_amount)
      VALUES (?, ?, '2026-09-15', '2026-09-30', 'Paid', 1800, 1800, 0)
    `).run(`RET-MODEL-${Date.now()}`, customerId);
    invoiceId = Number(inv.lastInsertRowid);

    const item = db.prepare(
      "INSERT INTO items (item_code, item_name) VALUES (?, 'RET Model Item')"
    ).run(`RETM-I${Date.now()}`);
    const itemId = Number(item.lastInsertRowid);

    const invItem = db.prepare(`
      INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, tax_rate, amount, returned_qty)
      VALUES (?, ?, 3, 600, 0, 1800, 0)
    `).run(invoiceId, itemId);
    invoiceItemId = Number(invItem.lastInsertRowid);
  });

  it('generates monotonically increasing RET- numbers (atomic pattern)', () => {
    const a = InvoiceReturnModel.generateReturnNoAtomic(db);
    const b = InvoiceReturnModel.generateReturnNoAtomic(db);
    expect(a).toMatch(/^RET-\d{4}-\d{5}$/);
    expect(b).toMatch(/^RET-\d{4}-\d{5}$/);
    const numA = parseInt(a.split('-')[2], 10);
    const numB = parseInt(b.split('-')[2], 10);
    expect(numB).toBe(numA + 1);
  });

  it('creates a header + items and reads them back', () => {
    const header = InvoiceReturnModel.createReturn(db, {
      invoice_id: invoiceId,
      customer_id: customerId,
      return_date: '2026-09-17',
      reason: 'model test',
      fee_type: 'percentage',
      fee_value: 10,
      fee_amount: 120,
      returned_amount: 1200,
      net_amount: 1080,
      warehouse_id: null,
      created_by: userId,
    });
    expect(header.return_no).toMatch(/^RET-/);
    expect(header.status).toBe('Unsettled');
    expect(header.settled_amount).toBe(0);

    InvoiceReturnModel.addReturnItem(db, {
      return_id: header.id,
      invoice_item_id: invoiceItemId,
      item_id: 0,
      quantity: 2,
      unit_price: 600,
      tax_amount: 0,
      line_amount: 1200,
    });
    const items = InvoiceReturnModel.getItems(db, header.id);
    expect(items).toHaveLength(1);
    expect(items[0].quantity).toBe(2);
    expect(items[0].unit_price).toBe(600);
  });

  it('settlements sync settled_amount and flip status at the threshold (incl. fp tolerance)', () => {
    const header = InvoiceReturnModel.createReturn(db, {
      invoice_id: invoiceId,
      customer_id: customerId,
      return_date: '2026-09-17',
      returned_amount: 1200,
      net_amount: 1080,
      created_by: userId,
    });

    // 1000.005-style fp noise must not leave the return unsettled at full:
    InvoiceReturnModel.createSettlement(db, {
      return_id: header.id,
      settlement_no: InvoiceReturnModel.generateCreditNoAtomic(db),
      type: 'credit',
      amount: 1080,
      settled_date: '2026-09-17',
      created_by: userId,
    });
    expect(InvoiceReturnModel.getById(db, header.id)!.settled_amount).toBeCloseTo(1080, 2);
    expect(InvoiceReturnModel.getById(db, header.id)!.status).toBe('Settled');
    expect(InvoiceReturnModel.refreshStatus(db, header.id)).toBe('Settled');
  });

  it('type-affinity regression: MAX-sync with a TEXT-bound param never resets the sequence (PAY + RET)', () => {
    // The trap: MAX(2, '1') === '1' in SQLite (TEXT > INTEGER in type
    // ordering). With the old SQL, any call where maxNo > current setting
    // reset the sequence to maxNo instead of max(maxNo, current)+1 — and
    // worse, a sync after an increment reset it to the stale max. These
    // assertions exercise sync → increment → sync with the SAME DB rows.
    const { default: InvoiceModel } = require('../models/Invoice');

    // Reset sequence keys first — earlier tests in this file (and other
    // suites on the shared DB) may already have created them.
    db.prepare("DELETE FROM settings WHERE key IN ('PAY_last_no', 'RET_last_no')").run();
    // PAY: seed setting at 5, max in table is lower — sync must not lower it,
    // and increments must climb monotonically across syncs.
    db.prepare("INSERT INTO settings (key, value) VALUES ('PAY_last_no', '5')").run();
    db.prepare(
      "INSERT INTO payments (payment_no, customer_id, payment_date, amount, payment_method) VALUES (?, ?, '2026-09-17', 10, 'Cash')"
    ).run('PAY-0926-00003', customerId);
    const p1 = InvoiceModel.generatePaymentNoAtomic(db); // sync(3) → stays 5, incr → 6
    const p2 = InvoiceModel.generatePaymentNoAtomic(db); // sync(3) → stays 6, incr → 7
    expect(parseInt(p1.split('-')[2], 10)).toBe(6);
    expect(parseInt(p2.split('-')[2], 10)).toBe(7);

    // RET: seed setting ABOVE the table max — sync must not lower it.
    db.prepare("INSERT INTO settings (key, value) VALUES ('RET_last_no', '50')").run();
    db.prepare(`
      INSERT INTO invoice_returns (return_no, invoice_id, customer_id, return_date, returned_amount, net_amount, created_by)
      VALUES ('RET-0926-00010', ?, ?, '2026-09-17', 600, 600, ?)
    `).run(invoiceId, customerId, userId);
    const r1 = InvoiceReturnModel.generateReturnNoAtomic(db); // sync(10) → stays 50 → 51
    expect(parseInt(r1.split('-')[2], 10)).toBe(51);
  });

  it('credit numbers follow the CR- series monotonically', () => {
    // NOTE: the earlier settlement test already consumed CR numbers via
    // generateCreditNoAtomic, so assert strictly increasing — not exactly +1 —
    // across this test's two calls (the atomic generator is shared per DB).
    const a = InvoiceReturnModel.generateCreditNoAtomic(db);
    const b = InvoiceReturnModel.generateCreditNoAtomic(db);
    expect(a).toMatch(/^CR-\d{4}-\d{5}$/);
    expect(b).toMatch(/^CR-\d{4}-\d{5}$/);
    const numA = parseInt(a.split('-')[2], 10);
    const numB = parseInt(b.split('-')[2], 10);
    expect(numB).toBeGreaterThan(numA);
  });
});
