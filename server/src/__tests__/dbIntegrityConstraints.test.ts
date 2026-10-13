/**
 * Audit `db-integrity-constraints` — database-layer integrity guards.
 *
 * DB-001: `goods_receipt_items` carried three foreign keys and no indexes at
 * all, so the `goods_receipts` ON DELETE CASCADE and every parent update
 * full-scanned the goods-receipt hot path.
 *
 * These assert the shape of the live schema produced by the migration runner,
 * not a hand-applied fixture, so they test the same boot path production uses.
 */
import fs from 'fs';
import { afterEach, describe, expect, it } from '@jest/globals';
import path from 'path';
import db from '../config/database';
import PurchaseOrderModel from '../models/PurchaseOrder';
import { assertJournalEntriesBalance, verifyMigrationChecksums } from '../config/database';

/** Minimal parent rows so invoice_returns' FKs are satisfiable. */
function seedReturnParents(): { invoiceId: number } {
  const hasCustomer = db.prepare('SELECT id FROM customers LIMIT 1').get() as { id: number } | undefined;
  if (!hasCustomer) {
    db.prepare(
      `INSERT INTO customers (customer_code, customer_name, is_active) VALUES ('DBI-C1', 'DB Integrity Co', 1)`,
    ).run();
  }
  const customerId = (db.prepare('SELECT id FROM customers ORDER BY id LIMIT 1').get() as { id: number }).id;

  const seq = (db.prepare('SELECT COUNT(*) AS n FROM invoices').get() as { n: number }).n + 1;
  const invoiceId = Number(
    db.prepare(
      `INSERT INTO invoices (invoice_no, customer_id, invoice_date, due_date, status,
         total_amount, paid_amount, balance_amount, created_by)
       VALUES (?, ?, '2026-03-01', '2026-04-01', 'Issued', 0, 0, 0, 1)`,
    ).run(`DBI-INV-${seq}`, customerId).lastInsertRowid,
  );
  return { invoiceId };
}

const indexColumns = (table: string, index: string): string[] => {
  const rows = db
    .prepare(`SELECT name FROM pragma_index_info(?)`)
    .all(index) as Array<{ name: string }>;
  return rows.map((r) => r.name);
};

const hasIndex = (table: string, column: string): boolean => {
  const indexes = db
    .prepare(`SELECT name FROM pragma_index_list(?)`)
    .all(table) as Array<{ name: string }>;
  return indexes.some((i) => indexColumns(table, i.name).includes(column));
};

