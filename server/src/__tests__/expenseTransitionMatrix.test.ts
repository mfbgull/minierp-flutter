/**
 * TASK 25 Option A: expense status machine Draft → Recorded → Cancelled.
 * Cash/GL semantics: leave-Draft posts; Recorded is GL-worthy; Cancelled voids.
 */
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import OwnerCapitalModel, { generateCapitalNo } from '../models/OwnerCapital';

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

describe('Expense status machine (TASK 25 Option A)', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    // Draft → Recorded is funds-guarded; seed capital so cash covers postings.
    db.transaction(() => {
      OwnerCapitalModel.create(db, {
        capital_no: generateCapitalNo(db, '2026-01-01'),
        capital_date: '2026-01-01',
        amount: 1_000_000,
        payment_method: 'Cash',
        created_by: 1,
      });
    })();
  });

  async function createExpense(): Promise<number> {
    const res = await request(app)
      .post('/api/expenses')
      .set('Cookie', authCookie)
      .send({
        expense_date: '2026-09-20',
        expense_category: 'Utilities',
        description: 'transition matrix',
        amount: 50,
        payment_method: 'cash',
      });
    expect([200, 201]).toContain(res.status);
    const row = res.body?.data ?? res.body;
    expect(row.status).toBe('Draft');
    return row.id as number;
  }

  async function setStatus(id: number, status: string) {
    return request(app)
      .put(`/api/expenses/${id}`)
      .set('Cookie', authCookie)
      .send({ status });
  }

  function activeExpenseLines(expenseId: number): number {
    const r = db.prepare(
      `SELECT COUNT(*) as n FROM journal_lines
       WHERE reference_type = 'EXPENSE' AND reference_id = ? AND voided = 0`
    ).get(expenseId) as { n: number };
    return r.n;
  }

  it('status-options returns only Draft, Recorded, Cancelled', async () => {
    const res = await request(app)
      .get('/api/expenses/status-options')
      .set('Cookie', authCookie);
    expect(res.status).toBe(200);
    const values = (res.body?.data ?? res.body)
      .map((o: { value: string }) => o.value)
      .sort();
    expect(values).toEqual(['Cancelled', 'Draft', 'Recorded']);
  });

  it('allows Draft → Recorded (posts GL)', async () => {
    const id = await createExpense();
    expect(activeExpenseLines(id)).toBe(0);
    const res = await setStatus(id, 'Recorded');
    expect(res.status).toBe(200);
    expect(activeExpenseLines(id)).toBe(2);
  });

  it('allows Draft → Cancelled (no GL)', async () => {
    const id = await createExpense();
    const res = await setStatus(id, 'Cancelled');
    expect(res.status).toBe(200);
    expect(activeExpenseLines(id)).toBe(0);
  });

  it('allows Recorded → Cancelled (voids GL)', async () => {
    const id = await createExpense();
    await setStatus(id, 'Recorded');
    expect(activeExpenseLines(id)).toBe(2);
    const res = await setStatus(id, 'Cancelled');
    expect(res.status).toBe(200);
    expect(activeExpenseLines(id)).toBe(0);
  });

  it('rejects Recorded → Draft', async () => {
    const id = await createExpense();
    await setStatus(id, 'Recorded');
    const res = await setStatus(id, 'Draft');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot move an expense from Recorded to Draft/i);
  });

  it('rejects Cancelled → Draft', async () => {
    const id = await createExpense();
    await setStatus(id, 'Cancelled');
    const res = await setStatus(id, 'Draft');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot move an expense from Cancelled to Draft/i);
  });

  it('rejects Cancelled → Recorded', async () => {
    const id = await createExpense();
    await setStatus(id, 'Cancelled');
    const res = await setStatus(id, 'Recorded');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Cannot move an expense from Cancelled to Recorded/i);
  });

  it('rejects legacy vocabulary Submitted/Approved/Paid as invalid status', async () => {
    for (const legacy of ['Submitted', 'Approved', 'Paid']) {
      const id = await createExpense();
      const res = await setStatus(id, legacy);
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/Invalid status/i);
    }
  });

  it('rejects field edits on a Recorded expense (immutable)', async () => {
    const id = await createExpense();
    await setStatus(id, 'Recorded');
    const res = await request(app)
      .put(`/api/expenses/${id}`)
      .set('Cookie', authCookie)
      .send({ description: 'edited after record' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/immutable/i);
  });
});
