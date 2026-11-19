import Database from 'better-sqlite3';
import logger from '../utils/logger';
import { isFeatureEnabled } from '../utils/featureFlags';
import { BusinessRuleError } from '../utils/businessRuleError';
import { roundQty, qtyEpsilon } from '../utils/quantity';
import StockMovementModel from './StockMovement';

export interface StockReservation {
  id: number;
  item_id: number;
  warehouse_id: number;
  location_id?: number;
  batch_id?: number;
  quantity_reserved: number;
  reference_doctype: string;
  reference_docno: string;
  reference_line_id?: number;
  status: string;
  created_at: string;
  released_at?: string;
  consumed_at?: string;
}

export interface StockReservationBin {
  id?: number;
  batch_id: number;
  location_id: number;
  quantity_reserved: number;
  /** Durable original allocation (migration 130); survives a partial sale. */
  quantity_allocated?: number;
}

type ReservationInput = Omit<StockReservation, 'id' | 'status' | 'created_at' | 'released_at' | 'consumed_at'> & {
  bins?: Array<{ batch_id: number; location_id: number; quantity: number }>;
  /** Stored child-bin signature of an existing reservation, for duplicate checks. */
  storedBinSignature?: string;
};

function assertMatchingReservation(existing: StockReservation, data: ReservationInput, qty: number): void {
  const sameStock = existing.item_id === data.item_id && existing.warehouse_id === data.warehouse_id &&
    (existing.location_id ?? null) === (data.location_id ?? null) && (existing.batch_id ?? null) === (data.batch_id ?? null);
  // Decision B: for a bins[] request the parent columns are null, so compare
  // the requested allocation to the stored child rows instead.
  const requestedBins = (data.bins ?? [])
    .map((b) => `${b.batch_id}:${b.location_id}:${roundQty(b.quantity)}`).sort().join('|');
  // A RELEASED row has no child rows left (release drops them), so there is no
  // stored signature to compare. Its allocations were returned in full, so
  // nothing is being reused: re-creating with an explicit bins[] is a genuine
  // reactivation, and the guard below only has to protect LIVE reservations.
  const released = existing.status === 'RELEASED';
  const sameBins = requestedBins.length === 0 || released || requestedBins === data.storedBinSignature;
  const sameQuantity = existing.status !== 'ACTIVE' || Number(existing.quantity_reserved) === qty;
  if (!sameStock || !sameBins || !sameQuantity) throw new BusinessRuleError(409, 'Reservation reference already has different stock or quantity');
}

