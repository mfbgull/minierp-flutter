import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

describe('company lifecycle API', () => {
  let cookie: string;
  beforeAll(async () => { cookie = await getAuthCookie(); });
  const base = '/api/inventory/item-companies';
  it('creates canonical names, renames, archives, restores and deletes unused companies', async () => {
    const created = await request(app).post(base).set('Cookie', cookie).send({ company_name: ' Lifecycle Company ' });
    expect(created.status).toBe(201);
    const id = created.body.id;
    expect(created.body.company_name).toBe('Lifecycle Company');
    const duplicate = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'lifecycle company' });
    expect(duplicate.body.id).toBe(id);
    expect(duplicate.body.company_name).toBe('Lifecycle Company');
    expect((await request(app).put(`${base}/${id}`).set('Cookie', cookie).send({ company_name: 'Renamed Company' })).status).toBe(200);
    expect((await request(app).post(`${base}/${id}/archive`).set('Cookie', cookie)).body.is_active).toBe(0);
    expect((await request(app).post(`${base}/${id}/restore`).set('Cookie', cookie)).body.is_active).toBe(1);
    expect((await request(app).delete(`${base}/${id}`).set('Cookie', cookie)).status).toBe(200);
    expect((await request(app).get(`${base}/${id}`).set('Cookie', cookie)).status).toBe(404);
  });
  it('retains referenced companies even for inactive products', async () => {
    const created = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'Referenced Company' });
    const id = created.body.id;
    db.prepare('INSERT INTO items(item_code,item_name,unit_of_measure,company_id,is_active) VALUES (?,?,?,?,0)').run('COMP-REF', 'Referenced product', 'Nos', id);
    const rejected = await request(app).delete(`${base}/${id}`).set('Cookie', cookie);
    expect(rejected.status).toBe(409);
    expect(rejected.body.error).toContain('archive');
    expect((await request(app).get(`${base}/${id}/products`).set('Cookie', cookie)).body.pagination.totalItems).toBe(1);
  });
  it('rejects invalid input and unauthenticated mutations', async () => {
    expect((await request(app).post(base).set('Cookie', cookie).send({ company_name: ' ' })).status).toBe(400);
    expect((await request(app).get(`${base}/invalid`).set('Cookie', cookie)).status).toBe(400);
    expect((await request(app).post(base).send({ company_name: 'Unauthorized' })).status).toBe(401);
  });

  it('rejects rename conflicts and archived names on create', async () => {
    const first = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'Conflict Alpha' });
    const second = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'Conflict Beta' });
    expect((await request(app).put(`${base}/${second.body.id}`).set('Cookie', cookie)
      .send({ company_name: 'conflict alpha' })).status).toBe(409);

    await request(app).post(`${base}/${first.body.id}/archive`).set('Cookie', cookie);
    const reused = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'CONFLICT ALPHA' });
    expect(reused.status).toBe(409);
    expect(reused.body.error).toMatch(/archived/i);
  });

  it('filters active, archived and all companies', async () => {
    const active = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'Filter Active' });
    const archived = await request(app).post(base).set('Cookie', cookie).send({ company_name: 'Filter Archived' });
    await request(app).post(`${base}/${archived.body.id}/archive`).set('Cookie', cookie);

    const activeList = await request(app).get(`${base}?search=Filter&status=active`).set('Cookie', cookie);
    expect(activeList.body.data.map((c: { id: number }) => c.id)).toEqual([active.body.id]);
    const archivedList = await request(app).get(`${base}?search=Filter&status=archived`).set('Cookie', cookie);
    expect(archivedList.body.data.map((c: { id: number }) => c.id)).toEqual([archived.body.id]);
    const allList = await request(app).get(`${base}?search=Filter&status=all`).set('Cookie', cookie);
    expect(allList.body.data.map((c: { id: number }) => c.id).sort()).toEqual([active.body.id, archived.body.id].sort());
  });
});

