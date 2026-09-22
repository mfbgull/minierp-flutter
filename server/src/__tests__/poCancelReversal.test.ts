/**
 * Reversal-rules Phase 1 regression tests — C3 (purchase-order
 * cancellation), updated for ACC-16 receipt-only posting.
 *
 * Under ACC-16 a PO submission posts NOTHING (no GL entry, no supplier-
 * ledger debit) — a submitted PO is a commitment, not a liability. The
 * payable comes into existence only when goods are received. Cancellation
 * therefore has nothing to reverse and must also stay ledger-silent.
 *
 * Audit cases covered:
 *   6. Submitted → Cancelled → no supplier-ledger rows ever created; net 0
 *   7. Cancelled → Submitted is blocked by the state machine; no rows appear
 */
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
  const tokenCookie = (Array.isArray(cookies) ? cookies : [cookies])
    .find((c: string) => c.startsWith('token='));
  return tokenCookie ? tokenCookie.split(';')[0] : '';
}

describe('Purchase-order cancellation AP reversal (C3, ACC-16 model)', () => {
  let authCookie: string;
  let itemId: number;
  let supplierId: number;

  beforeAll(async () => {
    authCookie = await getAuthCookie();
    expect(authCookie).not.toBe('');

    const item = await request(app)
      .post('/api/inventory/items')
      .set('Cookie', authCookie)
      .send({ item_code: `C3-${Date.now()}`, item_name: 'C3 Test Item' });
    expect(item.status).toBe(201);
    itemId = item.body.id;

    const supplier = await request(app)
      .post('/api/suppliers')
      .set('Cookie', authCookie)
      .send({
        supplier_code: `C3-SUP-${Date.now()}`,
        supplier_name: 'C3 Test Supplier',
      });
    expect(supplier.status).toBe(201);
    supplierId = supplier.body.data.id;
  });

  async function createSubmittedPo(): Promise<{ poId: number; poNo: string; supplierId: number }> {
    const create = await request(app)
      .post('/api/purchase-orders')
      .set('Cookie', authCookie)
      .send({
        supplier_id: supplierId,
        po_date: '2026-08-10',
        items: [{ item_id: itemId, quantity: 5, unit_price: 20 }],
      });
    expect(create.status).toBe(201);
    const poId = create.body.id as number;

    const submit = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Submitted' });
    expect(submit.status).toBe(200);

    const poNo = (db.prepare('SELECT po_no FROM purchase_orders WHERE id = ?').get(poId) as { po_no: string }).po_no;
    return { poId, poNo, supplierId };
  }

  it('case 6: cancelling a submitted PO leaves no supplier-ledger rows — net supplier effect 0', async () => {
    const { poId, poNo, supplierId: supId } = await createSubmittedPo();

    // ACC-16: submission posted NOTHING — no commitment debit exists
    const afterSubmit = db.prepare(
      `SELECT COUNT(*) AS n FROM supplier_ledger WHERE reference_no = ?`
    ).get(poNo) as { n: number };
    expect(afterSubmit.n).toBe(0);

    const balanceBefore = (db.prepare(
      'SELECT current_balance FROM suppliers WHERE id = ?'
    ).get(supId) as { current_balance: number }).current_balance;

    const cancel = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Cancelled' });
    expect(cancel.status).toBe(200);

    // Cancellation is ledger-silent too: nothing to reverse
    const rows = db.prepare(
      'SELECT transaction_type, debit, credit, voided FROM supplier_ledger WHERE reference_no = ?'
    ).all(poNo) as Array<{ transaction_type: string; debit: number; credit: number; voided: number }>;
    expect(rows.length).toBe(0);

    // Net effect on the supplier is zero — balance untouched
    const balanceAfter = (db.prepare(
      'SELECT current_balance FROM suppliers WHERE id = ?'
    ).get(supId) as { current_balance: number }).current_balance;
    expect(balanceAfter).toBeCloseTo(balanceBefore, 2);
  });

  it('case 7: Submitted → Cancelled → Submitted is blocked; no supplier-ledger rows appear', async () => {
    const { poId, poNo } = await createSubmittedPo();

    const cancel = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Cancelled' });
    expect(cancel.status).toBe(200);

    // Cancelled → Submitted must be rejected by the state machine
    const resubmit = await request(app)
      .post(`/api/purchase-orders/${poId}/status`)
      .set('Cookie', authCookie)
      .send({ status: 'Submitted' });
    // Phase 5: illegal transitions map to 400 (client error), not 500
    expect(resubmit.status).toBe(400);

    // Still cancelled, and still zero ledger rows of any kind
    const po = db.prepare('SELECT status FROM purchase_orders WHERE id = ?').get(poId) as { status: string };
    expect(po.status).toBe('Cancelled');
    const rows = db.prepare(
      'SELECT transaction_type, voided FROM supplier_ledger WHERE reference_no = ?'
    ).all(poNo) as Array<{ transaction_type: string; voided: number }>;
    expect(rows.length).toBe(0);
  });
});
