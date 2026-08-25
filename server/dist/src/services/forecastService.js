"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateAllForecasts = generateAllForecasts;
exports.getOrGenerateForecasts = getOrGenerateForecasts;
exports.getDashboardData = getDashboardData;
exports.getTrendData = getTrendData;
exports.computeForecastAccuracy = computeForecastAccuracy;
exports.getAccuracy = getAccuracy;
exports.getAccuracyTimeSeries = getAccuracyTimeSeries;
exports.applyOverride = applyOverride;
exports.getModelConfig = getModelConfig;
exports.setModelConfig = setModelConfig;
exports.getSeasonalEvents = getSeasonalEvents;
exports.createSeasonalEvent = createSeasonalEvent;
exports.deleteSeasonalEvent = deleteSeasonalEvent;
exports.getSafetyStock = getSafetyStock;
exports.getForecastsForExport = getForecastsForExport;
exports.getForecastRuns = getForecastRuns;
const database_1 = __importDefault(require("../config/database"));
// ============================================================
// 1. CONFIG & HELPERS
// ============================================================
/** Default lead time in days when no config exists */
const DEFAULT_LEAD_TIME = 7;
/** Default service level (95%) */
const DEFAULT_SERVICE_LEVEL = 0.95;
/** Number of trailing months to use for bias calculation */
const BIAS_WINDOW_MONTHS = 3;
/** Minimum data points needed for forecast */
const MIN_DATA_POINTS = 2;
/**
 * Load model config for a given item. Falls back: item-specific → category → default.
 */
function loadModelConfig(item) {
    // Try item-specific first
    const itemConfig = database_1.default.prepare(`
    SELECT * FROM forecast_model_config WHERE item_id = ?
  `).get(item.id);
    if (itemConfig)
        return itemConfig;
    // Try category-based
    if (item.category) {
        const catConfig = database_1.default.prepare(`
      SELECT * FROM forecast_model_config WHERE category = ?
    `).get(item.category);
        if (catConfig)
            return catConfig;
    }
    // Return default
    return {
        id: 0,
        item_id: null,
        category: null,
        model_type: 'weighted_moving_average',
        ses_alpha: null,
        holt_alpha: null,
        holt_beta: null,
        hw_alpha: null,
        hw_beta: null,
        hw_gamma: null,
        seasonal_periods: 12,
        service_level: DEFAULT_SERVICE_LEVEL,
        lead_time_days: DEFAULT_LEAD_TIME,
        bias_correction: 1,
        created_at: '',
        updated_at: ''
    };
}
/**
 * Get seasonal multipliers active for a given date and item/category.
 * For recurring events, shifts the event window to the current year.
 * Returns 1.0 if no events match.
 */
function getSeasonalMultiplier(dateStr, item) {
    const currentYear = new Date().getFullYear();
    // For non-recurring events, check as-is
    const nonRecurringEvents = database_1.default.prepare(`
    SELECT multiplier FROM forecast_seasonal_events
    WHERE is_recurring = 0
      AND start_date <= ? AND end_date >= ?
      AND (applies_to_item_id IS NULL OR applies_to_item_id = ?)
      AND (applies_to_category IS NULL OR applies_to_category = ?)
  `).all(dateStr, dateStr, item.id, item.category || '');
    // For recurring events, adjust dates to current year
    const recurringEvents = database_1.default.prepare(`
    SELECT event_name, start_date, end_date, multiplier
    FROM forecast_seasonal_events
    WHERE is_recurring = 1
      AND (applies_to_item_id IS NULL OR applies_to_item_id = ?)
      AND (applies_to_category IS NULL OR applies_to_category = ?)
  `).all(item.id, item.category || '');
    let multiplier = 1.0;
    // Apply non-recurring events
    for (const e of nonRecurringEvents) {
        multiplier *= e.multiplier;
    }
    // Apply recurring events with year-shifted dates
    for (const e of recurringEvents) {
        // Shift the event window to the current year
        const shiftedStart = `${currentYear}-${e.start_date.slice(5)}`;
        const shiftedEnd = `${currentYear}-${e.end_date.slice(5)}`;
        if (dateStr >= shiftedStart && dateStr <= shiftedEnd) {
            multiplier *= e.multiplier;
        }
    }
    return multiplier;
}
// ============================================================
// 2. FORECASTING ALGORITHMS
// ============================================================
/**
 * Weighted Moving Average — retains existing behavior.
 * Sales data in ASC order (oldest first).
 * Uses the most recent 3 periods with weights [0.5, 0.3, 0.2].
 */
function calculateWMA(sales) {
    if (sales.length === 0)
        return 0;
    if (sales.length === 1)
        return sales[0];
    const weights = [0.5, 0.3, 0.2];
    let sum = 0;
    let weightSum = 0;
    const count = Math.min(sales.length, 3);
    for (let i = 0; i < count; i++) {
        const idx = sales.length - 1 - i;
        sum += sales[idx] * weights[i];
        weightSum += weights[i];
    }
    return sum / weightSum;
}
/**
 * Simple Exponential Smoothing (SES).
 * Uses alpha (default 0.3) to smooth the time series.
 * Forecast = last smoothed value.
 */
