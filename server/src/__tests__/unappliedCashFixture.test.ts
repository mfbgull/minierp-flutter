import fs from 'fs';
import path from 'path';
import express from 'express';
import request from 'supertest';
import db, { dbSeedReady } from '../config/database';
import accounting from '../services/accountingService';
import * as checks from './helpers/accountingInvariants';
import { pruneIdempotencyKeys } from '../utils/idempotency';
import { createFixtureApps } from '../../scripts/fixtures/unapplied-cash-ui.cjs';

const directory = fs.mkdtempSync(path.join(__dirname, '../../.tmp-test/f7-http-'));
fs.writeFileSync(path.join(directory, 'fixture-id'), 'owned');
const downstream = express();
downstream.get('/api/unapplied-cash/capabilities', (_req, res) => res.json({ supported: true }));
downstream.post('/api/customers/:id/unapplied-cash', (req, res) => res.status(req.params.id === '9' ? 400 : 200).json({ committed: true }));
const { api, control } = createFixtureApps({
  db, accounting, checks, pruneIdempotencyKeys, directory, marker: 'owned',
  before: [], fingerprints: () => [], app: downstream,
});
const command = (body: object) => request(control).post('/command').set('X-Fixture-Token', 'mini-erp-f7-local').send(body);
beforeAll(async () => { await dbSeedReady; });
afterAll(() => fs.rmSync(directory, { recursive: true, force: true }));

it('rejects missing/wrong control tokens and invalid roles/actions', async () => {
  await request(control).get('/health').expect(403);
  await request(control).get('/health').set('X-Fixture-Token', 'wrong').expect(403);
  await command({ action: 'role', kind: 'admin' }).expect(400);
  await command({ action: 'unknown' }).expect(400);
  await command({ action: 'drop', path: '/api/settings' }).expect(400);
});

it('creates restricted users and real customers/invoices in the isolated database', async () => {
  for (const kind of ['read', 'partial']) {
    const role = await command({ action: 'role', kind }).expect(200);
    expect(role.body.token).toEqual(expect.any(String));
    expect(role.body.user.permissions.map((permission: { action: string }) => permission.action))
      .toEqual(kind === 'read' ? ['read'] : ['read', 'update']);
  }
  await command({ action: 'invoice', customerId: -1 }).expect(404);
  const customer = await command({ action: 'customer' }).expect(200);
  const invoice = await command({ action: 'invoice', customerId: customer.body.id }).expect(200);
  expect(db.prepare('SELECT balance_amount FROM invoices WHERE id=?').get(invoice.body.invoiceId)).toEqual({ balance_amount: 400 });
  expect(checks.glImbalances(db)).toEqual({ groups: [], totalDiff: 0 });
});

it('toggles capabilities and disconnects offline reads without affecting control requests', async () => {
  await request(api).get('/api/unapplied-cash/capabilities').expect(200, { supported: true });
  await command({ action: 'capabilities', unsupported: true }).expect(200);
  await request(api).get('/api/unapplied-cash/capabilities').expect(200, { success: true, data: {} });
  await command({ action: 'capabilities', unsupported: false }).expect(200);
  await command({ action: 'offline', enabled: true }).expect(200);
  await expect(request(api).get('/api/unapplied-cash/capabilities')).rejects.toThrow();
  await command({ action: 'offline', enabled: false }).expect(200);
  await request(api).get('/api/unapplied-cash/capabilities').expect(200);
});

it('drops a successful write response once, preserves errors, and reports write attempts', async () => {
  await command({ action: 'drop', path: '/api/customers/9/unapplied-cash' }).expect(200);
  await request(api).post('/api/customers/9/unapplied-cash').expect(400);
  await command({ action: 'drop', path: '/api/customers/1/unapplied-cash' }).expect(200);
  await expect(request(api).post('/api/customers/1/unapplied-cash')).rejects.toThrow();
  await request(api).post('/api/customers/1/unapplied-cash').expect(200);
  await command({ action: 'period', closed: true }).expect(200, { closed: true });
  await command({ action: 'period', closed: false }).expect(200, { closed: false });
  await command({ action: 'prune' }).expect(200, { pruned: 0, retained: 0 });
  const status = await request(control).get('/status').set('X-Fixture-Token', 'mini-erp-f7-local').expect(200);
  expect(status.body.writeRequests).toBe(3);
  expect(status.body.canonicalUnchanged).toBe(true);
  await request(control).get('/health').set('X-Fixture-Token', 'mini-erp-f7-local').expect(200);
});
