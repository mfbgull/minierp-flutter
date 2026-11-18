import Database from 'better-sqlite3';
import logger from '../utils/logger';
import { isFeatureEnabled } from '../utils/featureFlags';
import { BusinessRuleError } from '../utils/businessRuleError';
import { roundQty, qtyEpsilon } from '../utils/quantity';

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
  batch_id: number;
  location_id: number;
  quantity_reserved: number;
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
  const sameBins = requestedBins.length === 0 || requestedBins === data.storedBinSignature;
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
    const bins: StockReservationBin[] = data.bins && data.bins.length > 0
      ? data.bins.map((b) => ({ batch_id: b.batch_id, location_id: b.location_id, quantity_reserved: roundQty(b.quantity) }))
      : (data.location_id && data.batch_id)
        ? [{ batch_id: data.batch_id, location_id: data.location_id, quantity_reserved: qty }]
        : [];
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

    if (existing) {
      assertMatchingReservation(existing, { ...data, storedBinSignature: this.getBinSignature(existing.id, db) }, qty);
      if (existing.status === 'ACTIVE') {
        logger.warn(`[Reservation] Duplicate reservation for ${data.reference_doctype}:${data.reference_docno}:${data.reference_line_id}`);
        return existing;
      }
      if (existing.status === 'RELEASED') {
        this.reserveBins(db, existing, bins, 1);
        // Re-activate a released reservation
        db.prepare(`
          UPDATE stock_reservations
          SET status = 'ACTIVE', released_at = NULL, quantity_reserved = ?
          WHERE id = ?
        `).run(qty, existing.id);
        return { ...existing, quantity_reserved: qty, status: 'ACTIVE', released_at: undefined } as StockReservation;
      }
      throw new BusinessRuleError(409, 'Consumed reservation cannot be reactivated');
    }

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

  /** Child-bin rows for a reservation, oldest first. */
  static getBins(reservationId: number, db: Database.Database): StockReservationBin[] {
    return db.prepare(`
      SELECT batch_id, location_id, quantity_reserved FROM stock_reservation_bins
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
  private static reserveBins(db: Database.Database, row: Pick<StockReservation, 'id' | 'item_id' | 'warehouse_id'>, bins: StockReservationBin[], sign: 1 | -1): void {
    const stored = bins.length > 0 ? bins : this.getBins(row.id, db);
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
    if (bins.length > 0) {
      // Fresh allocation: persist the child rows that later release/consume read.
      const insert = db.prepare(`INSERT INTO stock_reservation_bins (reservation_id, batch_id, location_id, quantity_reserved) VALUES (?, ?, ?, ?)`);
      for (const bin of bins) insert.run(row.id, bin.batch_id, bin.location_id, bin.quantity_reserved);
    }
  }

  /**
   * Decision B: drain child-bin rows oldest-first by `quantity` (the amount
   * actually sold). Reduces each row's reserve in place and deletes rows that
   * reach zero, so a partial sale keeps the remainder linked to the same bins.
   */
  private static consumeBins(db: Database.Database, reservationId: number, quantity: number): void {
    let left = roundQty(quantity);
    const rows = db.prepare(`SELECT id, quantity_reserved FROM stock_reservation_bins WHERE reservation_id = ? ORDER BY id ASC`)
      .all(reservationId) as Array<{ id: number; quantity_reserved: number }>;
    const del = db.prepare('DELETE FROM stock_reservation_bins WHERE id = ?');
    const upd = db.prepare('UPDATE stock_reservation_bins SET quantity_reserved = ? WHERE id = ?');
    for (const r of rows) {
      if (left <= 0) break;
      const take = Math.min(left, roundQty(r.quantity_reserved));
      const rest = roundQty(r.quantity_reserved - take);
      if (rest <= 0) del.run(r.id); else upd.run(rest, r.id);
      left = roundQty(left - take);
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
    this.reserveBins(db, existing, [], -1);
    this.consumeBins(db, existing.id, Number(existing.quantity_reserved));

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
  static getActiveById(id: number, db: Database.Database): StockReservation | undefined {
    return db.prepare(`
      SELECT * FROM stock_reservations WHERE id = ? AND status = 'ACTIVE'
    `).get(id) as StockReservation | undefined;
  }

  /**
   * S-1: fulfil `quantity` of the reservation named by id. Decrements the
   * reservation by the sold quantity; a partial sale leaves the remainder
   * ACTIVE (reserve 4, sell 1 -> 3 reserved), only a full sale flips it to
   * CONSUMED. Releases the bin's reserved for exactly the sold quantity, so
   * available = physical - reserved stays correct.
   */
  /**
   * Release `quantity` of reserve, draining child-bin rows oldest-first and
   * releasing each drained bin by exactly the amount taken (so `available`
   * stays `physical - reserved`). Used by partial consumption and void-reopen
   * bookkeeping.
   */
  private static releaseBinsPartial(db: Database.Database, row: StockReservation, quantity: number): void {
    let left = roundQty(quantity);
    for (const bin of this.getBins(row.id, db)) {
      if (left <= 0) break;
      const take = roundQty(Math.min(left, Number(bin.quantity_reserved)));
      if (take <= 0) continue;
      this.reserveBins(db, row, [{ ...bin, quantity_reserved: take }], -1);
      this.consumeBins(db, row.id, take);
      left = roundQty(left - take);
    }
    if (left > 0 && row.batch_id && row.location_id) {
      // Legacy single-bin rows with no child rows.
      this.reserveBins(db, row, [{ batch_id: row.batch_id, location_id: row.location_id, quantity_reserved: left }], -1);
    }
  }

  static markConsumedPartial(db: Database.Database, existing: StockReservation, quantity: number): StockReservation {
    const sold = Math.min(quantity, Number(existing.quantity_reserved));
    if (sold <= 0) return existing;
    this.releaseBinsPartial(db, existing, sold);

    const remaining = roundQty(Number(existing.quantity_reserved) - sold);
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
    this.reserveBins(db, existing, [], -1);
    this.consumeBins(db, existing.id, Number(existing.quantity_reserved));

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

    if (existing.status === 'CONSUMED') {
      // Consume deleted the child rows; the sale is void, so reserve the sold
      // quantity once more and restore the parent row to ACTIVE.
      if (existing.batch_id && existing.location_id) {
        this.reserveBins(db, existing, [{ batch_id: existing.batch_id, location_id: existing.location_id, quantity_reserved: quantity }], 1);
      }
      db.prepare(`UPDATE stock_reservations SET status = 'ACTIVE', consumed_at = NULL, quantity_reserved = ? WHERE id = ?`)
        .run(quantity, existing.id);
      return;
    }

    if (existing.status === 'ACTIVE') {
      // Partial consumption: add the sold quantity back onto the same bins.
      let left = roundQty(quantity);
      const bins = this.getBins(existing.id, db);
      for (const bin of bins) {
        if (left <= 0) break;
        const add = roundQty(Math.min(left, Number(bin.quantity_reserved)));
        if (add <= 0) continue;
        this.reserveBins(db, existing, [{ ...bin, quantity_reserved: add }], 1);
        db.prepare('UPDATE stock_reservation_bins SET quantity_reserved = ? WHERE reservation_id = ? AND batch_id = ? AND location_id = ?')
          .run(roundQty(bin.quantity_reserved + add), existing.id, bin.batch_id, bin.location_id);
        left = roundQty(left - add);
      }
      if (left > 0 && existing.batch_id && existing.location_id) {
        this.reserveBins(db, existing, [{ batch_id: existing.batch_id, location_id: existing.location_id, quantity_reserved: left }], 1);
      }
      db.prepare(`UPDATE stock_reservations SET quantity_reserved = ? WHERE id = ?`)
        .run(roundQty(Number(existing.quantity_reserved) + quantity), existing.id);
    }
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
