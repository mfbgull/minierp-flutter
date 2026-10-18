import { beforeAll, beforeEach, test, expect, jest } from '@jest/globals';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import ledgerUtils from '../utils/ledgerUtils';
import logger from '../utils/logger';
import { getAuthCookie, createCustomer } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { pruneIdempotencyKeys } from '../utils/idempotency';

let cookie: string;
let customerId: number;
let sequence = 0;
beforeAll(async () => {
  cookie = await getAuthCookie();
  expect(cookie).not.toBe('');
});
beforeEach(async () => { customerId = await createCustomer(`Held cash API ${++sequence}`, cookie); });

function post(path: string, body: object, key = `cash-api-${++sequence}`) {
  return request(app).post(path).set('Cookie', cookie).set('Idempotency-Key', key).send(body);
}

function receipt(amount = 500) {
  return post(`/api/customers/${customerId}/unapplied-cash`, { amount, operation_date: '2026-10-01', payment_method: 'Cash' });
}

function invoice(owner = customerId, amount = 1000): number {
  const invoiceNo = `CASH-API-${++sequence}`;
  const invoiceId = Number(db.prepare(`INSERT INTO invoices (invoice_no,customer_id,invoice_date,total_amount,balance_amount,paid_amount)
    VALUES (?,?,'2026-10-01',?,?,0)`).run(invoiceNo, owner, amount, amount).lastInsertRowid);
  ledgerUtils.createLedgerEntry(owner, '2026-10-01', 'INVOICE', invoiceNo, amount, 0, 'API fixture invoice', db);
  ledgerUtils.recalcCustomerBalanceFromLedger(owner, db);
  const debit = AccountingService.getAccountByCode(db, '1100');
  const credit = AccountingService.getAccountByCode(db, '4000');
  if (!debit || !credit) throw new Error('Missing fixture accounts');
  AccountingService.postEntry(db, { entry_date: '2026-10-01', description: 'API fixture invoice', reference_type: 'INVOICE', reference_id: invoiceId,
    lines: [{ account_id: debit.id, debit: amount }, { account_id: credit.id, credit: amount }] });
  return invoiceId;
}

test('mounted receive/apply/refund retain receipt identity and preserve A-N', async () => {
  const received = await receipt();
  expect(received.status).toBe(201);
  expectAllInvariantsHold('received advance');
  const invoiceId = invoice(customerId, 400);
  expectAllInvariantsHold('invoice issued');
  const applied = await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 400 }] });
  expect(applied.status).toBe(200);
  expectAllInvariantsHold('cash applied');
  const refunded = await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 100, payment_method: 'Cash' });
  expect(refunded.status).toBe(200);
  expect(db.prepare('SELECT amount,payment_kind FROM payments WHERE customer_id=? ORDER BY id').all(customerId)).toEqual([
    { amount: 500, payment_kind: 'UNAPPLIED_RECEIPT' }, { amount: -100, payment_kind: 'REFUND' },
  ]);
  expect(db.prepare('SELECT paid_amount,balance_amount FROM invoices WHERE id=?').get(invoiceId)).toEqual({ paid_amount: 400, balance_amount: 0 });
  expect(db.prepare('SELECT current_balance,credit_balance FROM customers WHERE id=?').get(customerId)).toEqual({ current_balance: 0, credit_balance: 0 });
  expect(db.prepare('SELECT payment_id,amount FROM payment_allocations WHERE invoice_id=?').get(invoiceId)).toEqual({ payment_id: received.body.data.paymentId, amount: 400 });
  expectAllInvariantsHold('mounted lifecycle');
});

