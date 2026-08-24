"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const better_sqlite3_1 = __importDefault(require("better-sqlite3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const PurchaseReturn_1 = __importDefault(require("../models/PurchaseReturn"));
const purchaseReturnBackfill_1 = require("../utils/purchaseReturnBackfill");
/**
 * Fixture: replay the real migration chain on an in-memory DB so the model
 * runs against the same schema production boots with. init.sql is the base
 * schema; the incremental migrations add purchases, stock_batches, the
 * financial/GL tables and the new purchase-returns tables.
 */
function createFixture() {
    const db = new better_sqlite3_1.default(':memory:');
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
        'create-customer-ledger.sql',
        'add-gl-void-attribution.sql',
    ];
    for (const file of migrations) {
        const sql = fs_1.default.readFileSync(path_1.default.join(__dirname, '..', 'migrations', file), 'utf8');
        db.exec(sql);
    }
    // suppliers.current_balance is added programmatically at boot
    // (config/database.ts) — replicate for rebuildBalances.
    const supCols = db.prepare(`SELECT name FROM pragma_table_info('suppliers')`).all();
    if (!supCols.some((c) => c.name === 'current_balance')) {
        db.exec('ALTER TABLE suppliers ADD COLUMN current_balance DECIMAL(15,2) DEFAULT 0');
    }
    // Replicate the programmatic ALTERs from runBatchCostingMigration (the
    // SQL file only creates stock_batches; the column adds are applied in
    // code on boot).
    const cols = db.prepare(`SELECT name FROM pragma_table_info('stock_movements')`).all();
    const has = (n) => cols.some((c) => c.name === n);
    if (!has('batch_id'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN batch_id INTEGER REFERENCES stock_batches(id)');
    if (!has('financial_value'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN financial_value DECIMAL(15,4) DEFAULT 0');
    if (!has('financial_posted'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN financial_posted BOOLEAN DEFAULT FALSE');
    if (!has('journal_entry_id'))
        db.exec('ALTER TABLE stock_movements ADD COLUMN journal_entry_id INTEGER REFERENCES journal_entries(id)');
    // Seed the minimal master data the flows need.
    db.prepare(`
    INSERT INTO users (username, email, password_hash, full_name, role, is_active)
    VALUES ('admin', 'a@b.c', 'x', 'Admin', 'admin', 1)
  `).run();
    db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
    VALUES ('IT-1', 'Widget', 'Nos', 10, 1, 1), ('IT-2', 'Gadget', 'Nos', 20, 1, 1)
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
/** A purchased unit sits in a batch layer so returns can consume it. */
/**
 * Seed a purchase for item N (defaults to a fresh item+warehouse pair so
 * tests don't collide on the stock_balances UNIQUE(item_id, warehouse_id)).
 * Returns the purchase id.
 */
let seedCounter = 0;
function seedPurchase(db, overrides = {}) {
    const qty = overrides.quantity ?? 10;
    seedCounter += 1;
    const itemId = overrides.item_id ?? seedCounter;
    const warehouseId = overrides.warehouse_id ?? 1;
    if (!db.prepare('SELECT id FROM items WHERE id = ?').get(itemId)) {
        db.prepare(`
      INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
      VALUES (?, ?, ?, 'Nos', ?, 1, 1)
    `).run(itemId, `IT-${itemId}`, `Item ${itemId}`, overrides.unit_cost ?? 10);
    }
    const result = db.prepare(`
    INSERT INTO purchases (
      purchase_no, item_id, warehouse_id, quantity, unit_cost, total_cost,
      supplier_id, supplier_name, purchase_date, created_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
  `).run(overrides.purchase_no ?? `PURCH-${Date.now()}-${seedCounter}`, itemId, warehouseId, qty, overrides.unit_cost ?? 10, qty * (overrides.unit_cost ?? 10), overrides.supplier_id ?? 1, overrides.supplier_name ?? 'Acme Supplies', overrides.purchase_date ?? '2026-07-01');
    const purchaseId = result.lastInsertRowid;
    db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, ?, ?, 'PURCHASE', ?, ?, ?, ?, ?)
  `).run(`BATCH-${purchaseId}`, itemId, warehouseId, purchaseId, qty, qty, overrides.unit_cost ?? 10, overrides.purchase_date ?? '2026-07-01');
    db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity)
    VALUES (?, ?, ?)
  `).run(itemId, warehouseId, qty);
    db.prepare(`UPDATE items SET current_stock = ? WHERE id = ?`)
        .run(qty, itemId);
    return purchaseId;
}
function seedPO(db, overrides = {}) {
    const qty = overrides.quantity ?? 10;
    const received = overrides.received_quantity ?? 10;
    seedCounter += 1;
    const itemId = overrides.item_id ?? seedCounter;
    const warehouseId = overrides.warehouse_id ?? 1;
    if (!db.prepare('SELECT id FROM items WHERE id = ?').get(itemId)) {
        db.prepare(`
      INSERT INTO items (id, item_code, item_name, unit_of_measure, standard_cost, is_purchased, is_active)
      VALUES (?, ?, ?, 'Nos', ?, 1, 1)
    `).run(itemId, `IT-${itemId}`, `Item ${itemId}`, overrides.unit_price ?? 10);
    }
    const poResult = db.prepare(`
    INSERT INTO purchase_orders (
      po_no, supplier_id, po_date, status, total_amount, warehouse_id, created_by
    ) VALUES (?, ?, ?, 'Submitted', ?, ?, 1)
  `).run(overrides.po_no ?? `PO-${Date.now()}-${seedCounter}`, overrides.supplier_id ?? 1, overrides.po_date ?? '2026-07-01', qty * (overrides.unit_price ?? 10), warehouseId);
    const poId = poResult.lastInsertRowid;
    const itemResult = db.prepare(`
    INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity, unit_price, amount)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(poId, itemId, qty, received, overrides.unit_price ?? 10, received * (overrides.unit_price ?? 10));
    const poItemId = itemResult.lastInsertRowid;
    db.prepare(`
    INSERT INTO stock_batches (
      batch_no, item_id, warehouse_id, source_type, source_id,
      quantity_original, quantity_remaining, unit_cost, received_date
    ) VALUES (?, ?, ?, 'GOODS_RECEIPT', ?, ?, ?, ?, ?)
  `).run(`BATCH-PO-${poItemId}`, itemId, warehouseId, poItemId, received, received, overrides.unit_price ?? 10, overrides.po_date ?? '2026-07-01');
    db.prepare(`
    INSERT INTO stock_balances (item_id, warehouse_id, quantity)
    VALUES (?, ?, ?)
  `).run(itemId, warehouseId, received);
    db.prepare(`UPDATE items SET current_stock = ? WHERE id = ?`)
        .run(received, itemId);
    return { poId, poItemId };
}
describe('PurchaseReturnModel', () => {
    describe('create — direct purchase source', () => {
        it('records the return header + line, deducts stock and posted qty, posts GL + credit note', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db);
            const result = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                reason: 'Damaged',
                items: [{ source_item_id: purchaseId, quantity: 4 }],
            }, 1, db);
            expect(result.return_no).toMatch(/^PR-\d{4}-\d{4}$/);
            expect(result.status).toBe('POSTED');
            expect(result.total_qty).toBe(4);
            expect(result.total_amount).toBe(40);
            expect(result.items).toHaveLength(1);
            expect(result.credit_no).toMatch(/^CN-\d{4}-\d{4}$/);
            // Header row persisted
            const header = db.prepare('SELECT * FROM purchase_returns WHERE id = ?').get(result.id);
            expect(header.status).toBe('POSTED');
            expect(header.credit_note_id).not.toBeNull();
            // Stock reduced: 10 - 4 = 6
            const balance = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = 1 AND warehouse_id = 1').get();
            expect(balance.quantity).toBe(6);
            // Source returned_quantity tracked
            const purchase = db.prepare('SELECT returned_quantity FROM purchases WHERE id = ?').get(purchaseId);
            expect(purchase.returned_quantity).toBe(4);
            // Negative movement linked to the header
            const movement = db.prepare(`SELECT * FROM stock_movements WHERE purchase_return_id = ?`).get(result.id);
            expect(movement).toBeDefined();
            expect(movement.quantity).toBe(-4);
            // Credit note + supplier ledger entry posted
            const creditNote = db.prepare('SELECT * FROM credit_notes WHERE id = ?').get(header.credit_note_id);
            expect(creditNote.supplier_id).toBe(1);
            expect(creditNote.amount).toBe(40);
            const ledger = db.prepare(`SELECT * FROM supplier_ledger WHERE reference_no = ?`).get(creditNote.credit_no);
            expect(ledger.transaction_type).toBe('CREDIT_NOTE');
            expect(ledger.credit).toBe(40);
            // GL reversal posted against the return id
            const journal = db.prepare(`
        SELECT * FROM journal_lines WHERE reference_type = 'PURCHASE_RETURN' AND reference_id = ?
      `).all(result.id);
            expect(journal.length).toBe(2);
        });
        it('rejects a line quantity above the remaining returnable quantity', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 5 });
            // First return takes 4 of 5.
            PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 4 }],
            }, 1, db);
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-02',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 2 }], // only 1 left
            }, 1, db)).toThrow(/exceeds remaining available/);
        });
        it('rejects a line from a different source document', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db);
            const otherId = seedPurchase(db, { item_id: 2 });
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: otherId, quantity: 1 }],
            }, 1, db)).toThrow(/does not belong to source/);
        });
    });
    describe('create — PO receipt source', () => {
        it('caps at net received quantity (received minus already returned)', () => {
            const db = createFixture();
            const { poId, poItemId } = seedPO(db, { received_quantity: 8 });
            const result = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE_ORDER',
                source_id: poId,
                warehouse_id: 1,
                items: [{ source_item_id: poItemId, quantity: 8 }],
            }, 1, db);
            expect(result.status).toBe('POSTED');
            expect(result.total_qty).toBe(8);
            expect(result.return_type).toBe('PO_RETURN');
            const poItem = db.prepare('SELECT returned_quantity FROM purchase_order_items WHERE id = ?').get(poItemId);
            expect(poItem.returned_quantity).toBe(8);
            // Credit note supplier resolved from the PO's supplier_id.
            const header = db.prepare('SELECT credit_note_id FROM purchase_returns WHERE id = ?').get(result.id);
            const creditNote = db.prepare('SELECT supplier_id FROM credit_notes WHERE id = ?').get(header.credit_note_id);
            expect(creditNote.supplier_id).toBe(1);
        });
        it('rejects when the return exceeds net received quantity', () => {
            const db = createFixture();
            const { poId, poItemId } = seedPO(db, { received_quantity: 5 });
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE_ORDER',
                source_id: poId,
                warehouse_id: 1,
                items: [{ source_item_id: poItemId, quantity: 6 }],
            }, 1, db)).toThrow(/exceeds net received quantity/);
        });
    });
    describe('void — full reversal', () => {
        it('restores stock, GL, credit note + ledger, and marks the header VOIDED', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 10 });
            const purchaseRow = db.prepare('SELECT item_id FROM purchases WHERE id = ?').get(purchaseId);
            const itemId = purchaseRow.item_id;
            const created = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 4 }],
            }, 1, db);
            const voided = PurchaseReturn_1.default.voidReturn(created.id, 1, 'Wrong stock', db);
            expect(voided.status).toBe('VOIDED');
            expect(voided.voided_reason).toBe('Wrong stock');
            // Stock restored: back to 10
            const balance = db.prepare('SELECT quantity FROM stock_balances WHERE item_id = ? AND warehouse_id = 1').get(itemId);
            expect(balance.quantity).toBe(10);
            // Source returned_quantity reset
            const purchase = db.prepare('SELECT returned_quantity FROM purchases WHERE id = ?').get(purchaseId);
            expect(purchase.returned_quantity).toBe(0);
            // Credit note voided + reversing ledger entry posted
            const header = db.prepare('SELECT credit_note_id FROM purchase_returns WHERE id = ?').get(created.id);
            const creditNote = db.prepare('SELECT * FROM credit_notes WHERE id = ?').get(header.credit_note_id);
            expect(creditNote.status).toBe('VOIDED');
            const reversal = db.prepare(`
        SELECT * FROM supplier_ledger WHERE transaction_type = 'CREDIT_NOTE_VOID'
      `).get();
            expect(reversal.debit).toBe(40);
            // GL journal lines voided
            const journal = db.prepare(`
        SELECT * FROM journal_lines WHERE reference_type = 'PURCHASE_RETURN' AND reference_id = ?
      `).all(created.id);
            expect(journal.length).toBe(2);
            expect(journal.every((j) => j.voided === 1)).toBe(true);
            // Positive reversal movement exists
            const reversalMovement = db.prepare(`
        SELECT * FROM stock_movements WHERE purchase_return_id = ? AND quantity > 0
      `).get(created.id);
            expect(reversalMovement).toBeDefined();
            expect(reversalMovement.quantity).toBe(4);
        });
        it('rejects voiding an already-voided return', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db);
            const created = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 2 }],
            }, 1, db);
            PurchaseReturn_1.default.voidReturn(created.id, 1, '', db);
            expect(() => PurchaseReturn_1.default.voidReturn(created.id, 1, '', db)).toThrow(/Only POSTED returns can be voided/);
        });
    });
    describe('legacy backfill', () => {
        it('groups legacy negative movements into headers + lines and back-links them', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 20, purchase_no: 'PURCH-LEGACY' });
            const { poId, poItemId } = seedPO(db, {
                po_no: 'PO-LEGACY', item_id: 1, received_quantity: 8, unit_price: 10,
            });
            // Three legacy movements: two PO returns (same doc+date+item) and one
            // purchase return. All are negative ADJUSTMENT movements from the old
            // stock-movement-only flow.
            db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost,
          reference_doctype, reference_docno, remarks, movement_date, created_by, created_at
        ) VALUES ('STK-L1', 1, 1, 'ADJUSTMENT', -5, 10, 'PO_RETURN', 'PO-LEGACY', 'r1', '2026-07-10', 1, '2026-07-10 10:00:00')
      `).run();
            db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost,
          reference_doctype, reference_docno, remarks, movement_date, created_by, created_at
        ) VALUES ('STK-L2', 1, 1, 'ADJUSTMENT', -3, 10, 'PO_RETURN', 'PO-LEGACY', 'r2', '2026-07-10', 1, '2026-07-10 10:01:00')
      `).run();
            db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost,
          reference_doctype, reference_docno, remarks, movement_date, created_by, created_at
        ) VALUES ('STK-L3', 1, 1, 'ADJUSTMENT', -2, 15, 'PURCHASE_RETURN', 'PURCH-LEGACY', 'r3', '2026-07-11', 1, '2026-07-11 10:00:00')
      `).run();
            const created = (0, purchaseReturnBackfill_1.backfillPurchaseReturns)(db);
            expect(created).toBe(2); // PO-LEGACY (2 movements) + PURCH-LEGACY (1)
            // PO header: both movements land in one header, 8 units total.
            const poHeaders = db.prepare(`
        SELECT * FROM purchase_returns WHERE return_type = 'PO_RETURN'
      `).all();
            expect(poHeaders).toHaveLength(1);
            expect(poHeaders[0].source_no).toBe('PO-LEGACY');
            expect(poHeaders[0].source_id).toBe(poId);
            expect(poHeaders[0].total_qty).toBe(8);
            expect(poHeaders[0].total_amount).toBe(80);
            expect(poHeaders[0].status).toBe('POSTED');
            expect(poHeaders[0].credit_note_id).toBeNull(); // legacy returns never had credit notes
            const poLines = db.prepare(`
        SELECT * FROM purchase_return_items WHERE purchase_return_id = ?
      `).all(poHeaders[0].id);
            expect(poLines).toHaveLength(2);
            expect(poLines.map((l) => l.source_item_id)).toEqual([poItemId, poItemId]);
            // Purchase header resolves source doc by purchase_no.
            const purchaseHeaders = db.prepare(`
        SELECT * FROM purchase_returns WHERE return_type = 'PURCHASE_RETURN'
      `).all();
            expect(purchaseHeaders).toHaveLength(1);
            expect(purchaseHeaders[0].source_id).toBe(purchaseId);
            expect(purchaseHeaders[0].total_qty).toBe(2);
            // Movements back-linked; nothing left orphaned.
            const linked = db.prepare(`
        SELECT COUNT(*) as c FROM stock_movements WHERE purchase_return_id IS NOT NULL
      `).get();
            expect(linked.c).toBe(3);
            const orphaned = db.prepare(`
        SELECT COUNT(*) as c FROM stock_movements
        WHERE reference_doctype IN ('PURCHASE_RETURN', 'PO_RETURN') AND quantity < 0
          AND purchase_return_id IS NULL
      `).get();
            expect(orphaned.c).toBe(0);
        });
        it('is idempotent — a second run creates no duplicate headers', () => {
            const db = createFixture();
            seedPurchase(db, { quantity: 20, purchase_no: 'PURCH-LEGACY' });
            db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type, quantity, unit_cost,
          reference_doctype, reference_docno, remarks, movement_date, created_by, created_at
        ) VALUES ('STK-L3', 1, 1, 'ADJUSTMENT', -2, 15, 'PURCHASE_RETURN', 'PURCH-LEGACY', 'r3', '2026-07-11', 1, '2026-07-11 10:00:00')
      `).run();
            expect((0, purchaseReturnBackfill_1.backfillPurchaseReturns)(db)).toBe(1);
            expect((0, purchaseReturnBackfill_1.backfillPurchaseReturns)(db)).toBe(0); // no-op on re-run
            const headers = db.prepare('SELECT COUNT(*) as c FROM purchase_returns').get();
            expect(headers.c).toBe(1);
        });
    });
    describe('financial-audit-p0-remediation (tasks 4.1-4.5)', () => {
        it('PRET-01: duplicate lines for the same source item validate as an aggregate', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 50 });
            // Two 50-unit lines against a 50-unit purchase → aggregate 100 > 50.
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [
                    { source_item_id: purchaseId, quantity: 50 },
                    { source_item_id: purchaseId, quantity: 50 },
                ],
            }, 1, db)).toThrow(/exceeds remaining available/);
            // Nothing was written on the failed attempt.
            expect(db.prepare('SELECT COUNT(*) c FROM purchase_returns').get().c).toBe(0);
            expect(db.prepare('SELECT returned_quantity q FROM purchases WHERE id = ?').get(purchaseId).q ?? 0).toBeLessThanOrEqual(50);
            db.close();
        });
        it('PRET-01: aggregate within headroom posts once with summed quantities', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 100 });
            const result = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [
                    { source_item_id: purchaseId, quantity: 30 },
                    { source_item_id: purchaseId, quantity: 40 },
                ],
            }, 1, db);
            expect(result.total_qty).toBe(70);
            const p = db.prepare('SELECT returned_quantity q FROM purchases WHERE id = ?').get(purchaseId);
            expect(Number(p.q)).toBe(70);
            db.close();
        });
        it('PRET-02: a full return after most stock was sold fails loudly (no silent short-consume)', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 10 });
            const itemRow = db.prepare('SELECT item_id FROM purchases WHERE id = ?').get(purchaseId);
            // Simulate 8 of the 10 units already sold out of the batch.
            db.prepare('UPDATE stock_batches SET quantity_remaining = 2 WHERE source_type = ? AND source_id = ?')
                .run('PURCHASE', purchaseId);
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 10 }],
            }, 1, db)).toThrow(/Insufficient stock in the source batch/);
        });
        it('PRET-05: void restores exactly the consumed batches (value identity)', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 10 });
            const batchBefore = db.prepare('SELECT quantity_remaining FROM stock_batches WHERE source_type = ? AND source_id = ?').get('PURCHASE', purchaseId);
            const created = PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 4 }],
            }, 1, db);
            PurchaseReturn_1.default.voidReturn(created.id, 1, 'wrong stock', db);
            const batchAfter = db.prepare('SELECT quantity_remaining FROM stock_batches WHERE source_type = ? AND source_id = ?').get('PURCHASE', purchaseId);
            expect(Number(batchAfter.quantity_remaining)).toBe(Number(batchBefore.quantity_remaining));
            // Consumption ledger recorded the line→batch link during create.
            const links = db.prepare(`
        SELECT COUNT(*) c FROM purchase_return_batches prb
        JOIN purchase_return_items pri ON pri.id = prb.return_line_id
        WHERE pri.purchase_return_id = ?
      `).get(created.id);
            expect(links.c).toBe(1);
            db.close();
        });
        it('PRET-06: overpaid returns require an explicit disposition', () => {
            const db = createFixture();
            const purchaseId = seedPurchase(db, { quantity: 10 });
            // Fully settled by an allocation.
            // payment_allocations/payment rows need a parent; use a real payment.
            // The base init.sql payments table requires customer_id NOT NULL;
            // relax it for this supplier-payment fixture row.
            // legacy_alter_table so the rename does not retarget purchase_allocations' FK.
            db.pragma('legacy_alter_table = ON');
            db.exec('ALTER TABLE payments RENAME TO payments_old');
            db.exec(`CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_no VARCHAR(50) UNIQUE NOT NULL,
        customer_id INTEGER,
        supplier_id INTEGER REFERENCES suppliers(id),
        invoice_id INTEGER,
        payment_date DATE NOT NULL,
        amount DECIMAL(15,2) NOT NULL,
        payment_method VARCHAR(50)
      )`);
            db.exec(`INSERT INTO payments (id, payment_no, customer_id, invoice_id, payment_date, amount)
        SELECT id, payment_no, customer_id, invoice_id, payment_date, amount FROM payments_old`);
            db.exec('DROP TABLE payments_old');
            db.pragma('legacy_alter_table = OFF');
            db.prepare(`
        INSERT INTO payments (payment_no, supplier_id, payment_date, amount, payment_method)
        VALUES ('PAYD1', 1, '2026-07-15', 100, 'Cash')
      `).run();
            const payId = db.prepare(`SELECT id FROM payments WHERE payment_no='PAYD1'`).get().id;
            // The RENAME retargeted purchase_allocations' payment FK to
            // payments_old; repoint it at the rebuilt payments table.
            db.exec('DROP TABLE purchase_allocations');
            db.exec(`CREATE TABLE purchase_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
        purchase_id INTEGER NOT NULL REFERENCES purchases(id),
        amount DECIMAL(15,2) NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`);
            db.prepare(`
        INSERT INTO purchase_allocations (payment_id, purchase_id, amount) VALUES (?, ?, ?)
      `).run(payId, purchaseId, 100);
            expect(() => PurchaseReturn_1.default.create({
                return_date: '2026-08-01',
                source_type: 'PURCHASE',
                source_id: purchaseId,
                warehouse_id: 1,
                items: [{ source_item_id: purchaseId, quantity: 10 }],
            }, 1, db)).toThrow(/Supply a disposition/);
            db.close();
        });
    });
});
//# sourceMappingURL=purchaseReturn.test.js.map