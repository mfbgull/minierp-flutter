import { localMonthCode } from '../utils/documentNumbering';
import Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { assertCashTimeline } from '../services/cashBalanceGuard';
import { getNextSequenceNumber } from '../utils/sequence';
import StockMovementModel from './StockMovement';

export interface WithdrawalItemInput {
  item_id: number;
  warehouse_id: number;
  quantity: number;
}

export interface OwnerWithdrawalFilters {
  status?: string;
  kind?: string;
  from_date?: string;
  to_date?: string;
  search?: string;
  page?: number;
  limit?: number;
  sortBy?: string;
  sortOrder?: string;
}

export interface CreateOwnerWithdrawalDTO {
  withdrawal_no: string;
  withdrawal_date: string;
  kind: 'cash' | 'goods';
  /** Cash kind only — ignored/rejected for goods (server-calculated). */
  amount?: number;
  payment_method?: string;
  note?: string;
  items?: WithdrawalItemInput[];
  created_by: number;
}

export interface UpdateOwnerWithdrawalDTO {
  withdrawal_date?: string;
  amount?: number;
  payment_method?: string | null;
  note?: string | null;
  items?: WithdrawalItemInput[] | null;
}

interface ConsumptionEntry {
  item_id: number;
  warehouse_id: number;
  batchId: number | null;
  consumed: number;
  unitCost: number;
  /** Every bin this entry drained, oldest first. The void must reverse these. */
  bins?: Array<{ locationId: number; quantity: number }>;
}

interface OriginalMovementRow {
  id: number;
  movement_no: string;
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost: number | null;
  batch_id: number | null;
}

/**
 * One live consumption lot of the document: a batch (or the legacy NULL-batch
 * bucket), the units taken from it, and the bins they left (migration 133).
 * Mirrors invoice_item_bin_consumption's shape.
 */
interface ConsumptionLot {
  batch_id: number | null;
  item_id: number;
  warehouse_id: number;
  quantity: number;
  unit_cost: number | null;
  bins: Array<{ location_id: number; quantity: number }>;
  /** False for a lot that predates the per-lot draw (migration 134). */
  binsRecorded: boolean;
}

interface OwnerWithdrawalRow {
  id: number;
  withdrawal_no: string;
  withdrawal_date: string;
  kind: 'cash' | 'goods';
  amount: number;
  payment_method: string | null;
  note: string | null;
  status: string;
}

const round2 = (n: number): number => parseFloat(n.toFixed(2));

export function generateWithdrawalNo(db: Database.Database, withdrawalDate: string): string {
  const date = new Date(withdrawalDate);
  const monthCode = localMonthCode(date, 'YYMM');

  // Shared atomic counter allocated inside the caller's INSERT transaction
  // (EXP-05 pattern); UNIQUE(withdrawal_no) backstops it.
  const nextNo = getNextSequenceNumber(db, `WD_last_no_${monthCode}`);
  return `WD-${monthCode}-${String(nextNo).padStart(5, '0')}`;
}

/**
 * Server-side FIFO/FEFO costing for the given user-entered lines.
 * Delegates to the SAME consumer sales COGS uses (FEFO when the item
 * tracks expiry, else FIFO by receipt order); availability is validated
 * against stock_balances and batches are decremented as they are
 * consumed. MUST run inside the caller's write transaction so the
 * decrements persist or roll back atomically with everything else.
 */
function consumeForLines(
  db: Database.Database,
  lines: WithdrawalItemInput[]
): { consumption: ConsumptionEntry[]; totalCost: number } {
  const consumption: ConsumptionEntry[] = [];
  let totalCost = 0;
  for (const line of lines) {
    const entries = StockMovementModel.consumeFromOldestBatches(
      line.item_id, line.warehouse_id, line.quantity, db
    );
    for (const e of entries) {
      consumption.push({
        item_id: line.item_id,
        warehouse_id: line.warehouse_id,
        batchId: e.batchId,
        consumed: e.consumed,
        unitCost: e.unitCost,
        bins: e.bins,
      });
      totalCost += e.consumed * e.unitCost;
    }
  }
  return { consumption, totalCost: round2(totalCost) };
}

