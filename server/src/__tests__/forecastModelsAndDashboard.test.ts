import { beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import {
  calculateHoltWinters,
  calculateSimpleARIMA,
  getDashboardData,
} from '../services/forecastService';

/**
 * Fallow health remediation — `calculateHoltWinters`, `calculateSimpleARIMA`
 * and `getDashboardData` (CRAP 42 each).
 */

const today = () => new Date().toISOString().split('T')[0];

function seedItem(opts: {
  code: string;
  stock: number;
  trend: 'growing' | 'stable' | 'declining';
  nextMonth: number;
  model?: string;
  confidence?: number;
}): number {
  const item = db
    .prepare('INSERT INTO items (item_code, item_name, current_stock) VALUES (?, ?, ?)')
    .run(opts.code, `${opts.code} name`, opts.stock);
  const itemId = Number(item.lastInsertRowid);
  const insert = db.prepare(`
    INSERT INTO demand_forecasts (
      item_id, forecast_date, period, predicted_quantity,
      confidence_level, trend_direction, trend_percentage, model_type
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const periods: [string, number][] = [
    ['next_week', Math.round(opts.nextMonth / 4)],
    ['next_month', opts.nextMonth],
    ['next_quarter', opts.nextMonth * 3],
  ];
  for (const [period, qty] of periods) {
    insert.run(
      itemId,
      today(),
      period,
      qty,
      opts.confidence ?? 80,
      opts.trend,
      5,
      opts.model ?? 'weighted_moving_average'
    );
  }
  return itemId;
}

describe('forecast model helpers', () => {
  describe('calculateHoltWinters', () => {
    it('returns 0 for an empty series', () => {
      expect(calculateHoltWinters([])).toBe(0);
    });

    it('falls back to Holt when the series is shorter than the season', () => {
      expect(calculateHoltWinters([3, 4, 5], 12)).toBe(6);
      expect(calculateHoltWinters([7], 12)).toBe(7);
    });

    it('handles exactly one full season without a trend estimate', () => {
      expect(calculateHoltWinters(new Array(12).fill(10), 12)).toBe(10);
    });

    it('estimates a trend once a partial second cycle is long enough', () => {
      const seasonal = Array.from({ length: 24 }, (_, i) => (i % 2 === 0 ? 10 : 20));
      const forecast = calculateHoltWinters(seasonal, 12);
      expect(Number.isFinite(forecast)).toBe(true);
      expect(forecast).toBeGreaterThan(0);
    });

    it('skips the trend estimate when the second cycle is too short', () => {
      const series = [...new Array(12).fill(10), 11, 12, 13, 14, 15];
      const forecast = calculateHoltWinters(series, 12);
      expect(Number.isFinite(forecast)).toBe(true);
      expect(forecast).toBeGreaterThan(0);
    });
  });

  describe('calculateSimpleARIMA', () => {
    it('returns 0 for an empty series', () => {
      expect(calculateSimpleARIMA([])).toBe(0);
    });

    it('falls back to the weighted moving average below three points', () => {
      expect(calculateSimpleARIMA([5])).toBe(5);
      expect(calculateSimpleARIMA([5, 7])).toBe(6.25);
    });

    it('returns a flat forecast for a constant series (zero denominator)', () => {
      expect(calculateSimpleARIMA([5, 5, 5])).toBe(5);
    });

    it('projects the next differenced value for a varying series', () => {
      expect(calculateSimpleARIMA([0, 1, 4, 6])).toBe(8);
    });

    it('clamps a negative projection to zero demand', () => {
      expect(calculateSimpleARIMA([10, 1, 0])).toBe(0);
    });
  });
});

describe('getDashboardData', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM forecast_accuracy').run();
    db.prepare('DELETE FROM demand_forecasts').run();
    db.prepare('DELETE FROM forecast_runs').run();
    db.prepare('DELETE FROM items').run();
  });

  it('returns an empty summary when no items are active', () => {
    expect(getDashboardData()).toEqual({
      summary: {
        totalItems: 0,
        itemsNeedingRestock: 0,
        avgConfidence: 0,
        criticalAlerts: 0,
        avgAccuracy: null,
        modelDistribution: {},
      },
      alerts: [],
      topGrowing: [],
      topDeclining: [],
    });
  });

  it('summarizes cached forecasts, alerts and trends', () => {
    seedItem({ code: 'FG-A', stock: 0, trend: 'growing', nextMonth: 100 });
    seedItem({ code: 'FG-B', stock: 16, trend: 'declining', nextMonth: 50 });
    const adequateId = seedItem({
      code: 'FG-C',
      stock: 60,
      trend: 'stable',
      nextMonth: 50,
      model: 'arima',
      confidence: 60,
    });
    db.prepare(
      `INSERT INTO forecast_accuracy
         (forecast_date, item_id, period, model_type, predicted_quantity, mape, computed_at)
       VALUES (?, ?, 'next_month', 'arima', 50, 12.5, datetime('now'))`
    ).run(today(), adequateId);

    const data = getDashboardData();

    expect(data.summary.totalItems).toBe(3);
    expect(data.summary.itemsNeedingRestock).toBe(2);
    expect(data.summary.criticalAlerts).toBe(1);
    expect(data.summary.avgAccuracy).toBeCloseTo(12.5, 5);
    expect(data.summary.avgConfidence).toBe(Math.round((80 + 80 + 60) / 3));
    expect(data.summary.modelDistribution).toEqual({
      weighted_moving_average: 2,
      arima: 1,
    });

    expect(data.alerts.map(a => [a.itemName, a.alertLevel])).toEqual([
      ['FG-A name', 'critical'],
      ['FG-B name', 'warning'],
    ]);
    expect(data.alerts[0].predictedDemand).toBe(100);
    expect(data.topGrowing.map(f => f.itemCode)).toEqual(['FG-A']);
    expect(data.topDeclining.map(f => f.itemCode)).toEqual(['FG-B']);
  });
});
