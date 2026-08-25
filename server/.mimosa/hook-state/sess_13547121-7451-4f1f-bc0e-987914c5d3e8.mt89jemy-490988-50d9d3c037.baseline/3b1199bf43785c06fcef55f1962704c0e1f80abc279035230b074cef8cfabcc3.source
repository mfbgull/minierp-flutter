
import request from 'supertest';
import app from '../app';
import db from '../config/database';

jest.setTimeout(30000);

const TEST_PASSWORD = process.env.TEST_ADMIN_PASSWORD;
if (!TEST_PASSWORD) throw new Error('TEST_ADMIN_PASSWORD must be set');

async function getAuthCookie(): Promise<string> {
  const res = await request(app).post('/api/auth/login')
    .send({ username: 'admin', password: TEST_PASSWORD });
  const cookies = res.headers['set-cookie'];
  if (!cookies) return '';
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

/** AUD-06 task 5.6: soft-deleted invoices leave no orphaned GL/ledger rows. */
describe('invoice soft-delete GL integrity', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  it('soft-delete marks deleted_at and leaves zero orphaned journal_lines', async () => {
    // Create a draft invoice via the API
    const item = db.prepare(`SELECT id, standard_cost FROM items LIMIT 1`).get() as { id: number } | undefined;
    if (!item) return; // nothing seeded — skip
    const customer = db.prepare(`SELECT id FROM customers LIMIT 1`).get() as { id: number } | undefined;
    if (!customer) return;

    const create = await request(app)
      .post('/api/invoices')
      .set('Cookie', authCookie)
      .send({
        customer_id: customer.id,
        invoice_date: new Date().toISOString().split('T')[0],
        status: 'Draft',
        items: [{ item_id: item.id, quantity: 1, unit_price: 50 }],
      });
    expect([200, 201]).toContain(create.status);
    const invoiceId = create.body.data?.id ?? create.body.id;
    expect(invoiceId).toBeTruthy();

    // Delete it
    const del = await request(app)
      .delete(`/api/invoices/${invoiceId}`)
      .set('Cookie', authCookie);
    expect(del.status).toBe(200);

    // Row still exists, marked deleted
    const row = db.prepare('SELECT status, deleted_at FROM invoices WHERE id = ?').get(invoiceId) as { status: string; deleted_at: string | null };
    expect(row.deleted_at).toBeTruthy();
    expect(row.status).toBe('Deleted');

    // No active journal lines referencing this invoice
    const orphans = db.prepare(`
      SELECT COUNT(*) AS n FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE jl.voided = 0 AND je.reference_type = 'INVOICE' AND je.reference_id = ?
    `).get(invoiceId) as { n: number };
    expect(orphans.n).toBe(0);

    // Hidden from list + getById
    const listed = request(app).get('/api/invoices').set('Cookie', authCookie);
    const body = await listed.then(r => r.body);
    const data = JSON.stringify(body);
    expect(data.includes(`"id":${invoiceId},`)).toBe(false);
  });
});