/**
 * The document's live consumption, read from its own ledger.
 *
 * It deliberately does NOT read the outbound `stock_movements` rows. A re-post
 * leaves the superseded -4 next to the live -5, and restoring from history
 * replayed both: the second edit pushed a batch of 10 past quantity_original
 * and the CHECK rejected it with a 500. The ledger is replaced on every re-post
 * (and cleared on void, like the bin draw), so it always describes what the
 * ACTIVE withdrawal consumed.
 *
 * The bin draw belongs to the lot that took it, not to the batch: two lines
 * drawing one batch are two lots with their own bins, and giving each lot the
 * batch's whole draw restored it once per line (batch 10, bin 17).
 */
function getLiveConsumption(db: Database.Database, withdrawalId: number): ConsumptionLot[] {
  const lots = db.prepare(`
    SELECT id, batch_id, item_id, warehouse_id, quantity, unit_cost
    FROM owner_withdrawal_consumption
    WHERE withdrawal_id = ?
    ORDER BY id ASC
  `).all(withdrawalId) as Array<Omit<ConsumptionLot, 'bins'> & { id: number }>;
  const binStmt = db.prepare(`
    SELECT location_id, quantity FROM owner_withdrawal_bin_consumption
    WHERE withdrawal_id = ? AND batch_id = ? AND consumption_id = ?
    ORDER BY id ASC
  `);
  const legacyBinStmt = db.prepare(`
    SELECT location_id, quantity FROM owner_withdrawal_bin_consumption
    WHERE withdrawal_id = ? AND batch_id = ? AND consumption_id IS NULL
    ORDER BY id ASC
  `);
  return lots.map(({ id, ...lot }) => {
    const own = binStmt.all(withdrawalId, lot.batch_id, id) as Array<{ location_id: number; quantity: number }>;
    const bins = own.length > 0
      ? own
      : legacyBinStmt.all(withdrawalId, lot.batch_id) as Array<{ location_id: number; quantity: number }>;
    return {
      ...lot,
      quantity: Number(lot.quantity),
      unit_cost: lot.unit_cost === null ? null : Number(lot.unit_cost),
      bins: bins.map((b) => ({ location_id: b.location_id, quantity: Number(b.quantity) })),
      binsRecorded: own.length > 0,
    };
  });
}

/**
 * History fallback for documents posted before the consumption ledger: one
 * restore lot per outbound movement row, with no recorded bins.
 *
 * KNOWN LIMITATION (pre-134 documents only). This fallback reads the outbound
 * `stock_movements` rows and NOTHING else, so it has two defects:
 *
 * 1. A document EDITED before 134 keeps its superseded outbound rows and has
 *    no recorded lot, so it reverses the SUMMED rows. Void then tries to add
 *    back more than the batch holds (4 superseded + 5 live = 9 into a batch of
 *    10 holding 5). INV-21 `quantity_remaining <= quantity_original` rejects
 *    it and the void returns 500. A further edit after the upgrade fails the
 *    same way, or over-restores where the batch has headroom.
 * 2. A document posted after 133 but before 134 has bin draw rows with a NULL
 *    consumption_id. This fallback produces lots with no bins, so it never
 *    reads those rows and restores to the warehouse DEFAULT bin instead of the
 *    named bin that lost the units. Totals stay right, so the void returns 200
 *    with stock in the wrong bin.
 *
 * Both are accepted, not repaired: migration 134 does not backfill (the active
 * lines are not recoverable) and there is no runtime repair. No production
 * deployment predates 134 and the dev database is disposable test data.
 * Documents created or edited under 134 always have a lot, so neither defect
 * applies to them. See audit/DECISIONS.md, "Owner-withdrawal pre-134".
 */
function getConsumptionFromHistory(db: Database.Database, withdrawalNo: string): ConsumptionLot[] {
  return (db.prepare(`
    SELECT id, movement_no, item_id, warehouse_id, quantity, unit_cost, batch_id
    FROM stock_movements
    WHERE reference_doctype = 'OWNER_WITHDRAWAL' AND reference_docno = ?
    ORDER BY id ASC
  `).all(withdrawalNo) as OriginalMovementRow[]).map((m) => ({
    batch_id: m.batch_id,
    item_id: m.item_id,
    warehouse_id: m.warehouse_id,
    quantity: Math.abs(Number(m.quantity)),
    unit_cost: m.unit_cost,
    bins: [],
    binsRecorded: false,
  }));
}

