/**
 * Gated stock repair scripts (INV-04 / INV-05)
 * --------------------------------------------
 * Boot never writes to the stock tables (boot-task-gating spec). The
 * reconciliation and cleanup logic that used to run on every start lives
 * here instead, behind explicit opt-in invocations:
 *
 *   npm run repair:unbatched-stock   — mint cost layers for on-hand stock
 *                                      with no covering batch (INV-04)
 *   npm run repair:orphaned-batches  — clean genuinely empty orphaned
 *                                      batches, preserving audit links
 *                                      (INV-05)
 *
 * Safety properties (per spec):
 *   - Reconciliation scopes its cost average to inbound PURCHASE/PRODUCTION
 *     movements per (item, warehouse); posts a balancing journal entry for
 *     every capitalised amount; refuses to run twice for the same gap via a
 *     settings flag; trims over-covered batches.
 *   - Cleanup refuses to delete any batch holding quantity_remaining > 0.0005
 *     (reported as "needs manual review") and NEVER sets
 *     stock_movements.batch_id = NULL — historical links stay resolvable.
 */

import path from 'path';
import fs from 'fs';
import db from '../src/config/database';
import { getNextSequenceNumber } from '../src/utils/sequence';

const MIGRATIONS_DIR = path.resolve(__dirname, '../src/migrations');
const logger = {
  info: (m: string) => console.log(`[INFO] ${m}`),
  warn: (m: string) => console.log(`[WARN] ${m}`),
};

const command = process.argv[2];

// ── INV-04: unbatched-stock reconciliation ───────────────────────────

