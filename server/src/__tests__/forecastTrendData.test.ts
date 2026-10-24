import { beforeAll, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import { getTrendData } from '../services/forecastService';
import {
  createCustomer,
  createInvoice,
  createItem,
  getAuthCookie,
  purchaseStock,
} from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `forecastService.getTrendData` (CRAP 56).
 * Covers the item-scoped and all-items branches, the three-month moving
 * average + forecast, and an item with no sales history.
 */
describe('forecastService.getTrendData', () => {
  let cookie = '';
  let warehouseId = 0;
  let soldItem = 0;
  let quietItem = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    const warehouse = db
      .prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1')
      .get() as { id: number };
    warehouseId = warehouse.id;
    soldItem = await createItem('Trend sold item', cookie);
    quietItem = await createItem('Trend quiet item', cookie);
    await purchaseStock(soldItem, warehouseId, 100, 10, cookie, '2026-01-01');
    const customerId = await createCustomer('Trend customer', cookie);
    for (const [date, quantity] of [
      ['2026-08-15', 5],
      ['2026-09-15', 7],
      ['2026-10-15', 9],
    ] as const) {
      await createInvoice(
        {
          customerId,
          itemId: soldItem,
          lines: [{ quantity, unitPrice: 20 }],
          payment: null,
          invoiceDate: date,
        },
        cookie,
      );
    }
  });

  it('builds a moving average and a next-month forecast for a selling item', () => {
    const data = getTrendData(soldItem);
    expect(data.historicalTrends).toHaveLength(4);
    expect(data.historicalTrends[0].movingAvg).toBeUndefined();
    expect(data.historicalTrends[2].movingAvg).toBeGreaterThan(0);
    expect(data.historicalTrends[3].predicted).toBeGreaterThan(0);
    const breakdown = data.itemBreakdown.find(
      (row) => row.itemName === 'Trend sold item',
    );
    expect(breakdown).toBeDefined();
    expect(breakdown!.totalSold).toBe(21);
  });

  it('returns an all-items breakdown when no item is specified', () => {
    const data = getTrendData();
    expect(data.historicalTrends).toHaveLength(4);
    expect(data.itemBreakdown.length).toBeGreaterThanOrEqual(2);
  });

  it('returns an empty trend series for an item with no sales', () => {
    const data = getTrendData(quietItem);
    expect(data.historicalTrends).toEqual([]);
    expect(data.itemBreakdown).toHaveLength(1);
    expect(data.itemBreakdown[0].totalSold).toBe(0);
  });
});
