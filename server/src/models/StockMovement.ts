import Database from 'better-sqlite3';
import { getNextSequenceNumber } from '../utils/sequence';
import logger from '../utils/logger';
import AccountingService from '../services/accountingService';
import { sanitizeSortParams, STOCK_BALANCE_SORT_COLUMNS, STOCK_MOVEMENT_SORT_COLUMNS } from '../utils/sqlSanitizer';
import { isFeatureEnabled } from '../utils/featureFlags';
import { SellableStockUnavailableError } from '../types';
import { roundQty, qtyEpsilon, qtyLessThan, qtyPositive } from '../utils/quantity';
import { roundCurrency } from '../utils/currency';
import { SqlParam } from '../utils/sqlTypes';
import { recordBatchSources } from '../utils/batchSuppliers';

interface StockMovement {
  id: number;
  movement_no: string;
  item_id: number;
  warehouse_id: number;
  movement_type: string;
  quantity: number;
  unit_cost?: number;
  reference_doctype?: string;
  reference_docno?: string;
  remarks?: string;
  movement_date: string;
  created_by: number;
  created_at?: string;
  item_code?: string;
  item_name?: string;
  unit_of_measure?: string;
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_name?: string;
}

interface MovementFilters {
  item_id?: number;
  warehouse_id?: number;
  movement_type?: string;
  date_from?: string;
  date_to?: string;
  search?: string;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface StockBalanceFilters {
  search?: string;
  warehouse_code?: string;
  warehouse_id?: number;
  sortBy?: string;
  sortOrder?: string;
  page?: number;
  limit?: number;
}

interface PaginatedStockBalances {
  rows: StockMovement[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column for the stock-balances
// query (joined aliases; qualification avoids ambiguity).
const BALANCE_SORT_COLUMN_MAP: Record<string, string> = {
  item_code: 'i.item_code',
  item_name: 'i.item_name',
  warehouse_name: 'w.warehouse_name',
  quantity: 'sb.quantity',
};

interface PaginatedMovements {
  rows: StockMovement[];
  total: number;
  pageNum: number;
  limitNum: number;
}

// Whitelisted sort columns → qualified SQL column (the grid sorts on
// joined aliases like `item_name`; qualification avoids ambiguity).
const SORT_COLUMN_MAP: Record<string, string> = {
  movement_no: 'sm.movement_no',
  movement_date: 'sm.movement_date',
  item_name: 'i.item_name',
  warehouse_name: 'w.warehouse_name',
  movement_type: 'sm.movement_type',
  quantity: 'sm.quantity',
  reference_docno: 'sm.reference_docno',
  created_at: 'sm.created_at',
};

interface RecordMovementDTO {
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost?: number;
  reference_doctype?: string;
  reference_docno?: string;
  remarks?: string;
  movement_type: string;
  movement_date?: string;
  batch_id?: number;
  /** When true, skip H10 batch creation — the caller manages batches directly. */
  skipBatchCreation?: boolean;
  /** When true, an ADJUSTMENT movement records no GL leg at all. Set by paths
   *  that already post the inventory effect themselves, where a leg here is a
   *  duplicate — and a duplicate valued at items.standard_cost rather than the
   *  cost of the layer restored. See docs/known-issues.md item 1. */
  skipAdjustmentFinancialPosting?: boolean;
}

type ConsumptionEntry = { batchId: number | null; consumed: number; unitCost: number };

type LocationBatchRow = {
  id: number;
  unit_cost: number;
  received_date: string;
  expiry_date: string | null;
  qty_avail: number;
};

type LegacyBatchRow = { id: number; quantity_remaining: number; unit_cost: number };

/**
 * BUG-013 R1: the location statuses that may still be SOLD. DAMAGED stock is
 * sellable at scrap / reduced price, so it must be offered (with a warning the
 * caller raises) rather than hidden. Every other override — EXPIRED, BLOCKED,
 * QUARANTINED — stays unsellable. One shared rule so the flag-on allocator and
 * the flag-off legacy path cannot drift apart again.
 */
const SELLABLE_STATUS_OVERRIDES = ['ACTIVE', 'DAMAGED'] as const;

/** SQL fragment: the bin's status_override is missing (never overridden) or a
 *  sellable one. Built from a fixed code constant — never from request input —
 *  so it is safe to inline in queries that already use named parameters. */
function sellableStatusClause(column: string): string {
  const list = SELLABLE_STATUS_OVERRIDES.map((s) => `'${s}'`).join(', ');
  return `(${column} IS NULL OR ${column} IN (${list}))`;
}

/** Item name for a warning message, with a stable fallback. */
function itemName(db: Database.Database, itemId: number): string {
  return (db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as
    | { item_name: string }
    | undefined)?.item_name ?? `item ${itemId}`;
}

/** BUG-013 R1: the one warning text for selling held-damaged stock. */
function damagedWarning(db: Database.Database, itemId: number): string {
  return (
    `Item ${itemName(db, itemId)}: sold stock held in a DAMAGED location — ` +
    `confirm the goods are fit for the agreed scrap or reduced price.`
  );
}

/**
 * Push a warning once. A multi-batch sale runs the per-batch loop several
 * times; two damaged batches must not repeat the same line to the cashier.
 */
function pushUniqueWarning(warnings: string[], message: string): void {
  if (!warnings.includes(message)) warnings.push(message);
}

/**
 * BUG-013: drain ONE batch's sellable bins by AVAILABLE (physical - reserved)
 * for the pre-receipt fallback, which predates the location allocator. Caps at
 * the bin's available so a reservation survives, skips non-sellable bins so a
 * blocked bin is never eaten, and returns the same R1/R2 warnings the main
 * path raises.
 */
function consumeFallbackBins(
  db: Database.Database,
  batchId: number,
  warehouseId: number,
  take: number,
  itemId: number
): string[] {
  const warnings: string[] = [];
  const bins = db.prepare(`
    SELECT bsl.id, bsl.quantity_available, bsl.status_override
    FROM batch_stock_by_location bsl
    JOIN locations l ON bsl.location_id = l.id
    WHERE bsl.batch_id = ? AND l.warehouse_id = ?
      AND bsl.quantity_available > 0
      AND ${sellableStatusClause('bsl.status_override')}
    ORDER BY l.created_at ASC, bsl.id ASC
  `).all(batchId, warehouseId) as Array<{ id: number; quantity_available: number; status_override: string | null }>;

  const sellableAvailable = roundQty(bins.reduce((s, b) => s + roundQty(b.quantity_available), 0));
  let remaining = take;
  let hitDamaged = false;
  for (const bin of bins) {
    if (remaining <= 0) break;
    const amount = roundQty(Math.min(remaining, roundQty(bin.quantity_available)));
    if (amount > 0 && bin.status_override === 'DAMAGED') hitDamaged = true;
    db.prepare('UPDATE batch_stock_by_location SET quantity_physical = MAX(0, quantity_physical - ?) WHERE id = ?')
      .run(amount, bin.id);
    remaining -= amount;
  }

  if (hitDamaged) warnings.push(damagedWarning(db, itemId));
  if (bins.length > 0 && qtyLessThan(sellableAvailable, take)) {
    warnings.push(
      `Item ${itemName(db, itemId)}: only ${sellableAvailable} unit(s) are available in the location ledger ` +
      `for this batch, but ${take} were sold — the remainder came from the batch total. ` +
      `Run the batch-location backfill to reconcile.`
    );
  }
  return warnings;
}

/**
 * Sellable quantity for the item in the warehouse.
 *
 * `stock_balances` is the source of truth. `quantity_available` exists only
 * after the batch-location migration, so it is read only when the feature is
 * on — legacy databases (flag off, column absent) keep the old behaviour.
 *
 * With the flag on, legacy stock that predates batch costing has no
 * `batch_stock_by_location` rows, so `quantity_available` is 0 while
 * `quantity` still holds the real on-hand amount. Such stock must stay
 * consumable (the no-coverage fallback below prices it at standard cost with
 * batchId null), so fall back to `quantity` when the item has no per-location
 * coverage in this warehouse.
 */
function resolveAvailableQuantity(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  requiredQty: number,
  featureOn: boolean
): number {
  const balanceRow = db.prepare(`
    SELECT quantity${featureOn ? ', quantity_available' : ''} FROM stock_balances
    WHERE item_id = ? AND warehouse_id = ?
  `).get(itemId, warehouseId) as { quantity: number; quantity_available?: number } | undefined;

  let availableQty = featureOn
    ? (balanceRow ? roundQty(parseFloat(String(balanceRow.quantity_available ?? 0))) : 0)
    : (balanceRow ? roundQty(parseFloat(String(balanceRow.quantity))) : 0);

  if (featureOn) {
    // BUG-013. The flag-on read trusts stock_balances.quantity_available, a
    // mirror that only the flag-on write path maintains. On any database where
    // the mirror lagged — a flag flip, a batch written by a path that did not
    // refresh it, a legacy row — the mirror is LOWER than the truth and the
    // sale is refused with "sellable stock 0".
    //
    // Fall back to the batch-level total whenever the location table covers
    // less than the mirror claims. A location table that covers MORE than the
    // mirror (a block, a reservation) is left alone: the finer-grained number
    // must still gate the sale. This only ever raises the figure toward the
    // batch total, which the drift invariant independently caps at the real
    // quantity, so it cannot offer phantom stock.
    const coverage = db.prepare(`
      SELECT COALESCE(SUM(bsl.quantity_available), 0) as covered
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      JOIN stock_batches sb ON sb.id = bsl.batch_id
      WHERE l.warehouse_id = ? AND sb.item_id = ?
    `).get(warehouseId, itemId) as { covered: number };
    const covered = roundQty(coverage.covered);
    if (qtyLessThan(covered, availableQty) || qtyLessThan(availableQty, requiredQty)) {
      availableQty = balanceRow ? roundQty(parseFloat(String(balanceRow.quantity))) : 0;
    }
  }

  return availableQty;
}

/**
 * Batches eligible for consumption, aggregated across the locations of this
 * warehouse. `useFEFO` adds the expiry filter; both paths skip halted batches
 * and non-ACTIVE locations.
 */
function selectLocationBatches(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  asOf: string,
  useFEFO: boolean,
  opts?: { ignoreReceiptDate?: boolean }
): LocationBatchRow[] {
  const locationFilter = useFEFO
    ? `AND COALESCE(sb.halted, 0) = 0 AND ${sellableStatusClause('bsl.status_override')}
       AND (sb.expiry_date IS NULL OR sb.expiry_date >= @asOf)`
    : `AND COALESCE(sb.halted, 0) = 0 AND ${sellableStatusClause('bsl.status_override')}`;
  // ACCT-006 backdated fallback: drop the received_date cutoff so batches
  // received after the sale date are visible. Expiry sellability is still
  // judged at the sale date.
  const receiptFilter = opts?.ignoreReceiptDate ? '' : 'AND sb.received_date <= @asOf';

  return db.prepare(`
    SELECT sb.id, sb.unit_cost, sb.received_date, sb.expiry_date,
           SUM(bsl.quantity_available) as qty_avail
    FROM stock_batches sb
    JOIN batch_stock_by_location bsl ON sb.id = bsl.batch_id
    JOIN locations l ON bsl.location_id = l.id
    WHERE sb.item_id = ? AND l.warehouse_id = ?
      AND bsl.quantity_available > 0
      ${receiptFilter}
      ${locationFilter}
    GROUP BY sb.id
    ORDER BY
      CASE WHEN sb.expiry_date IS NULL THEN 1 ELSE 0 END,
      sb.expiry_date ASC,
      sb.received_date ASC,
      sb.id ASC
  `).all(itemId, warehouseId, { asOf }) as LocationBatchRow[];
}

/**
 * Stock exists in this warehouse but every batch/location is blocked or
 * expired. That is "no sellable stock", not legacy unbatched stock.
 */
function assertNoBlockedStockOnly(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  quantity: number
): void {
  const allBatchStock = db.prepare(`
    SELECT SUM(bsl.quantity_available) as total, COUNT(*) as rows_count
    FROM batch_stock_by_location bsl
    JOIN locations l ON bsl.location_id = l.id
    WHERE l.warehouse_id = ?
      AND EXISTS (
        SELECT 1 FROM stock_batches sb
        WHERE sb.id = bsl.batch_id AND sb.item_id = ?
      )
  `).get(warehouseId, itemId) as { total: number; rows_count: number } | undefined;
  const totalBlocked = allBatchStock?.total ?? 0;
  const coverageRows = allBatchStock?.rows_count ?? 0;
  if (totalBlocked <= 0 && coverageRows <= 0) return;

  const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
  throw new SellableStockUnavailableError(
    item?.item_name || `item ${itemId}`,
    quantity,
    0
  );
}

/**
 * Consume from the oldest eligible batch first. The location rows of a batch
 * are drawn down first, then the master batch row is decremented by the
 * batch's total take.
 */
function consumeBatchesByLocation(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  batchRows: LocationBatchRow[],
  roundedQty: number,
  warnings: string[]
): ConsumptionEntry[] {
  let remaining = roundedQty;
  const consumption: ConsumptionEntry[] = [];

  for (const batch of batchRows) {
    if (remaining <= 0) break;
    const batchAvail = roundQty(batch.qty_avail);
    const consumeFromThis = roundQty(Math.min(remaining, batchAvail));

    // Location rows for this batch in this warehouse. The batch-level
    // expiry/halted filter already ran in the outer batchRows query;
    // here only location sellability applies (ACTIVE status).
    // (The previous version referenced `sb.expiry_date` out of scope
    // — a latent "no such column" failure on every FEFO consumption.)
    const locRows = db.prepare(`
      SELECT bsl.id, bsl.quantity_available, bsl.status_override, l.created_at
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      WHERE bsl.batch_id = ? AND l.warehouse_id = ?
        AND bsl.quantity_available > 0
        AND ${sellableStatusClause('bsl.status_override')}
      ORDER BY l.created_at ASC, bsl.id ASC
    `).all(batch.id, warehouseId) as Array<{ id: number; quantity_available: number; status_override: string | null; created_at: string }>;

    // BUG-013 R1 (flag ON): selling from a DAMAGED bin is allowed, but never
    // silent. The warning is raised from the bins the take ACTUALLY hit — a
    // DAMAGED bin the allocator never reached must not cry wolf.
    let hitDamaged = false;

    let batchRemaining = consumeFromThis;
    for (const loc of locRows) {
      if (batchRemaining <= 0) break;
      const locAvail = roundQty(loc.quantity_available);
      const take = roundQty(Math.min(batchRemaining, locAvail));
      if (take > 0 && loc.status_override === 'DAMAGED') hitDamaged = true;
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = quantity_physical - ?, quantity_reserved = quantity_reserved
        WHERE id = ?
      `).run(take, loc.id);
      batchRemaining -= take;
    }

    if (hitDamaged) pushUniqueWarning(warnings, damagedWarning(db, itemId));

    // Also decrement master batch for backward compatibility
    db.prepare(`
      UPDATE stock_batches
      SET quantity_remaining = quantity_remaining - ?
      WHERE id = ?
    `).run(consumeFromThis, batch.id);

    consumption.push({ batchId: batch.id, consumed: consumeFromThis, unitCost: batch.unit_cost });
    remaining -= consumeFromThis;
  }

  if (qtyPositive(remaining)) {
    const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
    throw new SellableStockUnavailableError(
      item?.item_name || `item ${itemId}`,
      roundedQty,
      roundQty(roundedQty - remaining)
    );
  }

  return consumption;
}

/**
 * Batches for the legacy (feature-flag-off) path. FEFO additionally reports
 * the total tracked quantity so the caller can tell "all batches exhausted"
 * from "no batches at all".
 */
function selectLegacyBatches(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  asOf: string,
  useFEFO: boolean,
  availableQty: number,
  opts?: { ignoreReceiptDate?: boolean }
): { batches: LegacyBatchRow[]; totalBatchTrackedQty: number } {
  // ACCT-006 backdated fallback: drop the received_date cutoff (expiry
  // sellability is still judged at the sale date).
  const receiptFilter = opts?.ignoreReceiptDate ? '' : 'AND received_date <= @asOf';
  if (!useFEFO) {
    const batches = db.prepare(`
      SELECT id, quantity_remaining, unit_cost
      FROM stock_batches
      WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
        ${receiptFilter}
      ORDER BY received_date ASC, id ASC
    `).all(itemId, warehouseId, { asOf }) as LegacyBatchRow[];
    return { batches, totalBatchTrackedQty: 0 };
  }

  const batches = db.prepare(`
    SELECT id, quantity_remaining, unit_cost
    FROM stock_batches
    WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
      AND (halted = 0 OR halted IS NULL)
      ${receiptFilter}
      AND (expiry_date IS NULL OR expiry_date >= @asOf)
    ORDER BY
      CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END,
      expiry_date ASC,
      received_date ASC,
      id ASC
  `).all(itemId, warehouseId, { asOf }) as LegacyBatchRow[];

  if (batches.length > 0) return { batches, totalBatchTrackedQty: 0 };

  if (availableQty <= 0) return { batches, totalBatchTrackedQty: 0 };

  const allBatches = db.prepare(`
    SELECT SUM(quantity_remaining) as total
    FROM stock_batches
    WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
  `).get(itemId, warehouseId) as { total: number } | undefined;

  return { batches, totalBatchTrackedQty: allBatches?.total ?? 0 };
}

function consumeLegacyBatches(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  batches: LegacyBatchRow[],
  roundedQty: number,
  warnings: string[]
): ConsumptionEntry[] {
  let remaining = roundedQty;
  const consumption: ConsumptionEntry[] = [];

  for (const batch of batches) {
    if (remaining <= 0) break;

    // BUG-013 R4: the bins are the reservation ledger. Free units are
    //   master quantity - TOTAL reserved in this batch's bins
    // (not per-bin available, whose MAX(0, ...) hides an over-reservation).
    // A batch with no bin rows has no reservation evidence, so reserved is 0
    // and the legacy master-quantity rule stands.
    const binAgg = db.prepare(`
      SELECT COUNT(*) AS c,
             COALESCE(SUM(bsl.quantity_reserved), 0) AS reserved,
             -- Only the UNRESERVED part of a non-sellable bin is lost stock.
             -- A reserved unit is already subtracted below, so subtracting
             -- the full physical again would count it twice and hide free
             -- stock that lives elsewhere in the batch.
             COALESCE(SUM(CASE WHEN ${sellableStatusClause('bsl.status_override')}
                               THEN 0
                               ELSE MAX(0, bsl.quantity_physical - bsl.quantity_reserved) END), 0) AS unsellable
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      WHERE bsl.batch_id = ? AND l.warehouse_id = ?
    `).get(batch.id, warehouseId) as { c: number; avail: number; reserved: number; unsellable: number };
    const binCount = Number(binAgg.c);
    const binReserved = roundQty(Number(binAgg.reserved));
    // R1+R4: free = master - every reserved unit - the unreserved units parked
    // in a non-sellable bin (EXPIRED/BLOCKED/QUARANTINED). Disjoint terms: a
    // reserved unit is subtracted once, never twice. A batch with no bin rows
    // has neither reservation nor status evidence, so free is the master
    // quantity.
    const binUnsellable = roundQty(Number(binAgg.unsellable));
    const sellableHere = roundQty(
      Math.max(0, roundQty(batch.quantity_remaining) - binReserved - binUnsellable)
    );
    if (sellableHere <= 0) continue;
    //  - R1: a DAMAGED bin is still sellable, so read the shared sellable
    //    status clause instead of ignoring status entirely. EXPIRED/BLOCKED/
    //    QUARANTINED bins were silently sold before this.
    //  - R4: cap each take to the bin's AVAILABLE (physical - reserved), not
    //    its physical. Filtering on quantity_physical > 0 while taking
    //    quantity_physical hands out reserved units. The reserved promise
    //    survives the fallback.
    const locRows = db.prepare(`      SELECT bsl.id, bsl.quantity_available, bsl.status_override, l.created_at
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      WHERE bsl.batch_id = ? AND l.warehouse_id = ?
        AND bsl.quantity_available > 0
        AND ${sellableStatusClause('bsl.status_override')}
      ORDER BY l.created_at ASC, bsl.id ASC
    `).all(batch.id, warehouseId) as Array<{ id: number; quantity_available: number; status_override: string | null; created_at: string }>;

    // R2 compares the take against the SELLABLE bins' availability only. A
    // BLOCKED/EXPIRED bin is not stock the sale can have drawn on, so its
    // availability must not mask a real mirror shortfall.
    const binAvailable = roundQty(locRows.reduce((s, l) => s + roundQty(l.quantity_available), 0));
    const consumeFromThis = roundQty(Math.min(remaining, sellableHere));

    db.prepare(`
      UPDATE stock_batches
      SET quantity_remaining = quantity_remaining - ?
      WHERE id = ?
    `).run(consumeFromThis, batch.id);

    let locRemaining = consumeFromThis;
    let hitDamaged = false;
    for (const loc of locRows) {
      if (locRemaining <= 0) break;
      const take = roundQty(Math.min(locRemaining, roundQty(loc.quantity_available)));
      if (take > 0 && loc.status_override === 'DAMAGED') hitDamaged = true;
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = MAX(0, quantity_physical - ?)
        WHERE id = ?
      `).run(take, loc.id);
      locRemaining -= take;
    }

    // R1: warn only when the take actually reached a DAMAGED bin, and once
    // per sale (deduped by the caller-visible text), not once per batch.
    if (hitDamaged) pushUniqueWarning(warnings, damagedWarning(db, itemId));

    // R2: the bin layer under-covered this batch. Warn with the available
    // quantity; the master batch still backs the unit, so this is mirror lag
    // (never a true shortage — that already threw above).
    if (binCount > 0 && qtyLessThan(binAvailable, consumeFromThis)) {
      pushUniqueWarning(
        warnings,
        `Item ${itemName(db, itemId)}: only ${binAvailable} unit(s) are available in the location ledger ` +
        `for this batch, but ${consumeFromThis} were sold — the remainder came from the batch total. ` +
        `Run the batch-location backfill to reconcile.`
      );
    }

    consumption.push({ batchId: batch.id, consumed: consumeFromThis, unitCost: batch.unit_cost });
    remaining -= consumeFromThis;
  }

  if (qtyPositive(remaining)) {
    const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
    throw new SellableStockUnavailableError(
      item?.item_name || `item ${itemId}`,
      roundedQty,
      roundQty(roundedQty - remaining)
    );
  }

  return consumption;
}

/**
 * The legacy (feature-flag-off) consumption path: select batches, consume
 * them, and fall back to standard cost when the item has no batch rows.
 */
function consumeLegacyStock(
  db: Database.Database,
  itemId: number,
  warehouseId: number,
  quantity: number,
  roundedQty: number,
  asOf: string,
  useFEFO: boolean,
  availableQty: number,
  itemRow: { has_expiry: number; standard_cost: number; item_name: string } | undefined,
  warnings: string[]
): ConsumptionEntry[] {
  const { batches, totalBatchTrackedQty } = selectLegacyBatches(
    db, itemId, warehouseId, asOf, useFEFO, availableQty
  );

  if (batches.length === 0) {
    if (useFEFO && totalBatchTrackedQty > 0) {
      throw new SellableStockUnavailableError(
        itemRow?.item_name || `item ${itemId}`,
        quantity,
        0
      );
    }

    // Same distinction as the feature-flagged path. If this item HAS
    // batches in this warehouse and all of them are exhausted, that is "no
    // sellable stock", not legacy unbatched stock. Falling through would
    // fabricate the quantity at standard cost out of a balance no batch
    // backs, creating stock that does not exist.
    if (!useFEFO) {
      const tracked = db.prepare(`
        SELECT COUNT(*) AS batches FROM stock_batches
        WHERE item_id = ? AND warehouse_id = ?
      `).get(itemId, warehouseId) as { batches: number };
      if (Number(tracked.batches) > 0) {
        throw new SellableStockUnavailableError(
          itemRow?.item_name || `item ${itemId}`,
          quantity,
          0
        );
      }
    }

    const fallbackCost = itemRow?.standard_cost ?? 0;
    logger.warn(
      `[BatchCosting] No batch rows for ${itemRow?.item_name || 'item'} in warehouse. ` +
      `Using standard_cost (${fallbackCost}) for the entire ${quantity} units (legacy stock).`
    );
    return [{ batchId: null, consumed: quantity, unitCost: fallbackCost }];
  }

  return consumeLegacyBatches(db, itemId, warehouseId, batches, roundedQty, warnings);
}

class StockMovementModel {
  /**
   * Next sequence number for batch numbers (shared with PhysicalCount via
   * the settings table key BATCH_ADJ_last_no).
   */
  static getNextBatchSequence(db: Database.Database): number {
    db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES ('BATCH_ADJ_last_no', '1', CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET
        value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
        updated_at = CURRENT_TIMESTAMP
    `).run();
    const row = db.prepare(`SELECT value FROM settings WHERE key = 'BATCH_ADJ_last_no'`).get() as { value: string };
    return parseInt(row.value, 10);
  }

  static recordMovement(data: RecordMovementDTO, userId: number | null, db: Database.Database): { id: number; movement_no: string } {
    const transaction = db.transaction(() => {
      const movementNo = this.generateMovementNo(db);
      const qty = roundQty(data.quantity);

      // H10 fix: incoming movements (quantity > 0) without an explicit batch_id
      // create a costed batch so every sellable unit has an identifiable cost
      // layer for FIFO consumption.  Source type maps to the movement type
      // (ADJUSTMENT → ADJUSTMENT, everything else → OPENING).
      const createIncomingCostLayer = (): number | null => {
        let resolvedBatchId = data.batch_id || null;
        if (qty > 0 && !resolvedBatchId && !data.skipBatchCreation) {
          const batchSeq = this.getNextBatchSequence(db);
          const sourceType = data.movement_type === 'ADJUSTMENT' ? 'ADJUSTMENT' : 'OPENING';
          const batchNo = `BATCH-${new Date().getFullYear() % 100}-${sourceType === 'ADJUSTMENT' ? 'ADJ' : 'OP'}-${batchSeq.toString().padStart(4, '0')}`;
          const unitCost = data.unit_cost || 0;
          const batchResult = db.prepare(`
            INSERT INTO stock_batches (
              batch_no, item_id, warehouse_id, source_type,
              source_id, quantity_original, quantity_remaining,
              unit_cost, received_date
            ) VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?)
          `).run(
            batchNo,
            data.item_id,
            data.warehouse_id,
            sourceType,
            qty,
            qty,
            unitCost,
            data.movement_date || new Date().toISOString().split('T')[0]
          );
          resolvedBatchId = batchResult.lastInsertRowid as number;
        }
        return resolvedBatchId;
      };
      const resolvedBatchId = createIncomingCostLayer();
      // BUG-013: keep batch_stock_by_location in step with stock_batches from
      // the moment a batch exists. This is the shared batch-creation path for
      // purchases, openings and adjustments. The flag must not gate this write:
      // if it did, a batch created while the flag was off would be invisible to
      // the sellable query the moment the flag was turned on.
      if (resolvedBatchId && qty > 0) {
        this.syncBatchStockByLocationForNewBatch(resolvedBatchId, data.warehouse_id, qty, db);
      }

      const movementStmt = db.prepare(`
        INSERT INTO stock_movements (
          movement_no, item_id, warehouse_id, movement_type,
          quantity, unit_cost, reference_doctype, reference_docno,
          remarks, movement_date, created_by, batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const result = movementStmt.run(
        movementNo,
        data.item_id,
        data.warehouse_id,
        data.movement_type,
        qty,
        data.unit_cost || null,
        data.reference_doctype || null,
        data.reference_docno || null,
        data.remarks || null,
        data.movement_date || new Date().toISOString().split('T')[0],
        userId ?? null, // nullable: system-initiated movements (boot task) have no actor
        resolvedBatchId
      );

      const existingBalance = db.prepare(`
        SELECT * FROM stock_balances
        WHERE item_id = ? AND warehouse_id = ?
      `).get(data.item_id, data.warehouse_id) as Record<string, unknown> | undefined;

      if (existingBalance) {
        db.prepare(`
          UPDATE stock_balances
          SET quantity = quantity + ?,
              last_updated = CURRENT_TIMESTAMP
          WHERE item_id = ? AND warehouse_id = ?
        `).run(qty, data.item_id, data.warehouse_id);
      } else {
        db.prepare(`
          INSERT INTO stock_balances (item_id, warehouse_id, quantity)
          VALUES (?, ?, ?)
        `).run(data.item_id, data.warehouse_id, qty);
      }

      // New path: keep extension columns in sync with batch_stock_by_location
      if (isFeatureEnabled(db, 'feature_batch_locations')) {
        this.syncStockBalancesExtension(data.item_id, data.warehouse_id, db);
      }

      this.refreshItemStockMirror(data.item_id, db);

      // Post financial entry for ADJUSTMENT movements
      const movementId = result.lastInsertRowid as number;
      if (data.movement_type === 'ADJUSTMENT' && !data.skipAdjustmentFinancialPosting) {
        this.postFinancialEntryForAdjustment({
          id: movementId,
          item_id: data.item_id,
          quantity: data.quantity,
          movement_date: data.movement_date || new Date().toISOString().split('T')[0],
          created_by: userId,
          batch_id: resolvedBatchId,
          caller_unit_cost: data.unit_cost
        }, db);
      }

      return {
        id: movementId,
        movement_no: movementNo
      };
    });

