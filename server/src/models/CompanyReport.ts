import type Database from 'better-sqlite3';
import { allocateHeaderDiscount } from '../services/returnMath';
import { roundCurrency, decomposeLineAmount } from '../utils/currency';
import { columnExistsSafe } from './Reports';

interface PeriodLine {
  item_id: number;
  document_id: number;
  document_no: string;
  document_type: string;
  date: string;
  quantity: number;
  amount: number;
  is_return: number;
  supplier_id?: number | null;
}

interface SaleLine {
  invoice_id: number; invoice_no: string; invoice_date: string;
  item_id: number; company_id: number | null; quantity: number; unit_price: number;
  net_amount: number; tax_amount: number; tax_rate: number;
  discount_type: string; discount_value: number;
  header_scope: string; header_type: string; header_value: number;
}

function salesLines(companyId: number, start: string, end: string, db: Database.Database): PeriodLine[] {
  const source = db.prepare(`
    SELECT ii.*, i.company_id, h.invoice_no, h.invoice_date,
      h.discount_scope AS header_scope, h.discount_type AS header_type, h.discount_value AS header_value
    FROM invoice_items ii JOIN invoices h ON h.id = ii.invoice_id JOIN items i ON i.id = ii.item_id
    WHERE h.status <> 'Cancelled' AND h.invoice_date BETWEEN ? AND ?
      AND EXISTS (SELECT 1 FROM invoice_items x JOIN items p ON p.id = x.item_id WHERE x.invoice_id = h.id AND p.company_id = ?)
    ORDER BY h.id, ii.id
  `).all(start, end, companyId) as SaleLine[];
  const invoices = new Map<number, SaleLine[]>();
  for (const line of source) {
    const group = invoices.get(line.invoice_id) ?? [];
    group.push(line); invoices.set(line.invoice_id, group);
  }
  const result: PeriodLine[] = [];
  for (const group of invoices.values()) {
    const raw = group.map(line => ({ ...line, returnedQuantity: line.quantity, returnedRatio: 1,
      returnedNet: line.net_amount, returnedTax: line.tax_amount,
      returnedGross: roundCurrency(line.net_amount + line.tax_amount),
      lineGross: decomposeLineAmount({ quantity: line.quantity, unit_price: line.unit_price,
        tax_rate: line.tax_rate, discount_type: line.discount_type, discount_value: line.discount_value }).gross }));
    const first = group[0];
    const allocated = allocateHeaderDiscount(raw, { discount_scope: first.header_scope,
      discount_type: first.header_type, discount_value: first.header_value,
      invoiceSubtotal: raw.reduce((sum, line) => sum + line.lineGross, 0) });
    for (const line of allocated) if (line.company_id === companyId) result.push({
      item_id: line.item_id, document_id: line.invoice_id, document_no: line.invoice_no,
      document_type: 'INVOICE', date: line.invoice_date, quantity: line.quantity,
      amount: line.returnedGross, is_return: 0,
    });
  }
  return result.concat(db.prepare(`
    SELECT l.item_id, h.id AS document_id, h.return_no AS document_no, 'INVOICE_RETURN' AS document_type,
      h.return_date AS date, l.quantity, l.line_amount AS amount, 1 AS is_return
    FROM invoice_return_items l JOIN invoice_returns h ON h.id = l.return_id
    JOIN items i ON i.id = l.item_id
    WHERE i.company_id = ? AND h.status <> 'Voided' AND h.voided_at IS NULL
      AND h.return_date BETWEEN ? AND ?
  `).all(companyId, start, end) as PeriodLine[]);
}