function replaceConsumption(
  db: Database.Database,
  withdrawalId: number,
  consumption: ConsumptionEntry[],
): void {
  // Child first: the draw row references its lot.
  db.prepare('DELETE FROM owner_withdrawal_bin_consumption WHERE withdrawal_id = ?').run(withdrawalId);
  db.prepare('DELETE FROM owner_withdrawal_consumption WHERE withdrawal_id = ?').run(withdrawalId);
  const insertLot = db.prepare(`
    INSERT INTO owner_withdrawal_consumption
      (withdrawal_id, batch_id, item_id, warehouse_id, quantity, unit_cost)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const insertDraw = db.prepare(`
    INSERT INTO owner_withdrawal_bin_consumption
      (withdrawal_id, consumption_id, batch_id, location_id, quantity)
    VALUES (?, ?, ?, ?, ?)
  `);
  for (const e of consumption) {
    const lotId = insertLot.run(
      withdrawalId, e.batchId, e.item_id, e.warehouse_id, e.consumed, e.unitCost,
    ).lastInsertRowid;
    if (e.batchId === null) continue;
    for (const bin of e.bins ?? []) {
      insertDraw.run(withdrawalId, lotId, e.batchId, bin.locationId, bin.quantity);
    }
  }
}

function nextAdjBatchNo(db: Database.Database): string {
  const now = new Date();
  const monthCode = localMonthCode(now);
  const nextNo = getNextSequenceNumber(db, `BATCH_ADJ_last_no_${monthCode}`);
  return `BATCH-${monthCode}-ADJ-${String(nextNo).padStart(5, '0')}`;
}

/**
 * Return consumed stock WITHOUT mutating history: every live consumption lot
 * gets an inbound compensating OWNER_WITHDRAWAL_REVERSAL row.
 * Batch-tracked units go back into the exact original batch (hard-block
 * if that batch row no longer exists — no silent adjustments). The only
 * exception is the legacy NULL-batch case (pre-batch-tracking stock
 * consumed at standard_cost), which is restored into a new ADJUSTMENT-
 * sourced batch at the ORIGINAL unit_cost so quantity and value are both
 * preserved faithfully.
 */
function restoreConsumption(
  db: Database.Database,
  withdrawalId: number,
  withdrawalNo: string,
  userId: number
): void {
  // Both absent = a document posted before migration 134. Its recorded state
  // has no lot, so nothing below can tell a live line from a superseded one
  // and no bin draw is read. See the two pre-134 limitations on
  // getConsumptionFromHistory below.
  const live = getLiveConsumption(db, withdrawalId);
  const lots = live.length > 0 ? live : getConsumptionFromHistory(db, withdrawalNo);

  // Draw rows written before migration 134 carry no lot id. Those batches keep
  // the earlier rule "replay the batch's draw exactly once", so a pre-134
  // document does not double-count a batch drawn by two lines. Note this set is
  // only reached for a 134 lot whose bin rows are missing; a document with no
  // lot at all goes through getConsumptionFromHistory and restores to DEFAULT.
  const legacyDrawnOnce = new Set<number>();

  for (const lot of lots) {
    const qty = lot.quantity;
    const cost = lot.unit_cost ?? 0;

    let batchId = lot.batch_id;
    if (batchId !== null) {
      const res = db.prepare(`
        UPDATE stock_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?
      `).run(qty, batchId);
      if (res.changes === 0) {
        throw new Error(
          `Cannot reverse withdrawal ${withdrawalNo}: source batch #${batchId} of withdrawal ` +
          `${withdrawalNo} no longer exists. Restore the batch or correct inventory manually first.`
        );
      }
      // The consume moved the batch total AND the batch's bin rows, so the
      // reversal must move both. Return each quantity to the bin that lost it;
      // only a lot with no recorded draw falls back to DEFAULT.
      if (lot.bins.length > 0) {
        for (const b of lot.bins) {
          StockMovementModel.mirrorBatchLocationDelta(
            batchId, lot.warehouse_id, b.quantity, db, b.location_id,
          );
        }
      } else if (!lot.binsRecorded && !legacyDrawnOnce.has(batchId)) {
        legacyDrawnOnce.add(batchId);
        StockMovementModel.mirrorBatchLocationDelta(batchId, lot.warehouse_id, qty, db);
      }
    } else {
      // Legacy NULL-batch consumption — recreate a cost-faithful batch.
      const inserted = db.prepare(`
        INSERT INTO stock_batches (
          batch_no, item_id, warehouse_id, source_type, source_id,
          quantity_original, quantity_remaining, unit_cost, received_date
        ) VALUES (?, ?, ?, 'ADJUSTMENT', ?, ?, ?, ?, date('now'))
      `).run(
        nextAdjBatchNo(db), lot.item_id, lot.warehouse_id, withdrawalNo,
        qty, qty, cost
      );
      batchId = inserted.lastInsertRowid as number;
      // BUG-013: the recreated batch needs its location row, or the flag-on
      // sellable query cannot see it. (A brand-new batch, so the seed helper is
      // the right call here — it also seeds the DEFAULT bin the movement below
      // would otherwise find missing.)
      StockMovementModel.syncBatchStockByLocationForNewBatch(batchId, lot.warehouse_id, qty, db);
    }

    // Positive (inbound) compensating movement; history untouched.
    StockMovementModel.recordMovement({
      item_id: lot.item_id,
      warehouse_id: lot.warehouse_id,
      movement_type: 'OWNER_WITHDRAWAL_REVERSAL',
      quantity: qty,
      unit_cost: cost,
      reference_doctype: 'OWNER_WITHDRAWAL_REVERSAL',
      reference_docno: withdrawalNo,
      remarks: `Reversal of withdrawal ${withdrawalNo}`,
      batch_id: batchId,
    }, userId, db);
  }
}