export class StockReservationModel {
  static create(data: {
    item_id: number;
    warehouse_id: number;
    location_id?: number;
    batch_id?: number;
    quantity_reserved: number;
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
    /** Decision B: allocate across several bins; sum must equal quantity_reserved. */
    bins?: Array<{ batch_id: number; location_id: number; quantity: number }>;
  }, db: Database.Database): StockReservation {
    return db.transaction(() => {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) {
      throw new Error('Stock reservations require feature_batch_locations flag');
    }

    const qty = parseFloat(String(data.quantity_reserved));
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error(`Reservation quantity must be positive, got ${data.quantity_reserved}`);
    }

    // Decision B: normalize to a bin allocation list. No bins[] means the
    // classic single-bin shape from location_id/batch_id.
    const bins = this.normalizeCreateBins(data, qty);
    if (bins.length > 0) {
      const sum = roundQty(bins.reduce((s, b) => s + b.quantity_reserved, 0));
      if (sum !== qty) {
        throw new BusinessRuleError(409, `Reservation bins total ${sum} does not match quantity_reserved ${qty}`);
      }
    }
    const multiBin = bins.length > 1;

    // Idempotency: check if already reserved for this reference line
    const existing = db.prepare(`
      SELECT * FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id IS ?
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as StockReservation | undefined;

    if (existing) return this.createAgainstExisting(db, existing, data, bins, qty);

    const result = db.prepare(`
      INSERT INTO stock_reservations (
        item_id, warehouse_id, location_id, batch_id,
        quantity_reserved, reference_doctype, reference_docno, reference_line_id,
        status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE')
    `).run(
      data.item_id,
      data.warehouse_id,
      // Decision B: a multi-bin reservation keeps ONE logical row with a NULL
      // parent bin; the child rows in stock_reservation_bins hold the split.
      multiBin ? null : (data.location_id ?? null),
      multiBin ? null : (data.batch_id ?? null),
      qty,
      data.reference_doctype,
      data.reference_docno,
      data.reference_line_id ?? null
    );

    const id = result.lastInsertRowid as number;
    const created = this.getById(id, db)!;
    this.reserveBins(db, created, bins, 1);
    return this.getById(id, db)!;
    })();
  }

  /**
   * Bins named by the caller, else the classic single parent bin, else none.
   * Two entries for the same bin are refused: the child rows would be
   * indistinguishable, so apply/restore could not tell which one to touch.
   */
  private static normalizeCreateBins(data: { location_id?: number; batch_id?: number; bins?: Array<{ batch_id: number; location_id: number; quantity: number }> }, qty: number): StockReservationBin[] {
    if (data.bins && data.bins.length > 0) {
      const seen = new Set<string>();
      for (const b of data.bins) {
        const key = `${b.batch_id}:${b.location_id}`;
        if (seen.has(key)) throw new BusinessRuleError(409, 'Reservation bins contain a duplicate batch and location');
        seen.add(key);
      }
      return data.bins.map((b) => ({ batch_id: b.batch_id, location_id: b.location_id, quantity_reserved: roundQty(b.quantity) }));
    }
    if (data.location_id && data.batch_id) {
      return [{ batch_id: data.batch_id, location_id: data.location_id, quantity_reserved: qty }];
    }
    return [];
  }

  /** Reuse an existing row for this reference line: same data, reactivate or refuse. */
  private static createAgainstExisting(
    db: Database.Database,
    existing: StockReservation,
    data: ReservationInput,
    bins: StockReservationBin[],
    qty: number,
  ): StockReservation {
    assertMatchingReservation(existing, { ...data, storedBinSignature: this.getBinSignature(existing.id, db) }, qty);
    if (existing.status === 'ACTIVE') {
      logger.warn(`[Reservation] Duplicate reservation for ${data.reference_doctype}:${data.reference_docno}:${data.reference_line_id}`);
      return existing;
    }
    if (existing.status !== 'RELEASED') throw new BusinessRuleError(409, 'Consumed reservation cannot be reactivated');
    // A released MULTI-BIN row (parent bin columns NULL) had its child rows
    // dropped, so nothing names a bin to restore. Flipping it ACTIVE would owe
    // a quantity no bin backs. The legacy single-bin and batch-only shapes keep
    // their parent columns, so reactivating the row alone stays sufficient.
    const multiBin = existing.batch_id == null && existing.location_id == null;
    if (multiBin && bins.length === 0) {
      throw new BusinessRuleError(409, 'Cannot reactivate a released multi-bin reservation without an explicit allocation (bins[])');
    }

    this.reserveBins(db, existing, bins, 1);
    db.prepare(`
      UPDATE stock_reservations
      SET status = 'ACTIVE', released_at = NULL, quantity_reserved = ?
      WHERE id = ?
    `).run(qty, existing.id);
    return { ...existing, quantity_reserved: qty, status: 'ACTIVE', released_at: undefined } as StockReservation;
  }

  /** Child-bin rows for a reservation, oldest first. */
  /**
   * Live allocations: rows a sale may still drain. A row drained to zero by a
   * partial sale is kept in the table as void history but is not an allocation.
   */
  static getBins(reservationId: number, db: Database.Database): StockReservationBin[] {
    return this.getAllBinRows(reservationId, db).filter((b) => Number(b.quantity_reserved) > 0);
  }

  /** Every stored row, including the zeroed rows a partial sale keeps as history. */
  private static getAllBinRows(reservationId: number, db: Database.Database): StockReservationBin[] {
    return db.prepare(`
      SELECT id, batch_id, location_id, quantity_reserved, quantity_allocated FROM stock_reservation_bins
      WHERE reservation_id = ? ORDER BY id ASC
    `).all(reservationId) as StockReservationBin[];
  }

  /** Stable signature of a reservation's stored bins, for duplicate checks. */
  private static getBinSignature(reservationId: number, db: Database.Database): string {
    return this.getBins(reservationId, db)
      .map((b) => `${b.batch_id}:${b.location_id}:${roundQty(b.quantity_reserved)}`).sort().join('|');
  }

  /**
   * Decision B: apply `sign` (+1 reserve / -1 release) to every bin of the
   * reservation. Each guarded UPDATE refuses if the bin is unknown to this
   * item/warehouse or would go out of range; the caller's txn rolls back.
   * Batch-only reservations have no bins and keep their metadata workflow.
   */
  private static reserveBins(db: Database.Database, row: Pick<StockReservation, 'id' | 'item_id' | 'warehouse_id' | 'batch_id' | 'location_id' | 'quantity_reserved'>, bins: StockReservationBin[], sign: 1 | -1, persist = true): void {
    const stored = this.resolveBins(db, row, bins);
    if (stored.length === 0) return;
    for (const bin of stored) {
      const delta = sign * bin.quantity_reserved;
      // Float tolerance: a 0.3 reserve sold as three 0.1s leaves ~1e-17
      // residue, so an exact `>= 0` check refuses the final legal release.
      const eps = qtyEpsilon();
      const changed = db.prepare(`UPDATE batch_stock_by_location SET quantity_reserved=quantity_reserved+?
        WHERE batch_id=? AND location_id=? AND quantity_reserved+? >= -?
          AND quantity_reserved+? <= quantity_physical
          AND EXISTS(SELECT 1 FROM stock_batches b WHERE b.id=batch_id AND b.item_id=?)
          AND EXISTS(SELECT 1 FROM locations l WHERE l.id=location_id AND l.warehouse_id=?)`)
        .run(delta, bin.batch_id, bin.location_id, delta, eps, delta, row.item_id, row.warehouse_id);
      if (changed.changes !== 1) throw new BusinessRuleError(409, 'Reservation exceeds location availability or stock identity is invalid');
      // Snap decimal residue (0.3 sold as 3x0.1) back to a clean value, so
      // available = physical - reserved stays exact.
      db.prepare(`UPDATE batch_stock_by_location
        SET quantity_reserved = ROUND(quantity_reserved, 3)
        WHERE batch_id = ? AND location_id = ?`).run(bin.batch_id, bin.location_id);
    }
    // Only a fresh RESERVE persists child rows, and only when asked (a reopen
    // restores existing rows and must not duplicate them). A release never does.
    if (persist && sign === 1 && bins.length > 0) {
      const insert = db.prepare(`INSERT INTO stock_reservation_bins (reservation_id, batch_id, location_id, quantity_reserved, quantity_allocated) VALUES (?, ?, ?, ?, ?)`);
      for (const bin of bins) insert.run(row.id, bin.batch_id, bin.location_id, bin.quantity_reserved, bin.quantity_reserved);
    }
    // MEDIUM-1: every reservation bin write goes through here, so refresh the
    // stock_balances mirror in the SAME transaction. Without this a reader of
    // that mirror saw 0 reserved after create, or a stale value after a
    // consume, release or void restore. The flag selects what is READ, never
    // what is maintained, so this is ungated.
    StockMovementModel.syncStockBalancesExtension(row.item_id, row.warehouse_id, db);
  }

  /**
   * Bins this write must act on. An explicit list wins; otherwise use the
   * stored child rows; a legacy (pre-migration-129) row with no child rows
   * falls back to its parent batch/location columns.
   */
  private static resolveBins(
    db: Database.Database,
    row: Pick<StockReservation, 'id' | 'batch_id' | 'location_id' | 'quantity_reserved'>,
    bins: StockReservationBin[],
  ): StockReservationBin[] {
    if (bins.length > 0) return bins;
    const stored = this.getBins(row.id, db);
    if (stored.length > 0) return stored;
    if (row.batch_id != null && row.location_id != null) {
      return [{ batch_id: row.batch_id, location_id: row.location_id, quantity_reserved: roundQty(Number(row.quantity_reserved)) }];
    }
    return [];
  }

  /**
   * Decision B: reduce the named child-bin rows by the amounts drained. Each
   * entry's `quantity_reserved` is the amount TAKEN from that bin. Only named
   * rows are touched — never an arbitrary row for the same bin.
   *
   * A row that reaches zero is SET TO 0 (`keepRows`) rather than deleted, so a
   * later void can restore the exact per-bin allocation. Only a terminal
   * release drops the rows (`keepRows = false`).
   */
  private static consumeBins(db: Database.Database, reservationId: number, taken: StockReservationBin[], keepRows = true): void {
    const del = db.prepare('DELETE FROM stock_reservation_bins WHERE id = ?');
    const upd = db.prepare('UPDATE stock_reservation_bins SET quantity_reserved = ? WHERE id = ?');
    for (const t of taken) {
      const row = db.prepare('SELECT id, quantity_reserved FROM stock_reservation_bins WHERE reservation_id = ? AND batch_id = ? AND location_id = ?')
        .get(reservationId, t.batch_id, t.location_id) as { id: number; quantity_reserved: number } | undefined;
      if (!row) continue;
      const rest = roundQty(Number(row.quantity_reserved) - t.quantity_reserved);
      if (rest <= 0 && !keepRows) del.run(row.id); else upd.run(Math.max(rest, 0), row.id);
    }
  }

  static release(data: {
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
  }, db: Database.Database): StockReservation | undefined {
    return db.transaction(() => {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return undefined;

    const existing = db.prepare(`
      SELECT * FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id IS ?
        AND status = 'ACTIVE'
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as StockReservation | undefined;

    if (!existing) return undefined;
    this.drainAllocation(db, existing, Number(existing.quantity_reserved));
    // Release is terminal: drop the allocations entirely.
    db.prepare('DELETE FROM stock_reservation_bins WHERE reservation_id = ?').run(existing.id);

    db.prepare(`
      UPDATE stock_reservations
      SET status = 'RELEASED', released_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);

    return this.getById(existing.id, db);
    })();
  }

  /**
   * S-1: the ACTIVE reservation named by id, or undefined. Reads are not
   * gated by feature_batch_locations — only READS may depend on the flag, and
   * consuming an existing reservation is a WRITE that must work flag-off.
   */
  /**
   * NEW-2 Option 1: release a reservation BY ID, terminally.
   *
   * Used when an invoice edit changes a reserved line to a different item. The
   * reservation belonged to the item that is no longer on the invoice, so
   * reopening it (the cancel/delete rule) would leave the units held on a sale
   * that does not contain them - a stranded hold. Release is the honest answer:
   * the hold ends, and a later change back must reserve again.
   *
   * NOT gated by feature_batch_locations. The flag selects what is READ; a
   * release is a write and must work in both flag states, like every other
   * reservation write here.
   */
  static releaseById(db: Database.Database, reservationId: number, quantity?: number): void {
    const existing = this.getById(reservationId, db);
    if (!existing) return;
    // Already released is not an error - a second edit must stay idempotent.
    if (existing.status === 'RELEASED') return;

    const held = roundQty(Number(existing.quantity_reserved));
    // A partial release gives back only the unused remainder, so the part a
    // resulting line still needs stays held. Default is the whole reservation.
    const partialRequest = quantity != null && roundQty(Math.max(0, quantity)) < held;
    const releasing = quantity == null ? held : roundQty(Math.min(held, Math.max(0, quantity)));
    // A CONSUMED reservation holds nothing, so there is no quantity to give
    // back - but a terminal release must still happen, because the point is to
    // stop it being reopened for a line that no longer carries its item.
    if (releasing <= 0 && partialRequest) return;
    if (releasing > 0) this.drainAllocation(db, existing, releasing, partialRequest);
    // Releasing only part leaves the reservation ACTIVE for the rest: the edit
    // is not finished with it, so it must not go terminal.
    const partial = partialRequest;

    StockMovementModel.syncStockBalancesExtension(existing.item_id, existing.warehouse_id, db);

    if (partial) {
      // Keep the child rows: drainAllocation(zeroRows=false) zeroed only what
      // was released, and the remaining lines still need the rest.
      db.prepare('UPDATE stock_reservations SET quantity_reserved = ? WHERE id = ?')
        .run(roundQty(held - releasing), existing.id);
      return;
    }
    // Release is terminal: drop the allocations entirely, so a later reopen or
    // restore has nothing to hand back and the bin cannot be double-freed.
    db.prepare('DELETE FROM stock_reservation_bins WHERE reservation_id = ?').run(existing.id);
    db.prepare(`
      UPDATE stock_reservations
      SET status = 'RELEASED', quantity_reserved = 0, released_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);
  }

  static getActiveById(id: number, db: Database.Database): StockReservation | undefined {
    return db.prepare(`
      SELECT * FROM stock_reservations WHERE id = ? AND status = 'ACTIVE'
    `).get(id) as StockReservation | undefined;
  }

  /**
   * Reduce the reservation's reserve by `quantity`, draining its bins
   * oldest-first (explicit allocation, else stored rows, else the legacy parent
   * bin). Each drained bin is released by exactly the amount taken, so
   * `available = physical - reserved` stays correct.
   *
   * `keepRows` controls what happens to a child row that reaches zero: a
   * CONSUME keeps it (at 0) so a void can restore the exact allocations, while
   * a RELEASE deletes it. Falls back to the parent columns for legacy rows with
   * no child allocation.
   */
  private static drainAllocation(
    db: Database.Database,
    row: StockReservation,
    quantity: number,
    keepRows = true,
  ): StockReservationBin[] {
    let left = roundQty(quantity);
    const taken: StockReservationBin[] = [];
    for (const bin of this.resolveBins(db, row, [])) {
      if (left <= 0) break;
      const take = roundQty(Math.min(left, Number(bin.quantity_reserved)));
      if (take <= 0) continue;
      this.reserveBins(db, row, [{ batch_id: bin.batch_id, location_id: bin.location_id, quantity_reserved: take }], -1);
      this.consumeBins(db, row.id, [{ batch_id: bin.batch_id, location_id: bin.location_id, quantity_reserved: take }], keepRows);
      taken.push({ batch_id: bin.batch_id, location_id: bin.location_id, quantity_reserved: take });
      left = roundQty(left - take);
    }
    return taken;
  }

  static markConsumedPartial(db: Database.Database, existing: StockReservation, quantity: number): StockReservation {
    const sold = Math.min(quantity, Number(existing.quantity_reserved));
    if (sold <= 0) return existing;
    const remaining = roundQty(Number(existing.quantity_reserved) - sold);
    // Keep every child row (zeroed when fully drained) so a void can restore
    // the exact original allocation. Only a terminal release drops rows.
    this.drainAllocation(db, existing, sold, true);

    if (remaining <= 0) {
      db.prepare(`
        UPDATE stock_reservations
        SET status = 'CONSUMED', quantity_reserved = 0, consumed_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(existing.id);
    } else {
      db.prepare(`UPDATE stock_reservations SET quantity_reserved = ? WHERE id = ?`)
        .run(remaining, existing.id);
    }
    return this.getById(existing.id, db)!;
  }

  static consume(data: {
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
  }, db: Database.Database): StockReservation | undefined {
    // Only READS depend on feature_batch_locations; consuming an existing
    // reservation is a WRITE that also maintains batch_stock_by_location, so
    // it runs regardless of the flag.
    const existing = db.prepare(`
      SELECT * FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id IS ?
        AND status = 'ACTIVE'
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as StockReservation | undefined;

    if (!existing) return undefined;
    return this.markConsumed(db, existing);
  }

  /**
   * S-1: consume the reservation named by id — the one the sale actually
   * fulfils. Unlike a reference lookup, this can never release a different
   * reservation that happens to share the bin.
   */
  static consumeById(id: number, db: Database.Database): StockReservation | undefined {
    // Flag-independent: see consume().
    const existing = db.prepare(`
      SELECT * FROM stock_reservations WHERE id = ? AND status = 'ACTIVE'
    `).get(id) as StockReservation | undefined;

    if (!existing) return undefined;
    return this.markConsumed(db, existing);
  }

  /** Flip ACTIVE -> CONSUMED and release the bin's reserved quantity, so the
   *  consumed units are no longer double-counted as unavailable. */
  private static markConsumed(db: Database.Database, existing: StockReservation): StockReservation {
    // Full consume: release each bin's reserve but KEEP the child rows intact,
    // so a later void can restore the exact per-bin allocations.
    this.reserveBins(db, existing, [], -1);

    db.prepare(`
      UPDATE stock_reservations
      SET status = 'CONSUMED', quantity_reserved = 0, consumed_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);

    return this.getById(existing.id, db)!;
  }

  static autoReleaseExpired(db: Database.Database, ttlHours: number = 24): number {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return 0;

    return db.transaction(() => {
      const expired = db.prepare(`SELECT * FROM stock_reservations WHERE status = 'ACTIVE'
        AND created_at < datetime('now', ?)
        AND reference_doctype NOT IN ('QC_HOLD')
      `).all(`-${ttlHours} hours`) as StockReservation[];
      for (const row of expired) this.release(row, db);
      return expired.length;
    })();
  }

  static getByReference(doctype: string, docno: string, db: Database.Database): StockReservation[] {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return [];
    return db.prepare(`
      SELECT * FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ?
      ORDER BY id ASC
    `).all(doctype, docno) as StockReservation[];
  }

  static getById(id: number, db: Database.Database): StockReservation | undefined {
    return db.prepare(`SELECT * FROM stock_reservations WHERE id = ?`).get(id) as StockReservation | undefined;
  }

  /**
   * Decision A: reopen a reservation for a voided/cancelled sale, but only
   * while its source sales order is still active. A terminal (Invoiced /
   * Completed / Cancelled) source order, or a non-order reference, stays
   * consumed — the sale is gone for good.
   */
  static reopenForInvoiceLine(db: Database.Database, reservationId: number, quantity: number): void {
    const existing = this.getById(reservationId, db);
    if (!existing) return;
    if (!this.sourceOrderIsActive(db, existing)) return;

    // No ledger row (a line written before migration 131): the reservation's
    // own stored allocations are the only record of which bins it held, so
    // restore those rather than an increment of `quantity`.
    const draw = this.getAllBinRows(existing.id, db)
      .filter((b) => roundQty(Number(b.quantity_allocated ?? b.quantity_reserved)) > 0);
    if (quantity <= 0) return;
    this.restoreConsumedBins(db, reservationId, draw.map((b) => ({
      batch_id: b.batch_id,
      location_id: b.location_id,
      quantity_reserved: roundQty(Number(b.quantity_allocated ?? b.quantity_reserved)),
    })));
  }

  /**
   * S-1 restore: a deleted invoice coming back takes its reservation again.
   * The delete reopened the reserve (it holds the units again), so restore
   * DRAINS those bins a second time and marks the reservation CONSUMED, which
   * is exactly the state the invoice was in before it was deleted. A
   * reservation whose source order is no longer active is left alone -
   * symmetric with the reopen.
   */
  static reconsumedRestoredBins(
    db: Database.Database,
    reservationId: number,
    draw: Array<{ batch_id: number; location_id: number; quantity: number }>,
  ): void {
    const existing = this.getById(reservationId, db);
    if (!existing) return;
    if (!this.sourceOrderIsActive(db, existing)) return;
    const total = roundQty(draw.reduce((s, d) => s + Number(d.quantity), 0));
    if (total <= 0) return;
    // drainAllocation both releases the bin reserve and zeroes the child rows,
    // so the header still matches its children afterwards.
    this.drainAllocation(db, existing, total, true);
    const remaining = roundQty(Number(existing.quantity_reserved) - total);
    if (remaining <= 0) {
      db.prepare(`UPDATE stock_reservations SET status = 'CONSUMED', quantity_reserved = 0, consumed_at = CURRENT_TIMESTAMP WHERE id = ?`)
        .run(existing.id);
    } else {
      db.prepare('UPDATE stock_reservations SET quantity_reserved = ? WHERE id = ?').run(remaining, existing.id);
    }
  }

  /**
   * S-1: restore the exact bins an invoice line drained, using the durable
   * per-line ledger. It names each bin explicitly,
   * so voiding one of several invoices against a reservation restores only
   * that line's draw and never over-reserves a bin it did not take from.
   * The reservation goes back to ACTIVE and the parent is derived from the
   * child rows actually restored.
   */
  static restoreConsumedBins(db: Database.Database, reservationId: number, draw: StockReservationBin[]): void {
    const existing = this.getById(reservationId, db);
    if (!existing) return;
    if (!this.sourceOrderIsActive(db, existing)) return;

    const upd = db.prepare('UPDATE stock_reservation_bins SET quantity_reserved = ? WHERE reservation_id = ? AND batch_id = ? AND location_id = ?');
    const ins = db.prepare('INSERT INTO stock_reservation_bins (reservation_id, batch_id, location_id, quantity_reserved, quantity_allocated) VALUES (?, ?, ?, ?, ?)');
    for (const bin of draw) {
      const add = roundQty(Number(bin.quantity_reserved));
      if (add <= 0) continue;
      this.reserveBins(db, existing, [{ batch_id: bin.batch_id, location_id: bin.location_id, quantity_reserved: add }], 1, false);
      // Restore into the existing row when there is one (a partial sale keeps
      // a zeroed row), else recreate it, so the allocation total stays exact.
      const current = db.prepare('SELECT id, quantity_reserved FROM stock_reservation_bins WHERE reservation_id = ? AND batch_id = ? AND location_id = ?')
        .get(reservationId, bin.batch_id, bin.location_id) as { id: number; quantity_reserved: number } | undefined;
      if (current) {
        const restored = roundQty(Number(current.quantity_reserved) + add);
        db.prepare('UPDATE stock_reservation_bins SET quantity_reserved = ? WHERE id = ?').run(restored, current.id);
        db.prepare('UPDATE stock_reservation_bins SET quantity_allocated = MAX(COALESCE(quantity_allocated, 0), ?) WHERE id = ?').run(restored, current.id);
      } else {
        ins.run(reservationId, bin.batch_id, bin.location_id, add, add);
      }
    }

    const rows = this.getBins(reservationId, db);
    db.prepare(`UPDATE stock_reservations SET status = 'ACTIVE', consumed_at = NULL, quantity_reserved = ? WHERE id = ?`)
      .run(roundQty(rows.reduce((s, b) => s + Number(b.quantity_reserved), 0)), reservationId);
  }

  /** Decision A: active = a sales order in Draft, Confirmed or Delivered. */
  private static sourceOrderIsActive(db: Database.Database, reservation: StockReservation): boolean {
    if (reservation.reference_doctype !== 'SALES_ORDER') return false;
    const order = db.prepare(`SELECT status FROM sales_orders WHERE so_no = ?`)
      .get(reservation.reference_docno) as { status?: string } | undefined;
    return !!order && ['Draft', 'Confirmed', 'Delivered'].includes(order.status ?? '');
  }

  static getAll(db: Database.Database): StockReservation[] {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return [];
    return db.prepare(`SELECT * FROM stock_reservations ORDER BY created_at DESC`).all() as StockReservation[];
  }
}