describe('DB-001 — goods_receipt_items foreign keys are indexed', () => {
  it.each(['receipt_id', 'po_item_id', 'item_id'])(
    'goods_receipt_items has an index covering %s',
    (column) => {
      expect(hasIndex('goods_receipt_items', column)).toBe(true);
    },
  );

  it('names the indexes so a DBA can read the plan', () => {
    // Asserting the index NAME as well as the column: a stray index with the
    // right column still passes a column-only check, and these names are what
    // an operator greps for when reading EXPLAIN QUERY PLAN output.
    const names = (
      db.prepare(`SELECT name FROM pragma_index_list('goods_receipt_items')`).all() as Array<{
        name: string;
      }>
    ).map((r) => r.name);

    expect(names).toEqual(
      expect.arrayContaining([
        'idx_goods_receipt_items_receipt_id',
        'idx_goods_receipt_items_po_item_id',
        'idx_goods_receipt_items_item_id',
      ]),
    );
  });
});
describe('RET-008 — a return cannot settle for more than it owes back', () => {
  const insertReturn = (o: {
    returned: number; fee: number; net: number; settled: number;
  }): number => {
    const { invoiceId } = seedReturnParents();
    const n = (db.prepare('SELECT COUNT(*) AS n FROM invoice_returns').get() as { n: number }).n + 1;
    return Number(
      db.prepare(
        `INSERT INTO invoice_returns
           (return_no, invoice_id, customer_id, return_date, fee_amount,
            returned_amount, net_amount, settled_amount, created_by)
         VALUES (?, ?, 1, '2026-03-02', ?, ?, ?, ?, 1)`,
      ).run(
        `DBI-RET-${n}`,
        invoiceId,
        o.fee,
        o.returned,
        o.net,
        o.settled,
      ).lastInsertRowid,
    );
  };

  it('rejects a settlement above net_amount', () => {
    expect(() => insertReturn({ returned: 600, fee: 50, net: 550, settled: 600 }))
      .toThrow(/settled_amount cannot exceed net_amount/);
  });

  it('rejects a settlement above net_amount via UPDATE too', () => {
    const id = insertReturn({ returned: 600, fee: 50, net: 550, settled: 550 });
    expect(() =>
      db.prepare('UPDATE invoice_returns SET settled_amount = 600 WHERE id = ?').run(id),
    ).toThrow(/settled_amount cannot exceed net_amount/);
  });

  it('rejects lowering the net below an already-recorded settlement', () => {
    // The ceiling must hold from either side: raising settled, or shrinking
    // net after the fact.
    const id = insertReturn({ returned: 600, fee: 50, net: 550, settled: 550 });
    expect(() =>
      db.prepare('UPDATE invoice_returns SET net_amount = 100 WHERE id = ?').run(id),
    ).toThrow(/settled_amount cannot exceed net_amount/);
  });

  it('accepts a settlement exactly at net_amount', () => {
    expect(() => insertReturn({ returned: 600, fee: 50, net: 550, settled: 550 })).not.toThrow();
  });

  it('accepts a partial settlement', () => {
    expect(() => insertReturn({ returned: 600, fee: 50, net: 550, settled: 200 })).not.toThrow();
  });

  it('caps at net, not returned — the restocking fee is never payable back', () => {
    // The ledger words this finding as "exceeds returned_amount". Honouring
    // that literally would let this row settle 550 and then a further 50,
    // refunding the fee the customer was supposed to keep. Assert the real
    // invariant: nothing above net survives.
    const { invoiceId } = seedReturnParents();
    const n = (db.prepare('SELECT COUNT(*) AS n FROM invoice_returns').get() as { n: number }).n + 1;
    expect(() =>
      db.prepare(
        `INSERT INTO invoice_returns
           (return_no, invoice_id, customer_id, return_date, fee_amount,
            returned_amount, net_amount, settled_amount, created_by)
         VALUES (?, ?, 1, '2026-03-02', 50, 600, 550, 560, 1)`,
      ).run(`DBI-RET-${n}`, invoiceId),
    ).toThrow(/settled_amount cannot exceed net_amount/);
  });
});