function insertItems(
  db: Database.Database,
  withdrawalId: number,
  items: WithdrawalItemInput[]
): void {
  const stmt = db.prepare(`
    INSERT INTO owner_withdrawal_items (withdrawal_id, item_id, warehouse_id, quantity)
    VALUES (?, ?, ?, ?)
  `);
  for (const line of items) stmt.run(withdrawalId, line.item_id, line.warehouse_id, line.quantity);
}

function create(db: Database.Database, data: CreateOwnerWithdrawalDTO): { id: number; amount: number } {
  return db.transaction(() => {
    if (data.kind === 'cash') {
      const createCashWithdrawal = (): { id: number; amount: number } => {
        const amount = Number(data.amount);
        if (!Number.isFinite(amount) || amount <= 0) {
          throw new Error('Cash withdrawal amount must be a positive number');
        }
        const result = db.prepare(`
          INSERT INTO owner_withdrawals (
            withdrawal_no, withdrawal_date, kind, amount, payment_method, note, status, created_by
          ) VALUES (?, ?, 'cash', ?, ?, ?, 'posted', ?)
        `).run(
          data.withdrawal_no, data.withdrawal_date, amount,
          data.payment_method || 'cash', data.note || null, data.created_by
        );
        const newId = result.lastInsertRowid as number;

        AccountingService.assertNoActivePosting(db, 'OWNER_WITHDRAWAL', newId);
        const cashCode = AccountingService._cashOrBankAccountCode(data.payment_method || 'cash');
        const cash = AccountingService.getAccountByCode(db, cashCode);
        if (!cash) throw new Error(`Chart of accounts is missing required account: ${cashCode}`);
        AccountingService.assertSufficientFunds(db, {
          accountId: cash.id,
          amount,
          asOfDate: data.withdrawal_date,
          label: `owner withdrawal ${data.withdrawal_no}`,
        });
        AccountingService.postOwnerWithdrawalCashEntry(db, {
          withdrawalId: newId,
          withdrawalNo: data.withdrawal_no,
          amount,
          withdrawalDate: data.withdrawal_date,
          paymentMethod: data.payment_method || 'cash',
          userId: data.created_by,
        });
        // ACCT-013: a backdated cash withdrawal can overdraw a LATER day even
        // when the balance at its own date and today both look fine. The
        // point-in-time check above only guards the entry date; the
        // chronological suffix check closes the gap. Run it AFTER the posting
        // (like the edit path) so the new outflow is part of the timeline; a
        // throw rolls the whole transaction back.
        assertCashTimeline(db, {
          paymentMethod: data.payment_method || 'cash',
          fromDate: data.withdrawal_date,
        });
        return { id: newId, amount };
      };
      return createCashWithdrawal();
    }

    // ---- goods kind -------------------------------------------------
    const items = data.items ?? [];
    if (items.length === 0) {
      throw new Error('A goods withdrawal requires at least one item line');
    }

    // Consume FIRST (validates availability + costs the withdrawal).
    // Runs inside this transaction, so decrements roll back on any failure.
    const { consumption, totalCost } = consumeForLines(db, items);
    if (totalCost <= 0) {
      throw new Error(
        'Goods withdrawal value computed as zero — item cost data (batches/standard_cost) is missing'
      );
    }

    const result = db.prepare(`
      INSERT INTO owner_withdrawals (
        withdrawal_no, withdrawal_date, kind, amount, note, status, created_by
      ) VALUES (?, ?, 'goods', ?, ?, 'posted', ?)
    `).run(data.withdrawal_no, data.withdrawal_date, totalCost, data.note || null, data.created_by);
    const newId = result.lastInsertRowid as number;

    insertItems(db, newId, items);

    // One movement row per consumed batch (invoice COGS pattern).
    for (const e of consumption) {
      StockMovementModel.recordMovement({
        item_id: e.item_id,
        warehouse_id: e.warehouse_id,
        movement_type: 'OWNER_WITHDRAWAL',
        quantity: -e.consumed,
        unit_cost: e.unitCost,
        reference_doctype: 'OWNER_WITHDRAWAL',
        reference_docno: data.withdrawal_no,
        remarks: `Owner withdrawal ${data.withdrawal_no}`,
        movement_date: data.withdrawal_date,
        batch_id: e.batchId ?? undefined,
      }, data.created_by, db);
    }

    // Record what this document actually consumed, per batch and per bin (the
    // bin draw is migration 133). The reversal reads this, not history, so a
    // re-posted document reverses only its ACTIVE lines.
    replaceConsumption(db, newId, consumption);

    AccountingService.assertNoActivePosting(db, 'OWNER_WITHDRAWAL', newId);
    AccountingService.postOwnerWithdrawalGoodsEntry(db, {
      withdrawalId: newId,
      withdrawalNo: data.withdrawal_no,
      totalCost,
      withdrawalDate: data.withdrawal_date,
      userId: data.created_by,
    });

    return { id: newId, amount: totalCost };
  })();
}

