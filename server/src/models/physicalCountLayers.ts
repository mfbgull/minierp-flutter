import type Database from 'better-sqlite3';
import StockMovementModel from './StockMovement';
import { isFeatureEnabled } from '../utils/featureFlags';
import { BusinessRuleError } from '../utils/businessRuleError';

type Layer = { batch_id: number | null; location_id: number | null; quantity: number; unit_cost: number };

export function countConsumptionUnitCost(consumption: Array<{ consumed: number; unitCost: number }>, fallback: number | null): number | null {
  const totalConsumed = consumption.reduce((sum, layer) => sum + layer.consumed, 0);
  return totalConsumed > 0
    ? consumption.reduce((sum, layer) => sum + layer.consumed * layer.unitCost, 0) / totalConsumed
    : fallback;
}

export function consumeSurplusCountBins(db: Database.Database, batchId: number, warehouseId: number, quantity: number): void {
  if (!isFeatureEnabled(db, 'feature_batch_locations')) return;
  const bins = db.prepare(`SELECT b.id,b.quantity_available FROM batch_stock_by_location b
    JOIN locations l ON l.id=b.location_id WHERE b.batch_id=? AND l.warehouse_id=? ORDER BY b.id`)
    .all(batchId, warehouseId) as Array<{ id: number; quantity_available: number }>;
  let remaining = quantity;
  for (const bin of bins) {
    const take = Math.min(remaining, Number(bin.quantity_available));
    if (take > 0) db.prepare('UPDATE batch_stock_by_location SET quantity_physical=quantity_physical-? WHERE id=?').run(take, bin.id);
    remaining -= take;
  }
  if (remaining > 0.0005) throw new Error('Cannot correct surplus stock already consumed, transferred or reserved');
}

export function consumeCountLayers(db: Database.Database, itemId: number, warehouseId: number, quantity: number, date: string) {
  const locations = isFeatureEnabled(db, 'feature_batch_locations')
    ? db.prepare(`SELECT b.batch_id,b.location_id,b.quantity_physical AS quantity,s.unit_cost
        FROM batch_stock_by_location b JOIN stock_batches s ON s.id=b.batch_id JOIN locations l ON l.id=b.location_id
        WHERE s.item_id=? AND l.warehouse_id=?`).all(itemId, warehouseId) as Layer[]
    : [];
  const consumption = StockMovementModel.consumeFromOldestBatches(itemId, warehouseId, quantity, db, date);
  const layers: Layer[] = consumption.map(c => ({ batch_id: c.batchId, location_id: null, quantity: c.consumed, unit_cost: c.unitCost }));
  for (const loc of locations) {
    const after = db.prepare('SELECT quantity_physical AS quantity FROM batch_stock_by_location WHERE batch_id=? AND location_id=?')
      .get(loc.batch_id, loc.location_id) as { quantity: number };
    const consumed = Math.round((loc.quantity - after.quantity) * 1000) / 1000;
    if (consumed > 0) layers.push({ ...loc, quantity: consumed });
  }
  return {
    consumption,
    save(movementId: number) {
      const insert = db.prepare('INSERT INTO physical_count_layers(movement_id,batch_id,location_id,quantity,unit_cost) VALUES(?,?,?,?,?)');
      for (const layer of layers) insert.run(movementId, layer.batch_id, layer.location_id, layer.quantity, layer.unit_cost);
    },
  };
}

export function restoreCountLayers(db: Database.Database, movementId: number, quantity: number): void {
  const layers = db.prepare('SELECT batch_id,location_id,quantity,unit_cost FROM physical_count_layers WHERE movement_id=? ORDER BY id')
    .all(movementId) as Layer[];
  if (layers.length === 0) {
    // Historical primary-only provenance cannot establish multi-layer costs.
    throw new BusinessRuleError(409, `Count movement ${movementId} has no exact cost-layer provenance; reconciliation is required`);
  }
  const restored = layers.filter(l => l.location_id === null).reduce((sum, l) => sum + l.quantity, 0);
  if (Math.abs(restored - quantity) > 0.0005) throw new BusinessRuleError(409, 'Count layer provenance does not match the original shortage');
  for (const layer of layers) {
    if (layer.batch_id === null) continue; // Explicitly recorded unbatched legacy stock.
    if (layer.location_id === null) {
      db.prepare('UPDATE stock_batches SET quantity_remaining=quantity_remaining+? WHERE id=?').run(layer.quantity, layer.batch_id);
    } else {
      db.prepare(`UPDATE batch_stock_by_location SET quantity_physical=quantity_physical+?
        WHERE batch_id=? AND location_id=?`).run(layer.quantity, layer.batch_id, layer.location_id);
    }
  }
}
