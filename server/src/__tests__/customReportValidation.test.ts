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

function baseConfig(sort?: unknown): Record<string, unknown> {
  return {
    entity: 'invoices',
    columns: [{ field: 'total_amount' }],
    ...(sort === undefined ? {} : { sort }),
  };
}

describe('custom report sort validation', () => {
  let authCookie = '';
  const createdIds: number[] = [];
  let nameSeq = 0;

  const post = (config: Record<string, unknown>) =>
    request(app)
      .post('/api/reports/custom')
      .set('Cookie', authCookie)
      .send({ name: `sort-validation-${Date.now()}-${nameSeq++}`, config });

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');
  });

  afterAll(() => {
    const remove = db.prepare('DELETE FROM custom_reports WHERE id = ?');
    for (const id of createdIds) remove.run(id);
  });

  it('does not validate sort when it is absent', async () => {
    const res = await post(baseConfig());
    expect(res.status).toBe(201);
    createdIds.push(res.body.data.id);
  });

  it('does not validate sort when it is not an array', async () => {
    const res = await post(baseConfig({ field: 'total_amount' }));
    expect(res.status).toBe(201);
    createdIds.push(res.body.data.id);
  });

  it('accepts a valid array and an empty direction', async () => {
    const res = await post(baseConfig([{ field: 'total_amount', direction: '' }]));
    expect(res.status).toBe(201);
    createdIds.push(res.body.data.id);
  });

  it('accepts asc and desc case-insensitively', async () => {
    const asc = await post(baseConfig([{ field: 'total_amount', direction: 'ASC' }]));
    expect(asc.status).toBe(201);
    createdIds.push(asc.body.data.id);

    const desc = await post(baseConfig([{ field: 'total_amount', direction: 'desc' }]));
    expect(desc.status).toBe(201);
    createdIds.push(desc.body.data.id);
  });

  it('rejects a missing sort field', async () => {
    const res = await post(baseConfig([{}]));
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Invalid report config');
    expect(res.body.details).toContainEqual({
      field: 'sort[0].field',
      message: 'Sort field name is required',
    });
  });

  it('rejects a non-string sort field', async () => {
    const res = await post(baseConfig([{ field: 42 }]));
    expect(res.status).toBe(400);
    expect(res.body.details).toContainEqual({
      field: 'sort[0].field',
      message: 'Sort field name is required',
    });
  });

  it('rejects an unknown field with an entity-qualified message', async () => {
    const res = await post(baseConfig([{ field: 'not_a_field' }]));
    expect(res.status).toBe(400);
    expect(res.body.details).toContainEqual({
      field: 'sort[0].field',
      message: 'Sort field "not_a_field" not found on entity "invoices"',
    });
  });

  it('accepts a computed-column field', async () => {
    const res = await post({
      entity: 'invoices',
      columns: [{ field: 'total_amount' }],
      computedColumns: [{ name: 'doubled', expression: 'total_amount * 2', type: 'number' }],
      sort: [{ field: 'doubled', direction: 'asc' }],
    });
    expect(res.status).toBe(201);
    createdIds.push(res.body.data.id);
  });

  it('rejects an invalid direction', async () => {
    const res = await post(baseConfig([{ field: 'total_amount', direction: 'sideways' }]));
    expect(res.status).toBe(400);
    expect(res.body.details).toContainEqual({
      field: 'sort[0].direction',
      message: 'Sort direction must be "asc" or "desc"',
    });
  });

  it('accumulates errors in input order across multiple entries', async () => {
    const res = await post(baseConfig([{ field: '' }, { field: 'not_a_field', direction: 'sideways' }]));
    expect(res.status).toBe(400);
    expect(res.body.details.map((d: { field: string }) => d.field)).toEqual([
      'sort[0].field',
      'sort[1].field',
      'sort[1].direction',
    ]);
  });
});