/**
 * Informational costing preview for the form. consumeFromOldestBatches
 * decrements batch quantities while computing, so this runs inside a
 * SAVEPOINT that is always rolled back — strictly read-only effect.
 */
function quote(
  db: Database.Database,
  lines: WithdrawalItemInput[]
): { lines: Array<{ item_id: number; warehouse_id: number; batches: Array<{ batchId: number | null; quantity: number; unitCost: number }>; total: number }>; totalCost: number } {
  db.exec('SAVEPOINT owner_wd_quote');
  try {
    const out: Array<{ item_id: number; warehouse_id: number; batches: Array<{ batchId: number | null; quantity: number; unitCost: number }>; total: number }> = [];
    let totalCost = 0;
    for (const line of lines) {
      const entries = StockMovementModel.consumeFromOldestBatches(
        line.item_id, line.warehouse_id, line.quantity, db
      );
      let lineTotal = 0;
      const batches = entries.map((e) => {
        lineTotal += e.consumed * e.unitCost;
        return { batchId: e.batchId, quantity: e.consumed, unitCost: e.unitCost };
      });
      out.push({ item_id: line.item_id, warehouse_id: line.warehouse_id, batches, total: round2(lineTotal) });
      totalCost += lineTotal;
    }
    return { lines: out, totalCost: round2(totalCost) };
  } finally {
    db.exec('ROLLBACK TO owner_wd_quote');
    db.exec('RELEASE owner_wd_quote');
  }
}