function purchaseLines(companyId: number, start: string, end: string, db: Database.Database): PeriodLine[] {
  return db.prepare(`
    SELECT p.item_id, p.id AS document_id, p.purchase_no AS document_no, 'PURCHASE' AS document_type,
      p.purchase_date AS date, p.quantity, ROUND(p.total_cost + p.input_tax_amount, 2) AS amount,
      0 AS is_return, p.supplier_id
    FROM purchases p JOIN items i ON i.id = p.item_id
    WHERE i.company_id = @company AND p.voided_at IS NULL AND p.purchase_date BETWEEN @start AND @end
    UNION ALL
    SELECT l.item_id, h.id, h.receipt_no, 'GOODS_RECEIPT', h.receipt_date, l.received_quantity,
      ROUND(l.received_quantity * po.unit_price, 2) + l.input_tax_amount, 0, ph.supplier_id
    FROM goods_receipt_items l JOIN goods_receipts h ON h.id = l.receipt_id
    JOIN purchase_order_items po ON po.id = l.po_item_id JOIN purchase_orders ph ON ph.id = h.po_id
    JOIN items i ON i.id = l.item_id
    WHERE i.company_id = @company AND h.voided_at IS NULL AND h.receipt_date BETWEEN @start AND @end
    UNION ALL
    SELECT l.item_id, h.id, h.return_no, 'PURCHASE_RETURN', h.return_date, l.quantity,
      ROUND(l.amount + l.input_tax_amount, 2), 1, NULL
    FROM purchase_return_items l JOIN purchase_returns h ON h.id = l.purchase_return_id
    JOIN items i ON i.id = l.item_id
    WHERE i.company_id = @company AND h.status = 'POSTED' AND h.voided_at IS NULL AND h.return_date BETWEEN @start AND @end
  `).all({ company: companyId, start, end }) as PeriodLine[];
}

export function getCompanyPeriod(companyId: number, view: 'sales' | 'purchases', start: string, end: string,
  page: number, limit: number, db: Database.Database) {
  const lines = view === 'sales' ? salesLines(companyId, start, end, db) : purchaseLines(companyId, start, end, db);
  const products = db.prepare('SELECT id, item_code, item_name, unit_of_measure FROM items WHERE company_id = ? ORDER BY item_name, id')
    .all(companyId) as { id: number; item_code: string; item_name: string; unit_of_measure: string }[];
  const rows = products.map(product => {
    const transactions = lines.filter(line => line.item_id === product.id);
    const gross = transactions.filter(line => !line.is_return);
    const returns = transactions.filter(line => line.is_return);
    const grossValue = roundCurrency(gross.reduce((sum, line) => sum + line.amount, 0));
    const returnValue = roundCurrency(returns.reduce((sum, line) => sum + line.amount, 0));
    const grossQuantity = gross.reduce((sum, line) => sum + line.quantity, 0);
    const returnQuantity = returns.reduce((sum, line) => sum + line.quantity, 0);
    return { item_id: product.id, item_code: product.item_code, item_name: product.item_name,
      unit_of_measure: product.unit_of_measure, gross_quantity: grossQuantity, return_quantity: returnQuantity,
      net_quantity: grossQuantity - returnQuantity, gross_value: grossValue, return_value: returnValue,
      net_value: roundCurrency(grossValue - returnValue), transactions };
  }).filter(row => row.transactions.length > 0);
  const quantities: Record<string, { gross: number; returns: number; net: number }> = Object.create(null);
  for (const row of rows) {
    const bucket = quantities[row.unit_of_measure] ?? { gross: 0, returns: 0, net: 0 };
    bucket.gross += row.gross_quantity; bucket.returns += row.return_quantity; bucket.net += row.net_quantity;
    quantities[row.unit_of_measure] = bucket;
  }
  return { company_id: companyId, view, startDate: start, endDate: end, amount_basis: 'tax_inclusive_after_discounts_before_restocking_fees',
    rows: rows.slice((page - 1) * limit, page * limit),
    totals: { gross_value: roundCurrency(rows.reduce((s, r) => s + r.gross_value, 0)),
      return_value: roundCurrency(rows.reduce((s, r) => s + r.return_value, 0)),
      net_value: roundCurrency(rows.reduce((s, r) => s + r.net_value, 0)), quantities_by_uom: quantities },
    pagination: { page, limit, total: rows.length, totalPages: Math.ceil(rows.length / limit) } };
}