describe('item company assignment', () => {
  let cookie: string;
  beforeAll(async () => { cookie = await getAuthCookie(); });
  const companies = '/api/inventory/item-companies';
  const items = '/api/inventory/items';

  it('persists an explicit company id and returns canonical company fields', async () => {
    const company = await request(app).post(companies).set('Cookie', cookie).send({ company_name: 'Beta Industries' });
    const created = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-1', item_name: 'Assigned item', company_id: company.body.id });

    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({
      company_id: company.body.id,
      manufacturer_name: 'Beta Industries',
      company_is_active: 1,
    });

    const detail = await request(app).get(`${items}/${created.body.id}`).set('Cookie', cookie);
    expect(detail.body).toMatchObject({
      company_id: company.body.id,
      manufacturer_name: 'Beta Industries',
      company_is_active: 1,
    });

    const list = await request(app).get(`${items}?search=COMP-ITEM-1`).set('Cookie', cookie);
    expect(list.body.data[0]).toMatchObject({
      company_id: company.body.id,
      manufacturer_name: 'Beta Industries',
      company_is_active: 1,
    });
    expect((await request(app).get(`${companies}?search=Beta`).set('Cookie', cookie)).body.data[0].product_count).toBe(1);
  });

  it('resolves a legacy manufacturer name to one canonical company', async () => {
    const first = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-2', item_name: 'Legacy item', manufacturer_name: '  Gamma Corp  ' });
    expect(first.status).toBe(201);
    expect(first.body.manufacturer_name).toBe('Gamma Corp');
    expect(typeof first.body.company_id).toBe('number');

    const second = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-3', item_name: 'Legacy item two', manufacturer_name: 'gamma corp' });
    expect(second.body.company_id).toBe(first.body.company_id);
    expect(second.body.manufacturer_name).toBe('Gamma Corp');
  });

  it('rejects a new assignment to an archived company', async () => {
    const company = await request(app).post(companies).set('Cookie', cookie).send({ company_name: 'Archived Company' });
    await request(app).post(`${companies}/${company.body.id}/archive`).set('Cookie', cookie);

    const rejected = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-4', item_name: 'Rejected item', company_id: company.body.id });
    expect(rejected.status).toBe(400);
    expect(rejected.body.error).toMatch(/archived/i);
  });

  it('keeps an existing archived assignment during an unrelated edit', async () => {
    const company = await request(app).post(companies).set('Cookie', cookie).send({ company_name: 'Archived Later' });
    const item = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-5', item_name: 'Existing item', company_id: company.body.id });
    await request(app).post(`${companies}/${company.body.id}/archive`).set('Cookie', cookie);

    const updated = await request(app).put(`${items}/${item.body.id}`).set('Cookie', cookie)
      .send({ item_name: 'Existing item renamed', unit_of_measure: 'Nos', company_id: company.body.id });
    expect(updated.status).toBe(200);
    expect(updated.body).toMatchObject({
      company_id: company.body.id,
      company_is_active: 0,
      manufacturer_name: 'Archived Later',
    });
  });

  it('rejects an unknown company id and clears a blank manufacturer', async () => {
    const rejected = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-6', item_name: 'Unknown company', company_id: 999999 });
    expect(rejected.status).toBe(400);

    const company = await request(app).post(companies).set('Cookie', cookie).send({ company_name: 'Cleared Company' });
    const item = await request(app).post(items).set('Cookie', cookie)
      .send({ item_code: 'COMP-ITEM-7', item_name: 'Clearable item', company_id: company.body.id });
    const cleared = await request(app).put(`${items}/${item.body.id}`).set('Cookie', cookie)
      .send({ item_name: 'Clearable item', unit_of_measure: 'Nos', manufacturer_name: '   ' });
    expect(cleared.status).toBe(200);
    expect(cleared.body.company_id).toBeNull();
    expect(cleared.body.manufacturer_name).toBeNull();
  });
});