function getAll(db: Database.Database, filters: OwnerWithdrawalFilters = {}) {
  const pageNum = filters.page || 1;
  const limitNum = filters.limit || 10;
  const offset = (pageNum - 1) * limitNum;

  let query = `
    SELECT ow.id, ow.withdrawal_no, ow.withdrawal_date, ow.kind, ow.amount,
           ow.payment_method, ow.note, ow.status, ow.created_at,
           u.full_name as created_by_name,
           (SELECT COUNT(*) FROM owner_withdrawal_items i WHERE i.withdrawal_id = ow.id) AS item_line_count
    FROM owner_withdrawals ow LEFT JOIN users u ON ow.created_by = u.id WHERE 1=1
  `;
  const params: (string | number)[] = [];

  if (filters.status && filters.status !== 'all') {
    query += ' AND ow.status = ?';
    params.push(filters.status);
  } else if (!filters.status) {
    query += " AND ow.status = 'posted'";
  }
  if (filters.kind && filters.kind !== 'all') { query += ' AND ow.kind = ?'; params.push(filters.kind); }
  if (filters.from_date) { query += ' AND ow.withdrawal_date >= ?'; params.push(filters.from_date); }
  if (filters.to_date) { query += ' AND ow.withdrawal_date <= ?'; params.push(filters.to_date); }
  if (filters.search) {
    const term = `%${filters.search}%`;
    query += ' AND (ow.withdrawal_no LIKE ? OR ow.note LIKE ? OR ow.payment_method LIKE ?)';
    params.push(term, term, term);
  }

  query += ` ORDER BY ${filters.sortBy || 'ow.withdrawal_date'} ${filters.sortOrder || 'DESC'} LIMIT ? OFFSET ?`;
  params.push(limitNum, offset);

  return db.prepare(query).all(...params);
}

function getCount(db: Database.Database, filters: OwnerWithdrawalFilters = {}): number {
  let query = 'SELECT COUNT(*) as count FROM owner_withdrawals ow WHERE 1=1';
  const params: (string | number)[] = [];

  if (filters.status && filters.status !== 'all') {
    query += ' AND ow.status = ?';
    params.push(filters.status);
  } else if (!filters.status) {
    query += " AND ow.status = 'posted'";
  }
  if (filters.kind && filters.kind !== 'all') { query += ' AND ow.kind = ?'; params.push(filters.kind); }
  if (filters.from_date) { query += ' AND ow.withdrawal_date >= ?'; params.push(filters.from_date); }
  if (filters.to_date) { query += ' AND ow.withdrawal_date <= ?'; params.push(filters.to_date); }
  if (filters.search) {
    const term = `%${filters.search}%`;
    query += ' AND (ow.withdrawal_no LIKE ? OR ow.note LIKE ? OR ow.payment_method LIKE ?)';
    params.push(term, term, term);
  }

  return (db.prepare(query).get(...params) as { count: number }).count;
}

function getById(db: Database.Database, id: number): OwnerWithdrawalRow | undefined {
  return db.prepare(`
    SELECT ow.id, ow.withdrawal_no, ow.withdrawal_date, ow.kind, ow.amount,
           ow.payment_method, ow.note, ow.status, ow.created_at, ow.updated_at,
           u.full_name as created_by_name
    FROM owner_withdrawals ow LEFT JOIN users u ON ow.created_by = u.id WHERE ow.id = ?
  `).get(id) as OwnerWithdrawalRow | undefined;
}

function getItems(db: Database.Database, withdrawalId: number) {
  return db.prepare(`
    SELECT wi.id, wi.item_id, wi.warehouse_id, wi.quantity,
           i.item_name, i.item_code, w.warehouse_name
    FROM owner_withdrawal_items wi
    JOIN items i ON i.id = wi.item_id
    JOIN warehouses w ON w.id = wi.warehouse_id
    WHERE wi.withdrawal_id = ?
    ORDER BY wi.id ASC
  `).all(withdrawalId);
}