export interface CompanyStockRow {
  item_id: number;
  item_code: string;
  item_name: string;
  unit_of_measure: string;
  quantity: number;
  stock_value: number;
}

interface AggregateRow { item_id: number; q: number; v: number }
interface Bucket { q: number; v: number }

function bucketMap(rows: AggregateRow[]): Map<number, Bucket> {
  const map = new Map<number, Bucket>();
  for (const row of rows) map.set(row.item_id, { q: Number(row.q) || 0, v: Number(row.v) || 0 });
  return map;
}

interface StockSchema {
  warehouses: boolean;
  warehouse: boolean;
  expiry: boolean;
  halted: boolean;
  reservations: boolean;
  locations: boolean;
}

function stockSchema(db: Database.Database): StockSchema {
  const featureOn = columnExistsSafe(db, 'settings', 'key') &&
    !!(db.prepare(`SELECT 1 FROM settings WHERE key = 'feature_batch_locations' AND value = '1'`).get());
  return {
    warehouses: columnExistsSafe(db, 'warehouses', 'warehouse_code'),
    warehouse: columnExistsSafe(db, 'stock_batches', 'warehouse_id'),
    expiry: columnExistsSafe(db, 'stock_batches', 'expiry_date'),
    halted: columnExistsSafe(db, 'stock_batches', 'halted'),
    reservations: columnExistsSafe(db, 'stock_reservations', 'batch_id'),
    locations: featureOn && columnExistsSafe(db, 'batch_stock_by_location', 'batch_id'),
  };
}

function findExpiredWarehouseId(schema: StockSchema, db: Database.Database): number {
  if (!schema.warehouses || !schema.warehouse) return -1;
  const row = db.prepare(
    `SELECT id FROM warehouses WHERE warehouse_code = 'EXPIRED' AND is_active = 1`,
  ).get() as { id: number } | undefined;
  return row?.id ?? -1;
}

function sellableBuckets(
  companyId: number,
  schema: StockSchema,
  expiredWarehouseId: number,
  db: Database.Database,
): Map<number, Bucket> {
  const sellableWhere = ['sb.quantity_remaining > 0'];
  if (schema.warehouse) sellableWhere.push('sb.warehouse_id <> @expiredWarehouseId');
  if (schema.expiry) sellableWhere.push(`(sb.expiry_date IS NULL OR date(sb.expiry_date) >= date('now', 'localtime'))`);
  if (schema.halted) sellableWhere.push('COALESCE(sb.halted, 0) = 0');
  const sellableParams = schema.warehouse ? { companyId, expiredWarehouseId } : { companyId };
  return bucketMap(db.prepare(`
    SELECT sb.item_id, SUM(sb.quantity_remaining) AS q, SUM(sb.quantity_remaining * sb.unit_cost) AS v
    FROM stock_batches sb JOIN items i ON i.id = sb.item_id
    WHERE i.company_id = @companyId AND ${sellableWhere.join(' AND ')}
    GROUP BY sb.item_id
  `).all(sellableParams) as AggregateRow[]);
}

function reservedBuckets(companyId: number, enabled: boolean, db: Database.Database): Map<number, Bucket> {
  if (!enabled) return new Map<number, Bucket>();
  return bucketMap(db.prepare(`
    SELECT sb.item_id, SUM(sr.quantity_reserved) AS q,
      SUM(sr.quantity_reserved * COALESCE(sb.unit_cost, 0)) AS v
    FROM stock_reservations sr JOIN stock_batches sb ON sb.id = sr.batch_id
    JOIN items i ON i.id = sb.item_id
    WHERE sr.status = 'ACTIVE' AND i.company_id = @companyId
    GROUP BY sb.item_id
  `).all({ companyId }) as AggregateRow[]);
}

