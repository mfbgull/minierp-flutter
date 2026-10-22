import type Database from 'better-sqlite3';

interface SalesLine {
  readonly item_id: number;
  readonly quantity: number;
  readonly unit_price: number;
}

export function validateSalesWarehouse(db: Database.Database, warehouseId: number | undefined): void {
  if (warehouseId) {
    const warehouse = db.prepare('SELECT id FROM warehouses WHERE id = ? AND is_active = 1').get(warehouseId);
    if (!warehouse) throw new Error('Warehouse not found or inactive');
  }
}

export function validateSalesDocumentItems(db: Database.Database, items: readonly SalesLine[], document: string): void {
  if (!items || items.length === 0) throw new Error(`${document} must have at least one item`);
  for (const item of items) {
    const row = db.prepare('SELECT id, is_active FROM items WHERE id = ?').get(item.item_id) as { id: number; is_active: number } | undefined;
    if (!row) throw new Error(`Item ${item.item_id} not found`);
    if (!row.is_active) throw new Error(`Item ${item.item_id} is inactive`);
    if (item.quantity <= 0) throw new Error('Item quantity must be positive');
    if (item.unit_price < 0) throw new Error('Item unit price cannot be negative');
  }
}
