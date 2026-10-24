import { afterAll, describe, expect, it } from '@jest/globals';
import type { Database } from 'better-sqlite3';
import { cleanupFixtureDbs, createFixtureDb } from './helpers/productionSchema';
import { runBackfillGlPreposting } from '../migrations/backfillGlPreposting';

/**
 * Fallow health remediation — `backfill7GoodsReceipts` (CRAP 33).
 * Runs against isolated fixture databases only.
 */

afterAll(() => cleanupFixtureDbs());

function seedReceipt(
  db: Database,
  opts: { receiptNo: string; quantity: number; unitPrice: number; voided?: boolean }
): { receiptId: number; poItemId: number; supplierId: number } {
  const supplier = db
    .prepare(
      `INSERT INTO suppliers (supplier_code, supplier_name) VALUES (?, ?)`
    )
    .run(`SUP-${opts.receiptNo}`, `Supplier ${opts.receiptNo}`);
  const supplierId = Number(supplier.lastInsertRowid);
  const item = db
    .prepare(`INSERT INTO items (item_code, item_name) VALUES (?, ?)`)
    .run(`IT-${opts.receiptNo}`, `Item ${opts.receiptNo}`);
  const warehouse = db
    .prepare(
      `INSERT INTO warehouses (warehouse_code, warehouse_name) VALUES (?, ?)`
    )
    .run(`WH-${opts.receiptNo}`, `Warehouse ${opts.receiptNo}`);
  const po = db
    .prepare(
      `INSERT INTO purchase_orders (po_no, supplier_id, po_date, status, total_amount)
       VALUES (?, ?, '2026-01-05', 'Completed', ?)`
    )
    .run(`PO-${opts.receiptNo}`, supplierId, opts.quantity * opts.unitPrice);
  const poItem = db
    .prepare(
      `INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity, unit_price, amount)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .run(
      po.lastInsertRowid,
      item.lastInsertRowid,
      opts.quantity,
      opts.quantity,
      opts.unitPrice,
      opts.quantity * opts.unitPrice
    );
  const receipt = db
    .prepare(
      `INSERT INTO goods_receipts (receipt_no, po_id, receipt_date, warehouse_id${opts.voided === undefined ? '' : ', voided_at'})
       VALUES (?, ?, '2026-01-06', ?${opts.voided === undefined ? '' : ', ?'})`
    )
    .run(
      opts.receiptNo,
      po.lastInsertRowid,
      warehouse.lastInsertRowid,
      ...(opts.voided === undefined ? [] : [opts.voided ? '2026-01-07T00:00:00.000Z' : null])
    );
  db.prepare(
    `INSERT INTO goods_receipt_items (receipt_id, po_item_id, item_id, received_quantity)
     VALUES (?, ?, ?, ?)`
  ).run(receipt.lastInsertRowid, poItem.lastInsertRowid, item.lastInsertRowid, opts.quantity);
  return {
    receiptId: Number(receipt.lastInsertRowid),
    poItemId: Number(poItem.lastInsertRowid),
    supplierId,
  };
}

function journalLines(db: Database, receiptId: number): number {
  return (
    db
      .prepare(
        `SELECT COUNT(*) AS n FROM journal_lines
         WHERE reference_type = 'GOODS_RECEIPT' AND reference_id = ? AND voided = 0`
      )
      .get(receiptId) as { n: number }
  ).n;
}

describe('runBackfillGlPreposting goods receipts', () => {
  it('posts Dr 1200 / Cr 2000 and the supplier-ledger leg once', () => {
    const db = createFixtureDb({ reference: true });
    const { receiptId, supplierId } = seedReceipt(db, {
      receiptNo: 'GR-1',
      quantity: 2,
      unitPrice: 15,
    });

    runBackfillGlPreposting(db);

    expect(journalLines(db, receiptId)).toBe(2);
    const lines = db
      .prepare(
        `SELECT debit, credit FROM journal_lines
         WHERE reference_type = 'GOODS_RECEIPT' AND reference_id = ? ORDER BY id`
      )
      .all(receiptId) as Array<{ debit: number; credit: number }>;
    expect(lines.map(l => [l.debit, l.credit])).toEqual([
      [30, 0],
      [0, 30],
    ]);
    const ledger = db
      .prepare(
        `SELECT debit, credit FROM supplier_ledger
         WHERE supplier_id = ? AND transaction_type = 'GOODS_RECEIPT'`
      )
      .get(supplierId) as { debit: number; credit: number };
    expect(ledger).toEqual({ debit: 30, credit: 0 });

    runBackfillGlPreposting(db);
    expect(journalLines(db, receiptId)).toBe(2);
    expect(
      (
        db
          .prepare(
            `SELECT COUNT(*) AS n FROM supplier_ledger
             WHERE supplier_id = ? AND transaction_type = 'GOODS_RECEIPT'`
          )
          .get(supplierId) as { n: number }
      ).n
    ).toBe(1);
  });

  it('skips voided and zero-value receipts', () => {
    const db = createFixtureDb({ reference: true });
    const voided = seedReceipt(db, { receiptNo: 'GR-VOID', quantity: 1, unitPrice: 10, voided: true });
    const zero = seedReceipt(db, { receiptNo: 'GR-ZERO', quantity: 0, unitPrice: 10 });

    runBackfillGlPreposting(db);

    expect(journalLines(db, voided.receiptId)).toBe(0);
    expect(journalLines(db, zero.receiptId)).toBe(0);
  });

  it('handles a legacy database without the voided_at column', () => {
    const db = createFixtureDb({ reference: true });
    seedReceipt(db, { receiptNo: 'GR-LEGACY', quantity: 3, unitPrice: 4 });
    db.exec('ALTER TABLE goods_receipts DROP COLUMN voided_at');

    runBackfillGlPreposting(db);

    expect(
      (
        db
          .prepare(
            `SELECT COUNT(*) AS n FROM journal_lines
             WHERE reference_type = 'GOODS_RECEIPT' AND voided = 0`
          )
          .get() as { n: number }
      ).n
    ).toBe(2);
  });

  it('skips a receipt that is already ledgered', () => {
    const db = createFixtureDb({ reference: true });
    const { receiptId, supplierId } = seedReceipt(db, {
      receiptNo: 'GR-ALREADY',
      quantity: 1,
      unitPrice: 9,
    });
    db.prepare(
      `INSERT INTO supplier_ledger (
         supplier_id, transaction_date, transaction_type, reference_no,
         debit, credit, balance, description
       ) VALUES (?, '2026-01-06', 'GOODS_RECEIPT', 'GR-ALREADY', 9, 0, 9, 'pre-existing')`
    ).run(supplierId);

    runBackfillGlPreposting(db);

    expect(journalLines(db, receiptId)).toBe(2);
    const ledgerRows = db
      .prepare(
        `SELECT COUNT(*) AS n FROM supplier_ledger
         WHERE supplier_id = ? AND transaction_type = 'GOODS_RECEIPT'`
      )
      .get(supplierId) as { n: number };
    expect(ledgerRows.n).toBe(1);
  });
});
