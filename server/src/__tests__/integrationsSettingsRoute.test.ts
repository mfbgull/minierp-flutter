import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import settingsController from '../controllers/settingsController';
import logger from '../utils/logger';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `PUT /api/integrations/settings/:service`
 * inline handler (CRAP 30).
 */
describe('integration settings routes', () => {
  let cookie = '';

  beforeAll(async () => {
    cookie = await getAuthCookie();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('returns the integration status map', async () => {
    const res = await request(app).get('/api/integrations/settings').set('Cookie', cookie);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('email');
    expect(res.body).toHaveProperty('notifications');
  });

  it('updates a known service', async () => {
    const res = await request(app)
      .put('/api/integrations/settings/email')
      .set('Cookie', cookie)
      .send({ enabled: true, apiKey: 'key-123', from_email: 'erp@example.com' });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ success: true, message: 'Settings updated successfully' });
  });

  it('rejects an unknown service with 400', async () => {
    const res = await request(app)
      .put('/api/integrations/settings/nope')
      .set('Cookie', cookie)
      .send({ enabled: true });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Invalid service name' });
  });

  it('returns a sanitized 500 for an unexpected failure', async () => {
    jest.spyOn(logger, 'error').mockImplementation(() => logger);
    jest.spyOn(settingsController, 'updateIntegrationSettings').mockImplementation(() => {
      throw new Error('forced settings failure');
    });

    const res = await request(app)
      .put('/api/integrations/settings/email')
      .set('Cookie', cookie)
      .send({ enabled: true });

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to update integration settings' });
  });
});
