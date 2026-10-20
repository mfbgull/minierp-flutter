import { beforeAll, afterEach, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import logger from '../utils/logger';
import { getAuthCookie, createItem, purchaseStock, createCustomer } from './helpers/invoiceReturnSpec';
import db from '../config/database';

describe('Invoice migration telemetry preserves compatibility', () => {
  let cookie: string;
  let itemId: number;
  let customerId: number;
  beforeAll(async () => {
    cookie = await getAuthCookie();
    itemId = await createItem('Migration telemetry', cookie);
    customerId = await createCustomer('Migration telemetry', cookie);
    const warehouse = db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number };
    await purchaseStock(itemId, warehouse.id, 10, 10, cookie);
  });
  afterEach(() => { jest.restoreAllMocks(); });

  for (const route of ['/api/invoices', '/api/mobile-invoices/submit']) {
    it(`${route} accepts keyless and keyed writes and emits countable safe events`, async () => {
      const info = jest.spyOn(logger, 'info');
      const body = {
        customer_id: customerId, invoice_date: '2026-09-05',
        items: [{ item_id: itemId, quantity: 1, unit_price: 100 }],
        total_amount: 100, record_payment: false,
      };
      for (const keyed of [false, true]) {
        let operation = request(app).post(route).set('Cookie', cookie);
        if (keyed) operation = operation.set('Idempotency-Key', `telemetry-${route}-key`);
        const response = await operation.send(body);
        expect(response.status).toBe(201);
      }
      const events = info.mock.calls.map(([event]) => event).filter(event =>
        typeof event === 'object' && event !== null && 'message' in event && event.message === 'invoice_idempotency_observation');
      expect(events).toEqual([
        expect.objectContaining({ message: 'invoice_idempotency_observation', event: 'invoice_idempotency_observation', route: `POST ${route}`, keyed: false }),
        expect.objectContaining({ message: 'invoice_idempotency_observation', event: 'invoice_idempotency_observation', route: `POST ${route}`, keyed: true }),
      ]);
      for (const event of events) {
        expect(Object.keys(event).sort()).toEqual([
          'environment', 'event', 'keyed', 'level', 'message', 'route', 'service', 'timestamp',
        ]);
      }
    });
  }
});
