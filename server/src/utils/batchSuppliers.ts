import type Database from 'better-sqlite3';

export interface BatchSupplier {
  readonly supplier_id: number | null;
  readonly supplier_name: string | null;
}

interface OriginRow extends BatchSupplier {
  readonly root_id: number;
}

/** Resolve all contributors in one query, including repeated/mixed transfers.
 * UNION bounds traversal even if historical provenance contains a cycle.
 * Untraceable leaves stay explicit; no supplier is inferred from the item.
 */
export function batchSuppliers(db: Database.Database, batchIds: readonly number[]): Map<number, BatchSupplier[]> {
  const result = new Map<number, BatchSupplier[]>();
  if (batchIds.length === 0) return result;
  const rows = db.prepare(`
    WITH RECURSIVE ancestry(root_id, batch_id) AS (
      SELECT value, value FROM json_each(?)
      UNION
      SELECT a.root_id, s.source_batch_id
      FROM ancestry a JOIN stock_batch_sources s ON s.batch_id = a.batch_id
    )
    SELECT DISTINCT a.root_id,
      COALESCE(p.supplier_id, po.supplier_id) AS supplier_id,
      COALESCE(s.supplier_name, p.supplier_name) AS supplier_name
    FROM ancestry a
    LEFT JOIN stock_batches b ON b.id = a.batch_id
    LEFT JOIN purchases p ON b.source_type = 'PURCHASE' AND p.id = b.source_id AND p.item_id = b.item_id
    LEFT JOIN goods_receipt_items gri ON b.source_type = 'GOODS_RECEIPT' AND gri.id = b.source_id AND gri.item_id = b.item_id
    LEFT JOIN goods_receipts gr ON gr.id = gri.receipt_id
    LEFT JOIN purchase_orders po ON po.id = gr.po_id
    LEFT JOIN suppliers s ON s.id = COALESCE(p.supplier_id, po.supplier_id)
    WHERE NOT EXISTS (SELECT 1 FROM stock_batch_sources edge WHERE edge.batch_id = a.batch_id)
    ORDER BY a.root_id, supplier_name COLLATE NOCASE, supplier_id
  `).all(JSON.stringify(batchIds)) as OriginRow[];
  for (const row of rows) {
    const suppliers = result.get(row.root_id) ?? [];
    suppliers.push({ supplier_id: row.supplier_id, supplier_name: row.supplier_name });
    result.set(row.root_id, suppliers);
  }
  for (const id of batchIds) {
    if (!result.has(id)) result.set(id, [{ supplier_id: null, supplier_name: null }]);
  }
  return result;
}

export function recordBatchSources(
  db: Database.Database,
  batchId: number,
  sources: readonly { readonly batchId: number | null; readonly consumed: number }[],
): void {
  const insert = db.prepare('INSERT INTO stock_batch_sources(batch_id, source_batch_id, quantity) VALUES (?, ?, ?)');
  for (const source of sources) {
    insert.run(batchId, source.batchId, source.consumed);
  }
}
