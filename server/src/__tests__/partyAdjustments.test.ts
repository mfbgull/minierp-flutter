import { beforeAll, describe, expect, it, jest } from '@jest/globals';
import request from 'supertest';
import app from '../app';
import db from '../config/database';
import { createCustomer, createInvoice, createItem, getAuthCookie } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import ledgerUtils from '../utils/ledgerUtils';

describe('Customer and supplier noncash adjustments', () => {
  let cookie: string;
  beforeAll(async () => { cookie = await getAuthCookie(); });
  const post = (path: string, body: object, key = 'party-adjustment-key') => request(app).post(path)
    .set('Cookie', cookie).set('Idempotency-Key', key).send(body);

  async function fixture(code: string) {
    const customerId = await createCustomer(code, cookie);
    const supplier = await post('/api/suppliers', { supplier_code: code, supplier_name: code });
    expect(supplier.status).toBe(201);
    const supplierId: number = supplier.body.data.id;
    const itemId = await createItem(code, cookie);
    const purchase = await post('/api/purchases', { supplier_id: supplierId, item_id: itemId,
      warehouse_id: 1, quantity: 10, unit_cost: 100, purchase_date: '2026-09-01' }, `${code}-purchase`);
    expect([200, 201]).toContain(purchase.status);
    const purchaseId = db.prepare<[], { id: number }>('SELECT id FROM purchases ORDER BY id DESC LIMIT 1').get()?.id;
    const invoice = await createInvoice({ customerId, itemId, lines: [{ quantity: 10, unitPrice: 200 }], invoiceDate: '2026-09-02' }, cookie);
    const link = await post('/api/parties/link', { customer_id: customerId, supplier_id: supplierId, confirmed: true });
    expect(link.status).toBe(200);
    const partyId: number = link.body.data.id;
    return { customerId, supplierId, purchaseId, itemId, invoiceId: invoice.invoiceId, partyId,
      body: { adjustment_date: '2026-09-03', amount: 1000,
        receivables: [{ invoice_id: invoice.invoiceId, amount: 1000 }],
        payables: [{ kind: 'purchase', id: purchaseId, amount: 1000 }] } };
  }

  it('settles a 1000 purchase against a 2000 sale without cash and reverses once', async () => {
    const f = await fixture('PARTY-LIFECYCLE');
    const before = db.prepare('SELECT COUNT(*) AS count FROM payments').get();
    const result = await post(`/api/parties/${f.partyId}/adjustments`, f.body, 'party-lifecycle');
    expect(result.status).toBe(201);
    const adjustmentId: number = result.body.data.id;
    expect(db.prepare('SELECT COUNT(*) AS count FROM payments').get()).toEqual(before);
    const position = await request(app).get(`/api/parties/${f.partyId}/position`).set('Cookie', cookie);
    expect(position.body.data).toMatchObject({ customer_balance: 1000, supplier_balance: 0, net_balance: 1000 });
    expect(db.prepare('SELECT paid_amount, adjusted_amount, balance_amount FROM invoices WHERE id=?').get(f.invoiceId))
      .toEqual({ paid_amount: 0, adjusted_amount: 1000, balance_amount: 1000 });
    expectAllInvariantsHold('noncash party adjustment', db);
    expect((await request(app).put(`/api/invoices/${f.invoiceId}/cancel`).set('Cookie', cookie).send({ reason: 'Blocked' })).status).toBe(409);
    expect((await post(`/api/purchases/${f.purchaseId}/void`, { reason: 'Blocked' })).status).toBe(409);
    const replay = await post(`/api/parties/${f.partyId}/adjustments`, f.body, 'party-lifecycle');
    expect(replay.body.data.id).toBe(adjustmentId);
    const changed = await post(`/api/parties/${f.partyId}/adjustments`, { ...f.body, notes: 'Changed' }, 'party-lifecycle');
    expect(changed.status).toBe(409);
    const reversal = await post(`/api/parties/${f.partyId}/adjustments/${adjustmentId}/reverse`, { reason: 'Correction', reversal_date: '2026-09-04' });
    expect(reversal.status).toBe(200);
    expect((await post(`/api/parties/${f.partyId}/adjustments/${adjustmentId}/reverse`, { reason: 'Again', reversal_date: '2026-09-04' })).status).toBe(409);
    const restored = await request(app).get(`/api/parties/${f.partyId}/position`).set('Cookie', cookie);
    expect(restored.body.data).toMatchObject({ customer_balance: 2000, supplier_balance: 1000, net_balance: 1000 });
    expectAllInvariantsHold('party adjustment reversed', db);
  });

  it('accepts the remaining cash receipt without treating adjustment as collected cash', async () => {
    const f = await fixture('PARTY-CASH');
    expect((await post(`/api/parties/${f.partyId}/adjustments`, f.body, 'party-cash-adjust')).status).toBe(201);
    const receipt = await post('/api/payments', { customer_id: f.customerId, payment_date: '2026-09-04',
      amount: 1000, payment_method: 'Cash', invoice_allocations: [{ invoice_id: f.invoiceId, amount: 1000 }] }, 'party-cash-receipt');
    expect(receipt.status).toBe(201);
    expect(db.prepare('SELECT paid_amount,adjusted_amount,balance_amount FROM invoices WHERE id=?').get(f.invoiceId))
      .toEqual({ paid_amount: 1000, adjusted_amount: 1000, balance_amount: 0 });
    expectAllInvariantsHold('party adjustment plus cash receipt', db);
  });

  it('rolls back allocations, ledgers, journal and retry claim when balance rebuilding fails', async () => {
    const f = await fixture('PARTY-ROLLBACK');
    const before = db.prepare(`SELECT (SELECT COUNT(*) FROM party_adjustments) AS adjustments,
      (SELECT COUNT(*) FROM journal_lines) AS journal,(SELECT COUNT(*) FROM customer_ledger) AS customer,
      (SELECT COUNT(*) FROM supplier_ledger) AS supplier`).get();
    const rebuild = jest.spyOn(ledgerUtils, 'calculateInvoiceBalance').mockImplementationOnce(() => { throw new Error('Injected rebuild failure'); });
    try {
      expect((await post(`/api/parties/${f.partyId}/adjustments`, f.body, 'party-rollback')).status).toBe(500);
    } finally { rebuild.mockRestore(); }
    expect(db.prepare(`SELECT (SELECT COUNT(*) FROM party_adjustments) AS adjustments,
      (SELECT COUNT(*) FROM journal_lines) AS journal,(SELECT COUNT(*) FROM customer_ledger) AS customer,
      (SELECT COUNT(*) FROM supplier_ledger) AS supplier`).get()).toEqual(before);
    expect(db.prepare("SELECT resource_id FROM idempotency_keys WHERE scope='party-adjustments.create' AND key='party-rollback'").get()).toBeUndefined();
    expect((await post(`/api/parties/${f.partyId}/adjustments`, f.body, 'party-rollback')).status).toBe(201);
    expectAllInvariantsHold('rollback and retry', db);
  });

  it('settles multiple payable kinds and refuses an unreceived or excessive PO liability', async () => {
    const f = await fixture('PARTY-MULTI');
    const bill = await post('/api/supplier-bills', { supplier_id:f.supplierId,bill_no:'PARTY-BILL',bill_date:'2026-09-01',
      net_amount:100,input_tax_amount:15,description:'Service' }, 'party-multi-bill');
    expect(bill.status).toBe(201);
    const po = await post('/api/purchase-orders', { supplier_id:f.supplierId,warehouse_id:1,po_date:'2026-09-01',
      items:[{ item_id:f.itemId,quantity:10,unit_price:100 }] }, 'party-multi-po');
    expect(po.status).toBe(201);
    const poId: number = po.body.id;
    const lineId = db.prepare<[number], { id: number }>('SELECT id FROM purchase_order_items WHERE po_id=?').get(poId)?.id;
    const target = { ...f.body,payables:[{kind:'purchase_order',id:poId,amount:1000}] };
    expect((await post(`/api/parties/${f.partyId}/adjustments`,target,'party-unreceived')).status).toBe(400);
    expect((await post(`/api/purchase-orders/${poId}/status`,{status:'Submitted'})).status).toBe(200);
    expect((await post(`/api/purchase-orders/${poId}/receipts`,{receipt_date:'2026-09-02',warehouse_id:1,
      items:[{po_item_id:lineId,received_quantity:2}]},'party-multi-receipt')).status).toBe(201);
    expect((await post(`/api/parties/${f.partyId}/adjustments`,target,'party-excess-po')).status).toBe(400);
    const body = { ...f.body,amount:415,receivables:[{invoice_id:f.invoiceId,amount:415}],payables:[
      {kind:'purchase',id:f.purchaseId,amount:100},{kind:'purchase_order',id:poId,amount:200},
      {kind:'supplier_bill',id:bill.body.data.id,amount:115}] };
    expect((await post(`/api/parties/${f.partyId}/adjustments`,body,'party-multiple')).status).toBe(201);
    const detail = await request(app).get(`/api/parties/${f.partyId}/position`).set('Cookie',cookie);
    expect(detail.body.data).toMatchObject({customer_balance:1585,supplier_balance:900});
    expectAllInvariantsHold('mixed source adjustment',db);
  });

  it('creates a missing role, unlinks unused identities and preserves identities with adjustment history', async () => {
    const customerId = await createCustomer('PARTY-ROLE',cookie);
    const customer = db.prepare<[number], { party_id: number }>('SELECT party_id FROM customers WHERE id=?').get(customerId);
    const partyId = customer?.party_id;
    const unconfirmed = await post('/api/parties/link',{customer_id:customerId,supplier_id:1});
    expect(unconfirmed.status).toBe(400);
    const added = await post(`/api/parties/${partyId}/supplier`,{supplier_code:'PARTY-ROLE-S',supplier_name:'Same business'});
    expect(added.status).toBe(201);
    expect(added.body.data.supplier.name).toBe('Same business');
    expect((await post(`/api/parties/${partyId}/unlink`,{})).status).toBe(200);

    const supplier = await post('/api/suppliers',{supplier_code:'PARTY-ROLE-C',supplier_name:'Supplier only'},'party-role-supplier');
    expect(supplier.status).toBe(201);
    const supplierPartyId: number = supplier.body.data.party_id;
    const customerRole = await post(`/api/parties/${supplierPartyId}/customer`,{customer_name:'Supplier only',phone:'123'});
    expect(customerRole.status).toBe(201);
    expect(customerRole.body.data.customer.name).toBe('Supplier only');

    const f = await fixture('PARTY-LOCK');
    expect((await post(`/api/parties/${f.partyId}/adjustments`,f.body,'party-lock')).status).toBe(201);
    const history = await request(app).get(`/api/parties/${f.partyId}/adjustments?page=1&limit=25`).set('Cookie',cookie);
    expect(history.status).toBe(200);
    expect(history.body.data).toHaveLength(1);
    expect(history.body.pagination.totalItems).toBe(1);
    expect((await post(`/api/parties/${f.partyId}/unlink`,{})).status).toBe(409);
  });

  it('requires authentication and explicit non-admin permissions', async () => {
    expect((await request(app).get('/api/parties/1/position')).status).toBe(401);
    const roleId = Number(db.prepare("INSERT INTO roles(role_name,description) VALUES ('Party denied','No permissions')").run().lastInsertRowid);
    db.prepare(`INSERT INTO users(username,email,password_hash,full_name,role,role_id)
      SELECT 'party-denied','party-denied@example.test',password_hash,'Denied','user',? FROM users WHERE username='admin'`).run(roleId);
    const login = await request(app).post('/api/auth/login').send({username:'party-denied',password:process.env.TEST_ADMIN_PASSWORD});
    expect(login.status).toBe(200);
    const cookies = login.headers['set-cookie'] ?? [];
    const token = (Array.isArray(cookies) ? cookies : [cookies]).find(value=>value.startsWith('token='))?.split(';')[0] ?? '';
    expect((await request(app).post('/api/parties/link').set('Cookie',token).send({customer_id:1,supplier_id:1})).status).toBe(403);
    expect((await request(app).post('/api/parties/1/adjustments').set('Cookie',token).send({})).status).toBe(403);
    expect(db.prepare(`SELECT COUNT(*) AS count FROM role_permissions rp JOIN roles r ON r.id=rp.role_id
      JOIN permissions p ON p.id=rp.permission_id WHERE r.role_name<>'Admin' AND p.module IN ('parties','party_adjustments')`).get()).toEqual({count:0});
  });

  it('rejects invalid totals, duplicate targets and dates without posting', async () => {
    const f = await fixture('PARTY-INVALID');
    for (const body of [
      { ...f.body, amount: 1001 },
      { ...f.body, adjustment_date: '2026-08-01' },
      { ...f.body, receivables: [f.body.receivables[0], f.body.receivables[0]] },
    ]) {
      const before = db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get();
      expect((await post(`/api/parties/${f.partyId}/adjustments`, body, 'party-invalid')).status).toBe(400);
      expect(db.prepare('SELECT COUNT(*) AS count FROM journal_lines').get()).toEqual(before);
    }
  });
});