describe('PUR-012 / PUR-013 — goods-receipt guards live at the model, not only the edge', () => {
  /** The temp DB seeds users and warehouses but NOT suppliers or items. */
  function seedPurchasingParents(): { supplierId: number; itemId: number } {
    const itemId = (db.prepare('SELECT id FROM items ORDER BY id LIMIT 1').get() as
      | { id: number }
      | undefined)?.id ?? Number(
      db.prepare(
        `INSERT INTO items (item_code, item_name, is_active, current_stock)
         VALUES ('DBI-ITEM', 'DB Integrity Item', 1, 0)`,
      ).run().lastInsertRowid,
    );
    const supplierId = (db.prepare('SELECT id FROM suppliers ORDER BY id LIMIT 1').get() as
      | { id: number }
      | undefined)?.id ?? Number(
      db.prepare(
        `INSERT INTO suppliers (supplier_code, supplier_name) VALUES ('DBI-SUP', 'DB Integrity Supplier')`,
      ).run().lastInsertRowid,
    );
    return { supplierId, itemId };
  }

  /** A minimal PO with one open line, in the default warehouse. */
  function seedPurchaseOrder(): { poId: number; poItemId: number; warehouseId: number } {
    const { supplierId, itemId } = seedPurchasingParents();
    const warehouseId = (
      db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }
    ).id;
    const n = (db.prepare('SELECT COUNT(*) AS n FROM purchase_orders').get() as { n: number }).n + 1;
    const poId = Number(
      db.prepare(
        `INSERT INTO purchase_orders (po_no, supplier_id, warehouse_id, po_date, status,
           total_amount, created_by)
         VALUES (?, ?, ?, '2026-03-01', 'Submitted', 0, 1)`,
      ).run(`DBI-PO-${n}`, supplierId, warehouseId).lastInsertRowid,
    );
    const poItemId = Number(
      db.prepare(
        `INSERT INTO purchase_order_items (po_id, item_id, quantity, received_quantity,
           unit_price, amount)
         VALUES (?, ?, 10, 0, 5, 50)`,
      ).run(poId, itemId).lastInsertRowid,
    );
    return { poId, poItemId, warehouseId };
  }

  const receive = (poId: number, warehouseId: number, quantity: number, poItemId: number) =>
    PurchaseOrderModel.addReceipt(
      {
        po_id: poId,
        receipt_date: '2026-03-02',
        warehouse_id: warehouseId,
        items: [{ po_item_id: poItemId, received_quantity: quantity }],
      } as never,
      1,
      db,
    );

  it.each([0, -6])('rejects a received_quantity of %s', (quantity) => {
    const { poId, poItemId, warehouseId } = seedPurchaseOrder();
    expect(() => receive(poId, warehouseId, quantity, poItemId)).toThrow(
      /Received quantity must be greater than 0/,
    );
  });

  it('rejects a receipt into a warehouse other than the PO warehouse', () => {
    const { poId, poItemId, warehouseId } = seedPurchaseOrder();
    const other = db.prepare('SELECT id FROM warehouses WHERE id <> ? ORDER BY id LIMIT 1')
      .get(warehouseId) as { id: number } | undefined;
    if (!other) return; // single-warehouse fixture: nothing to collide with

    expect(() => receive(poId, other.id, 1, poItemId)).toThrow(
      /does not match Purchase Order warehouse/,
    );
  });

  it('accepts a receipt when the PO named no warehouse', () => {
    // A NULL po.warehouse_id authorises no particular warehouse, so the
    // receipt's is the only choice. Treating that as a mismatch blocked every
    // receipt against a warehouse-less PO — 22 tests across 5 suites.
    const { poId, poItemId, warehouseId } = seedPurchaseOrder();
    db.prepare('UPDATE purchase_orders SET warehouse_id = NULL WHERE id = ?').run(poId);
    expect(() => receive(poId, warehouseId, 1, poItemId)).not.toThrow();
  });

  it('accepts a valid receipt into the PO warehouse', () => {
    const { poId, poItemId, warehouseId } = seedPurchaseOrder();
    expect(() => receive(poId, warehouseId, 1, poItemId)).not.toThrow();
  });
});

describe('PUR-014 — a purchase balance never goes below zero', () => {
  it('clamps a negative computed balance to 0', () => {
    // Over-allocating a payment makes paid > cost; the derived balance must
    // floor at 0 rather than report a negative "Amount Due".
    const rows = db
      .prepare(
        `SELECT MAX(0, p.total_cost - COALESCE(pa.paid_amount, 0)) AS balance_amount
         FROM purchases p
         LEFT JOIN (SELECT purchase_id, SUM(amount) AS paid_amount
                    FROM purchase_allocations WHERE voided_at IS NULL
                    GROUP BY purchase_id) pa ON pa.purchase_id = p.id`,
      )
      .all() as Array<{ balance_amount: number }>;
    for (const r of rows) {
      expect(Number(r.balance_amount)).toBeGreaterThanOrEqual(0);
    }
  });

  it('the purchase queries floor the balance rather than subtracting raw', () => {
    const src = fs.readFileSync(
      path.join(__dirname, '..', 'models', 'Purchase.ts'),
      'utf8',
    );
    const derived =
      src.match(/p\.total_cost - COALESCE\(pa\.paid_amount, 0\) as balance_amount/g) ?? [];
    expect(derived.length).toBe(0);
  });
});