function calculateSES(sales, alpha = 0.3) {
    if (sales.length === 0)
        return 0;
    if (sales.length === 1)
        return sales[0];
    let smoothed = sales[0];
    for (let i = 1; i < sales.length; i++) {
        smoothed = alpha * sales[i] + (1 - alpha) * smoothed;
    }
    return smoothed;
}
/**
 * Holt's Linear Trend (Double Exponential Smoothing).
 * Uses alpha (level) and beta (trend).
 * Produces a forecast that extends linearly.
 */
function calculateHolts(sales, alpha = 0.3, beta = 0.1) {
    if (sales.length === 0)
        return 0;
    if (sales.length === 1)
        return sales[0];
    let level = sales[0];
    let trend = sales.length > 1 ? sales[1] - sales[0] : 0;
    for (let i = 1; i < sales.length; i++) {
        const newLevel = alpha * sales[i] + (1 - alpha) * (level + trend);
        const newTrend = beta * (newLevel - level) + (1 - beta) * trend;
        level = newLevel;
        trend = newTrend;
    }
    // 1-step ahead forecast
    return level + trend;
}
/**
 * Holt-Winters Seasonal (Triple Exponential Smoothing).
 * Adds a seasonal component to Holt's.
 * Assumes seasonal_periods (e.g., 12 for monthly data).
 * Returns the next period forecast.
 */
function calculateHoltWinters(sales, seasonalPeriods = 12, alpha = 0.3, beta = 0.1, gamma = 0.1) {
    if (sales.length === 0)
        return 0;
    if (sales.length < seasonalPeriods) {
        // Fall back to Holt's if not enough data for seasonality
        return calculateHolts(sales, alpha, beta);
    }
    // Initialize seasonals with first full cycle
    const seasonals = [];
    const initialLevel = sales.slice(0, seasonalPeriods).reduce((a, b) => a + b, 0) / seasonalPeriods;
    for (let i = 0; i < seasonalPeriods; i++) {
        seasonals.push(sales[i] / initialLevel);
    }
    let level = initialLevel;
    let trend = 0;
    // Estimate initial trend
    const secondCycle = sales.slice(seasonalPeriods, Math.min(seasonalPeriods * 2, sales.length));
    if (secondCycle.length >= seasonalPeriods / 2) {
        const secondAvg = secondCycle.reduce((a, b) => a + b, 0) / secondCycle.length;
        trend = (secondAvg - initialLevel) / seasonalPeriods;
    }
    // Run through data
    for (let i = 0; i < sales.length; i++) {
        const seasonalIdx = i % seasonalPeriods;
        const oldLevel = level;
        const seasonal = seasonals[seasonalIdx];
        level = alpha * (sales[i] / seasonal) + (1 - alpha) * (level + trend);
        trend = beta * (level - oldLevel) + (1 - beta) * trend;
        seasonals[seasonalIdx] = gamma * (sales[i] / level) + (1 - gamma) * seasonal;
    }
    // 1-step ahead forecast
    return (level + trend) * seasonals[sales.length % seasonalPeriods];
}
/**
 * Simplified ARIMA — approximates with AR(1) + differencing.
 * For real ARIMA, you'd use a stats library. This gives a reasonable
 * approximation for basic time series with trend.
 * Uses: first-order differencing + AR(1) coefficient estimate.
 */
function calculateSimpleARIMA(sales) {
    if (sales.length === 0)
        return 0;
    if (sales.length < 3)
        return calculateWMA(sales);
    // Difference the series
    const diffs = [];
    for (let i = 1; i < sales.length; i++) {
        diffs.push(sales[i] - sales[i - 1]);
    }
    // Estimate AR(1) coefficient via simple regression
    // φ = sum((x_{t-1} - μ)(x_t - μ)) / sum((x_{t-1} - μ)^2)
    const mean = diffs.reduce((a, b) => a + b, 0) / diffs.length;
    let num = 0, den = 0;
    for (let i = 1; i < diffs.length; i++) {
        num += (diffs[i - 1] - mean) * (diffs[i] - mean);
        den += (diffs[i - 1] - mean) ** 2;
    }
    const phi = den > 0 ? num / den : 0;
    // Forecast next differenced value
    const lastDiff = diffs[diffs.length - 1];
    const nextDiff = mean + phi * (lastDiff - mean);
    // Undo differencing
    const forecast = sales[sales.length - 1] + nextDiff;
    return Math.max(0, forecast); // Can't have negative demand
}
/**
 * Auto-select the best model based on past accuracy (lowest MAPE).
 * If no accuracy data, returns the configured model type.
 */
function autoSelectModel(itemId, configuredModel) {
    const accuracyData = database_1.default.prepare(`
    SELECT model_type, AVG(mape) as avg_mape, COUNT(*) as samples
    FROM forecast_accuracy
    WHERE item_id = ? AND mape IS NOT NULL
    GROUP BY model_type
    ORDER BY avg_mape ASC
    LIMIT 1
  `).get(itemId);
    if (accuracyData && accuracyData.samples >= 3) {
        return accuracyData.model_type;
    }
    return configuredModel;
}
/**
 * Run the selected forecast model on the sales data.
 * Sales data in ASC order (oldest first).
 */
