import request from 'supertest';
import app from '../app';
import db from '../config/database';

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
  const list = Array.isArray(cookies) ? cookies : [cookies];
  const token = list.find((c: string) => c.startsWith('token='));
  return token ? token.split(';')[0] : '';
}

type BorrowerRow = {
  name: string;
  phone: string | null;
  linked_type: string | null;
  linked_id: number | null;
};

describe('borrower field updates', () => {
  let authCookie = '';
  let seq = 0;
  const createdIds: number[] = [];
  const uniqueName = (prefix: string) => `${prefix}-${Date.now()}-${seq++}`;

  const create = (body: object) =>
    request(app).post('/api/owner-equity/borrowers').set('Cookie', authCookie).send(body);
  const update = (id: number, body: object) =>
    request(app).put(`/api/owner-equity/borrowers/${id}`).set('Cookie', authCookie).send(body);
  const row = (id: number): BorrowerRow =>
    db.prepare('SELECT name, phone, linked_type, linked_id FROM owner_personal_loan_borrowers WHERE id = ?')
      .get(id) as BorrowerRow;

  const make = async (body: object): Promise<number> => {
    const res = await create(body);
    expect(res.status).toBe(201);
    createdIds.push(res.body.data.id);
    return res.body.data.id;
  };

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  afterAll(() => {
    const remove = db.prepare('DELETE FROM owner_personal_loan_borrowers WHERE id = ?');
    for (const id of createdIds) remove.run(id);
  });

  it('updates each optional field independently, trims name and nulls empty values', async () => {
    const id = await make({ name: uniqueName('Independent'), phone: '111' });

    let res = await update(id, { name: '  Renamed  ' });
    expect(res.status).toBe(200);
    expect(res.body.data.name).toBe('Renamed');
    expect(res.body.data.phone).toBe('111');

    res = await update(id, { phone: '222' });
    expect(res.status).toBe(200);
    expect(res.body.data.phone).toBe('222');

    res = await update(id, { phone: '' });
    expect(res.status).toBe(200);
    expect(res.body.data.phone).toBeNull();

    res = await update(id, { linked_type: 'customer' });
    expect(res.status).toBe(200);
    expect(res.body.data.linked_type).toBe('customer');

    res = await update(id, { linked_id: 42 });
    expect(res.status).toBe(200);
    expect(res.body.data.linked_id).toBe(42);

    res = await update(id, { linked_id: 0 });
    expect(res.status).toBe(200);
    expect(res.body.data.linked_id).toBeNull();

    res = await update(id, { linked_type: '' });
    expect(res.status).toBe(200);
    expect(res.body.data.linked_type).toBeNull();
  });

  it('updates all fields together and leaves the row unchanged for an empty body', async () => {
    const id = await make({ name: uniqueName('All'), phone: '111' });

    let res = await update(id, {
      name: 'All Fields',
      phone: '333',
      linked_type: 'supplier',
      linked_id: 7,
    });
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      name: 'All Fields',
      phone: '333',
      linked_type: 'supplier',
      linked_id: 7,
    });

    const before = row(id);
    res = await update(id, {});
    expect(res.status).toBe(200);
    expect(row(id)).toEqual(before);
  });

  it('rejects an empty name without changing the row', async () => {
    const id = await make({ name: uniqueName('Empty'), phone: '111' });
    const before = row(id);

    const res = await update(id, { name: '   ' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ success: false, error: 'Borrower name cannot be empty' });
    expect(row(id)).toEqual(before);
  });

  it('rejects a duplicate name and link', async () => {
    const dupName = uniqueName('Duplicate');
    await make({ name: dupName, linked_type: 'customer', linked_id: 1 });
    const id = await make({ name: uniqueName('Other') });
    const before = row(id);

    const res = await update(id, { name: dupName, linked_type: 'customer', linked_id: 1 });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      success: false,
      error: 'A borrower with this name and link already exists',
    });
    expect(row(id)).toEqual(before);
  });

  it('returns 404 for an unknown borrower', async () => {
    const res = await update(999999, { name: 'Nobody' });
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ success: false, error: 'Borrower not found' });
  });
});
