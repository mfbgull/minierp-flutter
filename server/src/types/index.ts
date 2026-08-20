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

// ============ Customer Types ============
export interface Customer {
  id: number;
  customer_name: string;
  email?: string;
  phone?: string;
  billing_address?: string;
  shipping_address?: string;
  credit_limit?: number;
  created_at?: string;
  updated_at?: string;
}

export interface CreateCustomerDTO {
  customer_name: string;
  email?: string;
  phone?: string;
  billing_address?: string;
  shipping_address?: string;
  credit_limit?: number;
}

// ============ Item Types ============
export interface Item {
  id: number;
  item_code: string;
  item_name: string;
  description?: string;
  category?: string;
  unit_of_measure: string;
  current_stock: number;
  reorder_level?: number;
  standard_selling_price?: number;
  standard_cost?: number;
  is_raw_material: boolean;
  is_finished_good: boolean;
  is_purchased: boolean;
  has_expiry?: boolean;
  near_expiry_threshold_days?: number;
  created_at?: string;
  updated_at?: string;
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
  discount_scope?: string;
  discount_type?: string;
  discount_value?: number;
  notes?: string;
  terms?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
}

// ============ BOM Types ============
export interface BOMItemDTO {
  item_id: number;
  quantity: number;
}

export interface CreateBOMDTO {
  bom_name: string;
  finished_item_id: number;
  quantity: number;
  description?: string;
  items: BOMItemDTO[];
}

export interface BOM {
  id: number;
  bom_no: string;
  bom_name: string;
  finished_item_id: number;
  finished_item_name?: string;
  quantity: number;
  description?: string;
  is_active: boolean;
  created_at?: string;
  updated_at?: string;
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

/** Base demand_forecasts row from DB */
export interface DemandForecast {
  id: number;
  item_id: number;
  forecast_date: string;
  period: ForecastPeriod;
  predicted_quantity: number;
  confidence_level: number;
  trend_direction: TrendDirection;
  trend_percentage: number;
  model_type: string;
  is_manual_override: number;
  override_reason: string | null;
  override_expires: string | null;
  bias_adjustment: number | null;
  seasonal_multiplier: number | null;
  run_id: string | null;
  created_at: string;
  updated_at: string;
}

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

/** Forecast accuracy record */
export interface ForecastAccuracy {
  id: number;
  forecast_date: string;
  item_id: number;
  period: ForecastPeriod;
  model_type: string;
  predicted_quantity: number;
  actual_quantity: number | null;
  mape: number | null;
  mae: number | null;
  smape: number | null;
  is_override: number;
  computed_at: string | null;
  created_at: string;
}

/** Track a forecast run */
export interface ForecastRun {
  id: number;
  run_id: string;
  run_type: 'auto' | 'manual' | 'scheduled';
  started_at: string;
  completed_at: string | null;
  items_processed: number;
  errors: number;
  status: 'running' | 'completed' | 'failed';
  error_message: string | null;
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

/** ABC classification for items */
export interface ABCClassification {
  itemId: number;
  itemName: string;
  annualValue: number;
  class: 'A' | 'B' | 'C';
}

// ============ Stock Balance Types ============
export interface StockBalance {
  id: number;
  item_id: number;
  warehouse_id: number;
  quantity: number;
  last_updated: string;
}

// ============ Warehouse Types ============
export interface Warehouse {
  id: number;
  warehouse_code: string;
  warehouse_name: string;
  location?: string;
  created_at?: string;
  updated_at?: string;
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

// ============ Integration Service Types ============
export interface Setting {
  key: string;
  value: string;
}

export interface TaxRate {
  rate: number;
  state?: string;
  zip?: string;
  country?: string;
  name?: string;
}

export interface TaxCalculation {
  amount: number;
  rate: number;
  tax: number;
  jurisdiction: string;
}

export interface TaxJarResponse {
  error?: string;
  tax?: TaxCalculation;
  validation?: any;
  categories?: Array<{ name: string }>;
}

export interface FixerResponse {
  success?: boolean;
  error?: { info: string };
  base?: string;
  date?: string;
  rates?: Record<string, number>;
}

export interface WeatherResponse {
  error?: { info: string };
  main?: { temp: number; humidity: number };
  weather?: Array<{ description: string }>;
  name?: string;
}

export interface NotificationResponse {
  success?: boolean;
  message?: string;
}

export interface EmailResponse {
  success?: boolean;
  message?: string;
  messageId?: string;
}

export interface NumverifyResponse {
  success?: boolean;
  valid?: boolean;
  error?: { info: string };
  number?: {
    country_code: string;
    country_name: string;
    location: string;
    carrier: string;
    line_type: string;
  };
}

// ============ Batch Costing Types ============
export interface StockBatch {
  id: number;
  batch_no: string;
  item_id: number;
  warehouse_id: number;
  source_type: 'PRODUCTION' | 'PURCHASE';
  source_id: number;
  quantity_original: number;
  quantity_remaining: number;
  unit_cost: number;
  received_date: string;
  expiry_date?: string | null;
  halted?: boolean;
  halted_reason?: string | null;
  created_at?: string;
  // Joined fields
  item_code?: string;
  item_name?: string;
  warehouse_code?: string;
  warehouse_name?: string;
  source_no?: string; // production_no or purchase_no
}

export interface BatchSummary {
  batch_no: string;
  item_id: number;
  item_code: string;
  item_name: string;
  warehouse_name: string;
  source_type: string;
  source_no: string;
  quantity_original: number;
  quantity_remaining: number;
  unit_cost: number;
  total_value: number;
  received_date: string;
  expiry_date?: string | null;
  halted?: boolean;
  halted_reason?: string | null;
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

export interface ActivityStat {
  action?: string;
  count?: number;
  username?: string;
  date?: string;
}