function runModel(modelType, sales, config) {
    let forecast;
    switch (modelType) {
        case 'weighted_moving_average':
            forecast = calculateWMA(sales);
            break;
        case 'simple_exponential_smoothing':
            forecast = calculateSES(sales, config.ses_alpha ?? 0.3);
            break;
        case 'holts_linear_trend':
            forecast = calculateHolts(sales, config.holt_alpha ?? 0.3, config.holt_beta ?? 0.1);
            break;
        case 'holt_winters':
            forecast = calculateHoltWinters(sales, config.seasonal_periods ?? 12, config.hw_alpha ?? 0.3, config.hw_beta ?? 0.1, config.hw_gamma ?? 0.1);
            break;
        case 'arima':
            forecast = calculateSimpleARIMA(sales);
            break;
        default:
            forecast = calculateWMA(sales);
    }
    forecast = Math.max(0, forecast);
    // Calculate confidence based on model fit (coefficient of variation)
    const confidence = calculateConfidence(sales);
    return { forecast, confidence };
}
// ============================================================
// 3. TREND DETECTION (unchanged from original)
// ============================================================
function detectTrend(sales) {
    if (sales.length === 0) {
        return { direction: 'stable', percentage: 0 };
    }
    if (sales.length < 3) {
        return { direction: 'stable', percentage: 0 };
    }
    const recent = sales.slice(-3);
    const oldest = recent[0];
    const newest = recent[recent.length - 1];
    if (oldest === 0) {
        if (newest > 0)
            return { direction: 'growing', percentage: 100 };
        return { direction: 'stable', percentage: 0 };
    }
    const change = ((newest - oldest) / oldest) * 100;
    if (change > 5)
        return { direction: 'growing', percentage: Math.round(change * 10) / 10 };
    if (change < -5)
        return { direction: 'declining', percentage: Math.round(change * 10) / 10 };
    return { direction: 'stable', percentage: Math.round(change * 10) / 10 };
}
function calculateConfidence(sales) {
    if (sales.length < 3)
        return 50;
    const mean = sales.reduce((a, b) => a + b, 0) / sales.length;
    if (mean === 0)
        return 50;
    const squaredDiffs = sales.map(v => Math.pow(v - mean, 2));
    const variance = squaredDiffs.reduce((a, b) => a + b, 0) / sales.length;
    const stdDev = Math.sqrt(variance);
    const cv = stdDev / mean;
    if (cv < 0.15)
        return 90;
    if (cv < 0.30)
        return 70;
    return 50;
}
// ============================================================
// 4. BIAS CORRECTION & AUTO-LEARNING
// ============================================================
/**
 * Calculate bias factor for an item from recent forecast accuracy.
 * Returns a value between -1 and 1 where:
 *   positive = model over-estimates (actual < predicted)
 *   negative = model under-estimates (actual > predicted)
 * Returns null if insufficient data.
 */
function calculateBiasFactor(itemId) {
    const biasData = database_1.default.prepare(`
    SELECT AVG((actual_quantity - predicted_quantity) / NULLIF(predicted_quantity, 0)) as bias
    FROM forecast_accuracy
    WHERE item_id = ?
      AND actual_quantity IS NOT NULL
      AND computed_at >= date('now', '-${BIAS_WINDOW_MONTHS} months')
      AND mape IS NOT NULL
  `).get(itemId);
    if (!biasData || biasData.bias === null)
        return null;
    // Clamp to reasonable range
    return Math.max(-0.5, Math.min(0.5, biasData.bias));
}
// ============================================================
// 5. SAFETY STOCK CALCULATION
// ============================================================
/**
 * Safety Stock = Z × √(LT) × σ_daily
 * Simplified formula that assumes constant lead time (lead time variability = 0).
 * The full formula would be: Z × √(LT × σ²_demand + σ²_LT × D²)
 * Where σ²_LT = variance of lead time (defaults to 0 until data is available).
 *
 *   Z = z-score for target service level
 *   LT = lead time in days
 *   σ_daily = standard deviation of daily demand
 */
