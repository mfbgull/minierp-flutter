import Database from 'better-sqlite3';

export type HistoricalIntegrityCode = 'C1' | 'C2' | 'C3' | 'H10';

export type HistoricalIntegrityCheck =
  | 'return_reference_collision'
  | 'return_reference_orphan'
  | 'return_restock_quantity_mismatch'
  | 'goods_receipt_without_gl'
  | 'unbatched_stock_balance'
  | 'unbatched_positive_movement'
  | 'invalid_stock_batch';

export interface HistoricalIntegrityFinding {
  code: HistoricalIntegrityCode;
  check: HistoricalIntegrityCheck;
  severity: 'high' | 'medium';
  document: string;
  reference: string;
  affectedQuantity: number | null;
  affectedAmount: number | null;
  expected: string;
  actual: string;
  proposedRepair: string;
}

export interface HistoricalIntegrityReport {
  mode: 'report-only';
  dryRun: true;
  backupRecommended: true;
  scannedAt: string;
  findings: HistoricalIntegrityFinding[];
  summary: {
    total: number;
    byCode: Record<HistoricalIntegrityCode, number>;
  };
  auditLog: string[];
}

interface C1GroupRow {
  reference_type: string;
  reference_id: number;
  debit: number | null;
  credit: number | null;
  void_reason: string | null;
  return_id: number | null;
  return_no: string | null;
  invoice_id: number | null;
  invoice_no: string | null;
}

interface C1OrphanRow {
  reference_type: string;
  reference_id: number;
  debit: number | null;
  credit: number | null;
}

interface C2Row {
  return_id: number;
  return_no: string;
  invoice_no: string;
  item_id: number;
  expected_quantity: number;
  actual_quantity: number;
  movement_id: number;
  movement_no: string;
  unit_cost: number;
  standard_cost: number;
}

interface C3Row {
  receipt_id: number;
  receipt_no: string;
  po_id: number;
  affected_quantity: number;
  affected_amount: number;
  active_line_count: number;
}

interface H10BalanceRow {
  item_id: number;
  warehouse_id: number;
  item_code: string;
  on_hand: number;
  covered: number;
  standard_cost: number;
}

interface H10MovementRow {
  movement_id: number;
  movement_no: string;
  item_id: number;
  item_code: string;
  quantity: number;
  unit_cost: number;
  standard_cost: number;
  has_batch_id: boolean;
}

interface H10BatchRow {
  batch_id: number;
  batch_no: string;
  item_id: number;
  item_code: string;
  quantity_original: number;
  quantity_remaining: number;
  unit_cost: number;
  standard_cost: number;
}

const REQUIRED_TABLES = [
  'invoices',
  'invoice_returns',
  'invoice_return_items',
  'journal_lines',
  'items',
  'stock_movements',
  'stock_balances',
  'stock_batches',
  'goods_receipts',
  'goods_receipt_items',
  'purchase_order_items',
] as const;

function tableExists(db: Database.Database, tableName: string): boolean {
  const row = db.prepare(`
    SELECT 1 AS present
    FROM sqlite_master
    WHERE type = 'table' AND name = ?
    LIMIT 1
  `).get(tableName) as { present: number } | undefined;
  return row !== undefined;
}

function hasColumn(db: Database.Database, tableName: string, columnName: string): boolean {
  const row = db.prepare(`
    SELECT 1 AS present
    FROM pragma_table_info(?)
    WHERE name = ?
    LIMIT 1
  `).get(tableName, columnName) as { present: number } | undefined;
  return row !== undefined;
}

function validateSchema(db: Database.Database): void {
  const missing = REQUIRED_TABLES.filter((tableName) => !tableExists(db, tableName));
  if (missing.length > 0) {
    throw new Error(`Historical integrity scan is missing required tables: ${missing.join(', ')}`);
  }
}

