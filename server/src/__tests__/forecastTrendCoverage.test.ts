import { beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import { detectTrend, getTrendData } from '../services/forecastService';

/**
 * Fallow health remediation — `forecastService.detectTrend` (CRAP 40.7) and
 * `getTrendData` (CRAP 56).
 */

function monthOffset(offset: number): string {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() - offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

describe('detectTrend', () => {
  it('returns stable with no data', () => {
    expect(detectTrend([])).toEqual({ direction: 'stable', percentage: 0 });
  });

  it('returns stable below three points', () => {
    expect(detectTrend([1, 2])).toEqual({ direction: 'stable', percentage: 0 });
  });

  it('detects growth and declines from the last three points', () => {
    expect(detectTrend([10, 10, 20])).toEqual({ direction: 'growing', percentage: 100 });
    expect(detectTrend([20, 10, 5])).toEqual({ direction: 'declining', percentage: -75 });
    expect(detectTrend([10, 10, 10])).toEqual({ direction: 'stable', percentage: 0 });
  });

  it('treats a zero baseline as growth or stable', () => {
    expect(detectTrend([0, 0, 5])).toEqual({ direction: 'growing', percentage: 100 });
    expect(detectTrend([0, 0, 0])).toEqual({ direction: 'stable', percentage: 0 });
  });

  it('rounds the percentage to one decimal', () => {
    expect(detectTrend([100, 100, 107])).toEqual({ direction: 'growing', percentage: 7 });
  });
});

describe('getTrendData', () => {
  let customerId = 0;

  beforeEach(() => {
    db.prepare('DELETE FROM invoice_items').run();
    db.prepare('DELETE FROM invoices').run();
    db.prepare('DELETE FROM items').run();
    db.prepare('DELETE FROM customers').run();
    customerId = Number(
      db
        .prepare(
          `INSERT INTO customers (customer_code, customer_name)
           VALUES ('CUST-TREND', 'Trend Customer')`
        )
        .run().lastInsertRowid
    );
  });

  function seedSales(code: string, quantities: number[]): number {
    const item = db
      .prepare('INSERT INTO items (item_code, item_name) VALUES (?, ?)')
      .run(code, `${code} name`);
    const itemId = Number(item.lastInsertRowid);
    quantities.forEach((qty, idx) => {
      const invoice = db
        .prepare(
          `INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount)
           VALUES (?, ?, ?, 'Unpaid', ?)`
        )
        .run(
          `${code}-INV-${idx}`,
          customerId,
          `${monthOffset(quantities.length - 1 - idx)}-15`,
          qty * 10
        );
      db.prepare(
        `INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
         VALUES (?, ?, ?, 10, ?)`
      ).run(invoice.lastInsertRowid, itemId, qty, qty * 10);
    });
    return itemId;
  }

  it('builds monthly history, moving averages and a next-month forecast', () => {
    const itemId = seedSales('TREND-A', [10, 20, 30]);

    const data = getTrendData(itemId);

    expect(data.historicalTrends).toHaveLength(4);
    expect(data.historicalTrends.slice(0, 3).map(t => [t.month, t.actual])).toEqual([
      [monthOffset(2), 10],
      [monthOffset(1), 20],
      [monthOffset(0), 30],
    ]);
    expect(data.historicalTrends[2].movingAvg).toBe(23);
    expect(data.historicalTrends[3].actual).toBeNull();
    expect(data.historicalTrends[3].predicted).toBe(23);
    expect(data.itemBreakdown).toEqual([
      { itemName: 'TREND-A name', totalSold: 60, trend: 'growing' },
    ]);
  });

  it('returns an empty history for an item without sales and for the global view', () => {
    seedSales('TREND-B', []);

    const byItem = getTrendData(
      (db.prepare(`SELECT id FROM items WHERE item_code = 'TREND-B'`).get() as { id: number }).id
    );
    expect(byItem.historicalTrends).toEqual([]);
    expect(byItem.itemBreakdown).toEqual([
      { itemName: 'TREND-B name', totalSold: 0, trend: 'stable' },
    ]);
  });

  it('ranks the global breakdown and handles zero-sale months', () => {
    seedSales('TREND-C', [0, 10, 20]);
    seedSales('TREND-D', []);

    const global = getTrendData();

    expect(global.itemBreakdown).toEqual([
      { itemName: 'TREND-C name', totalSold: 30, trend: 'growing' },
      { itemName: 'TREND-D name', totalSold: 0, trend: 'stable' },
    ]);
    expect(global.historicalTrends).toHaveLength(4);
    expect(global.historicalTrends[0]).toEqual({
      month: global.historicalTrends[0].month,
      actual: 0,
      predicted: null,
    });
  });
});
