/**
 * Demand-forecast cache read.
 *
 * When `demand_forecasts` already holds rows for today, the service returns
 * them instead of recomputing. That path (`cachedForecastItem`) had no test,
 * so its CRAP score was computed from zero coverage.
 */
import db from '../config/database';
import ItemModel from '../models/Item';
import { getOrGenerateForecasts } from '../services/forecastService';

let itemSeq = 0;

function activeItemId(): number {
  const existing = db
    .prepare('SELECT id FROM items WHERE is_active = 1 ORDER BY id LIMIT 1')
    .get() as { id: number } | undefined;
  if (existing) return existing.id;

  itemSeq += 1;
  return ItemModel.create(
    {
      item_code: `FC-CACHE-${itemSeq}`,
      item_name: `Forecast cache item ${itemSeq}`,
      category: 'ForecastTests',
      unit_of_measure: 'Nos',
      standard_cost: 10,
      standard_selling_price: 20,
    },
    1,
    db
  );
}

describe('demand forecast cache', () => {
  it('serves today\'s cached rows without regenerating', () => {
    const itemId = activeItemId();
    const today = new Date().toISOString().split('T')[0];

    db.prepare('DELETE FROM demand_forecasts WHERE forecast_date = ?').run(today);
    db.prepare(`
      INSERT INTO demand_forecasts (
        item_id, forecast_date, period, predicted_quantity,
        confidence_level, trend_direction, trend_percentage,
        model_type, bias_adjustment, seasonal_multiplier, run_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(itemId, today, 'next_week', 42, 70, 'growing', 5, 'weighted_moving_average', null, null, 'fc_cache_test');

    const results = getOrGenerateForecasts();
    const cached = results.find((r) => r.itemId === itemId);

    expect(cached).toBeDefined();
    expect(cached!.predictedDemand.nextWeek).toBe(42);
    expect(cached!.trend).toBe('growing');
    expect(cached!.trendPercentage).toBe(5);
    expect(cached!.modelType).toBe('weighted_moving_average');
    expect(cached!.lastUpdated).toBe(today);
    expect(cached!.isOverride).toBe(false);
  });
});
