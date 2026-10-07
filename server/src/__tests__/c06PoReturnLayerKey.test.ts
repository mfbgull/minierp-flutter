import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import PurchaseOrderModel from '../models/PurchaseOrder';
import PurchaseReturnModel from '../models/PurchaseReturn';

/**
 * C-06 — PO-source purchase returns.
 *
 * The layer lookup used to key on `source_id = purchase_order_items.id`, while
 * `PurchaseOrder.addReceipt` writes `source_id = goods_receipt_items.id`.
 * Independent autoincrement sequences, so the lookup matched nothing and every
 * PO return failed. The suite stayed green because the old fixture hand-wrote
 * `source_id = poItemId` — a shape production never produces.
 *
 * Every fixture in this file goes through the real `addReceipt`, so the test
 * data has the same shape production writes.
 */

function createFixture(): Database.Database {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');

  const migrations = [
    'init.sql',
    'add-purchases-table.sql',
    'add-purchase-return-fields.sql',
    'add-batch-costing.sql',
    'add-stock-adjustment-financial.sql',
    'create-supplier-ledger.sql',
    'add-gl-foundation.sql',
    'create-payment-allocations.sql',
    'add-supplier-payment-support.sql',
    'add-purchase-supplier-payment.sql',
    'add-purchase-returns-tables.sql',
    'add-purchase-return-batches.sql',
    'add-disposition-and-supplier-refunds.sql',
    'create-customer-ledger.sql',
    'add-gl-void-attribution.sql',
    'add-production-tables.sql',
    'add-payments-purchase-order-id.sql',
    'add-invoice-soft-delete.sql',
    'add-audit-trail-fields.sql',
    'add-salary-payments.sql',
    'add-payment-salary-void-columns.sql',
  ];

  for (const file of migrations) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', file), 'utf8'));
  }

  const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all() as { name: string }[];
  if (!supCols.some((c) => c.name === 'current_balance')) {
    db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
  }

  const mvCols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all() as { name: string }[];
  const has = (n: string) => mvCols.some((c) => c.name === n);
  if (!has('batch_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
  if (!has('financial_value')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
  if (!has('financial_posted')) db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
  if (!has('journal_entry_id')) db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');

  for (const file of ['add-item-expiry-tracking.sql', 'add-expired-stock.sql']) {
    db.exec(fs.readFileSync(path.join(__dirname, '..', 'migrations', file), 'utf8'));
  }

  db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('admin', 'a@b.c', 'x', 'Admin', 'admin', 1)
  `).run();
  db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
    VALUES ('IT-1', 'Widget', 'Nos', 10, 1, 1)
  `).run();
  db.prepare(`
    INSERT INTO warehouses (warehouse_code, warehouse_name, is_active) VALUES ('WH-1', 'Main', 1)
  `).run();
  db.prepare(`
    INSERT INTO suppliers (supplier_code, supplier_name, is_active) VALUES ('SUP-1', 'Acme', 1)
  `).run();

  desyncReceiptItemSequence(db);

  return db;
}

/**
 * Desynchronise `goods_receipt_items.id` from `purchase_order_items.id`.
 *
 * In a pristine database both sequences start at 1 and advance in lockstep, so
 * the wrong-key bug is invisible: `source_id = 1` accidentally matches
 * `goods_receipt_items.id = 1`. Production desynchronises them the moment a
 * receipt item exists without a surviving PO line (voided receipt, re-keyed
 * receipt, migrated history), which is why the audit measured 100% failure on
 * real data while a clean-DB fixture looked healthy.
 *
 * Inserting receipt items directly reproduces that offset deterministically.
 */
function desyncReceiptItemSequence(db: Database.Database, offset = 3): void {
  const poId = db.prepare(`
    INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount, warehouse_id, created_by)
    VALUES ('PO-DESEED', 1, '2026-06-01', 'Submitted', 0, 1, 1)
  `).run().lastInsertRowid as number;

  const poItemId = db.prepare(`
    INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity, unit_price, amount)
    VALUES (?, 1, 0, 0, 10, 0)
  `).run(poId).lastInsertRowid as number;

  const receiptId = db.prepare(`
    INSERT INTO goods_receipts (receipt_no, po_id, receipt_date, warehouse_id, created_by)
    VALUES (?, ?, '2026-06-01', 1, 1)
  `).run(`GR-DESEED-${Date.now()}`, poId).lastInsertRowid as number;

  for (let i = 0; i < offset; i++) {
    db.prepare(`
      INSERT INTO goods_receipt_items (receipt_id, po_item_id, item_id, received_quantity)
      VALUES (?, ?, 1, 0)
    `).run(receiptId, poItemId);
  }
}

/** Seed a submitted PO with one line. Goes through real INSERTs only. */
type PoSeed = { itemId?: number; qty?: number; received?: number; unitPrice?: number };

function seedPo(db: Database.Database, s: PoSeed = {}) {
  const itemId = s.itemId ?? 1;
  const qty = s.qty ?? 10;
  const unitPrice = s.unitPrice ?? 50;

  if (!db.prepare('SELECT id FROM items WHERE id = ?').get(itemId)) {
    db.prepare(`
      INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
      VALUES (?, ?, ?, 'Nos', ?, 1, 1)
    `).run(itemId, `IT-${itemId}`, `Item ${itemId}`, unitPrice);
  }

  const poId = db.prepare(`
    INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount, warehouse_id, created_by)
    VALUES (?, 1, '2026-07-01', 'Submitted', ?, 1, 1)
  `).run(`PO-${Date.now()}-${Math.floor(Math.random() * 1e6)}`, qty * unitPrice).lastInsertRowid as number;

  const poItemId = db.prepare(`
    INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity, unit_price, amount)
    VALUES (?, ?, ?, 0, ?, ?)
  `).run(poId, itemId, qty, unitPrice, qty * unitPrice).lastInsertRowid as number;

  return { poId, poItemId, itemId };
}

describe('C-06 — PO-source returns key on the receipt item id the writer actually wrote', () => {
  it('the receipt writes source_id = goods_receipt_items.id, not purchase_order_items.id', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 10 }] },
      1,
      db,
    );

    const batch = db.prepare(`
      SELECT source_type, source_id FROM stock_batches WHERE source_type = 'GOODS_RECEIPT'
    `).get() as { source_type: string; source_id: number };

    const gri = db.prepare(`
      SELECT id, po_item_id FROM goods_receipt_items WHERE po_item_id = ?
    `).get(poItemId) as { id: number; po_item_id: number };

    expect(gri.po_item_id).toBe(poItemId);
    expect(batch.source_id).toBe(gri.id);
    // The two sequences are independent; this is the whole defect.
    expect(batch.source_id).not.toBe(poItemId);
  });

  it('a return against a PO receipt succeeds and depletes the receipt batch', () => {
    const db = createFixture();
    const { poId, poItemId, itemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 10 }] },
      1,
      db,
    );

    const header = PurchaseReturnModel.create(
      {
        return_date: '2026-08-01',
        source_type: 'PURCHASE_ORDER',
        source_id: poId,
        warehouse_id: 1,
        reason: 'Damaged on arrival',
        items: [{ source_item_id: poItemId, quantity: 4 }],
      },
      1,
      db,
    );

    expect(header.id).toBeGreaterThan(0);

    const batch = db.prepare(`
      SELECT quantity_remaining FROM stock_batches WHERE source_type = 'GOODS_RECEIPT'
    `).get() as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBeCloseTo(6, 3);

    const line = db.prepare(`
      SELECT source_item_id, item_id, quantity, unit_cost FROM purchase_return_items WHERE purchase_return_id = ?
    `).get(header.id) as { source_item_id: number; item_id: number; quantity: number; unit_cost: number };
    expect(line.source_item_id).toBe(poItemId);
    expect(line.item_id).toBe(itemId);
    expect(line.quantity).toBeCloseTo(4, 3);
    expect(line.unit_cost).toBeCloseTo(50, 2);
  });

  it('records which batch it consumed, so void can restore exactly that layer', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 10 }] },
      1,
      db,
    );

    const header = PurchaseReturnModel.create(
      {
        return_date: '2026-08-01',
        source_type: 'PURCHASE_ORDER',
        source_id: poId,
        warehouse_id: 1,
        items: [{ source_item_id: poItemId, quantity: 4 }],
      },
      1,
      db,
    );

    const consumed = db.prepare(`
      SELECT prb.batch_id, prb.quantity, sb.source_id
      FROM purchase_return_batches prb
      JOIN purchase_return_items pri ON pri.id = prb.return_line_id
      JOIN stock_batches sb ON sb.id = prb.batch_id
      WHERE pri.purchase_return_id = ?
    `).all(header.id) as { batch_id: number; quantity: number; source_id: number }[];

    expect(consumed).toHaveLength(1);
    expect(consumed[0].quantity).toBeCloseTo(4, 3);

    const gri = db.prepare(`SELECT id FROM goods_receipt_items WHERE po_item_id = ?`).get(poItemId) as { id: number };
    expect(consumed[0].source_id).toBe(gri.id);
  });

  it('a partial return of 4 does not consume a sibling PO line layer', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    const poId2 = db.prepare(`
      INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount, warehouse_id, created_by)
      VALUES (?, 1, '2026-07-01', 'Submitted', 500, 1, 1)
    `).run(`PO-B-${Date.now()}`).lastInsertRowid as number;
    const poItem2 = db.prepare(`
      INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity, unit_price, amount)
      VALUES (?, 1, 10, 0, 50, 500)
    `).run(poId2).lastInsertRowid as number;

    PurchaseOrderModel.addReceipt(
      {
        po_id: poId,
        receipt_date: '2026-07-05',
        warehouse_id: 1,
        items: [{ po_item_id: poItemId, received_quantity: 10 }],
      },
      1,
      db,
    );
    PurchaseOrderModel.addReceipt(
      {
        po_id: poId2,
        receipt_date: '2026-07-05',
        warehouse_id: 1,
        items: [{ po_item_id: poItem2, received_quantity: 10 }],
      },
      1,
      db,
    );

    const before = db.prepare(`
      SELECT id, quantity_remaining FROM stock_batches ORDER BY id
    `).all() as { id: number; quantity_remaining: number }[];
    expect(before).toHaveLength(2);

    PurchaseReturnModel.create(
      {
        return_date: '2026-08-01',
        source_type: 'PURCHASE_ORDER',
        source_id: poId,
        warehouse_id: 1,
        items: [{ source_item_id: poItemId, quantity: 4 }],
      },
      1,
      db,
    );

    const after = db.prepare(`SELECT id, quantity_remaining FROM stock_batches ORDER BY id`).all() as {
      id: number;
      quantity_remaining: number;
    }[];

    expect(after[0].quantity_remaining).toBeCloseTo(6, 3);
    expect(after[1].quantity_remaining).toBeCloseTo(10, 3);
  });

  it('over-returning beyond what was received still fails loudly', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 6 }] },
      1,
      db,
    );

    expect(() =>
      PurchaseReturnModel.create(
        {
          return_date: '2026-08-01',
          source_type: 'PURCHASE_ORDER',
          source_id: poId,
          warehouse_id: 1,
          items: [{ source_item_id: poItemId, quantity: 9 }],
        },
        1,
        db,
      ),
    ).toThrow(/exceeds net received quantity/i);

    const batch = db.prepare(`SELECT quantity_remaining FROM stock_batches`).get() as { quantity_remaining: number };
    expect(batch.quantity_remaining).toBeCloseTo(6, 3);
  });

  it('create-then-void is a value-identity operation on inventory', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 10 }] },
      1,
      db,
    );

    const snapshot = () =>
      db.prepare(`
        SELECT sb.id, sb.quantity_remaining, sb.unit_cost
        FROM stock_batches sb ORDER BY sb.id
      `).all();

    const before = snapshot();

    const header = PurchaseReturnModel.create(
      {
        return_date: '2026-08-01',
        source_type: 'PURCHASE_ORDER',
        source_id: poId,
        warehouse_id: 1,
        items: [{ source_item_id: poItemId, quantity: 4 }],
      },
      1,
      db,
    );

    const mid = snapshot();
    expect((mid[0] as { quantity_remaining: number }).quantity_remaining).toBeCloseTo(6, 3);

    PurchaseReturnModel.voidReturn(header.id, 1, 'test void', db);

    expect(snapshot()).toEqual(before);
  });

  it('REGRESSION GUARD: every GOODS_RECEIPT batch resolves to a goods_receipt_items row', () => {
    const db = createFixture();
    const { poId, poItemId } = seedPo(db, { qty: 10 });

    PurchaseOrderModel.addReceipt(
      { po_id: poId, receipt_date: '2026-07-05', warehouse_id: 1, items: [{ po_item_id: poItemId, received_quantity: 10 }] },
      1,
      db,
    );

    const orphans = db.prepare(`
      SELECT sb.id, sb.source_id
      FROM stock_batches sb
      WHERE sb.source_type = 'GOODS_RECEIPT'
        AND NOT EXISTS (SELECT 1 FROM goods_receipt_items gri WHERE gri.id = sb.source_id)
    `).all() as { id: number; source_id: number }[];

    expect(orphans).toEqual([]);
  });
});