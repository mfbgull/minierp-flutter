import type Database from 'better-sqlite3';

interface SalesLine {
  readonly item_id: number;
  readonly quantity: number;
  readonly unit_price: number;
  readonly tax_rate?: number;
  readonly discount_type?: string;
  readonly discount_value?: number;
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
    validateSalesLineTaxDiscount(item, document);
  }
}

/**
 * BUG-006: tax and discount come from the client as rates and values; the
 * server recomputes every line amount from them and never trusts a
 * client-sent total. Reject values the arithmetic cannot mean.
 */
export function validateSalesLineTaxDiscount(item: SalesLine, document: string): void {
  if (item.tax_rate !== undefined) {
    if (typeof item.tax_rate !== 'number' || !Number.isFinite(item.tax_rate)) {
      throw new Error(`${document} tax rate must be a number`);
    }
    if (item.tax_rate < 0 || item.tax_rate > 100) {
      throw new Error(`${document} tax rate must be between 0 and 100`);
    }
  }
  const discountType = item.discount_type ?? 'none';
  if (!['none', 'percentage', 'flat'].includes(discountType)) {
    throw new Error(`${document} discount type is invalid`);
  }
  if (item.discount_value !== undefined) {
    if (typeof item.discount_value !== 'number' || !Number.isFinite(item.discount_value)) {
      throw new Error(`${document} discount value must be a number`);
    }
    if (item.discount_value < 0) {
      throw new Error(`${document} discount value cannot be negative`);
    }
    if (discountType === 'percentage' && item.discount_value >= 100) {
      throw new Error(`${document} percentage discount must be below 100`);
    }
  }
}
