/**
 * SupplierRefundModel — cash receipt against a supplier credit note.
 * Covers: create (ledger + GL), refundable cap, void reversal.
 */
import Database from 'better-sqlite3';
import SupplierRefundModel, { creditNoteRefundable } from '../models/SupplierRefund';
import PurchaseReturnModel from '../models/PurchaseReturn';
import AccountingService from '../services/accountingService';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());


function setupDb(): Database.Database {
  const db = createFixtureDb({ reference: true });

  db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('admin', 'a@b.c', 'x', 'Admin', 'admin', 1)
  `).run();
  db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
    VALUES ('IT-1', 'Widget', 'Nos', 10, 1, 1)
  `).run();
  db.prepare(`
    INSERT INTO warehouses (warehouse_code, warehouse_name, is_active)
    VALUES ('WH-1', 'Main', 1)
  `).run();
  db.prepare(`
    INSERT INTO suppliers (supplier_code, supplier_name, is_active)
    VALUES ('SUP-1', 'Acme Supplies', 1)
  `).run();

  return db;
}

let seedCounter = 0;

/** Seed a fully-paid purchase + the return against it (disposition stamped). */
function seedReturn(db: Database.Database, opts: { cash?: number; disposition?: string } = {}): {
  returnId: number; creditNoteId: number; total: number;
} {
  seedCounter += 1;
  const qty = 10;
  const unitCost = 10;
  const total = qty * unitCost;

  const itemResult = db.prepare(`
    INSERT INTO purchases (
      purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
      supplier_id, supplier_name, purchase_date, created_by
    ) VALUES (?, 1, 1, ?, ?, ?, 1, 'Acme Supplies', '2026-07-01', 1)
  `).run(`PURCH-SR-${seedCounter}`, qty, unitCost, total);
  const purchaseId = itemResult.lastInsertRowid as number;

  db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, 1, 1, 'PURCHASE', ?, ?, ?, ?, '2026-07-01')
  `).run(`BATCH-SR-${seedCounter}`, purchaseId, qty, qty, unitCost);

  db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity) VALUES (1, 1, ?)
  `).run(qty);
  db.prepare('UPDATE items SET current_stock = ? WHERE id = 1').run(qty);

  // Fully paid → the return must declare a disposition (PRET-06 path).
  const payResult = db.prepare(`
    INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method)
    VALUES (?, 1, '2026-07-01', ?, 'Cash')
  `).run(`PAY-SR-${seedCounter}`, total);
  db.prepare(`
    INSERT INTO purchase_allocations (payment_id, purchase_id, amount)
    VALUES (?, ?, ?)
  `).run(payResult.lastInsertRowid as number, purchaseId, total);

  if (opts.cash !== undefined && opts.cash > 0) {
    // Seed opening cash (Dr cash against opening equity) for GL context.
    const cash = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1000'`).get() as { id: number };
    const equity = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '3000'`).get() as { id: number } | undefined;
    if (equity) {
      AccountingService.postEntry(db, {
        entry_date: '2026-07-01',
        description: 'opening cash',
        lines: [
          { account_id: cash.id, debit: opts.cash, description: 'opening' },
          { account_id: equity.id, credit: opts.cash, description: 'opening' },
        ],
      });
    }
  }

  const created = PurchaseReturnModel.create(
    {
      return_date: '2026-07-02',
      source_type: 'PURCHASE',
      source_id: purchaseId,
      warehouse_id: 1,
      disposition: opts.disposition ?? 'refund_expected',
      items: [{ source_item_id: purchaseId, quantity: qty }],
    },
    1,
    db
  );

  const note = db.prepare(`SELECT id FROM credit_notes WHERE source_id = ?`)
    .get(created.id) as { id: number };

  return { returnId: created.id, creditNoteId: note.id, total };
}

describe('SupplierRefundModel', () => {
  test('create collects a credit-note refund: ledger debit, GL posting, refundable drops', () => {
    const db = setupDb();
    const { creditNoteId, total } = seedReturn(db, { cash: 1000, disposition: 'credit_on_account' });

    expect(creditNoteRefundable(creditNoteId, db)).toBe(total);

    const refund = SupplierRefundModel.create(
      {
        refund_date: '2026-07-03',
        credit_note_id: creditNoteId,
        amount: total,
        payment_method: 'cash',
      },
      1,
      db
    );

    expect(refund.status).toBe('POSTED');
    expect(refund.amount).toBe(total);
    expect(refund.refund_no).toMatch(/^SR-\d{4}-\d{4}$/);

    // Ledger: SUPPLIER_REFUND debit restores the supplier balance to ~0.
    const balance = db.prepare(
      `SELECT balance FROM supplier_ledger WHERE supplier_id = 1 ORDER BY id DESC LIMIT 1`
    ).get() as { balance: number };
    expect(Math.abs(balance.balance)).toBeLessThan(0.01);

    // GL: Dr Cash / Cr AP posted by reference.
    const gl = db.prepare(`
      SELECT SUM(jl.debit) AS dr, SUM(jl.credit) AS cr
      FROM journal_lines jl
      WHERE jl.reference_type = 'SUPPLIER_REFUND' AND jl.reference_id = ? AND jl.voided = 0
      GROUP BY jl.journal_entry_id
    `).all(refund.id) as Array<{ dr: number; cr: number }>;
    expect(gl).toHaveLength(1);
    expect(gl[0].dr).toBeCloseTo(total);
    expect(gl[0].cr).toBeCloseTo(total);

    expect(creditNoteRefundable(creditNoteId, db)).toBe(0);
  });

  test('rejects a refund exceeding the refundable balance', () => {
    const db = setupDb();
    const { creditNoteId, total } = seedReturn(db, { cash: 1000, disposition: 'credit_on_account' });

    expect(() =>
      SupplierRefundModel.create(
        { refund_date: '2026-07-03', credit_note_id: creditNoteId, amount: total + 1 },
        1, db
      )
    ).toThrow(/exceeds the refundable/);
  });

  test('refund_expected return auto-issues the cash refund collection in the same transaction', () => {
    const db = setupDb();
    const { creditNoteId, total } = seedReturn(db, { cash: 1000 });

    // The return itself collected the refund — refundable already 0.
    expect(creditNoteRefundable(creditNoteId, db)).toBe(0);

    const refunds = db.prepare(
      `SELECT * FROM supplier_refunds WHERE credit_note_id = ? AND status = 'POSTED'
    `).all(creditNoteId) as Array<{ amount: number; refund_no: string }>;
    expect(refunds).toHaveLength(1);
    expect(refunds[0].amount).toBe(total);

    // Ledger: CREDIT_NOTE credit + SUPPLIER_REFUND debit → balance ~0.
    const balance = db.prepare(
      `SELECT balance FROM supplier_ledger WHERE supplier_id = 1 ORDER BY id DESC LIMIT 1`
    ).get() as { balance: number };
    expect(Math.abs(balance.balance)).toBeLessThan(0.01);
  });

  test('refund_expected return collects the refund even with zero opening cash', () => {
    const db = setupDb();

    // The refund is money IN from the supplier — no funds guard applies,
    // so zero opening cash must not block the return or the collection.
    const { creditNoteId, total } = seedReturn(db, { cash: 0 });

    const returns = db.prepare(`SELECT COUNT(*) AS n FROM purchase_returns`).get() as { n: number };
    const notes = db.prepare(`SELECT COUNT(*) AS n FROM credit_notes`).get() as { n: number };
    const refunds = db.prepare(`SELECT COUNT(*) AS n FROM supplier_refunds`).get() as { n: number };
    expect(returns.n).toBe(1);
    expect(notes.n).toBe(1);
    expect(refunds.n).toBe(1);
    expect(creditNoteRefundable(creditNoteId, db)).toBe(0);
    expect(total).toBeGreaterThan(0);
  });

  test('PRET-001: voiding a refund_expected return also voids the auto-issued refund', () => {
    const db = setupDb();
    const { returnId, creditNoteId } = seedReturn(db, { cash: 1000 });

    // The refund_expected return auto-issued its cash collection.
    const refund = db.prepare(
      `SELECT id FROM supplier_refunds WHERE credit_note_id = ? AND status = 'POSTED'`
    ).get(creditNoteId) as { id: number };
    expect(refund).toBeDefined();

    PurchaseReturnModel.voidReturn(returnId, 1, 'PRET-001 regression', db);

    // The refund is voided WITH the return — a POSTED refund against a
    // VOIDED credit note made the paid-out cash invisible
    // (creditNoteRefundable returns 0 for a non-POSTED note).
    const after = db.prepare(`SELECT status FROM supplier_refunds WHERE id = ?`)
      .get(refund.id) as { status: string };
    expect(after.status).toBe('VOIDED');

    // GL: both reversal groups fully voided — no fabricated cash/AP survives.
    const live = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines
      WHERE voided = 0
        AND ((reference_type = 'SUPPLIER_REFUND' AND reference_id = ?)
          OR (reference_type = 'PURCHASE_RETURN' AND reference_id = ?))
    `).get(refund.id, returnId) as { n: number };
    expect(live.n).toBe(0);

    // Cash account holds only the seeded opening balance: the refund's
    // Dr 1000 leg is reversed, not left behind.
    const cash = db.prepare(`
      SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS net
      FROM journal_lines jl JOIN chart_of_accounts a ON a.id = jl.account_id
      WHERE a.code = '1000' AND jl.voided = 0
    `).get() as { net: number };
    expect(cash.net).toBeCloseTo(1000, 2);

    // Subledger: the supplier position returns to its pre-return value (~0).
    const balance = db.prepare(
      `SELECT balance FROM supplier_ledger WHERE supplier_id = 1 ORDER BY id DESC LIMIT 1`
    ).get() as { balance: number };
    expect(Math.abs(balance.balance)).toBeLessThan(0.01);
  });

  test('void reverses ledger + GL and restores the refundable balance', () => {
    const db = setupDb();
    const { creditNoteId, total } = seedReturn(db, { cash: 1000, disposition: 'credit_on_account' });

    const refund = SupplierRefundModel.create(
      { refund_date: '2026-07-03', credit_note_id: creditNoteId, amount: total },
      1, db
    );

    const voided = SupplierRefundModel.void(refund.id, 1, 'wrong amount', db);
    expect(voided.status).toBe('VOIDED');

    expect(creditNoteRefundable(creditNoteId, db)).toBe(total);

    // GL reversed (all lines voided by reference).
    const gl = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines jl
      WHERE jl.reference_type = 'SUPPLIER_REFUND' AND jl.reference_id = ? AND jl.voided = 0
    `).get(refund.id) as { n: number };
    expect(gl.n).toBe(0);

    // Voiding an already-voided refund fails.
    expect(() => SupplierRefundModel.void(refund.id, 1, '', db))
      .toThrow(/Only POSTED/);
  });
});