test('reversed unused receipt cannot subsequently fund an application or refund', async () => {
  const received = await receipt(60);
  const invoiceId = invoice(customerId, 400);
  expect((await post(`/api/payments/${received.body.data.paymentId}/reverse`, { reason: 'F7 unused receipt' })).status).toBe(200);
  expect((await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 1 }] })).status).toBe(409);
  expect((await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-02', amount: 1, payment_method: 'Cash' })).status).toBe(409);
  expect(db.prepare('SELECT paid_amount,balance_amount FROM invoices WHERE id=?').get(invoiceId)).toEqual({ paid_amount: 0, balance_amount: 400 });
  expect(db.prepare('SELECT COUNT(*) count FROM payments WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
  expectAllInvariantsHold('unused receipt fully retired');
});

test('receive replay is atomic and changed payload conflicts', async () => {
  const path = `/api/customers/${customerId}/unapplied-cash`;
  const body = { amount: 500, operation_date: '2026-10-01', payment_method: 'Cash' };
  const first = await post(path, body, 'receive-replay');
  const second = await post(path, body, 'receive-replay');
  expect(first.status).toBe(201);
  expect(second.status).toBe(200);
  expect(second.body.data).toEqual(first.body.data);
  const conflict = await post(path, { ...body, amount: 501 }, 'receive-replay');
  expect(conflict.status).toBe(409);
  expect(conflict.body.error.code).toBe('IDEMPOTENCY_CONFLICT');
  expect(db.prepare('SELECT COUNT(*) count FROM payments WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
});

test('receive replays after central keys expire, including after reversal', async () => {
  const path = `/api/customers/${customerId}/unapplied-cash`;
  const body = { amount: 500, operation_date: '2026-10-01', payment_method: 'Cash' };
  const first = await post(path, body, 'permanent-receive');
  expect(first.status).toBe(201);
  const paymentId = first.body.data.paymentId;
  db.prepare("UPDATE idempotency_keys SET completed_at='2020-01-01' WHERE scope='unapplied_cash.receive' AND key=?").run(`${customerId}:permanent-receive`);
  expect(pruneIdempotencyKeys(db, 30, new Date('2020-03-01T00:00:00Z'))).toBeGreaterThan(0);
  expect(db.prepare("SELECT resource_id FROM idempotency_keys WHERE scope='unapplied_cash.receive' AND key=?").get(`${customerId}:permanent-receive`)).toBeUndefined();
  const retry = await post(path, body, 'permanent-receive');
  expect(retry.status).toBe(200);
  expect(retry.body.data).toEqual(first.body.data);
  expect((await post(path, { ...body, amount: 501 }, 'permanent-receive')).status).toBe(409);
  expect((await post(`/api/payments/${paymentId}/reverse`, { reason: 'Replay fixture' })).status).toBe(200);
  expect((await post(path, body, 'permanent-receive')).body.data).toEqual(first.body.data);
  expect(db.prepare('SELECT COUNT(*) count FROM payments WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
  expect(db.prepare('SELECT COUNT(*) count FROM customer_credit_sources WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
  expect(db.prepare("SELECT COUNT(*) count FROM journal_entries WHERE reference_type='UNAPPLIED_RECEIPT' AND reference_id=?").get(paymentId)).toEqual({ count: 1 });
  expectAllInvariantsHold('pruned receive replay');
});

test('cash reads expose live capacities, receipt usage and activity without a second cash inflow', async () => {
  const received = await receipt();
  const invoiceId = invoice();
  expect((await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 400 }] })).status).toBe(200);
  const refunded = await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 100 });
  expect(refunded.status).toBe(200);
  const read = await request(app).get(`/api/customers/${customerId}/unapplied-cash?operation_date=2026-10-03`).set('Cookie', cookie);
  expect(read.status).toBe(200);
  expect(read.body.data).toMatchObject({ customer_id: customerId, remaining_amount: 0, available_amount: 0, refundable_amount: 0,
    receipts: [{ payment_id: received.body.data.paymentId, original_amount: 500, applied_amount: 400, refunded_amount: 100, remaining_amount: 0, can_reverse: false }] });
  const activity = await request(app).get(`/api/customers/${customerId}/unapplied-cash/activity?fromDate=2026-10-02&toDate=2026-10-03`).set('Cookie', cookie);
  expect(activity.status).toBe(200);
  expect(activity.body.data.map((row: { operation: string }) => row.operation)).toEqual(['REFUND', 'APPLY']);
  expect(activity.body.data[1].lines).toEqual([expect.objectContaining({ invoice_id: invoiceId, amount: 400 })]);
  const hub = await request(app).get('/api/payments/unified?limit=100').set('Cookie', cookie);
  expect(hub.status).toBe(200);
  expect(hub.body.data).toEqual(expect.arrayContaining([
    expect.objectContaining({ source_id: refunded.body.data.paymentId, source: 'payment', payment_kind: 'REFUND', amount: 100, direction: 'out' }),
    expect.objectContaining({ source_id: received.body.data.paymentId, source: 'payment', payment_kind: 'UNAPPLIED_RECEIPT', amount: 500, direction: 'in' }),
  ]));
  expect((await request(app).get(`/api/payments/${received.body.data.paymentId}`).set('Cookie', cookie)).body.data.payment_kind).toBe('UNAPPLIED_RECEIPT');
  expectAllInvariantsHold('cash read lifecycle');
});

test('apply replay, conflicts, duplicate invoice amounts and source overdraw cannot double-spend', async () => {
  await receipt();
  const invoiceId = invoice();
  const body = { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 400 }] };
  const first = await post('/api/unapplied-cash/apply', body, 'apply-replay');
  expect(first.status).toBe(200);
  expect((await post('/api/unapplied-cash/apply', body, 'apply-replay')).body.data).toEqual(first.body.data);
  expect((await post('/api/unapplied-cash/apply', { ...body, allocations: [{ invoice_id: invoiceId, amount: 401 }] }, 'apply-replay')).status).toBe(409);
  expect((await post('/api/unapplied-cash/apply', body)).status).toBe(409);
  expect((await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 400, payment_method: 'Cash' })).status).toBe(409);
  expect(db.prepare("SELECT COUNT(*) count FROM journal_entries WHERE reference_type='UNAPPLIED_APPLY' AND reference_id=?").get(first.body.data.applicationId)).toEqual({ count: 1 });
});