function getMovements(db: Database.Database, withdrawalNo: string) {
  return db.prepare(`
    SELECT sm.id, sm.movement_no, sm.movement_type, sm.quantity, sm.unit_cost,
           sm.batch_id, sm.remarks, sm.movement_date,
           i.item_name, i.item_code, w.warehouse_name,
           b.batch_no
    FROM stock_movements sm
    JOIN items i ON i.id = sm.item_id
    JOIN warehouses w ON w.id = sm.warehouse_id
    LEFT JOIN stock_batches b ON b.id = sm.batch_id
    WHERE sm.reference_doctype IN ('OWNER_WITHDRAWAL','OWNER_WITHDRAWAL_REVERSAL')
      AND sm.reference_docno = ?
    ORDER BY sm.id ASC
  `).all(withdrawalNo);
}

/**
 * Diff-based edit. Note-only changes touch metadata only. Anything else
 * (cash: date/amount/method; goods: lines/date) runs ONE atomic
 * transaction: restore stock via compensating movements → void old GL →
 * re-consume at current costs → post replacement GL.
 */
function update(
  db: Database.Database,
  id: number,
  data: UpdateOwnerWithdrawalDTO,
  opts: { userId: number }
): { amount: number } {
  const existing = getById(db, id);
  if (!existing) throw new Error('Owner withdrawal not found');
  if (existing.status === 'voided') throw new Error('A voided owner withdrawal cannot be edited');
  AccountingService.assertPeriodNotClosed(db, existing.withdrawal_date, `Owner withdrawal ${existing.withdrawal_no}`);

  if (existing.kind === 'cash') {
    const updateCashWithdrawal = (): { amount: number } => {
      const newDate = data.withdrawal_date ?? existing.withdrawal_date;
      const newAmount = data.amount !== undefined ? Number(data.amount) : existing.amount;
      const newMethod = data.payment_method !== undefined ? data.payment_method : existing.payment_method;
      const moneyChanged =
        String(newDate) !== String(existing.withdrawal_date) ||
        Number(newAmount) !== Number(existing.amount) ||
        String(newMethod ?? '') !== String(existing.payment_method ?? '');

      db.transaction(() => {
        if (moneyChanged) {
          if (!(newAmount > 0)) throw new Error('Cash withdrawal amount must be a positive number');

          AccountingService.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
            voidedBy: opts.userId ?? null,
            voidReason: 'Re-posted after edit',
          });

          db.prepare(`
            UPDATE owner_withdrawals SET withdrawal_date = ?, amount = ?, payment_method = ?,
              note = COALESCE(?, note), updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(newDate, newAmount, newMethod, data.note ?? null, id);

          AccountingService.postOwnerWithdrawalCashEntry(db, {
            withdrawalId: id,
            withdrawalNo: existing.withdrawal_no,
            amount: newAmount,
            withdrawalDate: newDate,
            paymentMethod: newMethod ?? undefined,
            userId: opts.userId,
          });
          // ACCT-013: chronological suffix check. Moving an outflow earlier can
          // overdraw a day between the new and old dates even when the balance
          // at the new date and today both look fine.
          assertCashTimeline(db, { paymentMethod: existing.payment_method, fromDate: existing.withdrawal_date });
          assertCashTimeline(db, { paymentMethod: newMethod ?? undefined, fromDate: newDate });
        } else {
          db.prepare(`
            UPDATE owner_withdrawals SET note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
          `).run(data.note !== undefined ? data.note : existing.note, id);
        }
      })();
      return { amount: moneyChanged ? Number(data.amount ?? existing.amount) : existing.amount };
    };
    return updateCashWithdrawal();
  }

  // ---- goods kind ---------------------------------------------------
  const itemsProvided = Array.isArray(data.items);
  const dateChanged =
    data.withdrawal_date !== undefined &&
    String(data.withdrawal_date) !== String(existing.withdrawal_date);
  const stockAffecting = itemsProvided || dateChanged;

  if (!stockAffecting) {
    db.prepare(`
      UPDATE owner_withdrawals SET note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
    `).run(data.note !== undefined ? data.note : existing.note, id);
    return { amount: existing.amount };
  }

  return db.transaction(() => {
    const newDate = data.withdrawal_date ?? existing.withdrawal_date;
    const newLines: WithdrawalItemInput[] = itemsProvided
      ? (data.items as WithdrawalItemInput[])
      : (getItems(db, id) as Array<{ item_id: number; warehouse_id: number; quantity: number }>).map(
          (r) => ({ item_id: r.item_id, warehouse_id: r.warehouse_id, quantity: r.quantity })
        );
    if (newLines.length === 0) {
      throw new Error('A goods withdrawal requires at least one item line');
    }

    // Restore the ACTIVE consumption (compensating movements only), then void
    // the old GL posting.
    restoreConsumption(db, id, existing.withdrawal_no, opts.userId);
    AccountingService.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
      voidedBy: opts.userId ?? null,
      voidReason: 'Re-posted after edit',
    });

    // Fresh consumption at current FEFO/FIFO state.
    const { consumption, totalCost } = consumeForLines(db, newLines);
    if (totalCost <= 0) {
      throw new Error('Goods withdrawal value computed as zero — item cost data (batches/standard_cost) is missing');
    }

    db.prepare('DELETE FROM owner_withdrawal_items WHERE withdrawal_id = ?').run(id);
    insertItems(db, id, newLines);

    for (const e of consumption) {
      StockMovementModel.recordMovement({
        item_id: e.item_id,
        warehouse_id: e.warehouse_id,
        movement_type: 'OWNER_WITHDRAWAL',
        quantity: -e.consumed,
        unit_cost: e.unitCost,
        reference_doctype: 'OWNER_WITHDRAWAL',
        reference_docno: existing.withdrawal_no,
        remarks: `Owner withdrawal ${existing.withdrawal_no} (re-posted)`,
        movement_date: newDate,
        batch_id: e.batchId ?? undefined,
      }, opts.userId, db);
    }

    // The re-posted withdrawal consumed different batches/bins: replace the old
    // lot and draw rows, so the next edit or void reverses the CURRENT
    // consumption, not the pre-edit one.
    replaceConsumption(db, id, consumption);

    db.prepare(`
      UPDATE owner_withdrawals SET withdrawal_date = ?, amount = ?,
        note = COALESCE(?, note), updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(newDate, totalCost, data.note ?? null, id);

    AccountingService.postOwnerWithdrawalGoodsEntry(db, {
      withdrawalId: id,
      withdrawalNo: existing.withdrawal_no,
      totalCost,
      withdrawalDate: newDate,
      userId: opts.userId,
    });

    return { amount: totalCost };
  })();
}

/**
 * Soft delete: goods stock returns via compensating movements, GL lines
 * are voided (kept with attribution), row marked voided. One transaction.
 */
function softVoid(
  db: Database.Database,
  id: number,
  opts: { userId: number; reason?: string }
): void {
  const existing = getById(db, id);
  if (!existing) throw new Error('Owner withdrawal not found');
  if (existing.status === 'voided') throw new Error('Owner withdrawal is already voided');
  AccountingService.assertPeriodNotClosed(db, existing.withdrawal_date, `Owner withdrawal ${existing.withdrawal_no}`);

  db.transaction(() => {
    if (existing.kind === 'goods') {
      restoreConsumption(db, id, existing.withdrawal_no, opts.userId);
      // The ledger is consumed by the reversal above; keep it describing live
      // withdrawals only, so a second reversal cannot restore twice.
      db.prepare('DELETE FROM owner_withdrawal_bin_consumption WHERE withdrawal_id = ?').run(id);
      db.prepare('DELETE FROM owner_withdrawal_consumption WHERE withdrawal_id = ?').run(id);
    }
    AccountingService.voidJournalLinesByReference(db, 'OWNER_WITHDRAWAL', id, {
      voidedBy: opts.userId ?? null,
      voidReason: opts.reason || 'Owner withdrawal voided',
    });
    db.prepare(`
      UPDATE owner_withdrawals SET status = 'voided', voided_at = CURRENT_TIMESTAMP,
        voided_by = ?, void_reason = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(opts.userId ?? null, opts.reason || 'Owner withdrawal voided', id);
  })();
}

export default {
  generateWithdrawalNo,
  create,
  quote,
  getAll,
  getCount,
  getById,
  getItems,
  getMovements,
  update,
  softVoid,
};
