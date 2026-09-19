// Integration tests for async bcrypt auth + token refresh
// (SHORTCOMINGS-FIX 2.1 + 6.1)

import request from 'supertest';
import app from '../app';

describe('Async auth (bcrypt non-blocking)', () => {
  it('login works with correct credentials', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.token).toBeDefined();
    expect(res.body.data.refreshToken).toBeDefined();
    expect(res.body.data.user).toBeDefined();
  });

  it('login fails with wrong password', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', password: 'wrong-password' });
    expect(res.status).toBe(401);
    expect(res.body.success).toBe(false);
  });

  it('login fails with missing fields', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin' });
    expect(res.status).toBe(400);
  });
});

describe('Token refresh', () => {
  let refreshToken: string;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', password: process.env.TEST_ADMIN_PASSWORD });
    refreshToken = res.body.data.refreshToken;
  });

  it('refresh endpoint returns a new access token', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.token).toBeDefined();
    expect(typeof res.body.data.token).toBe('string');
    expect(res.body.data.token.length).toBeGreaterThan(10);
  });

  it('refresh fails with invalid token', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({ refreshToken: 'invalid-token-here' });
    expect(res.status).toBe(401);
  });

  it('refresh fails with empty body', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({});
    expect(res.status).toBe(400);
  });
});