    return transaction();
  }

  static generateMovementNo(db: Database.Database): string {
    const year = new Date().getFullYear();
    const settingKey = `STK_last_no_${year}`;

    db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES (?, '1', CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET
        value = CAST(CAST(settings.value AS INTEGER) + 1 AS TEXT),
        updated_at = CURRENT_TIMESTAMP
    `).run(settingKey);

    const setting = db.prepare('SELECT value FROM settings WHERE key = ?').get(settingKey) as { value: string };
    const nextNo = parseInt(setting.value);

    return `STK-${year}-${nextNo.toString().padStart(4, '0')}`;
  }

  static getAll(filters: MovementFilters = {}, db: Database.Database): PaginatedMovements {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        sm.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name,
        u.full_name as created_by_name,
        sb.batch_no
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      LEFT JOIN users u ON sm.created_by = u.id
      LEFT JOIN stock_batches sb ON sm.batch_id = sb.id
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: SqlParam[] = [];

    if (filters.item_id) {
      conditions.push('sm.item_id = ?');
      params.push(filters.item_id);
    }

    if (filters.warehouse_id) {
      conditions.push('sm.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    if (filters.movement_type) {
      conditions.push('sm.movement_type = ?');
      params.push(filters.movement_type);
    }

    if (filters.date_from) {
      conditions.push('sm.movement_date >= ?');
      params.push(filters.date_from);
    }

    if (filters.date_to) {
      conditions.push('sm.movement_date <= ?');
      params.push(filters.date_to);
    }

    if (filters.search) {
      conditions.push(
        '(sm.movement_no LIKE ? OR i.item_name LIKE ? OR i.item_code LIKE ? OR COALESCE(sm.reference_docno, \'\') LIKE ? OR w.warehouse_name LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term, term, term);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: newest movement first).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'movement_date',
      filters.sortOrder || 'DESC',
      STOCK_MOVEMENT_SORT_COLUMNS,
      'movement_date',
      'DESC'
    );
    const sortColumn = SORT_COLUMN_MAP[column] || 'sm.movement_date';

    const offset = (pageNum - 1) * limitNum;
    const query =
      `${select}${where} ORDER BY ${sortColumn} ${order}, sm.id DESC LIMIT ? OFFSET ?`;

    const countQuery =
      `SELECT COUNT(*) as total FROM stock_movements sm
       JOIN items i ON sm.item_id = i.id
       JOIN warehouses w ON sm.warehouse_id = w.id
       WHERE 1=1${where}`;
    const countRow = db.prepare(countQuery).get(...params) as { total: number };

    const rows = db.prepare(query).all(...params, limitNum, offset) as StockMovement[];

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  static getById(id: number, db: Database.Database): StockMovement | undefined {
    return db.prepare(`
      SELECT
        sm.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_movements sm
      JOIN items i ON sm.item_id = i.id
      JOIN warehouses w ON sm.warehouse_id = w.id
      WHERE sm.id = ?
    `).get(id) as StockMovement | undefined;
  }

  static getItemLedger(itemId: number, warehouseId: number | null = null, db: Database.Database): StockMovement[] {
    let query = `
      SELECT
        sm.*,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_movements sm
      JOIN warehouses w ON sm.warehouse_id = w.id
      WHERE sm.item_id = ?
    `;
    const params: SqlParam[] = [itemId];

    if (warehouseId) {
      query += ' AND sm.warehouse_id = ?';
      params.push(warehouseId);
    }

    query += ' ORDER BY sm.movement_date DESC, sm.created_at DESC';

    return db.prepare(query).all(...params) as StockMovement[];
  }

  static getStockSummary(db: Database.Database) {
    return db.prepare(`
      SELECT
        i.id,
        i.item_code,
        i.item_name,
        i.category,
        i.unit_of_measure,
        i.current_stock,
        i.reorder_level,
        i.standard_cost,
        i.current_stock * i.standard_cost as stock_value,
        CASE
          WHEN i.current_stock <= i.reorder_level AND i.reorder_level > 0 THEN 1
          ELSE 0
        END as low_stock
      FROM items i
      WHERE i.is_active = 1
      ORDER BY i.item_name
    `).all();
  }

  static getBalance(itemId: number, warehouseId: number, db: Database.Database) {
    return db.prepare(`
      SELECT COALESCE(quantity, 0) as quantity
      FROM stock_balances
      WHERE item_id = ? AND warehouse_id = ?
    `).get(itemId, warehouseId);
  }

  static postFinancialEntryForAdjustment(params: {
    id: number;
    item_id: number;
    quantity: number;
    movement_date: string;
    // recordMovement accepts a null userId (system-originated movements),
    // and journal_entries.created_by is nullable, so this must be too.
    created_by: number | null;
    batch_id?: number | null;
    /** Cost the caller recorded on the movement — the cost at which the layer
     *  was relieved. Wins over anything re-derived below. */
    caller_unit_cost?: number;
  }, db: Database.Database): void {
    const { id, item_id, quantity, movement_date, created_by, batch_id } = params;

    let unitCost = params.caller_unit_cost || 0;
    if (!unitCost && batch_id) {
      const batch = db.prepare(`
        SELECT unit_cost FROM stock_batches WHERE id = ?
      `).get(batch_id) as { unit_cost: number } | undefined;
      unitCost = batch?.unit_cost || 0;
    }
    if (!unitCost) {
      const item = db.prepare(`
        SELECT standard_cost FROM items WHERE id = ?
      `).get(item_id) as { standard_cost: number } | undefined;
      unitCost = item?.standard_cost || 0;
    }

    const value = Math.abs(quantity) * unitCost;

    // RESOLVED (2026-10-04): the earlier "KNOWN QUESTION" here cited movement
    // 150 (quantity -2, unit_cost 300, financial_value 1000) as a possible
    // revaluation artifact. That reading was wrong, and the count that
    // suggested it was measured against the wrong baseline.
    //
    // Measured: `financial_value` and `journal_entry_id` are written ONLY by
    // this function, at this line. Every other movement type leaves both at
    // 0/NULL because its GL posting is emitted by the owning service
    // (purchase, sale) rather than through the adjustment leg. So the
    // population contract is: financial_value is populated for ADJUSTMENT
    // movements only.
    //
    // On `server/database/erp.db` (85 movements) 58 rows are 0-with-no-entry,
    // and 65 mismatch |qty| * unit_cost — dominated by PURCHASE and SALE rows
    // where the column was simply never written. The same shape appears on a
    // freshly migrated database, so it is structural, not a revaluation
    // artifact. (An earlier note said 59 anomalies; that figure compared
    // against items.standard_cost instead of unit_cost and should not be used.)
    //
    // Consequence: financial_value is NOT a movement's financial value. It is
    // an adjustment-leg audit field. Resolve its consumers before treating it
    // as authoritative. See docs/stock-authority-map.md.

    if (value === 0) return;

    const isRemoval = quantity < 0;

    const accounts = isRemoval
      ? { debit: 'inventory_shrinkage', credit: 'inventory_asset' }
      : { debit: 'inventory_asset', credit: 'inventory_correction' };

    const description = isRemoval
      ? `Stock removal: ${Math.abs(quantity)} units @ ${unitCost}`
      : `Stock addition: ${Math.abs(quantity)} units @ ${unitCost}`;

    const journalEntryId = AccountingService.postLegacyStockEntry(db, {
      referenceType: 'stock_adjustment',
      referenceId: id,
      entryDate: movement_date,
      description,
      debitTextCode: accounts.debit,
      creditTextCode: accounts.credit,
      amount: value,
      createdBy: created_by
    });

    db.prepare(`
      UPDATE stock_movements
      SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
      WHERE id = ?
    `).run(value, journalEntryId, id);
  }

  static voidJournalEntry(journalEntryId: number, db: Database.Database): void {
    db.prepare(`
      UPDATE journal_entries SET voided = TRUE WHERE id = ?
    `).run(journalEntryId);
  }

  /**
   * Post a financial entry for a PRODUCTION output movement.
   *
   * Context: prior to this fix, ProductionModel.recordProduction inserted
   * the output stock_movement row with financial_value=NULL and
   * financial_posted=FALSE. StockMovementModel.postFinancialEntryForAdjustment
   * only handles movement_type='ADJUSTMENT', so production output was
   * never linked to a journal entry. The result: the inventory asset
   * account on the GL was never updated when goods were produced, and
   * the balance sheet inventory figure drifted from the actual
   * stock-on-hand value.
   *
   * This posts a single-line journal entry:
   *   Debit:  inventory_asset
   *   Credit: production_clearing
   *   Amount: totalBatchCost (material + overhead), using the
   *           cost-per-unit already computed by the production flow.
   *
   * The clearing account is a temporary holding account that reflects
   * the net cost of goods produced in a period; a year-end / period-end
   * close can clear it to COGS. A multi-line split (Dr finished goods,
   * Cr raw materials, Cr overhead) requires a journal_lines table
   * upgrade and is out of scope for this fix.
   */
  static postFinancialEntryForProduction(params: {
    id: number;            // stock_movements.id of the output row
    item_id: number;
    quantity: number;
    total_batch_cost: number;  // already includes overhead
    movement_date: string;
    created_by: number;
  }, db: Database.Database): void {
    const { id, total_batch_cost, movement_date, created_by } = params;

    // Defensive: skip zero-value movements so we don't create noise
    // journal entries for $0 productions (e.g., pure rework).
    if (!total_batch_cost || total_batch_cost <= 0) {
      return;
    }

    const value = total_batch_cost;

    const journalEntryId = AccountingService.postLegacyStockEntry(db, {
      referenceType: 'production',
      referenceId: id,
      entryDate: movement_date,
      description: `Production output: ${params.quantity} units (total cost ${value.toFixed(2)})`,
      debitTextCode: 'inventory_asset',
      creditTextCode: 'production_clearing',
      amount: value,
      createdBy: created_by
    });

    db.prepare(`
      UPDATE stock_movements
      SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
      WHERE id = ?
    `).run(value, journalEntryId, id);
  }

  static getStockBalances(
    filters: StockBalanceFilters = {},
    db: Database.Database
  ): PaginatedStockBalances {
    const pageNum = filters.page || 1;
    const limitNum = filters.limit || 10;

    const select = `
      SELECT
        sb.*,
        i.item_code,
        i.item_name,
        i.unit_of_measure,
        w.warehouse_code,
        w.warehouse_name
      FROM stock_balances sb
      JOIN items i ON sb.item_id = i.id
      JOIN warehouses w ON sb.warehouse_id = w.id
      WHERE 1=1
    `;
    const conditions: string[] = [];
    const params: SqlParam[] = [];

    if (filters.search) {
      conditions.push(
        '(i.item_code LIKE ? OR i.item_name LIKE ? OR w.warehouse_name LIKE ?)'
      );
      const term = `%${filters.search}%`;
      params.push(term, term, term);
    }

    if (filters.warehouse_code) {
      conditions.push('w.warehouse_code = ?');
      params.push(filters.warehouse_code);
    }

    if (filters.warehouse_id !== undefined) {
      conditions.push('sb.warehouse_id = ?');
      params.push(filters.warehouse_id);
    }

    const where = conditions.length ? ` AND ${conditions.join(' AND ')}` : '';

    // Sort — whitelisted via sqlSanitizer, mapped to qualified columns
    // (default matches the pre-paging behavior: item code then warehouse).
    const { column, order } = sanitizeSortParams(
      filters.sortBy || 'item_code',
      filters.sortOrder || 'ASC',
      STOCK_BALANCE_SORT_COLUMNS,
      'item_code',
      'ASC'
    );
    const sortColumn = BALANCE_SORT_COLUMN_MAP[column] || 'i.item_code';

    const offset = (pageNum - 1) * limitNum;
    const query =
      `${select}${where} ORDER BY ${sortColumn} ${order}, sb.item_id, w.warehouse_code LIMIT ? OFFSET ?`;
    const countQuery =
      `SELECT COUNT(*) as total FROM stock_balances sb
       JOIN items i ON sb.item_id = i.id
       JOIN warehouses w ON sb.warehouse_id = w.id
       WHERE 1=1${where}`;

    const countRow = db.prepare(countQuery).get(...params) as { total: number };
    const rows = db.prepare(query).all(...params, limitNum, offset) as StockMovement[];

    return { rows, total: countRow.total, pageNum, limitNum };
  }

  /**
   * Consume a quantity of an item from the oldest available stock batches (FIFO).
   * Deducts quantity_remaining from each batch until the required quantity is met.
   * Returns an array of { batchId, consumed, unitCost } for recording movements.
   *
   * CRITICAL-5 fix: previously, when the total batch-tracked stock was less
   * than the requested quantity, the function silently fell back to the
   * item's standard_cost for the remainder, masking real shortages and
   * under-costing COGS. This made the pre-check in ProductionModel
   * recordProduction a lie under concurrent load, and could even let stock
   * go negative (the existing balance update would clamp at zero on the
   * next read but the batch update would still execute).
   *
   * New behavior:
   *  1. Reads the authoritative warehouse stock from stock_balances. If
   *     the available qty is strictly less than the requested qty, throws.
   *  2. If batches cover the request exactly, returns the FIFO breakdown.
   *  3. If the item has positive stock in the warehouse but no batch rows
   *     (legacy stock added before batch costing was enabled), falls back
   *     to standard_cost for the entire quantity, with a single
   *     warning-level log entry.
   *  4. If batches partially cover the request (some batches existed with
   *     qty but their sum is < requested), the function throws, because
   *     this case implies a partial migration or a stale batch, neither
   *     of which should be silently papered over.
   */
  /**
   * Refresh the denormalized items.current_stock mirror from the
   * authoritative stock_balances quantity.
   *
   * TASK 35: this SQL was duplicated across eight write sites. Any writer of
   * stock_balances.quantity that forgot its copy left the mirror stale, and
   * the mirror is what the reorder alerts and the GL reconciliation fallback
   * for batch-less items read. stockAuthority.test.ts pins the equality.
   */
  /**
   * Refresh the denormalized items.current_stock mirror from the
   * authoritative stock_balances quantity.
   *
   * TASK 35: this SQL was duplicated across eight write sites. Any writer of
   * stock_balances.quantity that forgot its copy left the mirror stale, and
   * the mirror is what the reorder alerts and the GL reconciliation fallback
   * for batch-less items read. stockAuthority.test.ts pins the equality.
   */
  static refreshItemStockMirror(itemId: number, db: Database.Database): void {
    db.prepare(`
      UPDATE items
      SET current_stock = (
        SELECT COALESCE(SUM(quantity), 0)
        FROM stock_balances
        WHERE item_id = ?
      )
      WHERE id = ?
    `).run(itemId, itemId);
  }

  /**
   * Move a batch's DEFAULT-bin mirror row by `delta`, creating it if absent.
   *
   * BUG-014: four paths wrote `batch_stock_by_location` INSIDE an
   * `isFeatureEnabled('feature_batch_locations')` branch while the matching
   * `stock_batches` write sat outside it. With the flag off the batch moved and
   * the mirror did not, so a later flag flip showed stock in a bin that held
   * nothing. The flag chooses which source is READ, never which is WRITTEN.
   *
   * Quantities clamp at zero: a reversal may restore less than the bin holds
   * when part of the batch was sold, and the table has a CHECK that the
   * physical quantity is not negative. Callers pass a signed delta.
   */
  static mirrorBatchLocationDelta(
    batchId: number,
    warehouseId: number,
    delta: number,
    db: Database.Database,
  ): void {
    const locRow = db.prepare(`
      SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1
    `).get(warehouseId) as { id: number } | undefined;
    if (!locRow) return;
    // Get-or-create first, so a batch that never had a row still gets one.
    db.prepare(`
      INSERT OR IGNORE INTO batch_stock_by_location
        (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
      VALUES (?, ?, 0, 0, 0)
    `).run(batchId, locRow.id);
    // MAX(0, ...) on both columns: the driver cannot express it in one UPDATE
    // without repeating the expression, and the CHECK forbids a negative.
    db.prepare(`
      UPDATE batch_stock_by_location
      SET quantity_physical  = MAX(0, quantity_physical + ?),
          quantity_available = MAX(0, quantity_available + ?),
          updated_at = CURRENT_TIMESTAMP
      WHERE batch_id = ? AND location_id = ?
    `).run(delta, delta, batchId, locRow.id);
  }

  static syncBatchStockByLocationForNewBatch(batchId: number, warehouseId: number, quantity: number, db: Database.Database): void {
    // Deliberately NOT gated on feature_batch_locations. The flag chooses which
    // source the sellable query READS; it must never decide whether the second
    // source is MAINTAINED. Gating this write is what made a flag flip lose
    // every existing batch (BUG-013): rows only appeared for batches bought
    // while the flag was already on. Writing one extra row keeps the two
    // sources in step at all times, so a flip is safe.
    const locRow = db.prepare(`
      SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1
    `).get(warehouseId) as { id: number } | undefined;
    if (!locRow) return;
    db.prepare(`
      INSERT OR IGNORE INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
      VALUES (?, ?, ?, 0, ?)
    `).run(batchId, locRow.id, quantity, quantity);
  }

  static syncStockBalancesExtension(itemId: number, warehouseId: number, db: Database.Database): void {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return;
    const sums = db.prepare(`
      SELECT COALESCE(SUM(bsl.quantity_physical), 0) as physical,
             COALESCE(SUM(bsl.quantity_reserved), 0) as reserved,
             COALESCE(SUM(bsl.quantity_available), 0) as available
      FROM batch_stock_by_location bsl
      JOIN locations l ON bsl.location_id = l.id
      WHERE l.warehouse_id = ?
        AND EXISTS (
          SELECT 1 FROM stock_batches sb
          WHERE sb.id = bsl.batch_id AND sb.item_id = ?
        )
    `).get(warehouseId, itemId) as { physical: number; reserved: number; available: number };

    db.prepare(`
      UPDATE stock_balances
      SET quantity_physical = ?, quantity_reserved = ?, quantity_available = ?, last_updated = CURRENT_TIMESTAMP
      WHERE item_id = ? AND warehouse_id = ?
    `).run(sums.physical, sums.reserved, sums.available, itemId, warehouseId);
  }

  /**
   * Core sellable-availability SQL fragment: one row per item+warehouse
   * with the quantity sellable (non-expired `expiry_date >= date('now')`
   * or NULL, non-halted, ACTIVE-location batches — the same rules
   * consumeFromOldestBatches enforces when allocating a sale — plus
   * legacy non-batch-tracked stock, floored at 0 per warehouse so
   * batch-tracked items never double-count). Computed read only.
   */
  private static sellableAvailabilityByWarehouseSql(db: Database.Database): string {
    const featureOn = isFeatureEnabled(db, 'feature_batch_locations');

    const batchSellable = featureOn
      ? `SELECT item_id, warehouse_id, SUM(sellable) AS sellable
         FROM (
           -- Batches mirrored to the location table: read the bins. This is the
           -- authoritative source for MIRRORED units, grouped by the BIN's
           -- warehouse — the bin, not the batch, says where stock sits.
           SELECT sb.item_id, l.warehouse_id, SUM(bsl.quantity_available) AS sellable
           FROM stock_batches sb
           JOIN batch_stock_by_location bsl ON sb.id = bsl.batch_id
           JOIN locations l ON bsl.location_id = l.id
           WHERE bsl.quantity_available > 0
             AND (sb.halted = 0 OR sb.halted IS NULL)
             AND ${sellableStatusClause('bsl.status_override')}
             AND (sb.expiry_date IS NULL OR sb.expiry_date >= date('now'))
           GROUP BY sb.item_id, l.warehouse_id
           UNION ALL
           -- BUG-013: units NOT mirrored in any bin are untracked, not gone.
           -- Coverage is PER UNIT, not per batch: a partly covered batch keeps
           -- the mirrored part in the branch above and the remainder here. A
           -- per-batch NOT EXISTS test would drop those remainder units.
           SELECT sb.item_id, sb.warehouse_id,
                  SUM(MAX(sb.quantity_remaining - COALESCE(cov.mirrored, 0), 0)) AS sellable
           FROM stock_batches sb
           LEFT JOIN (
             SELECT bsl.batch_id, SUM(bsl.quantity_available) AS mirrored
             FROM batch_stock_by_location bsl
             WHERE bsl.quantity_available > 0
             GROUP BY bsl.batch_id
           ) cov ON cov.batch_id = sb.id
           WHERE sb.quantity_remaining > 0
             AND (sb.halted = 0 OR sb.halted IS NULL)
             AND (sb.expiry_date IS NULL OR sb.expiry_date >= date('now'))
           GROUP BY sb.item_id, sb.warehouse_id
         )
         GROUP BY item_id, warehouse_id`
      : `SELECT sb.item_id, sb.warehouse_id, SUM(sb.quantity_remaining) AS sellable
         FROM stock_batches sb
         WHERE sb.quantity_remaining > 0
           AND (sb.halted = 0 OR sb.halted IS NULL)
           AND (sb.expiry_date IS NULL OR sb.expiry_date >= date('now'))
         GROUP BY sb.item_id, sb.warehouse_id`;

    return `
      SELECT bs.item_id, bs.warehouse_id, bs.sellable AS sellable_qty
      FROM (${batchSellable}) bs
      UNION ALL
      SELECT i.id AS item_id, sb_q.warehouse_id,
             MAX(COALESCE(sb_q.quantity, 0) - COALESCE(ba.total, 0), 0) AS sellable_qty
      FROM items i
      JOIN stock_balances sb_q ON sb_q.item_id = i.id
      LEFT JOIN (
        -- Deduct exactly the stock the batch branch above does NOT report, so
        -- the residual is only genuinely UNBATCHED stock.
        --
        -- Two traps, both hit in practice:
        -- Warehouse attribution: the branch counts mirrored units under the
        --    BIN's warehouse and unmirrored units under the BATCH's warehouse,
        --    so the unmirrored total must use sb.warehouse_id, not a single
        --    batch total grepped by one warehouse.
        --  * Excluded batches. An expired or halted batch is filtered out of
        --    the branch, so its units must STILL be deducted here. Otherwise
        --    balances minus deducted leaves them in the residual and an expired
        --    batch is sellable again. The deduction is therefore unfiltered.
        SELECT item_id, warehouse_id, SUM(mirrored) AS total
        FROM (
          -- Mirrored units belong to the bin's warehouse.
          SELECT sb.item_id, l.warehouse_id, SUM(bsl.quantity_available) AS mirrored
          FROM stock_batches sb
          JOIN batch_stock_by_location bsl ON sb.id = bsl.batch_id
          JOIN locations l ON bsl.location_id = l.id
          WHERE bsl.quantity_available > 0
          GROUP BY sb.item_id, l.warehouse_id
          UNION ALL
          -- Unmirrored units belong to the batch's own warehouse. This is
          -- quantity_remaining minus mirrored_in_this_batch, computed without
          -- the branch's eligibility filters so an expired or halted batch
          -- still reduces the residual instead of reappearing as sellable.
          SELECT sb.item_id, sb.warehouse_id,
                 SUM(MAX(sb.quantity_remaining - COALESCE(cov.mirrored, 0), 0)) AS mirrored
          FROM stock_batches sb
          LEFT JOIN (
            SELECT bsl.batch_id, SUM(bsl.quantity_available) AS mirrored
            FROM batch_stock_by_location bsl
            WHERE bsl.quantity_available > 0
            GROUP BY bsl.batch_id
          ) cov ON cov.batch_id = sb.id
          WHERE sb.quantity_remaining > 0
          GROUP BY sb.item_id, sb.warehouse_id
        )
        GROUP BY item_id, warehouse_id
      ) ba ON ba.item_id = i.id AND ba.warehouse_id = sb_q.warehouse_id
      GROUP BY i.id, sb_q.warehouse_id
      HAVING MAX(COALESCE(sb_q.quantity, 0) - COALESCE(ba.total, 0), 0) > 0
    `;
  }
  /**
   * Per-item sellable availability (summed across warehouses) as a SQL
   * subquery fragment usable in LEFT JOINs by the items list query.
   */
  static sellableAvailabilitySql(db: Database.Database): string {
    return `
      SELECT item_id, ROUND(SUM(sellable_qty), 3) AS sellable_qty
      FROM (${this.sellableAvailabilityByWarehouseSql(db)})
      GROUP BY item_id
    `;
  }

  /**
   * Sellable availability rows: per item+warehouse sellable quantity.
   * Computed read only — never mutates stock tables, so invariant E
   * (stock_balances.quantity == Σ stock_batches.quantity_remaining)
   * is untouched.
   */
  static getSellableAvailability(
    itemId: number | null,
    warehouseId: number | null,
    db: Database.Database
  ): Array<{ item_id: number; warehouse_id: number; sellable_qty: number }> {
    const conditions: string[] = [];
    const params: Array<number | string> = [];
    if (itemId !== null) {
      conditions.push('item_id = ?');
      params.push(itemId);
    }
    if (warehouseId !== null) {
      conditions.push('warehouse_id = ?');
      params.push(warehouseId);
    }
    const where = conditions.length > 0 ? ` WHERE ${conditions.join(' AND ')}` : '';
    const sql = `
      SELECT item_id, warehouse_id, ROUND(SUM(sellable_qty), 3) AS sellable_qty
      FROM (${this.sellableAvailabilityByWarehouseSql(db)})
      ${where}
      GROUP BY item_id, warehouse_id
      HAVING SUM(sellable_qty) > 0
      ORDER BY item_id, warehouse_id
    `;
    return db.prepare(sql).all(...params) as Array<{ item_id: number; warehouse_id: number; sellable_qty: number }>;
  }

  static consumeFromOldestBatches(
    itemId: number,
    warehouseId: number,
    quantity: number,
    db: Database.Database,
    asOfDate?: string,
    warnings?: string[]
  ): Array<{ batchId: number | null; consumed: number; unitCost: number }> {
    // Eligibility is judged as of the document date; absent one, today.
    const asOf = asOfDate ?? new Date().toISOString().slice(0, 10);
    const roundedQty = roundQty(quantity);
    if (roundedQty <= 0) {
      throw new Error(`consumeFromOldestBatches: quantity must be positive, got ${roundedQty}`);
    }

    const featureOn = isFeatureEnabled(db, 'feature_batch_locations');

    const availableQty = resolveAvailableQuantity(db, itemId, warehouseId, roundedQty, featureOn);

    if (qtyLessThan(availableQty, roundedQty)) {
      const item = db.prepare('SELECT item_name FROM items WHERE id = ?').get(itemId) as { item_name: string } | undefined;
      throw new SellableStockUnavailableError(
        item?.item_name || `item ${itemId}`,
        roundedQty,
        availableQty
      );
    }

    // Check if item has expiry tracking — determines FEFO vs FIFO
    const itemRow = db.prepare('SELECT has_expiry, standard_cost, item_name FROM items WHERE id = ?').get(itemId) as { has_expiry: number; standard_cost: number; item_name: string } | undefined;
    const useFEFO = itemRow?.has_expiry === 1;

    if (featureOn) {
      const batchRows = selectLocationBatches(db, itemId, warehouseId, asOf, useFEFO);

      // BUG-013: a batch with no location coverage is not gone, it is simply not
      // yet location-tracked (a flag flip, or a row written by a path that did
      // not refresh the location table). The flag chooses which source is READ;
      // it must never make stock disappear. Add such batches at their master
      // quantity. Done in JS so the location query and its FEFO rules are
      // untouched; consumeBatchesByLocation already decrements the master row
      // and only touches location rows that exist.
      const missing = db.prepare(`
        SELECT sb.id, sb.unit_cost, sb.received_date, sb.expiry_date,
               sb.quantity_remaining AS qty_avail
        FROM stock_batches sb
        WHERE sb.item_id = ? AND sb.warehouse_id = ?
          AND sb.quantity_remaining > 0
          AND NOT EXISTS (
            SELECT 1 FROM batch_stock_by_location bsl
            WHERE bsl.batch_id = sb.id AND bsl.quantity_available > 0
          )
          ${useFEFO ? "AND COALESCE(sb.halted, 0) = 0 AND (sb.expiry_date IS NULL OR sb.expiry_date >= @asOf)" : ''}
      `).all(itemId, warehouseId, { asOf }) as LocationBatchRow[];
      if (missing.length > 0) {
        logger.warn(
          `[BatchLocations] ${missing.length} batch(es) for item ${itemId} in warehouse ${warehouseId} ` +
          `carry stock but no location row; selling them from the batch total (BUG-013 guard). ` +
          `This means the location table is behind — run the backfill if it persists.`
        );
        batchRows.push(...missing);
        // Keep the documented order: dated expiry first (soonest first), then
        // undated, then FIFO by receipt date and id.
        batchRows.sort((a, b) => {
          const aDated = a.expiry_date ? 0 : 1;
          const bDated = b.expiry_date ? 0 : 1;
          if (aDated !== bDated) return aDated - bDated;
          if (a.expiry_date && b.expiry_date && a.expiry_date !== b.expiry_date) {
            return a.expiry_date < b.expiry_date ? -1 : 1;
          }
          if (a.received_date !== b.received_date) return a.received_date < b.received_date ? -1 : 1;
          return a.id - b.id;
        });
      }

      // Check if stock exists but all batches/locations are blocked/expired.
      if (batchRows.length === 0 && availableQty > 0) {
        assertNoBlockedStockOnly(db, itemId, warehouseId, quantity);
      }

      if (batchRows.length === 0) {
        // Batches exist but carry no batch_stock_by_location rows (the
        // batch-locations rollout is transitional — API purchases create
        // stock_batches without location rows). Consume them batch-level
        // with the legacy rules so the sale stays batch-linked at actual
        // cost: a standard-cost phantom sale here would consume no batch
        // and drift GL inventory away from batch values.
        const tracked = db.prepare(`
          SELECT COUNT(*) AS c FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
        `).get(itemId, warehouseId) as { c: number };
        if (Number(tracked.c) > 0) {
          return consumeLegacyStock(
            db, itemId, warehouseId, quantity, roundedQty, asOf, useFEFO, availableQty, itemRow,
            warnings ?? []
          );
        }

        // Legacy case: positive warehouse stock and no batch rows at all.
        const fallbackCost = itemRow?.standard_cost ?? 0;
        logger.warn(
          `[BatchCosting] No batch_stock_by_location rows for ${itemRow?.item_name || 'item'} in warehouse. ` +
          `Using standard_cost (${fallbackCost}) for the entire ${quantity} units (legacy stock).`
        );
        return [{ batchId: null, consumed: quantity, unitCost: fallbackCost }];
      }

      return consumeBatchesByLocation(db, itemId, warehouseId, batchRows, roundedQty, warnings ?? []);
    }

    // Legacy path (feature flag off): original behavior unchanged.
    return consumeLegacyStock(
      db, itemId, warehouseId, quantity, roundedQty, asOf, useFEFO, availableQty, itemRow,
      warnings ?? []
    );
  }

  /**
   * ACCT-006: sale consumption with the backdated-before-receipt fallback.
   *
   * The named D19 case is decided BEFORE any consumption (so a partially
   * consumed as-of layer can never poison the check): every remaining batch
   * in this warehouse was received after the sale date, current sellable
   * stock covers the quantity, and the later stock was already sellable
   * (expiry-wise) on the sale date. Those later batches are then consumed
   * at their actual recorded cost. The oversell guard (current sellable
   * stock) is never bypassed; D19 accepts the historical as-of position
   * going negative and asks callers to flag + warn instead. Everything else
   * (as-of stock present, expired-only stock, oversell) keeps the normal
   * allocator behavior, including its refusals.
   *
   * Returns whether the fallback fired, plus the first receipt date for the
   * caller's warning text.
   */
  static consumeForSale(
    itemId: number,
    warehouseId: number,
    quantity: number,
    db: Database.Database,
    saleDate: string
  ): { consumption: ConsumptionEntry[]; backdatedBeforeReceipt: boolean; firstReceiptDate: string | null; warnings: string[] } {
    const warnings: string[] = [];
    const fallback = this.preReceiptFallback(db, itemId, warehouseId, quantity, saleDate, warnings);
    if (fallback !== null) return { ...fallback, backdatedBeforeReceipt: true, warnings: fallback.warnings };
    return {
      consumption: this.consumeFromOldestBatches(itemId, warehouseId, quantity, db, saleDate, warnings),
      backdatedBeforeReceipt: false,
      firstReceiptDate: null,
      warnings,
    };
  }

  /**
   * The named ACCT-006 case, checked and consumed atomically (better-sqlite3
   * keeps this synchronous inside the caller's transaction). Returns null
   * whenever any precondition fails so the caller runs the normal as-of
   * allocator, whose refusals stay intact (expired-only stock, oversell,
   * as-of stock present, blocked locations).
   */
  private static preReceiptFallback(
    db: Database.Database,
    itemId: number,
    warehouseId: number,
    quantity: number,
    saleDate: string,
    warnings: string[] = []
  ): { consumption: ConsumptionEntry[]; firstReceiptDate: string | null; warnings: string[] } | null {
    const roundedQty = roundQty(quantity);
    const useFEFO = (db.prepare('SELECT has_expiry FROM items WHERE id = ?').get(itemId) as
      | { has_expiry: number }
      | undefined)?.has_expiry === 1;

    if (isFeatureEnabled(db, 'feature_batch_locations')) {
      const withLocations = selectLocationBatches(db, itemId, warehouseId, saleDate, useFEFO, {
        ignoreReceiptDate: true,
      });
      const hasLocationRows = db.prepare(`
        SELECT 1 FROM batch_stock_by_location bsl
        JOIN locations l ON bsl.location_id = l.id
        WHERE l.warehouse_id = ?
          AND EXISTS (SELECT 1 FROM stock_batches sb WHERE sb.id = bsl.batch_id AND sb.item_id = ?)
        LIMIT 1
      `).get(warehouseId, itemId);
      if (hasLocationRows) {
        // Location rows exist: sellability (ACTIVE status, expiry at the
        // sale date) is judged on them only. The fallback needs the as-of
        // position empty and the later receipts covering the quantity.
        if (withLocations.length === 0) return null;
        const covered = roundQty(withLocations.reduce((s, b) => s + Number(b.qty_avail), 0));
        if (qtyLessThan(covered, roundedQty)) return null;
        const asOfRows = selectLocationBatches(db, itemId, warehouseId, saleDate, useFEFO);
        if (asOfRows.length > 0) return null;
        const firstReceiptDate = (db.prepare(`
          SELECT MIN(received_date) AS d FROM stock_batches
          WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
        `).get(itemId, warehouseId) as { d: string | null }).d;
        return {
          consumption: consumeBatchesByLocation(db, itemId, warehouseId, withLocations, roundedQty, warnings),
          firstReceiptDate,
          warnings,
        };
      }
      // No location rows: fall through to the batch-level path (API-purchased
      // batches predate the location layer).
    }

    // Batch-level eligibility (both flags): the as-of position must be empty
    // and later receipts must cover the quantity.
    const expiryFilter = useFEFO ? 'AND (expiry_date IS NULL OR expiry_date >= @sale)' : '';
    const asOfQty = db.prepare(`
      SELECT COALESCE(SUM(quantity_remaining), 0) AS q FROM stock_batches
      WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
        AND received_date <= @sale
        AND (halted = 0 OR halted IS NULL)
        ${expiryFilter}
    `).get(itemId, warehouseId, { sale: saleDate }) as { q: number };
    if (Number(asOfQty.q) > 0) return null;

    const batches = db.prepare(`
      SELECT id, quantity_remaining, unit_cost, received_date
      FROM stock_batches
      WHERE item_id = ? AND warehouse_id = ? AND quantity_remaining > 0
        AND (halted = 0 OR halted IS NULL)
        ${expiryFilter}
      ORDER BY received_date ASC, id ASC
    `).all(itemId, warehouseId, { sale: saleDate }) as Array<LegacyBatchRow & { received_date: string }>;
    const covered = roundQty(batches.reduce((s, b) => s + Number(b.quantity_remaining), 0));
    if (batches.length === 0 || qtyLessThan(covered, roundedQty)) return null;

    const consumption: ConsumptionEntry[] = [];
    let remaining = roundedQty;
    for (const batch of batches) {
      if (remaining <= 0) break;
      const take = roundQty(Math.min(remaining, roundQty(Number(batch.quantity_remaining))));
      db.prepare(`
        UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?
      `).run(take, batch.id);
      // BUG-013: mirror the consume on the location rows (no-op when absent).
      // The bin is drained by AVAILABLE and only when sellable, so the
      // fallback cannot eat a blocked bin or a reservation. A DAMAGED bin the
      // take actually reached raises the same warning the main path raises.
      const batchWarnings = consumeFallbackBins(db, batch.id, warehouseId, take, itemId);
      for (const w of batchWarnings) pushUniqueWarning(warnings, w);
      consumption.push({ batchId: batch.id, consumed: take, unitCost: batch.unit_cost });
      remaining -= take;
    }
    return { consumption, firstReceiptDate: batches[0].received_date, warnings };
  }

    /**
   * INV-02: atomic two-warehouse transfer. Consumes FIFO layers at the
   * source warehouse and inserts a mirrored TRANSFER batch at the
   * destination inside ONE transaction. Both movements are written
   * server-side; the IN leg's reference_docno carries the OUT leg's
   * movement number so the pair stays linked.
   */
  static recordTransfer(
    data: { item_id: number; from_warehouse_id: number; to_warehouse_id: number; quantity: number; remarks?: string | null },
    userId: number,
    db: Database.Database
  ): { out: { id: number; movement_no: string }; in: { id: number; movement_no: string } } {
    if (data.from_warehouse_id === data.to_warehouse_id) {
      throw new Error('Source and destination warehouses must differ');
    }
    const qty = roundQty(parseFloat(String(data.quantity)));
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error(`Transfer quantity must be positive, got ${data.quantity}`);
    }

    const run = db.transaction(() => {
      // Availability is checked INSIDE the transaction by the consumer.
      const consumption = this.consumeFromOldestBatches(
        data.item_id,
        data.from_warehouse_id,
        qty,
        db
      );

      // OUT leg (negative), batch-linked to the primary consumed layer.
      const out = this.recordMovement({
        item_id: data.item_id,
        warehouse_id: data.from_warehouse_id,
        movement_type: 'TRANSFER',
        quantity: -qty,
        unit_cost: consumption.length > 0 ? consumption[0].unitCost : undefined,
        reference_doctype: 'TRANSFER',
        remarks: data.remarks || `Transfer to warehouse ${data.to_warehouse_id}`,
        batch_id: consumption.length > 0 && consumption[0].batchId !== null ? consumption[0].batchId : undefined
      }, userId, db);

      // Mirror cost layer at destination (TRANSFER-sourced).
      const totalConsumed = consumption.reduce((s, c) => s + c.consumed, 0);
      const avgCost = totalConsumed > 0
        ? consumption.reduce((s, c) => s + c.consumed * c.unitCost, 0) / totalConsumed
        : 0;

      const nextNo = getNextSequenceNumber(db, 'BATCH_TRF_last_no');
      const batchNo = `BATCH-${new Date().getFullYear() % 100}-TRF-${nextNo.toString().padStart(4, '0')}`;
      const today = new Date().toISOString().split('T')[0];
      const mirrorBatch = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date
        ) VALUES (?, ?, ?, 'TRANSFER', ?, ?, ?, ?, ?)
      `).run(batchNo, data.item_id, data.to_warehouse_id, out.id, qty, qty, avgCost, today);
      const mirrorBatchId = mirrorBatch.lastInsertRowid as number;

      recordBatchSources(db, mirrorBatchId, consumption);

      // New path: seed batch_stock_by_location for the mirrored batch at destination
      this.syncBatchStockByLocationForNewBatch(mirrorBatchId, data.to_warehouse_id, qty, db);

      // IN leg (positive), linked to the mirrored layer and back-referencing
      // the OUT movement number.
      const into = this.recordMovement({
        item_id: data.item_id,
        warehouse_id: data.to_warehouse_id,
        movement_type: 'TRANSFER',
        quantity: qty,
        unit_cost: avgCost,
        reference_doctype: 'TRANSFER',
        reference_docno: out.movement_no,
        remarks: data.remarks || `Transfer from warehouse ${data.from_warehouse_id}`,
        batch_id: mirrorBatchId
      }, userId, db);

      return { out, in: into };
    });