function expiredBuckets(
  companyId: number,
  schema: StockSchema,
  expiredWarehouseId: number,
  db: Database.Database,
): Map<number, Bucket> {
  if (!schema.warehouses || !schema.warehouse) return new Map<number, Bucket>();
  return bucketMap(db.prepare(`
    SELECT sb.item_id, SUM(sb.quantity_remaining) AS q, SUM(sb.quantity_remaining * sb.unit_cost) AS v
    FROM stock_batches sb JOIN items i ON i.id = sb.item_id
    WHERE i.company_id = @companyId AND sb.quantity_remaining > 0
      AND sb.warehouse_id = @expiredWarehouseId
    GROUP BY sb.item_id
  `).all({ companyId, expiredWarehouseId }) as AggregateRow[]);
}

function damagedBuckets(companyId: number, enabled: boolean, db: Database.Database): Map<number, Bucket> {
  if (!enabled) return new Map<number, Bucket>();
  return bucketMap(db.prepare(`
    SELECT sb.item_id, SUM(bsl.quantity_physical) AS q, SUM(bsl.quantity_physical * sb.unit_cost) AS v
    FROM batch_stock_by_location bsl JOIN stock_batches sb ON sb.id = bsl.batch_id
    JOIN items i ON i.id = sb.item_id
    WHERE i.company_id = @companyId AND bsl.quantity_physical > 0
      AND bsl.status_override = 'DAMAGED'
    GROUP BY sb.item_id
  `).all({ companyId }) as AggregateRow[]);
}

export function getCompanyStock(companyId: number, page: number, limit: number, db: Database.Database) {
  const products = db.prepare(`
    SELECT id AS item_id, item_code, item_name, unit_of_measure
    FROM items WHERE company_id = ? ORDER BY item_name, id
  `).all(companyId) as Array<Omit<CompanyStockRow, 'quantity' | 'stock_value'>>;

  const schema = stockSchema(db);
  const expiredWarehouseId = findExpiredWarehouseId(schema, db);
  const sellable = sellableBuckets(companyId, schema, expiredWarehouseId, db);
  const reserved = reservedBuckets(companyId, schema.reservations, db);
  const expired = expiredBuckets(companyId, schema, expiredWarehouseId, db);
  const damaged = damagedBuckets(companyId, schema.locations, db);

  const zero: Bucket = { q: 0, v: 0 };
  const rows: CompanyStockRow[] = products.map(product => {
    const sellableBucket = sellable.get(product.item_id) ?? zero;
    const reservedBucket = reserved.get(product.item_id) ?? zero;
    const expiredBucket = expired.get(product.item_id) ?? zero;
    const damagedBucket = damaged.get(product.item_id) ?? zero;
    return {
      ...product,
      quantity: Math.round(
        (sellableBucket.q - reservedBucket.q + expiredBucket.q + damagedBucket.q) * 100,
      ) / 100,
      stock_value: Math.round(
        (sellableBucket.v - reservedBucket.v + expiredBucket.v + damagedBucket.v) * 100,
      ) / 100,
    };
  });

  const quantities: Record<string, number> = Object.create(null) as Record<string, number>;
  for (const row of rows) quantities[row.unit_of_measure] = (quantities[row.unit_of_measure] ?? 0) + row.quantity;
  return {
    company_id: companyId,
    as_of: new Date().toISOString(),
    valuation_basis: 'remaining_batch_cost',
    rows: rows.slice((page - 1) * limit, page * limit),
    totals: {
      stock_value: Math.round(rows.reduce((sum, row) => sum + row.stock_value, 0) * 100) / 100,
      quantities_by_uom: quantities,
    },
    pagination: { page, limit, total: rows.length, totalPages: Math.ceil(rows.length / limit) },
  };
}
