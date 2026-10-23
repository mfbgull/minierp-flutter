import { afterEach, beforeAll, describe, expect, it, jest } from '@jest/globals';
import { Response } from 'express';
import request from 'supertest';
import app from '../app';
import { createBOM } from '../controllers/bomController';
import BOMModel from '../models/BOM';
import { AuthRequest } from '../types';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

/**
 * Fallow health remediation — `bomController.createBOM` (CRAP 132).
 *
 * The route's Zod schema rejects missing top-level fields before the
 * controller runs, so those guards are exercised directly. Per-item guards,
 * success and the error path run through the mounted route.
 */
describe('bomController.createBOM', () => {
  let cookie = '';
  let finishedItemId = 0;
  let materialItemId = 0;
  let seq = 0;

  beforeAll(async () => {
    cookie = await getAuthCookie();
    seq += 1;
    const suffix = `${Date.now()}-${seq}`;
    const finished = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', cookie)
      .send({
        item_code: `BOM-FG-${suffix}`,
        item_name: `BOM finished ${suffix}`,
        unit_of_measure: 'Nos',
        standard_cost: 10,
        is_finished_good: 1,
        is_active: 1,
      });
    expect(finished.status).toBe(201);
    finishedItemId = finished.body.id;
    const material = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', cookie)
      .send({
        item_code: `BOM-RM-${suffix}`,
        item_name: `BOM material ${suffix}`,
        unit_of_measure: 'Nos',
        standard_cost: 4,
        is_purchased: 1,
        is_active: 1,
      });
    expect(material.status).toBe(201);
    materialItemId = material.body.id;
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  function callDirect(body: Record<string, unknown>): {
    status: jest.Mock;
    json: jest.Mock;
    next: jest.Mock;
  } {
    const status = jest.fn();
    const json = jest.fn();
    const res = { status, json } as unknown as Response;
    status.mockReturnValue(res);
    const next = jest.fn();
    createBOM({ body } as unknown as AuthRequest, res, next);
    return { status, json, next };
  }

  const validBody = () => ({
    finished_item_id: finishedItemId,
    quantity: 1,
    bom_name: `BOM ${Date.now()}`,
    items: [{ item_id: materialItemId, quantity: 2 }],
  });

  const post = (body: Record<string, unknown>) =>
    request(app).post('/api/boms').set('Cookie', cookie).send(body);

  it('rejects a missing finished item at the controller guard', () => {
    const { status, json } = callDirect({
      quantity: 1,
      bom_name: 'BOM',
      items: [{ item_id: materialItemId, quantity: 1 }],
    });
    expect(status).toHaveBeenCalledWith(400);
    expect(json).toHaveBeenCalledWith(
      expect.objectContaining({ error: expect.stringMatching(/required/i) }),
    );
  });

  it('rejects a missing quantity at the controller guard', () => {
    const { status } = callDirect({
      finished_item_id: finishedItemId,
      bom_name: 'BOM',
      items: [{ item_id: materialItemId, quantity: 1 }],
    });
    expect(status).toHaveBeenCalledWith(400);
  });

  it('rejects a missing name at the controller guard', () => {
    const { status } = callDirect({
      finished_item_id: finishedItemId,
      quantity: 1,
      items: [{ item_id: materialItemId, quantity: 1 }],
    });
    expect(status).toHaveBeenCalledWith(400);
  });

  it('rejects a missing items array at the controller guard', () => {
    const { status } = callDirect({
      finished_item_id: finishedItemId,
      quantity: 1,
      bom_name: 'BOM',
    });
    expect(status).toHaveBeenCalledWith(400);
  });

  it('rejects an empty items array at the controller guard', () => {
    const { status } = callDirect({
      finished_item_id: finishedItemId,
      quantity: 1,
      bom_name: 'BOM',
      items: [],
    });
    expect(status).toHaveBeenCalledWith(400);
  });

  it('rejects a line with no item id', async () => {
    const res = await post({
      ...validBody(),
      items: [{ quantity: 2 }],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Each item/i);
  });

  it('rejects a line with no quantity', async () => {
    const res = await post({
      ...validBody(),
      items: [{ item_id: materialItemId }],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Each item/i);
  });

  it('rejects a line with a non-positive quantity', async () => {
    const res = await post({
      ...validBody(),
      items: [{ item_id: materialItemId, quantity: 0 }],
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Each item/i);
  });

  it('creates a BOM with valid lines', async () => {
    const res = await post(validBody());
    expect(res.status).toBe(201);
    expect(res.body.bom_no).toMatch(/^BOM-/);
    expect(res.body.items).toHaveLength(1);
  });

  it('passes a model failure to the error middleware', async () => {
    jest.spyOn(BOMModel, 'create').mockImplementationOnce(() => {
      throw new Error('forced BOM failure');
    });
    const res = await post(validBody());
    expect(res.status).toBe(500);
  });
});
