import request from 'supertest';
import app from '../app';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

function expectDeprecationHeaders(response: request.Response): void {
  expect(response.headers.deprecation).toBe('true');
  expect(response.headers.warning).toContain('/api/invoices');
  expect(response.headers.link).toBe('</api/invoices>; rel="successor-version"');
  expect(response.headers['x-deprecated-endpoint']).toBe('/api/mobile-invoices');
}

describe('deprecated mobile invoice API', () => {
  let authCookie = '';

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  it('adds deprecation metadata while preserving the tax-rate response', async () => {
    const response = await request(app)
      .get('/api/mobile-invoices/tax-rates')
      .set('Cookie', authCookie);

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(Array.isArray(response.body.data)).toBe(true);
    expectDeprecationHeaders(response);
  });

  it('preserves submit validation responses while marking the route deprecated', async () => {
    const response = await request(app)
      .post('/api/mobile-invoices/submit')
      .set('Cookie', authCookie)
      .send({ customer_id: 0, invoice_date: '2026-01-01', items: [{}] });

    expect(response.status).toBe(400);
    expect(response.body).toEqual({ error: 'Customer is required', field: 'customer_id' });
    expectDeprecationHeaders(response);
  });

  it('marks return compatibility responses without changing their contract', async () => {
    const response = await request(app)
      .post('/api/mobile-invoices/999999/return')
      .set('Cookie', authCookie)
      .send({ items: [] });

    expect(response.status).toBe(400);
    expect(response.body).toEqual({
      success: false,
      error: 'Invalid request: items must be a non-empty array',
    });
    expectDeprecationHeaders(response);
  });
});