    return run();
  }

  /**
   * Expired-stock plan Phase 2: batch-targeted paired-leg transfer used by
   * BOTH the boot task (expiryDetection.ts) and the write-off endpoint's
   * auto-transfer path — one implementation, one code path.
   *
   * Moves a SPECIFIC batch (not FEFO consumption) from its current warehouse
   * to the destination system warehouse (EXPIRED), following the exact
   * mirror-batch pattern of recordTransfer:
   *
   *  1. Zero the batch's batch_stock_by_location rows (so the OUT leg's
   *     syncStockBalancesExtension recomputes to 0, never stale).
   *  2. OUT leg at the source warehouse (−qty, batch-linked).
   *  3. Zero stock_batches.quantity_remaining — the caller's responsibility
   *     per the plan's ownership rule (recordMovement never writes
   *     stock_batches); done here so every caller inherits it exactly once.
   *  4. Mint a mirrored batch at the destination (source_type 'TRANSFER'
   *     per plan 1.5 — semantics ride on movement_type 'EXPIRY_TRANSFER').
   *  5. IN leg at the destination (+qty, mirror-batch-linked,
   *     reference_docno = OUT movement_no).
   *
   * Idempotency: refuses a batch that already has an EXPIRY_TRANSFER
   * movement. All work is one transaction.
   *
   * userId may be null for system-initiated transfers (boot task): the
   * created_by column is nullable and the audit trail distinguishes system
   * rows via the 'source=SYSTEM' remark instead of a borrowed admin id.
   */
  static recordExpiryTransfer(
    data: { batchId: number; toWarehouseId: number; remarks?: string | null },
    userId: number | null,
    db: Database.Database
  ): { out: { id: number; movement_no: string }; in: { id: number; movement_no: string }; mirrorBatchId: number } {
    const today = new Date().toISOString().split('T')[0];

    const run = db.transaction(() => {
      const batch = db.prepare(`
        SELECT id, batch_no, item_id, warehouse_id, quantity_remaining,
               unit_cost, expiry_date
        FROM stock_batches WHERE id = ?
      `).get(data.batchId) as {
        id: number; batch_no: string; item_id: number; warehouse_id: number;
        quantity_remaining: number; unit_cost: number | null; expiry_date: string | null;
      } | undefined;

      if (!batch) throw new Error(`Batch ${data.batchId} not found`);
      const qty = roundQty(Number(batch.quantity_remaining));
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new Error(`Batch ${batch.batch_no} has no remaining quantity to transfer`);
      }
      if (batch.warehouse_id === data.toWarehouseId) {
        throw new Error(`Batch ${batch.batch_no} is already at the destination warehouse`);
      }

      // Idempotency: never re-transfer a batch that already moved.
      const already = db.prepare(`
        SELECT 1 FROM stock_movements
        WHERE batch_id = ? AND movement_type = 'EXPIRY_TRANSFER' LIMIT 1
      `).get(batch.id);
      if (already) {
        throw new Error(`Batch ${batch.batch_no} already has an EXPIRY_TRANSFER movement`);
      }

      const systemRemark = userId === null ? ' source=SYSTEM' : '';
      const remarks = (data.remarks || `Expiry transfer: batch ${batch.batch_no} expired on ${batch.expiry_date ?? 'unknown'}`) + systemRemark;

      // 1. Drain the source batch's location rows BEFORE the OUT leg so the
      //    extension-column resync inside recordMovement sees the truth. This
      //    is UNGATED: the batch-level OUT leg below is ungated, so the mirror
      //    must move with it regardless of the flag (BUG-013).
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = 0, quantity_available = 0, updated_at = CURRENT_TIMESTAMP
        WHERE batch_id = ?
      `).run(batch.id);
      // 2. OUT leg (negative) at the source warehouse.
      const out = this.recordMovement({
        item_id: batch.item_id,
        warehouse_id: batch.warehouse_id,
        movement_type: 'EXPIRY_TRANSFER',
        quantity: -qty,
        unit_cost: batch.unit_cost ?? undefined,
        reference_doctype: 'EXPIRY_TRANSFER',
        reference_docno: batch.batch_no,
        remarks,
        batch_id: batch.id
      }, userId, db);

      // 3. Zero the source batch (single zeroing point — see docstring).
      db.prepare(`
        UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?
      `).run(batch.id);

      // 4. Mint the mirrored batch at the destination (TRANSFER source_type
      //    per plan 1.5; avoids a BATCH_SOURCE_TYPES table rebuild).
      const nextNo = getNextSequenceNumber(db, 'BATCH_EXP_last_no');
      const mirrorBatchNo = `BATCH-${new Date().getFullYear() % 100}-EXP-${nextNo.toString().padStart(4, '0')}`;
      const mirrorBatch = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date, expiry_date
        ) VALUES (?, ?, ?, 'TRANSFER', ?, ?, ?, ?, ?, ?)
      `).run(
        mirrorBatchNo, batch.item_id, data.toWarehouseId, out.id,
        qty, qty, batch.unit_cost, today, batch.expiry_date
      );
      const mirrorBatchId = mirrorBatch.lastInsertRowid as number;

      // Seed the mirror batch's location layer before the IN leg resync.
      recordBatchSources(db, mirrorBatchId, [{ batchId: batch.id, consumed: qty }]);
      this.syncBatchStockByLocationForNewBatch(mirrorBatchId, data.toWarehouseId, qty, db);

      // 5. IN leg (positive) at the destination, back-referencing the OUT leg.
      const into = this.recordMovement({
        item_id: batch.item_id,
        warehouse_id: data.toWarehouseId,
        movement_type: 'EXPIRY_TRANSFER',
        quantity: qty,
        unit_cost: batch.unit_cost ?? undefined,
        reference_doctype: 'EXPIRY_TRANSFER',
        reference_docno: out.movement_no,
        remarks,
        batch_id: mirrorBatchId
      }, userId, db);

      return { out, in: into, mirrorBatchId };
    });

    return run();
  }

  /**
   * Damage transfer: move a batch to the DAMAGED system warehouse.
   * Same paired-leg pattern as recordExpiryTransfer, but with
   * movement_type = 'DAMAGE_TRANSFER' and no GL impact (physical
   * reclassification only). Used by POST /inventory/damaged/transfer.
   */
  static recordDamageTransfer(
    data: { batchId: number; toWarehouseId: number; remarks?: string | null },
    userId: number | null,
    db: Database.Database
  ): { out: { id: number; movement_no: string }; in: { id: number; movement_no: string }; mirrorBatchId: number } {
    const today = new Date().toISOString().split('T')[0];

    const run = db.transaction(() => {
      const batch = db.prepare(`
        SELECT id, batch_no, item_id, warehouse_id, quantity_remaining,
               unit_cost, expiry_date
        FROM stock_batches WHERE id = ?
      `).get(data.batchId) as {
        id: number; batch_no: string; item_id: number; warehouse_id: number;
        quantity_remaining: number; unit_cost: number | null; expiry_date: string | null;
      } | undefined;

      if (!batch) throw new Error(`Batch ${data.batchId} not found`);
      const qty = roundQty(Number(batch.quantity_remaining));
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new Error(`Batch ${batch.batch_no} has no remaining quantity to transfer`);
      }
      if (batch.warehouse_id === data.toWarehouseId) {
        throw new Error(`Batch ${batch.batch_no} is already at the destination warehouse`);
      }

      const already = db.prepare(`
        SELECT 1 FROM stock_movements
        WHERE batch_id = ? AND movement_type = 'DAMAGE_TRANSFER' LIMIT 1
      `).get(batch.id);
      if (already) {
        throw new Error(`Batch ${batch.batch_no} already has a DAMAGE_TRANSFER movement`);
      }

      const systemRemark = userId === null ? ' source=SYSTEM' : '';
      const remarks = (data.remarks || `Damage transfer: batch ${batch.batch_no}`) + systemRemark;

      // UNGATED for the same reason as the expiry transfer above (BUG-013).
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = 0, quantity_available = 0, updated_at = CURRENT_TIMESTAMP
        WHERE batch_id = ?
      `).run(batch.id);

      const out = this.recordMovement({
        item_id: batch.item_id,
        warehouse_id: batch.warehouse_id,
        movement_type: 'DAMAGE_TRANSFER',
        quantity: -qty,
        unit_cost: batch.unit_cost ?? undefined,
        reference_doctype: 'DAMAGE_TRANSFER',
        reference_docno: batch.batch_no,
        remarks,
        batch_id: batch.id
      }, userId, db);

      db.prepare(`
        UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?
      `).run(batch.id);

      const nextNo = getNextSequenceNumber(db, 'BATCH_DAM_last_no');
      const mirrorBatchNo = `BATCH-${new Date().getFullYear() % 100}-DAM-${nextNo.toString().padStart(4, '0')}`;
      const mirrorBatch = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type,
          source_id, quantity_original, quantity_remaining,
          unit_cost, received_date, expiry_date
        ) VALUES (?, ?, ?, 'TRANSFER', ?, ?, ?, ?, ?, ?)
      `).run(
        mirrorBatchNo, batch.item_id, data.toWarehouseId, out.id,
        qty, qty, batch.unit_cost, today, batch.expiry_date
      );
      const mirrorBatchId = mirrorBatch.lastInsertRowid as number;

      recordBatchSources(db, mirrorBatchId, [{ batchId: batch.id, consumed: qty }]);
      this.syncBatchStockByLocationForNewBatch(mirrorBatchId, data.toWarehouseId, qty, db);

      const into = this.recordMovement({
        item_id: batch.item_id,
        warehouse_id: data.toWarehouseId,
        movement_type: 'DAMAGE_TRANSFER',
        quantity: qty,
        unit_cost: batch.unit_cost ?? undefined,
        reference_doctype: 'DAMAGE_TRANSFER',
        reference_docno: out.movement_no,
        remarks,
        batch_id: mirrorBatchId
      }, userId, db);

      return { out, in: into, mirrorBatchId };
    });

    return run();
  }

  /**
   * Expired-stock plan Phase 3: write off an expired batch.
   *
   * Writes the batch's remaining quantity off to a loss account with the
   * GL entry Dr <loss> / Cr inventory_asset. Used by the
   * POST /inventory/expired/write-off endpoint.
   *
   * Flow (one transaction per batch; recordMovement/recordExpiryTransfer
   * nesting becomes savepoints):
   *  1. If the batch is NOT yet at the EXPIRED warehouse, perform the
   *     expiry transfer first (same code path as the boot task —
   *     recordExpiryTransfer). The WRITE_OFF then lands on the mirrored
   *     batch at the EXPIRED warehouse, keeping the ledger consistent.
   *  2. Record a single WRITE_OFF movement (negative qty, batch-linked)
   *     via recordMovement — balances sync automatically, and the
   *     movement doubles as the audit record. "WRITTEN_OFF" is derivable
   *     from this movement (plan 1.3) — no status column.
   *  3. Post Dr <loss account> / Cr Inventory Asset (1200) at the
   *     batch's actual unit_cost (not standard_cost) via
   *     postLegacyStockEntry, and stamp the movement's financial columns.
   *
   * Idempotency: refuses a batch that already has a WRITE_OFF movement.
   */
  static writeOffBatch(
    args: {
      batchId: number;
      /** Warehouse the written-off batch ends up in: EXPIRED or DAMAGED. */
      targetWarehouseId: number;
      /**
       * WO-002: 'expired' still requires a past expiry date; 'damaged'
       * accepts any batch, so stock with no expiry at all can be written
       * off after a damage transfer.
       */
      disposition: 'expired' | 'damaged';
      reason: string;
      lossAccountCode: string;
    },
    userId: number,
    db: Database.Database
  ): { movementNo: string; journalEntryId: number | null; transferred: boolean; qty: number; value: number } {
    const today = new Date().toISOString().split('T')[0];

    const run = db.transaction(() => {
      const batch = db.prepare(`
        SELECT id, batch_no, item_id, warehouse_id, quantity_remaining,
               unit_cost, expiry_date
        FROM stock_batches WHERE id = ?
      `).get(args.batchId) as {
        id: number; batch_no: string; item_id: number; warehouse_id: number;
        quantity_remaining: number; unit_cost: number | null; expiry_date: string | null;
      } | undefined;

      if (!batch) throw new Error(`Batch ${args.batchId} not found`);
      if (args.disposition === 'expired' && (!batch.expiry_date || batch.expiry_date >= today)) {
        throw new Error(`Batch ${batch.batch_no} is not expired (expiry ${batch.expiry_date ?? 'none'})`);
      }

      // 1. Auto-transfer to the disposition warehouse when the batch is
      //    still elsewhere (EXPIRY_TRANSFER for expired, DAMAGE_TRANSFER
      //    for damaged — each keeps its own movement-type audit trail).
      let targetBatchId = batch.id;
      let transferred = false;
      if (batch.warehouse_id !== args.targetWarehouseId) {
        const transfer = args.disposition === 'damaged'
          ? this.recordDamageTransfer(
              { batchId: batch.id, toWarehouseId: args.targetWarehouseId },
              userId,
              db
            )
          : this.recordExpiryTransfer(
              { batchId: batch.id, toWarehouseId: args.targetWarehouseId },
              userId,
              db
            );
        targetBatchId = transfer.mirrorBatchId;
        transferred = true;
      }

      // Idempotency: either the source or the mirrored batch already
      // carrying a WRITE_OFF movement blocks a re-write-off.
      const alreadyOff = db.prepare(`
        SELECT 1 FROM stock_movements
        WHERE movement_type = 'WRITE_OFF' AND batch_id IN (?, ?) LIMIT 1
      `).get(batch.id, targetBatchId);
      if (alreadyOff) {
        throw new Error(`Batch ${batch.batch_no} is already written off`);
      }

      const target = db.prepare(`
        SELECT quantity_remaining, unit_cost FROM stock_batches WHERE id = ?
      `).get(targetBatchId) as { quantity_remaining: number; unit_cost: number | null };
      const qty = roundQty(Number(target.quantity_remaining));
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new Error(`Batch ${batch.batch_no} has no remaining quantity to write off`);
      }
      // WO-001: money, not quantity, precision. Use the batch's exact unit cost
      // and round the VALUE to currency precision (2dp) - rounding the unit cost
      // to 3dp first overstated e.g. 1,000 x 1.23456 as 1,235.00 instead of 1,234.56.
      const unitCost = Number(target.unit_cost ?? 0);
      const value = roundCurrency(qty * unitCost);

      // 2. WRITE_OFF movement (negative qty at the EXPIRED warehouse).
      const remarks = `[WRITE_OFF] reason=${args.reason} gl=${args.lossAccountCode} batch=${batch.batch_no}`;
      const movement = this.recordMovement({
        item_id: batch.item_id,
        warehouse_id: args.targetWarehouseId,
        movement_type: 'WRITE_OFF',
        quantity: -qty,
        unit_cost: unitCost || undefined,
        reference_doctype: 'WRITE_OFF',
        reference_docno: batch.batch_no,
        remarks,
        batch_id: targetBatchId,
        movement_date: today
      }, userId, db);

      // Zero the written-off batch (the caller's responsibility per the
      // stock_batches ownership rule — recordMovement never writes it).
      db.prepare(`UPDATE stock_batches SET quantity_remaining = 0 WHERE id = ?`).run(targetBatchId);

      // BUG-013: the batch-level zeroing above is UNGATED, so the location
      // mirror must be zeroed unconditionally too. recordMovement only resyncs
      // the extension columns when the flag is on, so with the flag off this
      // batch would keep a location row claiming stock that no longer exists.
      db.prepare(`
        UPDATE batch_stock_by_location
        SET quantity_physical = 0, quantity_available = 0, updated_at = CURRENT_TIMESTAMP
        WHERE batch_id = ?
      `).run(targetBatchId);

      // 3. GL posting: Dr <loss> / Cr inventory_asset at batch cost.
      const postWriteOffLoss = (): number | null => {
        let journalEntryId: number | null = null;
        if (value > 0) {
          const lossAcct = db.prepare(
            `SELECT id, code, text_code FROM chart_of_accounts WHERE code = ?`
          ).get(args.lossAccountCode) as { id: number; code: string; text_code: string | null } | undefined;
          if (!lossAcct || !lossAcct.text_code) {
            throw new Error(`Loss account ${args.lossAccountCode} not found in chart of accounts`);
          }
          journalEntryId = AccountingService.postLegacyStockEntry(db, {
            referenceType: 'WRITE_OFF',
            referenceId: movement.id,
            entryDate: today,
            description: `Write-off: ${qty} unit(s) of batch ${batch.batch_no} — ${args.reason}`,
            debitTextCode: lossAcct.text_code,
            creditTextCode: 'inventory_asset',
            amount: value,
            createdBy: userId
          });
          db.prepare(`
            UPDATE stock_movements
            SET financial_value = ?, financial_posted = TRUE, journal_entry_id = ?
            WHERE id = ?
          `).run(value, journalEntryId, movement.id);
        }
        return journalEntryId;
      };
      const journalEntryId = postWriteOffLoss();

      return { movementNo: movement.movement_no, journalEntryId, transferred, qty, value };
    });

    return run();
  }

  /**
   * Reversal-rules Phase 4: void a stock transfer.
   *
   * A transfer moved quantity from A to B with no GL effect (inventory
   * stays inventory), so the reversal is stock-only: restore the source
   * batch quantity, reverse both legs with equal-and-opposite
   * ADJUSTMENT movements, and rebuild balances. The original movements
   * are never deleted — the reversal movements reference them by
   * movement_no for the audit trail.
   *
   * Guards (all server-side, inside the transaction):
   *  - transfer legs must exist and not already be voided (idempotency);
   *  - the mirrored TRANSFER batch at the destination must still hold
   *    enough quantity_remaining — if the transferred units were already
   *    sold/consumed from the destination, voiding would drive stock
   *    negative, so the void is refused.
   */
  static voidTransfer(
    data: { outMovementNo: string },
    userId: number,
    db: Database.Database
  ): { reversedOut: { id: number; movement_no: string }; reversedIn: { id: number; movement_no: string } } {
    const run = db.transaction(() => {
      const outLeg = db.prepare(`
        SELECT id, movement_no, item_id, warehouse_id, quantity, unit_cost, remarks
        FROM stock_movements
        WHERE movement_no = ? AND movement_type = 'TRANSFER' AND quantity < 0
      `).get(data.outMovementNo) as {
        id: number; movement_no: string; item_id: number; warehouse_id: number;
        quantity: number; unit_cost: number | null; remarks: string | null;
      } | undefined;

      if (!outLeg) {
        throw new Error(`Transfer ${data.outMovementNo} not found`);
      }

      // Idempotency: a prior void already appended a reversal pair.
      const alreadyVoided = db.prepare(`
        SELECT COUNT(*) AS c FROM stock_movements
        WHERE reference_doctype = 'TRANSFER_VOID' AND reference_docno = ?
      `).get(outLeg.movement_no) as { c: number };
      if (alreadyVoided.c > 0) {
        throw new Error(`Transfer ${outLeg.movement_no} is already voided`);
      }

      const inLeg = db.prepare(`
        SELECT id, movement_no, warehouse_id, quantity, batch_id
        FROM stock_movements
        WHERE reference_docno = ? AND movement_type = 'TRANSFER' AND quantity > 0
      `).get(outLeg.movement_no) as {
        id: number; movement_no: string; warehouse_id: number; quantity: number; batch_id: number | null;
      } | undefined;

      if (!inLeg) {
        throw new Error(`Transfer ${outLeg.movement_no} is missing its destination leg — cannot void`);
      }

      const qty = roundQty(Math.abs(outLeg.quantity));

      // The mirrored TRANSFER batch at the destination must still hold the
      // transferred quantity. If those units were consumed (sold/transferred
      // onward), restoring them would create negative stock.
      if (inLeg.batch_id !== null) {
        const mirrorBatch = db.prepare(`
          SELECT quantity_remaining FROM stock_batches WHERE id = ?
        `).get(inLeg.batch_id) as { quantity_remaining: number } | undefined;
        if (!mirrorBatch) {
          throw new Error(`Transfer ${outLeg.movement_no} mirrored batch is missing — cannot void`);
        }
        if (roundQty(Number(mirrorBatch.quantity_remaining)) < qty - qtyEpsilon()) {
          throw new Error(
            `Cannot void transfer ${outLeg.movement_no}: ${qty} unit(s) were already consumed from the destination ` +
            `(only ${roundQty(Number(mirrorBatch.quantity_remaining))} remaining in the transfer batch)`
          );
        }
      }

      // 1. Restore the source batch quantity consumed by the OUT leg.
      const outConsumptions = db.prepare(`
        SELECT id, quantity, batch_id FROM stock_movements
        WHERE movement_no = ? AND movement_type = 'TRANSFER' AND quantity < 0
      `).all(outLeg.movement_no) as Array<{
        id: number; quantity: number; batch_id: number | null;
      }>;
      const restoreTransferSourceBatches = (): number | null => {
        let restoredBatchId: number | null = null;
        for (const leg of outConsumptions) {
          if (leg.batch_id !== null) {
            db.prepare(`
              UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?
            `).run(Math.abs(leg.quantity), leg.batch_id);
            if (restoredBatchId === null) restoredBatchId = leg.batch_id;
            // BUG-013: the batch_stock_by_location row is written by the
            // UNGATED create path, so the void must maintain it ungated too.
            // The flag chooses which source is READ, never which is WRITTEN.
            {
              const srcLoc = db.prepare(`
                SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1
              `).get(outLeg.warehouse_id) as { id: number } | undefined;
              if (srcLoc) {
                db.prepare(`
                  INSERT INTO batch_stock_by_location (batch_id, location_id, quantity_physical, quantity_reserved, quantity_available)
                  VALUES (?, ?, ?, 0, ?)
                  ON CONFLICT(batch_id, location_id) DO UPDATE SET
                    quantity_physical = quantity_physical + excluded.quantity_physical,
                    quantity_available = quantity_available + excluded.quantity_available
                `).run(leg.batch_id, srcLoc.id, Math.abs(leg.quantity), Math.abs(leg.quantity));
              }
            }
          }
        }
        return restoredBatchId;
      };
      const restoredBatchId = restoreTransferSourceBatches();

      const removeTransferDestinationStock = (): void => {
        // 2. Draw down the mirrored TRANSFER batch at the destination.
        if (inLeg.batch_id !== null) {
          db.prepare(`
            UPDATE stock_batches SET quantity_remaining = quantity_remaining - ? WHERE id = ?
          `).run(qty, inLeg.batch_id);
          // BUG-013: mirror of the source-side restore above — unconditional.
          {
            const dstLoc = db.prepare(`
              SELECT id FROM locations WHERE warehouse_id = ? AND location_code = 'DEFAULT' LIMIT 1
            `).get(inLeg.warehouse_id) as { id: number } | undefined;
            if (dstLoc) {
              db.prepare(`
                UPDATE batch_stock_by_location
                SET quantity_physical = quantity_physical - ?, quantity_available = quantity_available - ?
                WHERE batch_id = ? AND location_id = ?
              `).run(qty, qty, inLeg.batch_id, dstLoc.id);
            }
          }
        }
      };
      removeTransferDestinationStock();

      // 3. Equal-and-opposite ADJUSTMENT legs (no GL: adjustments post their
      // own GL only when financial — these cancel existing layers, and the
      // net inventory value change is zero because both legs share cost).
      const reversedOut = this.recordMovement({
        item_id: outLeg.item_id,
        warehouse_id: outLeg.warehouse_id,
        movement_type: 'ADJUSTMENT',
        quantity: qty,
        unit_cost: outLeg.unit_cost ?? undefined,
        batch_id: restoredBatchId ?? undefined,
        reference_doctype: 'TRANSFER_VOID',
        reference_docno: outLeg.movement_no,
        remarks: `Transfer ${outLeg.movement_no} voided — stock returned to source`,
        movement_date: new Date().toISOString().split('T')[0],
      }, userId, db);

      const reversedIn = this.recordMovement({
        item_id: outLeg.item_id,
        warehouse_id: inLeg.warehouse_id,
        movement_type: 'ADJUSTMENT',
        quantity: -qty,
        unit_cost: outLeg.unit_cost ?? undefined,
        reference_doctype: 'TRANSFER_VOID',
        reference_docno: outLeg.movement_no,
        remarks: `Transfer ${outLeg.movement_no} voided — stock removed from destination`,
        movement_date: new Date().toISOString().split('T')[0],
      }, userId, db);

      return { reversedOut, reversedIn };
    });

    return run();
  }

