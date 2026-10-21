import { Request } from 'express';

// ============ Auth Types ============
export interface AuthUser {
  id: number;
  username: string;
  email?: string;
  role: string;
}

export interface AuthRequest extends Request {
  user?: AuthUser;
}

// ============ Invoice Types ============
export type InvoiceStatus =
  | 'Draft'
  | 'Sent'
  | 'Unpaid'
  | 'Partially Paid'
  | 'Paid'
  | 'Overdue'
  | 'Cancelled'
  | 'Returned'
  | 'Partially Returned';

export interface InvoiceItemDTO {
  item_id: number;
  description?: string;
  quantity: number;
  unit_price: number;
  tax_rate?: number;
  discount_type?: 'flat' | 'percentage';
  discount_value?: number;
  warehouse_id?: number;
  /** Loose amount-driven lines: the entered bill amount is the line's
   * gross base (sales form flip model §5.2); otherwise qty × unit_price. */
  amount?: number;
}

export interface PaymentDTO {
  payment_date: string;
  amount: number;
  payment_method: string;
  reference_no?: string;
  notes?: string;
}

export interface CreateInvoiceDTO {
  invoice_no?: string;
  customer_id: number;
  invoice_date: string;
  due_date: string;
  status?: InvoiceStatus;
  discount_scope?: 'item' | 'invoice';
  discount_type?: 'flat' | 'percentage';
  discount_value?: number;
  items: InvoiceItemDTO[];
  notes?: string;
  terms?: string;
  total_amount: number;
  record_payment?: boolean;
  payment?: PaymentDTO;
  credit_offset?: number;
}

export interface Invoice {
  id: number;
  invoice_no: string;
  customer_id: number;
  customer_name?: string;
  invoice_date: string;
  due_date: string;
  status: InvoiceStatus;
  total_amount: number;
  paid_amount: number;
  balance_amount: number;
  credit_offset?: number;
  discount_scope?: string;
  discount_type?: string;
  discount_value?: number;
  notes?: string;
  terms?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
  deleted_at?: string | null;
  deleted_by?: number | null;
  deleted_from_status?: string | null;
  deleted_from_payment_status?: string | null;
  deleted_from_return_status?: string | null;
}

// ============ API Response Types ============

// ============ Forecast Types ============

/** Supported forecast model types */
export type ForecastModelType =
  | 'weighted_moving_average'
  | 'simple_exponential_smoothing'
  | 'holts_linear_trend'
  | 'holt_winters'
  | 'arima';

/** Reorder recommendation levels */
export type RecommendationLevel = 'order_now' | 'order_soon' | 'monitor' | 'adequate';

/** Trend directions */
export type TrendDirection = 'growing' | 'stable' | 'declining';

/** Forecast periods */
export type ForecastPeriod = 'next_week' | 'next_month' | 'next_quarter';

/** Per-item config for model selection */
export interface ForecastModelConfig {
  id: number;
  item_id: number | null;
  category: string | null;
  model_type: ForecastModelType;
  ses_alpha: number | null;
  holt_alpha: number | null;
  holt_beta: number | null;
  hw_alpha: number | null;
  hw_beta: number | null;
  hw_gamma: number | null;
  seasonal_periods: number;
  service_level: number;
  lead_time_days: number;
  bias_correction: number;
  created_at: string;
  updated_at: string;
}

/** A seasonal calendar event */
export interface SeasonalEvent {
  id: number;
  event_name: string;
  start_date: string;
  end_date: string;
  multiplier: number;
  applies_to_category: string | null;
  applies_to_item_id: number | null;
  is_recurring: number;
  created_at: string;
}

/** Enhanced forecast result returned by the service */
export interface ForecastResult {
  itemId: number;
  itemCode: string;
  itemName: string;
  category: string;
  currentStock: number;
  predictedDemand: {
    nextWeek: number;
    nextMonth: number;
    nextQuarter: number;
  };
  trend: TrendDirection;
  trendPercentage: number;
  confidence: number;
  recommendation: RecommendationLevel;
  modelType: ForecastModelType;
  safetyStock: number;
  reorderPoint: number;
  biasAdjustment: number | null;
  seasonalMultiplier: number | null;
  isOverride: boolean;
  lastUpdated: string;
}

/** Dashboard summary data */
export interface ForecastDashboardData {
  summary: {
    totalItems: number;
    itemsNeedingRestock: number;
    avgConfidence: number;
    criticalAlerts: number;
    avgAccuracy: number | null;
    modelDistribution: Record<string, number>;
  };
  alerts: ForecastAlert[];
  topGrowing: ForecastResult[];
  topDeclining: ForecastResult[];
}