test('refund replay creates one negative payment and conflicts on a changed amount', async () => {
  await receipt(300);
  const body = { customer_id: customerId, operation_date: '2026-10-03', amount: 300, payment_method: 'Cash' };
  const first = await post('/api/unapplied-cash/refund', body, 'refund-replay');
  expect(first.status).toBe(200);
  expect((await post('/api/unapplied-cash/refund', body, 'refund-replay')).body.data).toEqual(first.body.data);
  expect((await post('/api/unapplied-cash/refund', { ...body, amount: 301 }, 'refund-replay')).status).toBe(409);
  expect(db.prepare("SELECT COUNT(*) count FROM payments WHERE customer_id=? AND payment_kind='REFUND'").get(customerId)).toEqual({ count: 1 });
});

test('reverse retires unused cash, replays safely and cannot refund a voided source', async () => {
  const received = await receipt();
  const path = `/api/payments/${received.body.data.paymentId}/reverse`;
  expect((await post(path, { reason: 'Entered twice' }, 'reverse-replay')).status).toBe(200);
  expect((await post(path, { reason: 'Entered twice' }, 'reverse-replay')).status).toBe(200);
  expect((await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 1, payment_method: 'Cash' })).status).toBe(409);
  expectAllInvariantsHold('mounted reversal');
});

test('reverse with applied dependencies returns source and invoice details', async () => {
  const received = await receipt();
  const invoiceId = invoice();
  await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 50 }] });
  const blocked = await post(`/api/payments/${received.body.data.paymentId}/reverse`, { reason: 'Cannot reverse allocated cash' });
  expect(blocked.status).toBe(409);
  expect(blocked.body.error).toMatchObject({ code: 'UNAPPLIED_ALREADY_APPLIED', blockedBy: [{ consumed: 50, invoices: [invoiceId] }] });
});

test('cross-customer invoice references reject without allocating or changing AR', async () => {
  await receipt();
  const other = await createCustomer(`Other API ${++sequence}`, cookie);
  const invoiceId = invoice(other);
  const result = await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 50 }] });
  expect(result.status).toBe(409);
  expect(db.prepare('SELECT COUNT(*) count FROM payment_allocations WHERE invoice_id=?').get(invoiceId)).toEqual({ count: 0 });
});

test.each([
  { amount: -1, operation_date: '2026-10-01', payment_method: 'Cash' },
  { amount: 100, operation_date: '2026-02-30', payment_method: 'Cash' },
  { amount: 100, operation_date: '2026-10-01', payment_method: 'Credit' },
])('rejects malformed receive body with validation codes', async body => {
  const result = await post(`/api/customers/${customerId}/unapplied-cash`, body);
  expect(result.status).toBe(400);
  expect(result.body.error.code).toBe('VALIDATION_ERROR');
});

test('requires idempotency keys, rejects malformed IDs and returns missing customer 404', async () => {
  const body = { amount: 100, operation_date: '2026-10-01', payment_method: 'Cash' };
  expect((await request(app).post(`/api/customers/${customerId}/unapplied-cash`).set('Cookie', cookie).send(body)).status).toBe(400);
  expect((await post('/api/customers/no-id/unapplied-cash', body)).status).toBe(400);
  expect((await post('/api/customers/99999999/unapplied-cash', body)).status).toBe(404);
});

