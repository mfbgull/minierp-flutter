import Database from 'better-sqlite3';
import logger from '../utils/logger';
import { isFeatureEnabled } from '../utils/featureFlags';
import { BusinessRuleError } from '../utils/businessRuleError';

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

type ReservationInput = Omit<StockReservation, 'id' | 'status' | 'created_at' | 'released_at' | 'consumed_at'>;

function assertMatchingReservation(existing: StockReservation, data: ReservationInput, qty: number): void {
  const sameStock = existing.item_id === data.item_id && existing.warehouse_id === data.warehouse_id &&
    (existing.location_id ?? null) === (data.location_id ?? null) && (existing.batch_id ?? null) === (data.batch_id ?? null);
  const sameQuantity = existing.status !== 'ACTIVE' || Number(existing.quantity_reserved) === qty;
  if (!sameStock || !sameQuantity) throw new BusinessRuleError(409, 'Reservation reference already has different stock or quantity');
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
  }, db: Database.Database): StockReservation {
    return db.transaction(() => {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) {
      throw new Error('Stock reservations require feature_batch_locations flag');
    }

    const qty = parseFloat(String(data.quantity_reserved));
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error(`Reservation quantity must be positive, got ${data.quantity_reserved}`);
    }

    // Idempotency: check if already reserved for this reference line
    const existing = db.prepare(`
      SELECT * FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id IS ?
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as StockReservation | undefined;

    if (existing) {
      assertMatchingReservation(existing, data, qty);
      if (existing.status === 'ACTIVE') {
        logger.warn(`[Reservation] Duplicate reservation for ${data.reference_doctype}:${data.reference_docno}:${data.reference_line_id}`);
        return existing;
      }
      if (existing.status === 'RELEASED') {
        this.changeLocationReserved(db, existing, qty);
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
      data.location_id ?? null,
      data.batch_id ?? null,
      qty,
      data.reference_doctype,
      data.reference_docno,
      data.reference_line_id ?? null
    );

    const id = result.lastInsertRowid as number;
    const created = this.getById(id, db)!;
    this.changeLocationReserved(db, created, qty);
    return created;
    })();
  }

  private static changeLocationReserved(db: Database.Database, row: Pick<StockReservation, 'item_id' | 'warehouse_id' | 'location_id' | 'batch_id'>, delta: number): void {
    // Batch-only reservations have no selected bin; retain their existing metadata workflow.
    if (!row.location_id || !row.batch_id) return;
    const changed = db.prepare(`UPDATE batch_stock_by_location SET quantity_reserved=quantity_reserved+?
      WHERE batch_id=? AND location_id=? AND quantity_reserved+? >= 0
        AND quantity_reserved+? <= quantity_physical
        AND EXISTS(SELECT 1 FROM stock_batches b WHERE b.id=batch_id AND b.item_id=?)
        AND EXISTS(SELECT 1 FROM locations l WHERE l.id=location_id AND l.warehouse_id=?)`)
      .run(delta, row.batch_id ?? null, row.location_id ?? null, delta, delta, row.item_id, row.warehouse_id);
    if (changed.changes !== 1) throw new BusinessRuleError(409, 'Reservation exceeds location availability or stock identity is invalid');
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
    this.changeLocationReserved(db, existing, -Number(existing.quantity_reserved));

    db.prepare(`
      UPDATE stock_reservations
      SET status = 'RELEASED', released_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);

    return this.getById(existing.id, db);
    })();
  }

  static consume(data: {
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
  }, db: Database.Database): StockReservation | undefined {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return undefined;

    const existing = db.prepare(`
      SELECT id FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id IS ?
        AND status = 'ACTIVE'
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as { id: number } | undefined;

    if (!existing) return undefined;

    db.prepare(`
      UPDATE stock_reservations
      SET status = 'CONSUMED', consumed_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);

    return this.getById(existing.id, db);
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

  static getAll(db: Database.Database): StockReservation[] {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return [];
    return db.prepare(`SELECT * FROM stock_reservations ORDER BY created_at DESC`).all() as StockReservation[];
  }
}