describe('PUR-015 — the GL backfill skips voided purchases and mirrors receipts to the subledger', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '..', 'migrations', 'backfillGlPreposting.ts'),
    'utf8',
  );

  it('filters the purchases query on voided_at', () => {
    const block = src.slice(
      src.indexOf('FROM purchases'),
      src.indexOf('FROM purchases') + 220,
    );
    expect(block).toMatch(/voided_at IS NULL/);
  });

  it('writes a supplier_ledger leg for each backfilled goods receipt', () => {
    expect(src).toMatch(/INSERT INTO supplier_ledger/);
    // DEBIT-normal: a receipt increases what we owe the supplier.
    const idx = src.indexOf('INSERT INTO supplier_ledger');
    const stmt = src.slice(idx, idx + 420);
    expect(stmt).toMatch(/'GOODS_RECEIPT'/);
    expect(stmt).toMatch(/debit, credit, balance/);
  });

  it('does not double-post a ledger row that already exists', () => {
    const idx = src.indexOf('INSERT INTO supplier_ledger');
    const region = src.slice(Math.max(0, idx - 700), idx);
    expect(region).toMatch(/alreadyLedgered/);
  });
});

describe('DB-003 — inline migrations are verified at runtime, not just in source', () => {
  const MIGRATIONS_DIR = path.join(__dirname, '..', 'migrations');

  const inlineRows = (): Array<{ filename: string; checksum: string }> =>
    db
      .prepare("SELECT filename, checksum FROM schema_migrations WHERE filename LIKE 'fn.%'")
      .all() as Array<{ filename: string; checksum: string }>;

  it('records a real body hash for every inline migration', () => {
    const rows = inlineRows();
    expect(rows.length).toBeGreaterThan(0);
    const unverifiable = rows.filter((r) => !/^[0-9a-f]{16}$/.test(r.checksum));
    expect(unverifiable.map((r) => r.filename)).toEqual([]);
  });

  it('leaves no inline row stuck at the unverifiable placeholder', () => {
    const stuck = db
      .prepare("SELECT COUNT(*) AS n FROM schema_migrations WHERE checksum = 'inline'")
      .get() as { n: number };
    expect(stuck.n).toBe(0);
  });

  it('aborts when an inline migration body no longer matches its hash', () => {
    const target = inlineRows()[0];
    const original = target.checksum;
    db.prepare('UPDATE schema_migrations SET checksum = ? WHERE filename = ?')
      .run('deadbeefdeadbeef', target.filename);
    try {
      expect(() => verifyMigrationChecksums(db, MIGRATIONS_DIR)).toThrow(
        /was modified after it was applied/,
      );
    } finally {
      db.prepare('UPDATE schema_migrations SET checksum = ? WHERE filename = ?')
        .run(original, target.filename);
    }
  });

  it('passes on an untouched ledger', () => {
    expect(() => verifyMigrationChecksums(db, MIGRATIONS_DIR)).not.toThrow();
  });
});

describe('DB-003 — migration checksum verification covers inline runners', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'config', 'database.ts'), 'utf8');

  it('no longer skips inline rows outright', () => {
    expect(src).not.toMatch(/if \(checksum === 'inline'\) continue;/);
  });

  it('hashes the inline body instead of a missing file', () => {
    expect(src).toMatch(/function checksumOfFunction/);
    // The old path could only ever return 'inline' for a fn.* key, because the
    // key names a function and there is no such file to read.
    expect(src).toMatch(/fn\.toString\(\)|fn\)\.toString\(\)/);
  });

  it('registers fn.* bodies so verification can re-hash them', () => {
    expect(src).toMatch(/inlineMigrations\.set\(key, fn\)/);
    expect(src).toMatch(/inlineMigrations\.get\(filename\)/);
  });

  it('adopts a baseline for pre-existing inline rows rather than aborting every boot', () => {
    // Without this, the first boot after the change would throw on all 66
    // legacy inline rows and take every existing install offline.
    expect(src).toMatch(/UPDATE schema_migrations SET checksum = \? WHERE filename = \?/);
  });

  it('still aborts on a genuine mismatch between two real hashes', () => {
    const idx = src.indexOf('if (current !== checksum)');
    expect(idx).toBeGreaterThan(-1);
    expect(src.slice(idx, idx + 200)).toMatch(/throw new Error/);
  });

  it('stamps fn.* rows with the body hash at apply time', () => {
    const idx = src.indexOf('const checksum = fn');
    expect(idx).toBeGreaterThan(-1);
    expect(src.slice(idx, idx + 160)).toMatch(/checksumOfFunction\(key, fn\)/);
  });
});

