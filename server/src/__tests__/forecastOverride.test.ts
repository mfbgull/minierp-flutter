import { describe, expect, it } from '@jest/globals';
import db from '../config/database';
import { applyOverride } from '../services/forecastService';

/**
 * Fallow health remediation — `forecastService.applyOverride` (CRAP 72).
 * Covers expired/indefinite overrides, all three periods, reason defaults,
 * and replacement of existing rows.
 */
function itemFixture(): number {
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const result = db.prepare(`
    INSERT INTO items (item_code, item_name, unit_of_measure)
    VALUES (?, ?, 'Nos')
  `).run(`FC-OVR-${suffix}`, `Forecast override ${suffix}`);
  return Number(result.lastInsertRowid);
}

function today(): string {
  return new Date().toISOString().split('T')[0];
}

function rowsFor(itemId: number) {
  return db
    .prepare(
      `SELECT period, predicted_quantity, model_type, is_manual_override,
              override_reason, override_expires
       FROM demand_forecasts
       WHERE item_id = ? AND forecast_date = ?
       ORDER BY period`,
    )
    .all(itemId, today()) as Array<{
    period: string;
    predicted_quantity: number;
    model_type: string;
    is_manual_override: number;
    override_reason: string;
    override_expires: string | null;
  }>;
}

describe('forecastService.applyOverride', () => {
  it('replaces existing forecasts with an expiring next-week override', () => {
    const itemId = itemFixture();
    const seed = db.prepare(`
      INSERT INTO demand_forecasts (item_id, forecast_date, period, predicted_quantity)
      VALUES (?, ?, ?, 1)
    `);
    seed.run(itemId, today(), 'next_week');
    seed.run(itemId, today(), 'next_month');
    seed.run(itemId, today(), 'next_quarter');

    applyOverride({
      itemId,
      nextWeek: 10,
      reason: 'Promo week',
      expiresDays: 7,
    });

    const expectedExpiry = (
      db.prepare(`SELECT date(?, '+7 days') AS d`).get(today()) as {
        d: string;
      }
    ).d;
    expect(rowsFor(itemId)).toEqual([
      {
        period: 'next_week',
        predicted_quantity: 10,
        model_type: 'manual_override',
        is_manual_override: 1,
        override_reason: 'Promo week',
        override_expires: expectedExpiry,
      },
    ]);
  });

  it('writes month and quarter overrides with the default reason and no expiry', () => {
    const itemId = itemFixture();

    applyOverride({ itemId, nextMonth: 20, nextQuarter: 30 });

    expect(rowsFor(itemId)).toEqual([
      {
        period: 'next_month',
        predicted_quantity: 20,
        model_type: 'manual_override',
        is_manual_override: 1,
        override_reason: 'Manual override',
        override_expires: null,
      },
      {
        period: 'next_quarter',
        predicted_quantity: 30,
        model_type: 'manual_override',
        is_manual_override: 1,
        override_reason: 'Manual override',
        override_expires: null,
      },
    ]);
  });
});