function calculateSafetyStock(sales, leadTimeDays, serviceLevel) {
    // Z-scores for common service levels
    const zScores = {
        0.90: 1.28,
        0.95: 1.65,
        0.975: 1.96,
        0.99: 2.33
    };
    // Find nearest z-score
    const keys = Object.keys(zScores).map(Number).sort((a, b) => a - b);
    let zScore = zScores[0.95]; // default
    for (const k of keys) {
        if (serviceLevel <= k) {
            zScore = zScores[k];
            break;
        }
    }
    // Monthly sales → daily demand
    const monthlyAvg = sales.length > 0
        ? sales.reduce((a, b) => a + b, 0) / sales.length
        : 0;
    const dailyDemand = monthlyAvg / 30;
    // Standard deviation of monthly demand (converted to daily)
    let demandStdDev = 0;
    if (sales.length >= 2) {
        const mean = sales.reduce((a, b) => a + b, 0) / sales.length;
        const variance = sales.reduce((sum, v) => sum + (v - mean) ** 2, 0) / (sales.length - 1);
        demandStdDev = Math.sqrt(variance) / Math.sqrt(30); // convert to daily
    }
    const safetyStock = Math.round(zScore * Math.sqrt(leadTimeDays) * demandStdDev);
    const reorderPoint = Math.round(dailyDemand * leadTimeDays + safetyStock);
    return { safetyStock, reorderPoint, dailyDemand: Math.round(dailyDemand * 100) / 100, demandStdDev: Math.round(demandStdDev * 100) / 100, zScore };
}
// ============================================================
// 6. RECOMMENDATION LOGIC (enhanced)
// ============================================================
function getRecommendation(currentStock, predictedDemand, safetyStock, reorderPoint) {
    if (predictedDemand <= 0)
        return 'monitor';
    // Enhanced: compare stock against reorder point
    if (currentStock <= reorderPoint)
        return 'order_now';
    const warningLevel = reorderPoint * 1.3;
    if (currentStock <= warningLevel)
        return 'order_soon';
    const ratio = currentStock / predictedDemand;
    if (ratio < 1.0)
        return 'monitor';
    return 'adequate';
}
// ============================================================
// 7. BATCH DATA FETCHING
// ============================================================
function getAllHistoricalSales(itemIds) {
    if (itemIds.length === 0)
        return new Map();
    const placeholders = itemIds.map(() => '?').join(',');
    const results = database_1.default.prepare(`
    SELECT
      ii.item_id,
      strftime('%Y-%m', i.invoice_date) as month,
      SUM(ii.quantity) as total_quantity
    FROM invoice_items ii
    JOIN invoices i ON i.id = ii.invoice_id
    WHERE ii.item_id IN (${placeholders})
      AND i.invoice_date >= date('now', '-12 months')
      AND i.status != 'Cancelled'
    GROUP BY ii.item_id, strftime('%Y-%m', i.invoice_date)
    ORDER BY ii.item_id, month ASC
  `).all(...itemIds);
    const salesMap = new Map();
    for (const r of results) {
        if (!salesMap.has(r.item_id)) {
            salesMap.set(r.item_id, []);
        }
        salesMap.get(r.item_id).push(r.total_quantity);
    }
    for (const id of itemIds) {
        if (!salesMap.has(id)) {
            salesMap.set(id, []);
        }
    }
    return salesMap;
}
// ============================================================
// 8. BUILD ITEM FORECAST (enhanced)
// ============================================================
function buildItemForecast(item, sales, config) {
    const modelType = config.bias_correction
        ? autoSelectModel(item.id, config.model_type)
        : config.model_type;
    // Run the model
    const { forecast: monthlyAvg, confidence } = runModel(modelType, sales, config);
    // Apply seasonal multiplier
    const today = new Date().toISOString().split('T')[0];
    const seasonalMultiplier = getSeasonalMultiplier(today, item);
    // Apply bias correction
    let biasAdjustment = null;
    let adjustedForecast = monthlyAvg * seasonalMultiplier;
    if (config.bias_correction) {
        const biasFactor = calculateBiasFactor(item.id);
        if (biasFactor !== null) {
            biasAdjustment = Math.round(biasFactor * 100); // Store as percentage
            adjustedForecast = adjustedForecast * (1 - biasFactor);
        }
    }
    adjustedForecast = Math.max(0, adjustedForecast);
    // Compute time horizons
    const nextWeek = Math.round(adjustedForecast / 4);
    const nextMonth = Math.round(adjustedForecast);
    const nextQuarter = Math.round(adjustedForecast * 3);
    const { direction, percentage } = detectTrend(sales);
    // Safety stock
    const { safetyStock, reorderPoint } = calculateSafetyStock(sales, config.lead_time_days, config.service_level);
    const recommendation = getRecommendation(item.current_stock, nextMonth, safetyStock, reorderPoint);
    return {
        itemId: item.id,
        itemCode: item.item_code,
        itemName: item.item_name,
        category: item.category || 'Uncategorized',
        currentStock: item.current_stock,
        predictedDemand: { nextWeek, nextMonth, nextQuarter },
        trend: direction,
        trendPercentage: percentage,
        confidence,
        recommendation,
        modelType,
        safetyStock,
        reorderPoint,
        biasAdjustment,
        seasonalMultiplier,
        isOverride: false,
        lastUpdated: today
    };
}
// ============================================================
// 9. CACHING (read/write demand_forecasts + forecast_accuracy)
// ============================================================
function saveForecastsToDb(forecasts, runId) {
    const today = new Date().toISOString().split('T')[0];
    // Clear old forecasts for today
    database_1.default.prepare('DELETE FROM demand_forecasts WHERE forecast_date = ?').run(today);
    const insert = database_1.default.prepare(`
    INSERT INTO demand_forecasts (
      item_id, forecast_date, period, predicted_quantity,
      confidence_level, trend_direction, trend_percentage,
      model_type, bias_adjustment, seasonal_multiplier, run_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
    const insertMany = database_1.default.transaction((items) => {
        for (const f of items) {
            const periods = [
                ['next_week', f.predictedDemand.nextWeek],
                ['next_month', f.predictedDemand.nextMonth],
                ['next_quarter', f.predictedDemand.nextQuarter]
            ];
            for (const [period, qty] of periods) {
                insert.run(f.itemId, today, period, qty, f.confidence, f.trend, f.trendPercentage, f.modelType, f.biasAdjustment, f.seasonalMultiplier, runId);
            }
        }
    });
    insertMany(forecasts);
    // Also save to forecast_accuracy for tracking
    saveForecastsToAccuracy(forecasts, runId);
}
/**
 * Save forecast predictions to forecast_accuracy table so they can be
 * compared against actuals later.
 */
function saveForecastsToAccuracy(forecasts, runId) {
    const today = new Date().toISOString().split('T')[0];
    const insert = database_1.default.prepare(`
    INSERT OR IGNORE INTO forecast_accuracy (
      forecast_date, item_id, period, model_type,
      predicted_quantity, is_override
    ) VALUES (?, ?, ?, ?, ?, ?)
  `);
    // Delete existing entries for today so we can re-insert
    database_1.default.prepare('DELETE FROM forecast_accuracy WHERE forecast_date = ?').run(today);
    const insertMany = database_1.default.transaction((items) => {
        for (const f of items) {
            insert.run(today, f.itemId, 'next_week', f.modelType, f.predictedDemand.nextWeek, f.isOverride ? 1 : 0);
            insert.run(today, f.itemId, 'next_month', f.modelType, f.predictedDemand.nextMonth, f.isOverride ? 1 : 0);
            insert.run(today, f.itemId, 'next_quarter', f.modelType, f.predictedDemand.nextQuarter, f.isOverride ? 1 : 0);
        }
    });
    insertMany(forecasts);
}
function readCachedForecasts() {
    const today = new Date().toISOString().split('T')[0];
    const cachedRows = database_1.default.prepare(`
    SELECT df.*, i.item_code, i.item_name, i.category, i.current_stock
    FROM demand_forecasts df
    JOIN items i ON i.id = df.item_id
    WHERE df.forecast_date = ?
    ORDER BY df.item_id, df.period
  `).all(today);
    if (cachedRows.length === 0)
        return null;
    const itemMap = new Map();
    for (const row of cachedRows) {
        if (!itemMap.has(row.item_id)) {
            const defaultLeadTime = DEFAULT_LEAD_TIME;
            itemMap.set(row.item_id, {
                itemId: row.item_id,
                itemCode: row.item_code,
                itemName: row.item_name,
                category: row.category || 'Uncategorized',
                currentStock: row.current_stock,
                predictedDemand: { nextWeek: 0, nextMonth: 0, nextQuarter: 0 },
                trend: row.trend_direction || 'stable',
                trendPercentage: row.trend_percentage || 0,
                confidence: row.confidence_level || 0,
                recommendation: 'monitor',
                modelType: row.model_type || 'weighted_moving_average',
                safetyStock: 0,
                reorderPoint: 0,
                biasAdjustment: row.bias_adjustment,
                seasonalMultiplier: row.seasonal_multiplier,
                isOverride: row.is_manual_override === 1,
                lastUpdated: today
            });
        }
        const item = itemMap.get(row.item_id);
        if (row.period === 'next_week')
            item.predictedDemand.nextWeek = Math.round(row.predicted_quantity);
        if (row.period === 'next_month')
            item.predictedDemand.nextMonth = Math.round(row.predicted_quantity);
        if (row.period === 'next_quarter')
            item.predictedDemand.nextQuarter = Math.round(row.predicted_quantity);
    }
    // Compute recommendation + safety stock for each cached item
    // Use the predicted demand to estimate daily demand and variability
    for (const item of itemMap.values()) {
        const config = loadModelConfig({
            id: item.itemId,
            category: item.category
        });
        // Estimate daily demand from the monthly prediction
        const estimatedDailyDemand = item.predictedDemand.nextMonth / 30;
        // Assume a default CV of 0.3 (moderate variability) when in cache mode
        const estimatedDailyStdDev = estimatedDailyDemand * 0.3;
        const leadTimeInDays = config.lead_time_days;
        const zScores = { 0.90: 1.28, 0.95: 1.65, 0.975: 1.96, 0.99: 2.33 };
        const keys = Object.keys(zScores).map(Number).sort((a, b) => a - b);
        let zScore = zScores[0.95];
        for (const k of keys) {
            if (config.service_level <= k) {
                zScore = zScores[k];
                break;
            }
        }
        const safetyStock = Math.round(zScore * Math.sqrt(leadTimeInDays) * estimatedDailyStdDev);
        const reorderPoint = Math.round(estimatedDailyDemand * leadTimeInDays + safetyStock);
        item.safetyStock = safetyStock;
        item.reorderPoint = reorderPoint;
        item.recommendation = getRecommendation(item.currentStock, item.predictedDemand.nextMonth, safetyStock, reorderPoint);
    }
    return Array.from(itemMap.values());
}
// ============================================================
// 10. MAIN FORECAST GENERATION
// ============================================================
/**
 * Generate a unique run ID for tracking.
 */
function generateRunId() {
    return `fc_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}
/**
 * Generate forecasts for all active items (expanded from only finished goods).
 */
function generateAllForecasts() {
    const runId = generateRunId();
    // Log the run
    database_1.default.prepare(`
    INSERT INTO forecast_runs (run_id, run_type, started_at, items_processed, status)
    VALUES (?, 'auto', datetime('now'), 0, 'running')
  `).run(runId);
    try {
        // EXPANDED: all active items instead of only finished goods
        const items = database_1.default.prepare(`
      SELECT id, item_code, item_name, category, current_stock
      FROM items
      WHERE is_active = 1
    `).all();
        const ids = items.map(i => i.id);
        const salesMap = getAllHistoricalSales(ids);
        const forecasts = items.map(item => {
            const config = loadModelConfig(item);
            const sales = salesMap.get(item.id) || [];
            return buildItemForecast(item, sales, config);
        });
        saveForecastsToDb(forecasts, runId);
        // Mark run as completed
        database_1.default.prepare(`
      UPDATE forecast_runs
      SET status = 'completed', items_processed = ?, completed_at = datetime('now')
      WHERE run_id = ?
    `).run(forecasts.length, runId);
        return forecasts;
    }
    catch (error) {
        database_1.default.prepare(`
      UPDATE forecast_runs
      SET status = 'failed', errors = errors + 1, error_message = ?, completed_at = datetime('now')
      WHERE run_id = ?
    `).run(String(error.message || error), runId);
        throw error;
    }
}
function getOrGenerateForecasts() {
    const cached = readCachedForecasts();
    if (cached)
        return cached;
    return generateAllForecasts();
}
// ============================================================
// 11. DASHBOARD DATA
// ============================================================
function getDashboardData() {
    const forecasts = getOrGenerateForecasts();
    // Compute model distribution
    const modelDistribution = {};
    for (const f of forecasts) {
        const m = f.modelType;
        modelDistribution[m] = (modelDistribution[m] || 0) + 1;
    }
    // Compute average accuracy from stored data
    const avgAccuracy = database_1.default.prepare(`
    SELECT AVG(mape) as avg_mape FROM forecast_accuracy
    WHERE mape IS NOT NULL AND computed_at >= date('now', '-30 days')
  `).get();
    const alerts = forecasts
        .filter(f => f.recommendation === 'order_now' || f.recommendation === 'order_soon')
        .map(f => ({
        itemId: f.itemId,
        itemName: f.itemName,
        currentStock: f.currentStock,
        predictedDemand: f.predictedDemand.nextMonth,
        safetyStock: f.safetyStock,
        alertLevel: f.recommendation === 'order_now' ? 'critical' : 'warning',
        recommendation: f.recommendation
    }))
        .sort((a, b) => {
        const ratioA = a.predictedDemand > 0 ? (a.currentStock - a.safetyStock) / a.predictedDemand : 0;
        const ratioB = b.predictedDemand > 0 ? (b.currentStock - b.safetyStock) / b.predictedDemand : 0;
        return ratioA - ratioB;
    });
    const criticalAlerts = alerts.filter(a => a.alertLevel === 'critical').length;
    const itemsNeedingRestock = alerts.length;
    const avgConfidence = forecasts.length > 0
        ? Math.round(forecasts.reduce((sum, f) => sum + f.confidence, 0) / forecasts.length)
        : 0;
    return {
        summary: {
            totalItems: forecasts.length,
            itemsNeedingRestock,
            avgConfidence,
            criticalAlerts,
            avgAccuracy: avgAccuracy?.avg_mape ?? null,
            modelDistribution
        },
        alerts,
        topGrowing: forecasts.filter(f => f.trend === 'growing').slice(0, 5),
        topDeclining: forecasts.filter(f => f.trend === 'declining').slice(0, 5)
    };
}
// ============================================================
// 12. TREND DATA (enhanced with seasonal decomposition)
// ============================================================
function getTrendData(itemId) {
    let items;
    if (itemId) {
        items = database_1.default.prepare('SELECT id, item_name FROM items WHERE id = ?').all(itemId);
    }
    else {
        items = database_1.default.prepare(`
      SELECT id, item_name FROM items
      WHERE is_active = 1
      LIMIT 10
    `).all();
    }
    const monthlySalesQuery = itemId
        ? `SELECT strftime('%Y-%m', i.invoice_date) as month, SUM(ii.quantity) as total
       FROM invoice_items ii
       JOIN invoices i ON i.id = ii.invoice_id
       WHERE ii.item_id = ? AND i.invoice_date >= date('now', '-12 months') AND i.status != 'Cancelled'
       GROUP BY month ORDER BY month ASC`
        : `SELECT strftime('%Y-%m', i.invoice_date) as month, SUM(ii.quantity) as total
       FROM invoice_items ii
       JOIN invoices i ON i.id = ii.invoice_id
       WHERE i.invoice_date >= date('now', '-12 months') AND i.status != 'Cancelled'
       GROUP BY month ORDER BY month ASC`;
    const monthlyData = itemId
        ? database_1.default.prepare(monthlySalesQuery).all(itemId)
        : database_1.default.prepare(monthlySalesQuery).all();
    // Historical data with moving average
    const historicalTrends = monthlyData.map(m => ({
        month: m.month,
        actual: m.total,
        predicted: null
    }));
    // Add 3-month moving average as trend line
    const totals = historicalTrends.map(t => t.actual || 0);
    for (let i = 2; i < historicalTrends.length; i++) {
        const window = totals.slice(i - 2, i + 1);
        historicalTrends[i].movingAvg = Math.round(calculateWMA(window));
    }
    // Add forecast for next month
    if (totals.length >= 3) {
        const nextMonthDate = getNextMonth(monthlyData[monthlyData.length - 1]?.month);
        const forecast = Math.round(calculateWMA(totals));
        historicalTrends.push({
            month: nextMonthDate,
            actual: null,
            predicted: forecast
        });
    }
    const ids = items.map(i => i.id);
    const salesMap = getAllHistoricalSales(ids);
    const itemBreakdown = items.map(item => {
        const sales = salesMap.get(item.id) || [];
        const totalSold = sales.reduce((a, b) => a + b, 0);
        const { direction } = detectTrend(sales);
        return {
            itemName: item.item_name,
            totalSold,
            trend: direction
        };
    }).sort((a, b) => b.totalSold - a.totalSold);
    return { historicalTrends, itemBreakdown };
}
function getNextMonth(currentMonth) {
    const [year, month] = currentMonth.split('-').map(Number);
    const date = new Date(year, month, 1);
    date.setMonth(date.getMonth() + 1);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}
// ============================================================
// 13. FORECAST ACCURACY — Compute actuals vs predictions
// ============================================================
/**
 * Backfill actual quantities for past forecast accuracy records.
 * Compares what was predicted vs what actually sold.
 */
function computeForecastAccuracy() {
    // Find all accuracy records without actual_quantity set
    const pending = database_1.default.prepare(`
    SELECT fa.id, fa.forecast_date, fa.item_id, fa.period, fa.predicted_quantity
    FROM forecast_accuracy fa
    WHERE fa.actual_quantity IS NULL
      AND fa.forecast_date < date('now')
  `).all();
    let computed = 0;
    let errors = 0;
    for (const record of pending) {
        try {
            // Determine the date range to sum actuals
            let startDate;
            let endDate;
            switch (record.period) {
                case 'next_week':
                    startDate = record.forecast_date;
                    endDate = database_1.default.prepare(`SELECT date(?, '+7 days') as d`).get(record.forecast_date).d;
                    break;
                case 'next_month':
                    startDate = record.forecast_date;
                    endDate = database_1.default.prepare(`SELECT date(?, '+1 month') as d`).get(record.forecast_date).d;
                    break;
                case 'next_quarter':
                    startDate = record.forecast_date;
                    endDate = database_1.default.prepare(`SELECT date(?, '+3 months') as d`).get(record.forecast_date).d;
                    break;
                default:
                    continue;
            }
            // Only compute if the period has ended
            const now = new Date().toISOString().split('T')[0];
            if (endDate > now)
                continue;
            // Sum actual sales in the period
            const actualResult = database_1.default.prepare(`
        SELECT COALESCE(SUM(ii.quantity), 0) as total
        FROM invoice_items ii
        JOIN invoices i ON i.id = ii.invoice_id
        WHERE ii.item_id = ?
          AND i.invoice_date >= ?
          AND i.invoice_date < ?
          AND i.status != 'Cancelled'
      `).get(record.item_id, startDate, endDate);
            const actualQty = actualResult.total;
            // Compute accuracy metrics
            const mape = record.predicted_quantity > 0
                ? Math.abs((actualQty - record.predicted_quantity) / record.predicted_quantity) * 100
                : (actualQty > 0 ? 100 : 0);
            const mae = Math.abs(actualQty - record.predicted_quantity);
            // sMAPE = 200% × |actual - predicted| / (|actual| + |predicted|)
            const smape = (actualQty + record.predicted_quantity) > 0
                ? (2 * Math.abs(actualQty - record.predicted_quantity) / (Math.abs(actualQty) + Math.abs(record.predicted_quantity))) * 100
                : 0;
            database_1.default.prepare(`
        UPDATE forecast_accuracy
        SET actual_quantity = ?, mape = ?, mae = ?, smape = ?, computed_at = datetime('now')
        WHERE id = ?
      `).run(actualQty, Math.round(mape * 100) / 100, Math.round(mae * 100) / 100, Math.round(smape * 100) / 100, record.id);
            computed++;
        }
        catch (error) {
            errors++;
        }
    }
    return { computed, errors };
}
// ============================================================
// 14. ACCURACY QUERIES
// ============================================================
/**
 * Get accuracy data for all items or a specific item.
 */
function getAccuracy(itemId) {
    let query;
    const params = [];
    if (itemId) {
        query = `
      SELECT
        fa.item_id as itemId,
        i.item_name as itemName,
        i.item_code as itemCode,
        AVG(fa.mape) as mape,
        AVG(fa.mae) as mae,
        AVG(fa.smape) as smape,
        COUNT(*) as sampleSize,
        fa.model_type as modelType,
        df.trend_direction as trend
      FROM forecast_accuracy fa
      JOIN items i ON i.id = fa.item_id
      LEFT JOIN (
        SELECT item_id, trend_direction FROM demand_forecasts
        WHERE forecast_date = date('now')
      ) df ON df.item_id = fa.item_id
      WHERE fa.item_id = ? AND fa.mape IS NOT NULL
      GROUP BY fa.item_id
    `;
        params.push(itemId);
    }
    else {
        query = `
      SELECT
        fa.item_id as itemId,
        i.item_name as itemName,
        i.item_code as itemCode,
        AVG(fa.mape) as mape,
        AVG(fa.mae) as mae,
        AVG(fa.smape) as smape,
        COUNT(*) as sampleSize,
        fa.model_type as modelType,
        df.trend_direction as trend
      FROM forecast_accuracy fa
      JOIN items i ON i.id = fa.item_id
      LEFT JOIN (
        SELECT item_id, trend_direction FROM demand_forecasts
        WHERE forecast_date = date('now')
      ) df ON df.item_id = fa.item_id
      WHERE fa.mape IS NOT NULL
      GROUP BY fa.item_id
      ORDER BY mape ASC
    `;
    }
    return database_1.default.prepare(query).all(...params);
}
/**
 * Get accuracy time series for a specific item.
 */
function getAccuracyTimeSeries(itemId) {
    return database_1.default.prepare(`
    SELECT forecast_date as forecastDate, period, predicted_quantity as predicted, actual_quantity as actual, mape, mae
    FROM forecast_accuracy
    WHERE item_id = ?
    ORDER BY forecast_date ASC, period ASC
  `).all(itemId);
}
// ============================================================
// 15. MANUAL OVERRIDES
// ============================================================
/**
 * Apply a manual override to a forecast.
 */
function applyOverride(override) {
    const today = new Date().toISOString().split('T')[0];
    const expiresDate = override.expiresDays
        ? database_1.default.prepare(`SELECT date(?, '+${override.expiresDays} days') as d`).get(today)
        : null;
    // Delete existing records first, then insert fresh override values
    database_1.default.prepare('DELETE FROM demand_forecasts WHERE item_id = ? AND forecast_date = ? AND period = ?').run(override.itemId, today, 'next_week');
    database_1.default.prepare('DELETE FROM demand_forecasts WHERE item_id = ? AND forecast_date = ? AND period = ?').run(override.itemId, today, 'next_month');
    database_1.default.prepare('DELETE FROM demand_forecasts WHERE item_id = ? AND forecast_date = ? AND period = ?').run(override.itemId, today, 'next_quarter');
    const insertOverride = database_1.default.prepare(`
    INSERT INTO demand_forecasts (
      item_id, forecast_date, period, predicted_quantity,
      confidence_level, trend_direction, trend_percentage,
      model_type, is_manual_override, override_reason, override_expires
    ) VALUES (?, ?, ?, ?, 90, 'stable', 0, 'manual_override', 1, ?, ?)
  `);
    const overrideReason = override.reason || 'Manual override';
    const expiresStr = expiresDate?.d || null;
    if (override.nextWeek !== undefined) {
        insertOverride.run(override.itemId, today, 'next_week', override.nextWeek, overrideReason, expiresStr);
    }
    if (override.nextMonth !== undefined) {
        insertOverride.run(override.itemId, today, 'next_month', override.nextMonth, overrideReason, expiresStr);
    }
    if (override.nextQuarter !== undefined) {
        insertOverride.run(override.itemId, today, 'next_quarter', override.nextQuarter, overrideReason, expiresStr);
    }
}
// ============================================================
// 16. MODEL CONFIG MANAGEMENT
// ============================================================
/**
 * Get the model config for an item.
 */
function getModelConfig(itemId) {
    return database_1.default.prepare('SELECT * FROM forecast_model_config WHERE item_id = ?').get(itemId);
}
/**
 * Set model config for an item.
 */
function setModelConfig(config) {
    const existing = database_1.default.prepare('SELECT id FROM forecast_model_config WHERE item_id = ?').get(config.item_id);
    if (existing) {
        const sets = [];
        const params = [];
        for (const [key, value] of Object.entries(config)) {
            if (key !== 'item_id' && key !== 'id') {
                sets.push(`${key} = ?`);
                params.push(value);
            }
        }
        sets.push("updated_at = CURRENT_TIMESTAMP");
        params.push(config.item_id);
        database_1.default.prepare(`UPDATE forecast_model_config SET ${sets.join(', ')} WHERE item_id = ?`).run(...params);
    }
    else {
        const keys = Object.keys(config).filter(k => k !== 'id');
        const values = keys.map(k => config[k]);
        const placeholders = keys.map(() => '?').join(', ');
        database_1.default.prepare(`INSERT INTO forecast_model_config (${keys.join(', ')}) VALUES (${placeholders})`).run(...values);
    }
}
// ============================================================
// 17. SEASONAL EVENTS CRUD
// ============================================================
function getSeasonalEvents() {
    return database_1.default.prepare('SELECT * FROM forecast_seasonal_events ORDER BY start_date ASC').all();
}
function createSeasonalEvent(event) {
    // Tomorrow's events are valid for checking
    database_1.default.prepare(`
    INSERT INTO forecast_seasonal_events (event_name, start_date, end_date, multiplier, applies_to_category, applies_to_item_id, is_recurring)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(event.event_name, event.start_date, event.end_date, event.multiplier || 1.0, event.applies_to_category || null, event.applies_to_item_id || null, event.is_recurring || 0);
}
function deleteSeasonalEvent(id) {
    database_1.default.prepare('DELETE FROM forecast_seasonal_events WHERE id = ?').run(id);
}
// ============================================================
// 18. SAFETY STOCK QUERY
// ============================================================
function getSafetyStock(itemId) {
    const items = itemId
        ? database_1.default.prepare('SELECT id, item_code, item_name, current_stock FROM items WHERE id = ?').all(itemId)
        : database_1.default.prepare('SELECT id, item_code, item_name, current_stock FROM items WHERE is_active = 1').all();
    const ids = items.map(i => i.id);
    const salesMap = getAllHistoricalSales(ids);
    return items.map(item => {
        const sales = salesMap.get(item.id) || [];
        const config = loadModelConfig({ id: item.id, category: item.category ?? null });
        const { safetyStock, reorderPoint, dailyDemand, demandStdDev, zScore } = calculateSafetyStock(sales, config.lead_time_days, config.service_level);
        return {
            itemId: item.id,
            itemName: item.item_name,
            itemCode: item.item_code,
            dailyDemand,
            demandStdDev,
            leadTimeDays: config.lead_time_days,
            serviceLevel: config.service_level,
            zScore,
            safetyStock,
            reorderPoint,
            currentStock: item.current_stock
        };
    });
}
// ============================================================
// 19. FORECAST EXPORT
// ============================================================
function getForecastsForExport() {
    return getOrGenerateForecasts();
}
// ============================================================
// 20. FORECAST RUN HISTORY
// ============================================================
function getForecastRuns(limit = 20) {
    return database_1.default.prepare(`
    SELECT * FROM forecast_runs ORDER BY started_at DESC LIMIT ?
  `).all(limit);
}
