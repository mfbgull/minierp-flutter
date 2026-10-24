import { beforeEach, describe, expect, it } from '@jest/globals';
import db from '../config/database';
import {
  computeForecastAccuracy,
  generateAllForecasts,
} from '../services/forecastService';

/**
 * Fallow health remediation — `runModel` (CRAP 49.5) and
 * `computeForecastAccuracy` (CRAP 110).
 */

function monthOffset(offset: number): string {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() - offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

let customerId = 0;
let invoiceSeq = 0;

function seedItem(code: string, opts: { sales?: number[]; stock?: number; category?: string } = {}): number {
  const item = db
    .prepare(
      `INSERT INTO items (item_code, item_name, current_stock, category)
       VALUES (?, ?, ?, ?)`
    )
    .run(code, `${code} name`, opts.stock ?? 0, opts.category ?? null);
  const itemId = Number(item.lastInsertRowid);
  const sales = opts.sales ?? [];
  sales.forEach((qty, idx) => {
    invoiceSeq += 1;
    const invoice = db
      .prepare(
        `INSERT INTO invoices (invoice_no, customer_id, invoice_date, status, total_amount)
         VALUES (?, ?, ?, 'Unpaid', ?)`
      )
      .run(
        `FC-INV-${invoiceSeq}`,
        customerId,
        `${monthOffset(sales.length - 1 - idx)}-15`,
        qty * 10
      );
    db.prepare(
      `INSERT INTO invoice_items (invoice_id, item_id, quantity, unit_price, amount)
       VALUES (?, ?, ?, 10, ?)`
    ).run(invoice.lastInsertRowid, itemId, qty, qty * 10);
  });
  return itemId;
}

function setConfig(
  itemId: number,
  modelType: string,
  extra: Record<string, unknown> = {}
): void {
  const cols = ['item_id', 'model_type', 'bias_correction', ...Object.keys(extra)];
  const values = [itemId, modelType, 0, ...Object.values(extra)];
  db.prepare(
    `INSERT INTO forecast_model_config (${cols.join(', ')})
     VALUES (${cols.map(() => '?').join(', ')})`
  ).run(...(values as Array<string | number>));
}

beforeEach(() => {
  db.prepare('DELETE FROM forecast_accuracy').run();
  db.prepare('DELETE FROM demand_forecasts').run();
  db.prepare('DELETE FROM forecast_runs').run();
  db.prepare('DELETE FROM forecast_model_config').run();
  db.prepare('DELETE FROM invoice_items').run();
  db.prepare('DELETE FROM invoices').run();
  db.prepare('DELETE FROM items').run();
  db.prepare('DELETE FROM customers').run();
  customerId = Number(
    db
      .prepare(
        `INSERT INTO customers (customer_code, customer_name) VALUES ('FC-CUST', 'Forecast Co')`
      )
      .run().lastInsertRowid
  );
});

describe('generateAllForecasts', () => {
  it('runs every configured model and caches the results', () => {
    const moving = seedItem('FC-WMA', { sales: [10, 20, 30, 40, 50], stock: 5 });
    const ses = seedItem('FC-SES', { sales: [10, 20, 30], stock: 50 });
    const holts = seedItem('FC-HOLTS', { sales: [10, 20, 30], stock: 50 });
    const winters = seedItem('FC-HW', { sales: [10, 20, 30, 40, 50], stock: 50 });
    const arima = seedItem('FC-ARIMA', { sales: [10, 20, 30], stock: 50 });
    const empty = seedItem('FC-EMPTY', { stock: 0, category: 'Widgets' });

    setConfig(moving, 'weighted_moving_average');
    setConfig(ses, 'simple_exponential_smoothing', { ses_alpha: 0.4 });
    setConfig(holts, 'holts_linear_trend', { holt_alpha: 0.4, holt_beta: 0.2 });
    setConfig(winters, 'holt_winters', { seasonal_periods: 4 });
    setConfig(arima, 'arima');
    db.prepare(
      `INSERT INTO forecast_model_config (category, model_type, bias_correction)
       VALUES ('Widgets', 'weighted_moving_average', 0)`
    ).run();

    const forecasts = generateAllForecasts();

    expect(forecasts).toHaveLength(6);
    expect(forecasts.map(f => f.modelType).sort()).toEqual([
      'arima',
      'holt_winters',
      'holts_linear_trend',
      'simple_exponential_smoothing',
      'weighted_moving_average',
      'weighted_moving_average',
    ]);
    for (const f of forecasts) {
      expect(f.predictedDemand.nextMonth).toBeGreaterThanOrEqual(0);
      expect(Number.isFinite(f.confidence)).toBe(true);
    }
    expect(forecasts.find(f => f.itemCode === 'FC-EMPTY')?.predictedDemand.nextMonth).toBe(0);

    const run = db
      .prepare(`SELECT status, items_processed FROM forecast_runs ORDER BY id DESC LIMIT 1`)
      .get() as { status: string; items_processed: number };
    expect(run).toEqual({ status: 'completed', items_processed: 6 });
    expect(
      (db.prepare('SELECT COUNT(*) AS n FROM demand_forecasts').get() as { n: number }).n
    ).toBe(18);
    expect(
      (db.prepare('SELECT COUNT(*) AS n FROM forecast_accuracy').get() as { n: number }).n
    ).toBe(18);
  });
});

describe('computeForecastAccuracy', () => {
  it('scores each elapsed period and skips future or unknown ones', () => {
    const sold = seedItem('FC-SOLD', { sales: [10, 20, 30, 40, 50] });
    const quiet = seedItem('FC-QUIET');

    const insert = db.prepare(
      `INSERT INTO forecast_accuracy
         (forecast_date, item_id, period, model_type, predicted_quantity)
       VALUES (?, ?, ?, 'weighted_moving_average', ?)`
    );
    const start = `${monthOffset(3)}-01`;
    insert.run(start, sold, 'next_week', 10);
    insert.run(start, sold, 'next_month', 10);
    insert.run(start, sold, 'next_quarter', 10);
    insert.run(start, sold, 'next_month', 0);
    insert.run(start, quiet, 'next_month', 0);
    insert.run(`${monthOffset(0)}-01`, sold, 'next_month', 50);

    const result = computeForecastAccuracy();

    expect(result).toEqual({ computed: 5, errors: 0 });

    const rows = db
      .prepare(
        `SELECT period, actual_quantity, mape, mae, smape, computed_at
         FROM forecast_accuracy
         WHERE item_id = ? AND forecast_date = ?
         ORDER BY id`
      )
      .all(sold, start) as Array<{
      period: string;
      actual_quantity: number;
      mape: number;
      mae: number;
      smape: number;
      computed_at: string | null;
    }>;
    expect(rows[0]).toMatchObject({ period: 'next_week', actual_quantity: 0, mape: 100, mae: 10 });
    expect(rows[1]).toMatchObject({ period: 'next_month', actual_quantity: 20, mape: 100, mae: 10 });
    expect(rows[1].smape).toBeCloseTo(66.67, 2);
    expect(rows[1].computed_at).toBeTruthy();
    expect(rows[2]).toMatchObject({ period: 'next_quarter', actual_quantity: 90, mape: 800, mae: 80 });
    expect(rows[3]).toMatchObject({ period: 'next_month', actual_quantity: 20, mape: 100 });

    const quietRow = db
      .prepare(
        `SELECT actual_quantity, mape, smape FROM forecast_accuracy
         WHERE item_id = ? AND period = 'next_month'`
      )
      .get(quiet) as { actual_quantity: number; mape: number; smape: number };
    expect(quietRow).toEqual({ actual_quantity: 0, mape: 0, smape: 0 });
  });
});
