import { Request, Response } from 'express';
import {
  getDashboardData, generateAllForecasts, getTrendData,
  getAccuracy, getAccuracyTimeSeries, applyOverride,
  getModelConfig, setModelConfig, getSeasonalEvents,
  createSeasonalEvent, deleteSeasonalEvent,
  getSafetyStock, computeForecastAccuracy,
  getForecastsForExport, getForecastRuns
} from '../services/forecastService';
import logger from '../utils/logger';

// ============ EXISTING ENDPOINTS (enhanced) ============

function getDashboard(req: Request, res: Response): void {
  try {
    const data = getDashboardData();
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast dashboard error:', error);
    res.status(500).json({ error: 'Failed to fetch forecast dashboard' });
  }
}

function getDemand(req: Request, res: Response): void {
  try {
    const page = Number(req.query.page) || 1;
    const limit = Number(req.query.limit) || 10;
    const { category, trend, recommendation, modelType, search } = req.query;
    let forecasts = generateAllForecasts();

    if (search) {
      const term = String(search).toLowerCase();
      forecasts = forecasts.filter(
        f =>
          f.itemCode.toLowerCase().includes(term) ||
          f.itemName.toLowerCase().includes(term)
      );
    }
    if (category) {
      forecasts = forecasts.filter(f => f.category === category);
    }
    if (trend) {
      forecasts = forecasts.filter(f => f.trend === trend);
    }
    if (recommendation) {
      forecasts = forecasts.filter(f => f.recommendation === recommendation);
    }
    if (modelType) {
      forecasts = forecasts.filter(f => f.modelType === modelType);
    }

    // Filter-then-slice: the forecast list is generated in memory, so
    // paging happens in JS after the filters narrow it.
    const total = forecasts.length;
    const totalPages = Math.max(1, Math.ceil(total / limit));
    const start = (page - 1) * limit;
    const rows = forecasts.slice(start, start + limit);

    // Flat envelope (data = list, pagination a sibling) — the shape the
    // client's `getPaged` helper parses.
    res.json({
      success: true,
      data: rows,
      pagination: {
        currentPage: page,
        totalPages,
        totalItems: total,
        hasNext: page < totalPages,
        hasPrev: page > 1
      }
    });
  } catch (error) {
    logger.error('Forecast demand error:', error);
    res.status(500).json({ error: 'Failed to fetch demand forecasts' });
  }
}

function getTrends(req: Request, res: Response): void {
  try {
    const itemId = req.query.itemId ? Number(req.query.itemId) : undefined;
    const data = getTrendData(itemId);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast trends error:', error);
    res.status(500).json({ error: 'Failed to fetch trend data' });
  }
}

function generateForecasts(req: Request, res: Response): void {
  try {
    const forecasts = generateAllForecasts();
    res.json({
      success: true,
      message: `Generated forecasts for ${forecasts.length} items`,
      data: { count: forecasts.length }
    });
  } catch (error) {
    logger.error('Generate forecasts error:', error);
    res.status(500).json({ error: 'Failed to generate forecasts' });
  }
}

// ============ NEW ENDPOINTS ============

/**
 * GET /api/forecasts/accuracy
 * Get forecast accuracy data with optional filters.
 */
function getAccuracyData(req: Request, res: Response): void {
  try {
    const itemId = req.query.itemId ? Number(req.query.itemId) : undefined;
    const data = getAccuracy(itemId);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast accuracy error:', error);
    res.status(500).json({ error: 'Failed to fetch accuracy data' });
  }
}

/**
 * GET /api/forecasts/accuracy/:itemId
 * Get accuracy time series for a single item.
 */
function getAccuracyDetail(req: Request, res: Response): void {
  try {
    const itemId = Number(req.params.itemId);
    const data = getAccuracyTimeSeries(itemId);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast accuracy detail error:', error);
    res.status(500).json({ error: 'Failed to fetch accuracy detail' });
  }
}

/**
 * GET /api/forecasts/models/:itemId
 * Get model config for an item.
 */
function getModelConfigHandler(req: Request, res: Response): void {
  try {
    const itemId = Number(req.params.itemId);
    const config = getModelConfig(itemId);
    res.json({ success: true, data: config });
  } catch (error) {
    logger.error('Get model config error:', error);
    res.status(500).json({ error: 'Failed to fetch model config' });
  }
}