/**
   * Record a batch-aware outgoing stock movement that consumes from oldest batches.
   * Creates one stock_movement per batch consumed, with batch_id and unit_cost.
   * For incoming movements (quantity >= 0), delegates to recordMovement.
   */
  static recordBatchMovement(
    data: RecordMovementDTO,
    userId: number,
    db: Database.Database
  ): Array<{ id: number; movement_no: string; quantity: number; unit_cost: number; batch_id: number | null }> {
    const absQty = Math.abs(data.quantity);

    if (data.quantity >= 0 || absQty === 0) {
      // Incoming or zero: just record normally
      const result = this.recordMovement(data, userId, db);
      return [{ ...result, quantity: data.quantity, unit_cost: data.unit_cost || 0, batch_id: null }];
    }

    // Outgoing: consume from oldest batches using FIFO
    const consumption = this.consumeFromOldestBatches(
      data.item_id,
      data.warehouse_id,
      absQty,
      db
    );

    const results: Array<{ id: number; movement_no: string; quantity: number; unit_cost: number; batch_id: number | null }> = [];

    for (const entry of consumption) {
      const result = this.recordMovement(
        {
          item_id: data.item_id,
          warehouse_id: data.warehouse_id,
          quantity: -entry.consumed,
          unit_cost: entry.unitCost,
          movement_type: data.movement_type,
          reference_doctype: data.reference_doctype,
          reference_docno: data.reference_docno,
          remarks: data.remarks
            ? `Batch: ${entry.batchId ?? 'Legacy'} - ${entry.consumed} @ ${entry.unitCost} | ${data.remarks}`
            : `Batch: ${entry.batchId ?? 'Legacy'} - ${entry.consumed} @ ${entry.unitCost}`,
          movement_date: data.movement_date,
          batch_id: entry.batchId ?? undefined,
        },
        userId,
        db
      );
      results.push({ ...result, quantity: -entry.consumed, unit_cost: entry.unitCost, batch_id: entry.batchId });
    }

    return results;
  }
}

export default StockMovementModel;
