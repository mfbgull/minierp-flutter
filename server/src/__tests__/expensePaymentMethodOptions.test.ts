import request from 'supertest';
import app from '../app';
import { isValidPaymentMethod } from '../services/cashService';

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) {
  throw new Error('TEST_ADMIN_PASSWORD environment variable must be set.');
}

async function getAuthCookie(): Promise<string> {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('TASK 26 payment method options', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  async function paymentMethodOptions(path: string): Promise<string[]> {
    const res = await request(app)
      .get(path)
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    const data = res.body?.data ?? res.body;
    return (data as Array<{ value: string }>).map((o) => o.value);
  }

  it('expense options exclude Other and every value is server-valid', async () => {
    const options = await paymentMethodOptions('/api/expenses/payment-method-options');
    expect(options).not.toContain('Other');
    expect(options.length).toBeGreaterThan(0);
    for (const value of options) {
      expect(isValidPaymentMethod(value)).toBe(true);
    }
  });

  it('owner-equity options exclude Other and every value is server-valid', async () => {
    const options = await paymentMethodOptions('/api/owner-equity/payment-method-options');
    expect(options).not.toContain('Other');
    expect(options.length).toBeGreaterThan(0);
    for (const value of options) {
      expect(isValidPaymentMethod(value)).toBe(true);
    }
  });

  it('every advertised expense payment method saves successfully', async () => {
    const options = await paymentMethodOptions('/api/expenses/payment-method-options');
    for (const method of options) {
      const res = await request(app)
        .post('/api/expenses')
        .set('Cookie', authCookie)
        .send({
          expense_date: '2026-09-21',
          expense_category: 'Utilities',
          description: `payment method ${method}`,
          amount: 1,
          payment_method: method,
        });
      expect({ method, status: res.status }).toEqual({ method, status: 201 });
    }
  });

  it('rejects payment_method Other on create', async () => {
    const res = await request(app)
      .post('/api/expenses')
      .set('Cookie', authCookie)
      .send({
        expense_date: '2026-09-21',
        expense_category: 'Utilities',
        description: 'other method',
        amount: 1,
        payment_method: 'Other',
      });
    expect(res.status).toBe(400);
    expect(String(res.body?.error ?? '')).toMatch(/Invalid payment_method/i);
  });
});