function numberValue(value: number | null | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function roundMoney(value: number): number {
  return Math.round(value * 10000) / 10000;
}

function amountFromGroup(debit: number | null, credit: number | null): number {
  return roundMoney(Math.max(numberValue(debit), numberValue(credit)));
}

function findC1Collisions(db: Database.Database): HistoricalIntegrityFinding[] {
  const rows = db.prepare(`
    SELECT
      jl.reference_type,
      jl.reference_id,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit,
      MAX(jl.void_reason) AS void_reason,
      r.id AS return_id,
      r.return_no,
      r.invoice_id,
      i.invoice_no
    FROM journal_lines jl
    LEFT JOIN invoice_returns r ON r.id = jl.reference_id
    LEFT JOIN invoices i ON i.id = r.invoice_id
    WHERE jl.voided = 1
      AND jl.reference_type IN ('INVOICE_RETURN', 'RETURN_FEE')
      AND (
        LOWER(COALESCE(jl.void_reason, '')) LIKE 'invoice % cancelled'
        OR LOWER(COALESCE(jl.void_reason, '')) LIKE 'invoice % deleted'
      )
    GROUP BY
      jl.reference_type,
      jl.reference_id,
      r.id,
      r.return_no,
      r.invoice_id,
      i.invoice_no
    ORDER BY jl.reference_type, jl.reference_id
  `).all() as C1GroupRow[];

  const findings: HistoricalIntegrityFinding[] = [];
  for (const row of rows) {
    const reason = row.void_reason?.trim() ?? '';
    const match = /^Invoice\s+(.+?)\s+(?:cancelled|deleted)$/i.exec(reason);
    if (!match) continue;

    const cancellingInvoiceNo = match[1].trim();
    if (row.return_id === null || row.invoice_no === null) {
      findings.push({
        code: 'C1',
        check: 'return_reference_orphan',
        severity: 'high',
        document: row.reference_type,
        reference: row.return_no ?? String(row.reference_id),
        affectedQuantity: null,
        affectedAmount: amountFromGroup(row.debit, row.credit),
        expected: `A return document and its owning invoice must resolve for ${row.reference_type} reference ${row.reference_id}.`,
        actual: `Cancellation attribution "${reason}" points to a missing return or invoice.`,
        proposedRepair: 'Reconstruct the missing return ownership from the audit trail before considering any GL repair; do not infer a repair from numeric IDs alone.',
      });
      continue;
    }

    if (row.invoice_no !== cancellingInvoiceNo) {
      findings.push({
        code: 'C1',
        check: 'return_reference_collision',
        severity: 'high',
        document: row.reference_type,
        // Same fallback as the orphan branch: a resolvable return_id whose
        // return_no is somehow NULL still gets a printable reference.
        reference: row.return_no ?? String(row.reference_id),
        affectedQuantity: null,
        affectedAmount: amountFromGroup(row.debit, row.credit),
        expected: `Return ${row.return_no} belongs to Invoice ${row.invoice_no}; only its owning invoice may void its GL.`,
        actual: `Its GL was voided by "${reason}" for Invoice ${cancellingInvoiceNo}.`,
        proposedRepair: 'Review the original return and cancellation audit rows, then restore/repost the affected return GL from its own return document only after backup and approval.',
      });
    }
  }
  return findings;
}

function findC1Orphans(db: Database.Database): HistoricalIntegrityFinding[] {
  const rows = db.prepare(`
    SELECT
      jl.reference_type,
      jl.reference_id,
      SUM(jl.debit) AS debit,
      SUM(jl.credit) AS credit
    FROM journal_lines jl
    LEFT JOIN invoice_returns r ON r.id = jl.reference_id
    WHERE jl.reference_type IN ('INVOICE_RETURN', 'RETURN_FEE')
      AND r.id IS NULL
    GROUP BY jl.reference_type, jl.reference_id
    ORDER BY jl.reference_type, jl.reference_id
  `).all() as C1OrphanRow[];

  return rows.map((row) => ({
    code: 'C1' as const,
    check: 'return_reference_orphan' as const,
    severity: 'high' as const,
    document: row.reference_type,
    reference: String(row.reference_id),
    affectedQuantity: null,
    affectedAmount: amountFromGroup(row.debit, row.credit),
    expected: `A return document must exist for ${row.reference_type} reference ${row.reference_id}.`,
    actual: 'No invoice_returns row resolves this journal reference.',
    proposedRepair: 'Identify the owning return from immutable document references and archived audit evidence before any repair; do not guess from the numeric reference ID.',
  }));
}

function findC2Mismatches(db: Database.Database): HistoricalIntegrityFinding[] {
  const rows = db.prepare(`
    SELECT
      r.id AS return_id,
      r.return_no,
      i.invoice_no,
      iri.item_id,
      iri.quantity AS expected_quantity,
      ABS(COALESCE(sm.quantity, 0)) AS actual_quantity,
      sm.id AS movement_id,
      sm.movement_no,
      COALESCE(sm.unit_cost, 0) AS unit_cost,
      COALESCE(it.standard_cost, 0) AS standard_cost
    FROM invoice_return_items iri
    JOIN invoice_returns r ON r.id = iri.return_id
    JOIN invoices i ON i.id = r.invoice_id
    JOIN items it ON it.id = iri.item_id
    JOIN stock_movements sm ON sm.id = iri.stock_movement_id
    WHERE iri.quantity > 0
      AND ABS(iri.quantity - ABS(COALESCE(sm.quantity, 0))) > 0.0005
    ORDER BY r.id, iri.id
  `).all() as C2Row[];

  return rows.map((row) => {
    const quantityDelta = roundMoney(row.expected_quantity - row.actual_quantity);
    const cost = row.unit_cost > 0 ? row.unit_cost : row.standard_cost;
    return {
      code: 'C2' as const,
      check: 'return_restock_quantity_mismatch' as const,
      severity: 'high' as const,
      document: 'INVOICE_RETURN',
      reference: row.return_no,
      affectedQuantity: quantityDelta,
      affectedAmount: roundMoney(quantityDelta * cost),
      expected: `Return ${row.return_no} line should restock ${row.expected_quantity} unit(s).`,
      actual: `Attributed movement ${row.movement_no} restocked ${row.actual_quantity} unit(s).`,
      proposedRepair: 'Restore only the quantity difference and its matching batch/COGS effect after reviewing the return and movement audit trail; create a backup first.',
    };
  });
}

function findC3MissingGl(db: Database.Database): HistoricalIntegrityFinding[] {
  const hasVoidedAt = hasColumn(db, 'goods_receipts', 'voided_at');
  const voidFilter = hasVoidedAt ? 'AND gr.voided_at IS NULL' : '';
  const rows = db.prepare(`
    WITH receipt_totals AS (
      SELECT
        gr.id AS receipt_id,
        gr.receipt_no,
        gr.po_id,
        COALESCE(SUM(gri.received_quantity), 0) AS affected_quantity,
        COALESCE(SUM(gri.received_quantity * poi.unit_price), 0) AS affected_amount
      FROM goods_receipts gr
      JOIN goods_receipt_items gri ON gri.receipt_id = gr.id
      JOIN purchase_order_items poi ON poi.id = gri.po_item_id
      WHERE 1 = 1 ${voidFilter}
      GROUP BY gr.id, gr.receipt_no, gr.po_id
    ),
    active_gl AS (
      SELECT reference_id, COUNT(*) AS active_line_count
      FROM journal_lines
      WHERE reference_type = 'GOODS_RECEIPT' AND voided = 0
      GROUP BY reference_id
    )
    SELECT
      rt.receipt_id,
      rt.receipt_no,
      rt.po_id,
      rt.affected_quantity,
      rt.affected_amount,
      COALESCE(ag.active_line_count, 0) AS active_line_count
    FROM receipt_totals rt
    LEFT JOIN active_gl ag ON ag.reference_id = rt.receipt_id
    WHERE rt.affected_amount > 0.005
      AND COALESCE(ag.active_line_count, 0) = 0
    ORDER BY rt.receipt_id
  `).all() as C3Row[];

  return rows.map((row) => ({
    code: 'C3' as const,
    check: 'goods_receipt_without_gl' as const,
    severity: 'high' as const,
    document: 'GOODS_RECEIPT',
    reference: row.receipt_no,
    affectedQuantity: numberValue(row.affected_quantity),
    affectedAmount: roundMoney(numberValue(row.affected_amount)),
    expected: `Post a balanced Dr 1200 / Cr 2000 receipt for ${roundMoney(numberValue(row.affected_amount)).toFixed(2)}.`,
    actual: `No active GOODS_RECEIPT journal lines were found (${row.active_line_count} active line(s)).`,
    proposedRepair: 'Backfill the receipt GL and supplier-liability effect only after backup and review; verify inventory and AP totals before applying it.',
  }));
}

function findH10UnbatchedBalances(db: Database.Database): HistoricalIntegrityFinding[] {
  const rows = db.prepare(`
    WITH coverage AS (
      SELECT
        item_id,
        warehouse_id,
        SUM(COALESCE(quantity_remaining, 0)) AS covered
      FROM stock_batches
      GROUP BY item_id, warehouse_id
    )
    SELECT
      sb.item_id,
      sb.warehouse_id,
      i.item_code,
      COALESCE(sb.quantity, 0) AS on_hand,
      COALESCE(c.covered, 0) AS covered,
      COALESCE(i.standard_cost, 0) AS standard_cost
    FROM stock_balances sb
    JOIN items i ON i.id = sb.item_id
    LEFT JOIN coverage c
      ON c.item_id = sb.item_id AND c.warehouse_id = sb.warehouse_id
    WHERE COALESCE(sb.quantity, 0) > 0
      AND COALESCE(sb.quantity, 0) - COALESCE(c.covered, 0) > 0.0005
    ORDER BY sb.item_id, sb.warehouse_id
  `).all() as H10BalanceRow[];

  return rows.map((row) => {
    const delta = roundMoney(row.on_hand - row.covered);
    return {
      code: 'H10' as const,
      check: 'unbatched_stock_balance' as const,
      severity: 'high' as const,
      document: 'STOCK_BALANCE',
      reference: `${row.item_id}/${row.warehouse_id}`,
      affectedQuantity: delta,
      affectedAmount: roundMoney(delta * row.standard_cost),
      expected: 'On-hand stock must be covered by a positive-cost stock batch layer.',
      actual: `On-hand quantity is ${row.on_hand}, but covering batches contain ${row.covered}.`,
      proposedRepair: 'Create or restore a costed batch from the historical inbound evidence after backup; do not silently post a standard-cost adjustment.',
    };
  });
}

function findH10UnbatchedMovements(db: Database.Database): HistoricalIntegrityFinding[] {
  const hasBatchId = hasColumn(db, 'stock_movements', 'batch_id');
  const batchPredicate = hasBatchId ? 'sm.batch_id IS NULL' : '1 = 1';
  const rows = db.prepare(`
    SELECT
      sm.id AS movement_id,
      sm.movement_no,
      sm.item_id,
      i.item_code,
      sm.quantity,
      COALESCE(sm.unit_cost, 0) AS unit_cost,
      COALESCE(i.standard_cost, 0) AS standard_cost,
      ${hasBatchId ? '1' : '0'} AS has_batch_id
    FROM stock_movements sm
    JOIN items i ON i.id = sm.item_id
    WHERE sm.quantity > 0
      AND sm.movement_type IN ('PURCHASE', 'PRODUCTION', 'ADJUSTMENT', 'OPENING', 'RETURN')
      AND ${batchPredicate}
    ORDER BY sm.id
  `).all() as H10MovementRow[];

  return rows.map((row) => {
    const cost = row.unit_cost > 0 ? row.unit_cost : row.standard_cost;
    return {
      code: 'H10' as const,
      check: 'unbatched_positive_movement' as const,
      severity: 'high' as const,
      document: 'STOCK_MOVEMENT',
      reference: row.movement_no,
      affectedQuantity: numberValue(row.quantity),
      affectedAmount: roundMoney(numberValue(row.quantity) * cost),
      expected: 'Every positive inventory movement must retain a traceable stock batch/cost layer.',
      actual: row.has_batch_id
        ? `Movement ${row.movement_no} has no batch_id.`
        : `The stock_movements table has no batch_id column; movement ${row.movement_no} cannot be batch-attributed.`,
      proposedRepair: 'Reconstruct the missing batch link from the movement and source document, then verify FIFO cost and GL impact after backup.',
    };
  });
}

function findH10InvalidBatches(db: Database.Database): HistoricalIntegrityFinding[] {
  const rows = db.prepare(`
    SELECT
      sb.id AS batch_id,
      sb.batch_no,
      sb.item_id,
      i.item_code,
      sb.quantity_original,
      sb.quantity_remaining,
      sb.unit_cost,
      COALESCE(i.standard_cost, 0) AS standard_cost
    FROM stock_batches sb
    JOIN items i ON i.id = sb.item_id
    WHERE sb.unit_cost <= 0 OR sb.quantity_original <= 0
    ORDER BY sb.id
  `).all() as H10BatchRow[];

  return rows.map((row) => {
    const affectedQuantity = numberValue(row.quantity_remaining);
    const cost = row.standard_cost > 0 ? row.standard_cost : 0;
    return {
      code: 'H10' as const,
      check: 'invalid_stock_batch' as const,
      severity: 'high' as const,
      document: 'STOCK_BATCH',
      reference: row.batch_no,
      affectedQuantity,
      affectedAmount: roundMoney(affectedQuantity * cost),
      expected: 'A stock batch must have positive original quantity and positive unit cost.',
      actual: `Batch has original quantity ${row.quantity_original}, unit cost ${row.unit_cost}, and remaining quantity ${row.quantity_remaining}.`,
      proposedRepair: 'Hold the batch for manual review and reconstruct its cost from source evidence; never replace missing cost with an unverified default.',
    };
  });
}

function createReport(findings: HistoricalIntegrityFinding[]): HistoricalIntegrityReport {
  const byCode: Record<HistoricalIntegrityCode, number> = {
    C1: 0,
    C2: 0,
    C3: 0,
    H10: 0,
  };
  for (const finding of findings) byCode[finding.code] += 1;

  const auditLog = [
    'Historical integrity scan started in report-only/dry-run mode.',
    `C1: ${byCode.C1} finding(s) for return/reference collisions or orphans.`,
    `C2: ${byCode.C2} finding(s) for return restock quantity mismatches.`,
    `C3: ${byCode.C3} finding(s) for goods receipts without GL.`,
    `H10: ${byCode.H10} finding(s) for unbatched or invalid stock cost layers.`,
    ...findings.map(
      (finding) => `[${finding.code}/${finding.check}] ${finding.document} ${finding.reference}: ${finding.actual}`,
    ),
    'No repair mode executed; no historical data was modified.',
    'Backup recommended: run npm run db:backup before any reviewed repair.',
  ];

  return {
    mode: 'report-only',
    dryRun: true,
    backupRecommended: true,
    scannedAt: new Date().toISOString(),
    findings,
    summary: {
      total: findings.length,
      byCode,
    },
    auditLog,
  };
}

export function scanHistoricalDataIntegrity(db: Database.Database): HistoricalIntegrityReport {
  validateSchema(db);
  const scan = db.transaction((): HistoricalIntegrityReport => createReport([
    ...findC1Collisions(db),
    ...findC1Orphans(db),
    ...findC2Mismatches(db),
    ...findC3MissingGl(db),
    ...findH10UnbatchedBalances(db),
    ...findH10UnbatchedMovements(db),
    ...findH10InvalidBatches(db),
  ]));
  return scan();
}