describe('DB-002 — the boot gate detects an unbalanced journal entry', () => {
  // Simulate privileged maintenance bypassing foreign keys. Detection must
  // still catch that committed corruption after enforcement is restored.
  function historicalWrite(write: () => void): void {
    expect(db.inTransaction).toBe(false);
    db.pragma('foreign_keys = OFF');
    try {
      write();
    } finally {
      db.pragma('foreign_keys = ON');
    }
    expect(db.pragma('foreign_keys', { simple: true })).toBe(1);
  }

  // These fixtures deliberately create UNBALANCED groups, and the assertion
  // scans every group in the table. Without this cleanup one test's drift
  // fails the next test's "does not throw" case.
  afterEach(() => {
    db.prepare('DELETE FROM journal_lines WHERE reference_type = ? AND reference_id >= ?')
      .run('DBI', 9001);
  });


  const accounts = (): { ar: number; ap: number } => {
    const ar = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1100'`).get() as { id: number };
    const ap = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '2000'`).get() as { id: number };
    return { ar: ar.id, ap: ap.id };
  };

  const addEntry = (entryId: number, legs: Array<{ account: number; debit: number; credit: number }>) => {
    historicalWrite(() => {
      for (const leg of legs) {
        db.prepare(
          `INSERT INTO journal_lines
             (journal_entry_id, account_id, debit, credit, line_date, reference_type, reference_id)
           VALUES (?, ?, ?, ?, '2026-03-01', 'DBI', ?)`,
        ).run(entryId, leg.account, leg.debit, leg.credit, entryId);
      }
    });
  };

  it('passes on a balanced entry', () => {
    const { ar, ap } = accounts();
    addEntry(9001, [
      { account: ar, debit: 250, credit: 0 },
      { account: ap, debit: 0, credit: 250 },
    ]);
    expect(() => assertJournalEntriesBalance(db)).not.toThrow();
  });

  it('fails when one side of an entry is missing', () => {
    const { ar } = accounts();
    addEntry(9002, [{ account: ar, debit: 175, credit: 0 }]);
    expect(() => assertJournalEntriesBalance(db)).toThrow(/unbalanced journal entr/);
  });

  it('names the offending entry and the drift', () => {
    const { ar, ap } = accounts();
    addEntry(9003, [
      { account: ar, debit: 100, credit: 0 },
      { account: ap, debit: 0, credit: 40 },
    ]);
    expect(() => assertJournalEntriesBalance(db)).toThrow(/#9003/);
    expect(() => assertJournalEntriesBalance(db)).toThrow(/60\.00/);
  });

  it('ignores fully voided lines', () => {
    const { ar, ap } = accounts();
    addEntry(9004, [
      { account: ar, debit: 90, credit: 0 },
      { account: ap, debit: 0, credit: 90 },
    ]);
    db.prepare('UPDATE journal_lines SET voided = 1 WHERE journal_entry_id = 9004').run();
    expect(() => assertJournalEntriesBalance(db)).not.toThrow();
  });

  it('a void that leaves a half-voided entry unbalanced is detected', () => {
    const { ar, ap } = accounts();
    addEntry(9005, [
      { account: ar, debit: 120, credit: 0 },
      { account: ap, debit: 0, credit: 120 },
    ]);
    historicalWrite(() => {
      db.prepare('UPDATE journal_lines SET voided = 1 WHERE journal_entry_id = 9005 AND account_id = ?')
        .run(ar);
    });
    expect(() => assertJournalEntriesBalance(db)).toThrow(/#9005/);
  });
});