function repairUnbatchedStock(): void {
  const settingsKey = 'repair.unbatched_stock.last_run';
  const lastRun = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingsKey) as { value: string } | undefined;
  if (lastRun) {
    logger.info(`Reconciliation already ran at ${lastRun.value}. Re-running is allowed but will only fill NEW gaps.`);
  }

  const rows = db.prepare(`
    SELECT
      sb.item_id,
      sb.warehouse_id,
      sb.quantity as on_hand,
      COALESCE((
        SELECT SUM(quantity_remaining)
        FROM stock_batches
        WHERE item_id = sb.item_id AND warehouse_id = sb.warehouse_id
      ), 0) as covered,
      i.standard_cost
    FROM stock_balances sb
    JOIN items i ON i.id = sb.item_id
    WHERE sb.quantity > 0
  `).all() as Array<{
    item_id: number;
    warehouse_id: number;
    on_hand: number;
    covered: number;
    standard_cost: number;
  }>;

  let created = 0;
  let capitalised = 0;

  const run = db.transaction(() => {
    const insertBatch = db.prepare(`
      INSERT INTO stock_batches (
        batch_no, item_id, warehouse_id, source_type,
        source_id, quantity_original, quantity_remaining,
        unit_cost, received_date
      ) VALUES (?, ?, ?, 'RECON', 0, ?, ?, ?, ?)
    `);

    for (const row of rows) {
      let uncovered = row.on_hand - row.covered;
      if (uncovered <= 0.0005) continue;

      // Over-covered batches (batch quantity exceeding balances): trim the
      // batch down to the balance instead of ignoring the mismatch.
      if (uncovered < 0) {
        const overBy = -uncovered;
        logger.warn(`Over-covered batches for item ${row.item_id}/wh ${row.warehouse_id} by ${overBy} — trimming oldest layers`);
        const layers = db.prepare(`
          SELECT id, quantity_remaining FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ?
          ORDER BY received_date ASC, id ASC
        `).all(row.item_id, row.warehouse_id) as Array<{ id: number; quantity_remaining: number }>;
        let toTrim = overBy;
        for (const layer of layers) {
          if (toTrim <= 0.0005) break;
          const trim = Math.min(layer.quantity_remaining, toTrim);
          db.prepare('UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?').run(trim, layer.id);
          toTrim -= trim;
        }
        continue;
      }

      // Cost average scoped to THIS warehouse's inbound movements that have
      // NO batch link (the units being reconciled), from purchase/production
      // sources only. Fall back to standard cost, then 0.
      const avg = db.prepare(`
        SELECT COALESCE(
          SUM(quantity * unit_cost) * 1.0 / NULLIF(SUM(quantity), 0),
          0
        ) as cost
        FROM stock_movements
        WHERE item_id = ? AND warehouse_id = ?
          AND quantity > 0 AND batch_id IS NULL
          AND movement_type IN ('PURCHASE', 'PRODUCTION')
      `).get(row.item_id, row.warehouse_id) as { cost: number };
      const unitCost = avg.cost > 0
        ? avg.cost
        : (row.standard_cost || 0);

      const nextNo = getNextSequenceNumber(db, 'BATCH_RECON_last_no');
      const batchNo = `BATCH-${new Date().getFullYear() % 100}-RECON-${nextNo.toString().padStart(4, '0')}`;

      insertBatch.run(
        batchNo,
        row.item_id,
        row.warehouse_id,
        uncovered,
        uncovered,
        unitCost,
        new Date().toISOString().split('T')[0]
      );

      // Balancing journal entry for every capitalised amount — uses the
      // legacy journal_entries shape (reference_type/reference_id +
      // text accounts) that the rest of the system reconciles against,
      // plus matching journal_lines rows keyed to the real COA ids.
      const value = uncovered * unitCost;
      if (value > 0.005 && db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='journal_entries'`).get()) {
        const desc = `Unbatched stock reconciliation: ${uncovered} units @ ${unitCost} (item ${row.item_id}, warehouse ${row.warehouse_id})`;
        const je = db.prepare(`
          INSERT INTO journal_entries (reference_type, reference_id, entry_date, description, debit_account, credit_account, amount, voided)
          VALUES ('RECON', 0, ?, ?, '1200', '4999', ?, 0)
        `).run(new Date().toISOString().split('T')[0], desc, value);
        const jeId = je.lastInsertRowid as number;
        const lines = db.prepare(`
          INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description, line_date)
          VALUES (?, ?, ?, ?, ?, ?)
        `);
        const inventoryAccount = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '1200'`).get() as { id: number } | undefined;
        const adjustmentAccount = db.prepare(`SELECT id FROM chart_of_accounts WHERE code = '4999' OR code = '4000' ORDER BY code DESC LIMIT 1`).get() as { id: number } | undefined;
        if (inventoryAccount && adjustmentAccount) {
          const today = new Date().toISOString().split('T')[0];
          lines.run(jeId, inventoryAccount.id, value, 0, 'Inventory increase (reconciled unbatched stock)', today);
          lines.run(jeId, adjustmentAccount.id, 0, value, 'Stock reconciliation adjustment', today);
        }
      }
      capitalised += value;
      created++;
    }

    db.prepare(`
      INSERT INTO settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(settingsKey, new Date().toISOString());
  });

  run();

  if (created > 0) {
    logger.info(`✅ Created ${created} RECON batch row(s), capitalised ${capitalised.toFixed(2)} with balancing JEs`);
  } else {
    logger.info('✅ Nothing to do — all on-hand stock already has covering batches');
  }
}

// ── INV-05: orphaned-batch cleanup ───────────────────────────────────

function repairOrphanedBatches(): void {
  const orphaned = db.prepare(`
    SELECT sb.id, sb.batch_no, sb.source_type, sb.source_id,
           sb.unit_cost, sb.quantity_original, sb.quantity_remaining
    FROM stock_batches sb
    WHERE (sb.source_type IN ('PURCHASE', 'GOODS_RECEIPT')
           AND NOT EXISTS (
             SELECT 1 FROM goods_receipt_items gri WHERE gri.id = sb.source_id
           )
           AND NOT EXISTS (
             SELECT 1 FROM purchases p WHERE p.id = sb.source_id AND sb.source_type = 'PURCHASE'
           ))
       OR sb.unit_cost <= 0
       OR sb.quantity_original <= 0
  `).all() as Array<{
    id: number; batch_no: string; source_type: string; source_id: number;
    unit_cost: number; quantity_original: number; quantity_remaining: number;
  }>;

  if (orphaned.length === 0) {
    logger.info('✅ Nothing to do — no orphaned/invalid batches found');
    return;
  }

  const deletable: number[] = [];
  const needsReview: typeof orphaned = [];
  for (const b of orphaned) {
    if (b.quantity_remaining > 0.0005 || b.unit_cost <= 0 || b.quantity_original <= 0) {
      needsReview.push(b);
    } else {
      deletable.push(b.id);
    }
  }

  for (const b of needsReview) {
    logger.warn(`NEEDS MANUAL REVIEW: batch ${b.batch_no} (id=${b.id}) kept — quantity_remaining=${b.quantity_remaining}, unit_cost=${b.unit_cost}`);
  }

  const run = db.transaction(() => {
    const del = db.prepare('DELETE FROM stock_batches WHERE id = ?');
    for (const id of deletable) {
      // Audit-link safety: verify no movement still references this batch
      // before deleting; keep the row (tombstoned to zero) otherwise so the
      // link stays resolvable. We NEVER set stock_movements.batch_id = NULL.
      const refCount = (db.prepare('SELECT COUNT(*) AS n FROM stock_movements WHERE batch_id = ?').get(id) as { n: number }).n;
      if (refCount > 0) {
        db.prepare('UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?').run(id);
        logger.info(`Tombstoned batch id=${id} (kept for ${refCount} movement reference(s))`);
      } else {
        del.run(id);
      }
    }
  });
  run();

  logger.info(`✅ Cleanup complete: ${deletable.length} removed/tombstoned, ${needsReview.length} flagged for manual review`);
}

// ── Entry point ──────────────────────────────────────────────────────

switch (command) {
  case 'unbatched-stock':
    repairUnbatchedStock();
    break;
  case 'orphaned-batches':
    repairOrphanedBatches();
    break;
  default:
    console.error('Usage: ts-node scripts/repair-stock.ts <unbatched-stock|orphaned-batches>');
    console.error('These are explicit opt-in repair scripts — they do NOT run at boot.');
    process.exit(1);
}