test('unauthenticated and unprivileged callers cannot write cash', async () => {
  const path = `/api/customers/${customerId}/unapplied-cash`;
  const body = { amount: 100, operation_date: '2026-10-01', payment_method: 'Cash' };
  expect((await request(app).post(path).send(body)).status).toBe(401);
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test JWT secret');
  const token = jwt.sign({ id: 99999999, username: 'no-permissions', role: 'user' }, secret, { issuer: 'mini-erp', audience: 'mini-erp-client', expiresIn: '1h' });
  expect((await request(app).post(path).set('Authorization', `Bearer ${token}`).send(body)).status).toBe(403);
});

test('closed periods return PERIOD_CLOSED for every operation', async () => {
  const received = await receipt();
  const invoiceId = invoice();
  db.prepare("UPDATE accounting_periods SET status='closed' WHERE period_name='2026-10'").run();
  try {
    const results = [
      await receipt(),
      await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 1 }] }),
      await post('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 1, payment_method: 'Cash' }),
      await post(`/api/payments/${received.body.data.paymentId}/reverse`, { reason: 'closed' }),
    ];
    for (const result of results) {
      expect(result.status).toBe(409);
      expect(result.body.error.code).toBe('PERIOD_CLOSED');
    }
  } finally { db.prepare("UPDATE accounting_periods SET status='open' WHERE period_name='2026-10'").run(); }
});

test('unexpected posting failures roll back and never expose internal diagnostics', async () => {
  const spy = jest.spyOn(AccountingService, 'postEntry').mockImplementationOnce(() => { throw new Error('SQL /private/server password=hidden'); });
  try {
    const result = await receipt();
    expect(result.status).toBe(500);
    expect(JSON.stringify(result.body)).not.toMatch(/SQL|private|password|hidden|stack/);
    expect(db.prepare('SELECT COUNT(*) count FROM payments WHERE customer_id=?').get(customerId)).toEqual({ count: 0 });
  } finally { spy.mockRestore(); }
});

test('missing invoices and receipts return 404 rather than a capacity conflict', async () => {
  await receipt();
  const result = await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: 99999999, amount: 1 }] });
  expect(result.status).toBe(404);
  expect(result.body.error.code).toBe('INVOICE_NOT_FOUND');
  expect((await post('/api/payments/99999999/reverse', {})).status).toBe(404);
});

test('duplicate invoice lines cannot exceed its balance, even when receipts have enough cash', async () => {
  await receipt(1500);
  const invoiceId = invoice();
  const result = await post('/api/unapplied-cash/apply', { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 600 }, { invoice_id: invoiceId, amount: 600 }] });
  expect(result.status).toBe(409);
  expect(db.prepare('SELECT COUNT(*) count FROM payment_allocations WHERE invoice_id=?').get(invoiceId)).toEqual({ count: 0 });
});

test.each([
  ['/api/unapplied-cash/apply', { customer_id: 1, operation_date: '2026-10-02', allocations: [{ invoice_id: 1, amount: 1 }] }],
  ['/api/unapplied-cash/refund', { customer_id: 1, operation_date: '2026-10-03', amount: 1, payment_method: 'Cash' }],
  ['/api/payments/99999999/reverse', {}],
])('authentication and permissions protect %s', async (path, body) => {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test JWT secret');
  const token = jwt.sign({ id: 99999999, username: 'no-permissions', role: 'user' }, secret, { issuer: 'mini-erp', audience: 'mini-erp-client', expiresIn: '1h' });
  expect((await request(app).post(path).send(body)).status).toBe(401);
  expect((await request(app).post(path).set('Authorization', `Bearer ${token}`).send(body)).status).toBe(403);
});

test('malformed JSON returns a safe 400', async () => {
  const logging = jest.spyOn(logger, 'error');
  try {
    const result = await request(app).post(`/api/customers/${customerId}/unapplied-cash`).set('Cookie', cookie)
      .set('Content-Type', 'application/json').set('Idempotency-Key', 'malformed-json').send('{"password":"dummy-secret",broken');
    expect(result.status).toBe(400);
    expect(result.body.error.code).toBe('VALIDATION_ERROR');
    expect(JSON.stringify(result.body)).not.toMatch(/broken|SyntaxError|stack|dummy-secret/);
    expect(logging).not.toHaveBeenCalled();
  } finally { logging.mockRestore(); }
});

