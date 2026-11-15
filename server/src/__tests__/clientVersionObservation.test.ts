/**
 * Client version header (task: X-Client-Version) and the keyless
 * natural-key duplicate guard on the legacy mobile-invoice submit.
 *
 * Both are warn/observe only — never a rejection. Written against the
 * decision that the client release ships before or with the server
 * mandate (see audit/DECISIONS.md).
 */
import request from 'supertest';
import { beforeAll, describe, expect, it, jest } from '@jest/globals';
import app from '../app';
import db from '../config/database';
import logger from '../utils/logger';
import { isVersionBelow, MIN_CLIENT_VERSION } from '../middleware/clientVersion';
import { createCustomer, createItem, getAuthCookie, purchaseStock } from './helpers/invoiceReturnSpec';

describe('client version observation', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
  });

  it('logs the version and warns below the minimum (warn only)', async () => {
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => logger);
    try {
      const res = await request(app)
        .get('/api/mobile-invoices/tax-rates')
        .set('Cookie', authCookie)
        .set('X-Client-Version', '0.0.1');

      expect(res.status).toBe(200); // never rejected on version
      expect(res.headers['x-min-client-version']).toBe(MIN_CLIENT_VERSION);
      const warned = warn.mock.calls.some(call =>
        String(call[0]).includes('below minimum supported version'),
      );
      expect(warned).toBe(true);
    } finally {
      warn.mockRestore();
    }
  });

  it('does not warn at or above the minimum', async () => {
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => logger);
    try {
      const res = await request(app)
        .get('/api/mobile-invoices/tax-rates')
        .set('Cookie', authCookie)
        .set('X-Client-Version', MIN_CLIENT_VERSION);
      expect(res.status).toBe(200);
      const warned = warn.mock.calls.some(call =>
        String(call[0]).includes('below minimum supported version'),
      );
      expect(warned).toBe(false);
    } finally {
      warn.mockRestore();
    }
  });

  it('is a no-op when the header is absent (old builds must keep working)', async () => {
    const res = await request(app)
      .get('/api/mobile-invoices/tax-rates')
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    expect(res.headers['x-min-client-version']).toBeUndefined();
  });

  it('compares versions numerically, not as strings', () => {
    expect(isVersionBelow('0.9.9', '0.10.0')).toBe(true);
    expect(isVersionBelow('0.10.0', '0.9.9')).toBe(false);
    expect(isVersionBelow('1.0.0', '0.10.0')).toBe(false);
    expect(isVersionBelow('garbage', '0.1.0')).toBe(false);
  });
});

describe('keyless mobile submit — observed only, no natural-key replay', () => {
  let authCookie: string;
  let warehouseId: number;
  let itemId: number;
  let customerId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    warehouseId = (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
    itemId = await createItem('Duplicate Guard Item', authCookie);
    await purchaseStock(itemId, warehouseId, 200, 10, authCookie);
    customerId = await createCustomer('Duplicate Guard Customer', authCookie);
  });

  it('a keyless repeat with an identical body creates a second invoice (no replay)', async () => {
    const payload = {
      customer_id: customerId,
      invoice_date: '2026-11-05',
      items: [{ item_id: itemId, quantity: 2, unit_price: 25, tax_rate: 0, warehouse_id: warehouseId }],
    };

    const first = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send(payload);
    expect(first.status).toBe(201);
    const firstId = (first.body as { data: { id: number } }).data.id;

    // Two genuinely separate invoices for the same customer, date and amount
    // are legal. A natural-key guard replayed them and was removed.
    const second = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send(payload);
    expect(second.status).toBe(201);
    expect(second.headers['x-idempotent-replay']).toBeUndefined();
    expect((second.body as { data: { id: number } }).data.id).not.toBe(firstId);

    const count = db.prepare(
      `SELECT COUNT(*) AS c FROM invoices WHERE customer_id = ? AND invoice_date = ?`,
    ).get(customerId, '2026-11-05') as { c: number };
    expect(count.c).toBe(2);
  });

  it('a keyed submit and a keyless submit with the same body create two invoices', async () => {
    const payload = {
      customer_id: customerId,
      invoice_date: '2026-11-06',
      items: [{ item_id: itemId, quantity: 1, unit_price: 30, tax_rate: 0, warehouse_id: warehouseId }],
    };
    const keyed = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Idempotency-Key', 'cv-obs-keyed-1')
      .set('Cookie', authCookie)
      .send(payload);
    expect(keyed.status).toBe(201);

    const keyless = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send(payload);
    expect(keyless.status).toBe(201);
    expect(keyless.headers['x-idempotent-replay']).toBeUndefined();
    expect((keyless.body as { data: { id: number } }).data.id)
      .not.toBe((keyed.body as { data: { id: number } }).data.id);

    const count = db.prepare(
      `SELECT COUNT(*) AS c FROM invoices WHERE customer_id = ? AND invoice_date = ?`,
    ).get(customerId, '2026-11-06') as { c: number };
    expect(count.c).toBe(2);
  });

  it('still logs the keyless write observation', async () => {
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => logger);
    try {
      const res = await request(app)
        .post('/api/mobile-invoices/submit')
        .set('Cookie', authCookie)
        .send({
          customer_id: customerId,
          invoice_date: '2026-11-07',
          items: [{ item_id: itemId, quantity: 1, unit_price: 55, tax_rate: 0, warehouse_id: warehouseId }],
        });
      expect(res.status).toBe(201);
      const observed = warn.mock.calls.some(call =>
        String(call[0]).includes('keyless write') && String(call[0]).includes('mobile_invoice'),
      );
      expect(observed).toBe(true);
    } finally {
      warn.mockRestore();
    }
  });
});