/** Alert for items needing attention */
export interface ForecastAlert {
  itemId: number;
  itemName: string;
  currentStock: number;
  predictedDemand: number;
  safetyStock: number;
  alertLevel: 'critical' | 'warning' | 'monitor' | 'adequate';
  recommendation: string;
}

/** Monthly data point for trend charts */
export interface MonthlySaleData {
  month: string;
  actual: number | null;
  predicted: number | null;
  movingAvg?: number | null;
}

/** Trend data response */
export interface TrendData {
  historicalTrends: MonthlySaleData[];
  itemBreakdown: {
    itemName: string;
    totalSold: number;
    trend: TrendDirection;
  }[];
}

/** Accuracy summary for an item */
export interface ItemAccuracy {
  itemId: number;
  itemName: string;
  itemCode: string;
  mape: number | null;
  mae: number | null;
  smape: number | null;
  sampleSize: number;
  modelType: string;
  trend: TrendDirection;
}

/** Accuracy data point for charts */
export interface AccuracyDataPoint {
  forecastDate: string;
  period: ForecastPeriod;
  predicted: number;
  actual: number | null;
  mape: number | null;
  mae: number | null;
}

/** Forecast override request */
export interface ForecastOverrideRequest {
  itemId: number;
  nextWeek?: number;
  nextMonth?: number;
  nextQuarter?: number;
  reason?: string;
  expiresDays?: number;
}

/** Safety stock result for an item */
export interface SafetyStockResult {
  itemId: number;
  itemName: string;
  itemCode: string;
  dailyDemand: number;
  demandStdDev: number;
  leadTimeDays: number;
  serviceLevel: number;
  zScore: number;
  safetyStock: number;
  reorderPoint: number;
  currentStock: number;
}

// ============ Stock Balance Types ============
export interface StockBalance {
  id: number;
  item_id: number;
  warehouse_id: number;
  quantity: number;
  last_updated: string;
}

// ============ Sales Order Types ============
export interface SalesOrder {
  id: number;
  so_no: string;
  customer_id: number;
  customer_name?: string;
  warehouse_id: number;
  order_date: string;
  expected_delivery_date?: string;
  status: 'Draft' | 'Confirmed' | 'Partial' | 'Completed' | 'Cancelled';
  total_amount: number;
  discount_scope?: 'item' | 'invoice';
  discount_type?: 'flat' | 'percentage';
  discount_value?: number;
  notes?: string;
  terms?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
  source_id?: number;
  source_type?: string;
}

export interface SalesOrderWithWarehouse extends SalesOrder {
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_username?: string;
}

// ============ Quotation Types ============
export interface Quotation {
  id: number;
  quotation_no: string;
  customer_id: number;
  customer_name?: string;
  warehouse_id: number;
  quotation_date: string;
  valid_until?: string;
  status: 'Draft' | 'Sent' | 'Accepted' | 'Rejected' | 'Expired';
  total_amount: number;
  discount_scope?: 'item' | 'invoice';
  discount_type?: 'flat' | 'percentage';
  discount_value?: number;
  notes?: string;
  terms?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
  source_id?: number;
  source_type?: string;
}

export interface QuotationWithWarehouse extends Quotation {
  warehouse_code?: string;
  warehouse_name?: string;
  created_by_username?: string;
}

// ============ Invoice Types (Extended) ============
export interface InvoiceWithUsername extends Invoice {
  created_by_username?: string;
}

// ============ Activity Log Types ============
export interface ActivityLogDbEntry {
  id: number;
  user_id: number | null;
  username?: string;
  action: string;
  entity_type: string;
  entity_id: number | null;
  description: string;
  metadata: string | null;
  ip_address: string | null;
  created_at: string;
}

// ============ Sellable Stock Errors ============

/**
 * Thrown when a sale line cannot be satisfied from sellable (non-expired,
 * non-halted, ACTIVE) batches. Controllers map this to HTTP 400 so the
 * client sees which item fell short and by how much.
 */
export class SellableStockUnavailableError extends Error {
  public readonly itemName: string;
  public readonly requestedQty: number;
  public readonly sellableQty: number;

  constructor(itemName: string, requestedQty: number, sellableQty: number) {
    super(
      `${itemName}: sellable stock ${sellableQty}, requested ${requestedQty} ` +
        `(expired, halted, or location-blocked batches are excluded from sale)`
    );
    this.name = 'SellableStockUnavailableError';
    this.itemName = itemName;
    this.requestedQty = requestedQty;
    this.sellableQty = sellableQty;
  }
}