test('failed keyed receive can retry and concurrent retries commit only one receipt', async () => {
  const path = `/api/customers/${customerId}/unapplied-cash`;
  const body = { amount: 500, operation_date: '2026-10-01', payment_method: 'Cash' };
  const spy = jest.spyOn(AccountingService, 'postEntry').mockImplementationOnce(() => { throw new Error('injected rollback'); });
  try { expect((await post(path, body, 'retry-receive')).status).toBe(500); }
  finally { spy.mockRestore(); }
  expect(db.prepare('SELECT COUNT(*) count FROM unapplied_receipt_replays WHERE customer_id=?').get(customerId)).toEqual({ count: 0 });
  const replies = await Promise.all([post(path, body, 'retry-receive'), post(path, body, 'retry-receive')]);
  expect(replies.map(reply => reply.status).sort()).toEqual([200, 201]);
  expect(replies[0].body.data).toEqual(replies[1].body.data);
  expect(db.prepare('SELECT COUNT(*) count FROM payments WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
  expect(db.prepare('SELECT COUNT(*) count FROM unapplied_receipt_replays WHERE customer_id=?').get(customerId)).toEqual({ count: 1 });
});

test('browser preflight permits the required idempotency header', async () => {
  const result = await request(app).options('/api/unapplied-cash/apply')
    .set('Origin', 'http://localhost:8080').set('Access-Control-Request-Method', 'POST')
    .set('Access-Control-Request-Headers', 'content-type,idempotency-key');
  expect(result.status).toBe(204);
  expect(String(result.headers['access-control-allow-headers']).toLowerCase()).toContain('idempotency-key');
});

test('non-admin payment permissions grant only their respective cash operations', async () => {
  const roleId = Number(db.prepare(`INSERT INTO roles (role_name,description,is_system_role,is_active)
    VALUES (?,'API permission fixture',0,1)`).run(`cash-role-${++sequence}`).lastInsertRowid);
  const userId = Number(db.prepare(`INSERT INTO users (username,email,password_hash,full_name,role,role_id,is_active)
    VALUES (?,?,'unused','Cash permission fixture','user',?,1)`).run(`cash-user-${sequence}`, `cash-${sequence}@example.test`, roleId).lastInsertRowid);
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('Missing test JWT secret');
  const token = jwt.sign({ id: userId, username: `cash-user-${sequence}`, role: 'user' }, secret, { issuer: 'mini-erp', audience: 'mini-erp-client', expiresIn: '1h' });
  function permission(action: string): void {
    const row = db.prepare<[string], { id: number }>("SELECT id FROM permissions WHERE module='payments' AND action=?").get(action);
    if (!row) throw new Error(`Missing payments:${action} fixture permission`);
    db.prepare('INSERT INTO role_permissions (role_id,permission_id) VALUES (?,?)').run(roleId, row.id);
  }
  function limitedPost(path: string, body: object) {
    return request(app).post(path).set('Authorization', `Bearer ${token}`).set('Idempotency-Key', `limited-${++sequence}`).send(body);
  }
  permission('create');
  const capability = await request(app).get('/api/unapplied-cash/capabilities').set('Authorization', `Bearer ${token}`);
  expect(capability.status).toBe(200);
  expect(capability.body.data.receive).toBe('durable-v1');
  expect((await request(app).get(`/api/customers/${customerId}/unapplied-cash`).set('Authorization', `Bearer ${token}`)).status).toBe(403);
  const received = await limitedPost(`/api/customers/${customerId}/unapplied-cash`, { amount: 500, operation_date: '2026-10-01' });
  expect(received.status).toBe(201);
  const invoiceId = invoice();
  const applyBody = { customer_id: customerId, operation_date: '2026-10-02', allocations: [{ invoice_id: invoiceId, amount: 100 }] };
  expect((await limitedPost('/api/unapplied-cash/apply', applyBody)).status).toBe(403);
  expect((await limitedPost(`/api/payments/${received.body.data.paymentId}/reverse`, {})).status).toBe(403);
  permission('update');
  expect((await limitedPost('/api/unapplied-cash/apply', applyBody)).status).toBe(200);
  expect((await limitedPost('/api/unapplied-cash/refund', { customer_id: customerId, operation_date: '2026-10-03', amount: 100 })).status).toBe(200);
  permission('delete');
  const unused = await limitedPost(`/api/customers/${customerId}/unapplied-cash`, { amount: 10, operation_date: '2026-10-04' });
  expect(unused.status).toBe(201);
  expect((await limitedPost(`/api/payments/${unused.body.data.paymentId}/reverse`, {})).status).toBe(200);
});
