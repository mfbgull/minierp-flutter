import Database from 'better-sqlite3';
import logger from '../utils/logger';
import { isFeatureEnabled } from '../utils/featureFlags';

interface StockReservation {
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
    if (!isFeatureEnabled(db, 'feature_batch_locations')) {
      throw new Error('Stock reservations require feature_batch_locations flag');
    }

    const qty = parseFloat(String(data.quantity_reserved));
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error(`Reservation quantity must be positive, got ${data.quantity_reserved}`);
    }

    // Idempotency: check if already reserved for this reference line
    const existing = db.prepare(`
      SELECT id, quantity_reserved, status FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id = ?
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as StockReservation | undefined;

    if (existing) {
      if (existing.status === 'ACTIVE') {
        logger.warn(`[Reservation] Duplicate reservation for ${data.reference_doctype}:${data.reference_docno}:${data.reference_line_id}`);
        return existing;
      }
      if (existing.status === 'RELEASED') {
        // Re-activate a released reservation
        db.prepare(`
          UPDATE stock_reservations
          SET status = 'ACTIVE', released_at = NULL, quantity_reserved = ?
          WHERE id = ?
        `).run(qty, existing.id);
        return { ...existing, quantity_reserved: qty, status: 'ACTIVE', released_at: undefined } as StockReservation;
      }
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
    return this.getById(id, db)!;
  }

  static release(data: {
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
  }, db: Database.Database): StockReservation | undefined {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return undefined;

    const existing = db.prepare(`
      SELECT id FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id = ?
        AND status = 'ACTIVE'
    `).get(data.reference_doctype, data.reference_docno, data.reference_line_id ?? null) as { id: number } | undefined;

    if (!existing) return undefined;

    db.prepare(`
      UPDATE stock_reservations
      SET status = 'RELEASED', released_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(existing.id);

    return this.getById(existing.id, db);
  }

  static consume(data: {
    reference_doctype: string;
    reference_docno: string;
    reference_line_id?: number;
  }, db: Database.Database): StockReservation | undefined {
    if (!isFeatureEnabled(db, 'feature_batch_locations')) return undefined;

    const existing = db.prepare(`
      SELECT id FROM stock_reservations
      WHERE reference_doctype = ? AND reference_docno = ? AND reference_line_id = ?
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

    const result = db.prepare(`
      UPDATE stock_reservations
      SET status = 'RELEASED', released_at = CURRENT_TIMESTAMP
      WHERE status = 'ACTIVE'
        AND created_at < datetime('now', ?)
        AND reference_doctype NOT IN ('QC_HOLD')
    `).run(`-${ttlHours} hours`);

    return result.changes;
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