/**
 * PUT /api/forecasts/models/:itemId
 * Set model config for an item.
 */
function setModelConfigHandler(req: Request, res: Response): void {
  try {
    const itemId = Number(req.params.itemId);
    const config = { item_id: itemId, ...req.body };
    setModelConfig(config);
    res.json({ success: true, message: 'Model config updated' });
  } catch (error) {
    logger.error('Set model config error:', error);
    res.status(500).json({ error: 'Failed to update model config' });
  }
}

/**
 * POST /api/forecasts/override
 * Apply a manual forecast override.
 */
function postOverride(req: Request, res: Response): void {
  try {
    const override = req.body;
    applyOverride(override);
    res.json({ success: true, message: 'Forecast override applied' });
  } catch (error) {
    logger.error('Forecast override error:', error);
    res.status(500).json({ error: 'Failed to apply override' });
  }
}

/**
 * GET /api/forecasts/safety-stock
 * Get safety stock calculations for all items or a specific item.
 */
function getSafetyStockHandler(req: Request, res: Response): void {
  try {
    const itemId = req.query.itemId ? Number(req.query.itemId) : undefined;
    const data = getSafetyStock(itemId);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Safety stock error:', error);
    res.status(500).json({ error: 'Failed to fetch safety stock data' });
  }
}

/**
 * GET /api/forecasts/seasonal-events
 * Get all seasonal events.
 */
function getSeasonalEventsHandler(req: Request, res: Response): void {
  try {
    const data = getSeasonalEvents();
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Seasonal events error:', error);
    res.status(500).json({ error: 'Failed to fetch seasonal events' });
  }
}

/**
 * POST /api/forecasts/seasonal-events
 * Create a new seasonal event.
 */
function postSeasonalEvent(req: Request, res: Response): void {
  try {
    const event = req.body;
    createSeasonalEvent(event);
    res.json({ success: true, message: 'Seasonal event created' });
  } catch (error) {
    logger.error('Create seasonal event error:', error);
    res.status(500).json({ error: 'Failed to create seasonal event' });
  }
}

/**
 * DELETE /api/forecasts/seasonal-events/:id
 * Delete a seasonal event.
 */
function deleteSeasonalEventHandler(req: Request, res: Response): void {
  try {
    const id = Number(req.params.id);
    deleteSeasonalEvent(id);
    res.json({ success: true, message: 'Seasonal event deleted' });
  } catch (error) {
    logger.error('Delete seasonal event error:', error);
    res.status(500).json({ error: 'Failed to delete seasonal event' });
  }
}

/**
 * POST /api/forecasts/compute-accuracy
 * Trigger accuracy computation (backfill actuals vs predictions).
 */
function postComputeAccuracy(req: Request, res: Response): void {
  try {
    const result = computeForecastAccuracy();
    res.json({
      success: true,
      message: `Computed accuracy for ${result.computed} records (${result.errors} errors)`,
      data: result
    });
  } catch (error) {
    logger.error('Compute accuracy error:', error);
    res.status(500).json({ error: 'Failed to compute accuracy' });
  }
}

/**
 * GET /api/forecasts/export
 * Export forecast data as JSON (frontend can convert to CSV/PDF).
 */
function getExport(req: Request, res: Response): void {
  try {
    const data = getForecastsForExport();
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast export error:', error);
    res.status(500).json({ error: 'Failed to export forecasts' });
  }
}

/**
 * GET /api/forecasts/runs
 * Get forecast run history.
 */
function getRuns(req: Request, res: Response): void {
  try {
    const limit = req.query.limit ? Number(req.query.limit) : 20;
    const data = getForecastRuns(limit);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('Forecast runs error:', error);
    res.status(500).json({ error: 'Failed to fetch forecast runs' });
  }
}

export default {
  // Existing
  getDashboard,
  getDemand,
  getTrends,
  generateForecasts,
  // New: Accuracy
  getAccuracyData,
  getAccuracyDetail,
  postComputeAccuracy,
  // New: Models
  getModelConfigHandler,
  setModelConfigHandler,
  // New: Override
  postOverride,
  // New: Safety Stock
  getSafetyStockHandler,
  // New: Seasonal Events
  getSeasonalEventsHandler,
  postSeasonalEvent,
  deleteSeasonalEventHandler,
  // New: Export & Runs
  getExport,
  getRuns
};
