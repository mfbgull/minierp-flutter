/**
 * ACCT-013 sweep: editing a cash OUTFLOW (owner withdrawal, expense) to an
 * earlier date must refuse when the move drives any later daily balance
 * negative. The point-in-time funds check at the NEW date passes in both
 * scenarios below — only the chronological suffix check catches the dip.
 */
import { beforeAll, beforeEach, afterEach, describe, expect, it } from '@jest/globals';
import request from 'supertest';
import fs from 'fs';
import path from 'path';
import app from '../app';
import db from '../config/database';
import { getAuthCookie } from './helpers/invoiceReturnSpec';
import { resolveSupplierByName } from './helpers/invoiceReturnSpec';
import { expectAllInvariantsHold } from './helpers/accountingInvariants';
import { PaymentRecordingService } from '../services/PaymentRecordingService';
import { createCustomer, createItem, createInvoice, purchaseStock } from './helpers/invoiceReturnSpec';
let cookie: string;

let supSeq = 0;
let itSeq = 0;

async function whId(): Promise<number> {
  return (db.prepare('SELECT id FROM warehouses ORDER BY id LIMIT 1').get() as { id: number }).id;
}

/** Submit + receive a purchase order so AP holds a payable to settle. */
async function poFor(poDate: string, supplierId: number, warehouseId: number): Promise<number> {
  itSeq += 1;
  const itemRes = await request(app).post('/api/inventory/items').set('Cookie', cookie)
    .send({ item_code: `TL-IT-${itSeq}`, item_name: `TL Item ${itSeq}`, unit_of_measure: 'pcs', current_stock: 0 });
  const itemId = (itemRes.body?.data ?? itemRes.body).id as number;

  const poRes = await request(app).post('/api/purchase-orders').set('Cookie', cookie)
    .send({ supplier_id: supplierId, po_date: poDate, items: [{ item_id: itemId, quantity: 10, unit_price: 25 }] });
  const po = poRes.body?.data ?? poRes.body;
  if (![200, 201].includes(poRes.status)) throw new Error(`PO create failed: ${poRes.status} ${JSON.stringify(poRes.body)}`);
  await request(app).post(`/api/purchase-orders/${po.id}/status`).set('Cookie', cookie).send({ status: 'Submitted' });

  const poItem = db.prepare('SELECT id FROM purchase_order_items WHERE po_id = ?').get(po.id) as { id: number };
  const recRes = await request(app).post(`/api/purchase-orders/${po.id}/receipts`).set('Cookie', cookie)
    .set('Idempotency-Key', `patch-cashOutflowEdi-po-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ receipt_date: poDate, warehouse_id: warehouseId, items: [{ po_item_id: poItem.id, received_quantity: 10 }] });
  if (![200, 201].includes(recRes.status)) throw new Error(`PO receipt failed: ${recRes.status} ${JSON.stringify(recRes.body)}`);
  return po.id as number;
}


beforeAll(async () => { cookie = await getAuthCookie(); });
beforeEach(() => { db.exec('SAVEPOINT outflow_edit_case'); });
afterEach(() => { db.exec('ROLLBACK TO outflow_edit_case; RELEASE outflow_edit_case'); });

async function capital(amount: number, date: string): Promise<number> {
  const response = await request(app).post('/api/owner-equity/capital').set('Cookie', cookie)
    .set('Idempotency-Key', `patch-cashOutflowEdi-11-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ amount, capital_date: date, payment_method: 'Cash' });
  expect(response.status).toBe(201);
  const data: { data: { id: number } } = response.body;
  return data.data.id;
}

/** Cash withdrawal (outflow); returns the row id. */
async function withdraw(amount: number, date: string): Promise<number> {
  const response = await request(app).post('/api/owner-equity/withdrawals').set('Cookie', cookie)
    .set('Idempotency-Key', `patch-cashOutflowEdi-12-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({ amount, withdrawal_date: date, payment_method: 'Cash', kind: 'cash' });
  expect(response.status).toBe(201);
  const data: { data: { id: number } } = response.body;
  return data.data.id;
}

async function createExpense(amount: number, date: string): Promise<number> {
  const response = await request(app).post('/api/expenses').set('Cookie', cookie)
    .set('Idempotency-Key', `patch-cashOutflowEdi-13-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
    .send({
      expense_category: 'Utilities', description: 'ACCT-013 dip fixture', amount,
      expense_date: date, payment_method: 'Cash', status: 'Recorded',
    });
  expect(response.status).toBe(201);
  const data: { data: { id: number } } = response.body;
  return data.data.id;
}

function snapshot(tables: string[]) {
  const out: Record<string, unknown[]> = {};
  for (const t of tables) {
    out[t] = db.prepare(`SELECT * FROM ${t} ORDER BY id`).all();
  }
  return out;
}

describe('editing a cash outflow to an earlier date cannot overdraw a later day (ACCT-013)', () => {
  it('refuses an owner-withdrawal edit whose new date leaves a later day negative', async () => {
    await capital(1000, '2026-09-01');
    await withdraw(400, '2026-09-05');
    await withdraw(350, '2026-09-07');
    await capital(400, '2026-09-09');
    // Valid at creation: balance at 2026-09-10 is 650 >= 500.
    const withdrawalId = await withdraw(500, '2026-09-10');
    const before = snapshot(['owner_withdrawals', 'journal_lines']);

    // Moving it to 2026-09-06 passes the point-in-time check at the new date
    // (balance 600 >= 500) but drives 2026-09-07 to -250.
    const response = await request(app).put(`/api/owner-equity/withdrawals/${withdrawalId}`)
      .set('Cookie', cookie)
      .send({ amount: 500, withdrawal_date: '2026-09-06', payment_method: 'Cash', kind: 'cash' });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-07');
    expect(snapshot(['owner_withdrawals', 'journal_lines'])).toEqual(before);
    expectAllInvariantsHold('after refused withdrawal edit');
  });

  it('refuses an expense edit whose new date leaves a later day negative', async () => {
    await capital(1000, '2026-09-01');
    await withdraw(400, '2026-09-05');
    await withdraw(350, '2026-09-07');
    await capital(200, '2026-09-08');
    // Valid at creation: balance at 2026-09-09 is 450 >= 300.
    const expenseId = await createExpense(300, '2026-09-09');
    const before = snapshot(['expenses', 'journal_lines']);

    // Moving it to 2026-09-06 passes the point-in-time check at the new date
    // (balance 600 >= 300) but drives 2026-09-07 to -50.
    const response = await request(app).put(`/api/expenses/${expenseId}`)
      .set('Cookie', cookie)
      .send({
        expense_category: 'Utilities', description: 'ACCT-013 dip fixture', amount: 300,
        expense_date: '2026-09-06', payment_method: 'Cash', status: 'Recorded',
      });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-07');
    expect(snapshot(['expenses', 'journal_lines'])).toEqual(before);
    expectAllInvariantsHold('after refused expense edit');
  });
});

describe('cash-timeline guard-rail: every cash-affecting model calls the chronological guard', () => {
  it('recording a backdated draft expense is refused when it overdrafts a later day', async () => {
    // An expense is created as a Draft with no GL. Cash moves when it leaves
    // Draft, so the guard must hold on that transition. Same dip as the
    // withdrawal case: individually affordable at 09-03 (850), but it drives
    // 09-05 to -50.
    await capital(1000, '2026-09-01');
    await withdraw(900, '2026-09-05');

    const draft = await request(app).post('/api/expenses').set('Cookie', cookie)
      .set('Idempotency-Key', `patch-cashOutflowEdi-14-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
      .send({
        expense_category: 'Utilities', description: 'Backdated dip fixture', amount: 150,
        expense_date: '2026-09-03', payment_method: 'Cash', status: 'Recorded',
      });
    expect(draft.status).toBe(201);
    const expenseId = draft.body.data.id as number;
    const before = snapshot(['expenses', 'journal_lines']);

    const response = await request(app).put(`/api/expenses/${expenseId}`)
      .set('Cookie', cookie)
      .send({
        expense_category: 'Utilities', description: 'Backdated dip fixture', amount: 150,
        expense_date: '2026-09-03', payment_method: 'Cash', status: 'Recorded',
      });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-05');
    expect(snapshot(['expenses', 'journal_lines'])).toEqual(before);
    expectAllInvariantsHold('after refused backdated expense');
  });

  it('creating a backdated owner withdrawal is refused when it overdrafts a later day', async () => {
    await capital(1000, '2026-09-01');
    await withdraw(900, '2026-09-05');
    const before = snapshot(['owner_withdrawals', 'journal_lines']);

    const response = await request(app).post('/api/owner-equity/withdrawals').set('Cookie', cookie)
      .set('Idempotency-Key', `patch-cashOutflowEdi-15-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
      .send({
        amount: 150, withdrawal_date: '2026-09-03', payment_method: 'Cash', kind: 'cash',
      });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-05');
    expect(snapshot(['owner_withdrawals', 'journal_lines'])).toEqual(before);
    expectAllInvariantsHold('after refused backdated withdrawal');
  });

  it('a backdated outflow that stays non-negative on every later day is accepted', async () => {
    // Same dates, but only Rs 50 goes out early against a Rs 100 cushion, so
    // every later day stays >= 0 and the guard must not fire.
    await capital(1000, '2026-09-01');
    await withdraw(900, '2026-09-05');

    const response = await request(app).post('/api/owner-equity/withdrawals').set('Cookie', cookie)
      .set('Idempotency-Key', `patch-cashOutflowEdi-16-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
      .send({
        amount: 50, withdrawal_date: '2026-09-03', payment_method: 'Cash', kind: 'cash',
      });

    expect(response.status).toBe(201);
    expectAllInvariantsHold('after accepted backdated withdrawal');
  });

  it('creating a backdated supplier payment is refused when it overdrafts a later day', async () => {
    // Same dip, but through a supplier payout. A PO receipt gives AP a balance
    // to pay; a later cash withdrawal then leaves too thin a cushion for a
    // backdated payout. Rs 100 cushion, Rs 150 backdated payout → 09-05 = -50.
    const supplierId = await resolveSupplierByName(`TL-Sup-${++supSeq}`, cookie);
    const warehouseId = await whId();
    const poId = await poFor('2026-09-01', supplierId, warehouseId);
    await capital(1000, '2026-09-01');
    await withdraw(900, '2026-09-05');

    const response = await request(app).post('/api/payments').set('Cookie', cookie)
      .set('Idempotency-Key', `patch-cashOutflowEdi-17-${Date.now()}-${Math.floor(Math.random() * 1e6)}`)
      .send({
        supplier_id: supplierId, payment_date: '2026-09-03', amount: 150, payment_method: 'cash',
        po_allocations: [{ po_id: poId, amount: 150 }],
      });

    expect(response.status).toBe(409);
    expect(response.body.error).toContain('Reverse the later spending first.');
    expect(response.body.error).toContain('2026-09-05');
    expectAllInvariantsHold('after refused backdated supplier payment');
  });

  it('a backdated cash refund is refused when it overdrafts a later day', async () => {
    // A refund posts cash out. No route backdates a refund today (the
    // settlement path always uses `today`), so the guard is proved at the
    // service seam: if a future caller passes an earlier refund date, this
    // dip must be refused. Capital 1000 (09-01), withdrawal 900 (09-05) leaves
    // Rs 100; a Rs 150 refund on 09-03 would drive 09-05 to -50.
    const customerId = await createCustomer(`TL-Refund-${++supSeq}`, cookie);
    const itemId = await createItem(`TL-Refund-Item-${++itSeq}`, cookie);
    await purchaseStock(itemId, await whId(), 5, 100, cookie, '2026-08-15');
    const { invoiceId } = await createInvoice({
      customerId, itemId, lines: [{ quantity: 1, unitPrice: 500 }], payment: 'full',
    }, cookie);
    await capital(1000, '2026-09-01');
    await withdraw(900, '2026-09-05');

    expect(() => new PaymentRecordingService(db).recordCustomerPayment({
      mode: 'REFUND',
      customerId,
      paymentDate: '2026-09-03',
      amount: 150,
      paymentMethod: 'Cash',
      userId: 1,
      allocations: [{ invoiceId, amount: 150 }],
    })).toThrow(/Reverse the later spending first\./);

    // The refused refund wrote nothing.
    expect(db.prepare("SELECT COUNT(*) n FROM payments WHERE payment_kind = 'REFUND'").get()).toEqual({ n: 0 });
    expectAllInvariantsHold('after refused backdated cash refund');
  });

  it('expense GL posts only through the guarded transition, and settlement posts are guarded', () => {
    const srcDir = path.join(__dirname, '..');
    // postExpenseEntry is the only writer of EXPENSE journal lines. It must
    // have exactly one caller: the Draft→Recorded/edit transition in
    // Expense.ts, which sits next to an assertCashTimeline. Any new caller is
    // a bypass and must be added to the guard list above.
    const callers: string[] = [];
    for (const area of ['models', 'services', 'controllers', 'routes']) {
      const dir = path.join(srcDir, area);
      if (!fs.existsSync(dir)) continue;
      for (const file of fs.readdirSync(dir)) {
        if (!file.endsWith('.ts')) continue;
        const source = fs.readFileSync(path.join(dir, file), 'utf8');
        if (file === 'accountingService.ts') continue; // the definition
        if (source.includes('postExpenseEntry(')) callers.push(`${area}/${file}`);
      }
    }
    if (callers.length !== 1 || callers[0] !== 'models/Expense.ts') {
      throw new Error(`postExpenseEntry must be called only from models/Expense.ts; found: ${callers.join(', ')}`);
    }
    const expenseSource = fs.readFileSync(path.join(srcDir, 'models', 'Expense.ts'), 'utf8');
    if (!expenseSource.includes('postExpenseEntry(') || !expenseSource.includes('assertCashTimeline')) {
      throw new Error('Expense.ts must pair its postExpenseEntry call with assertCashTimeline');
    }
    // Credit-expense settlements are an independent cash outflow.
    const settlement = fs.readFileSync(path.join(srcDir, 'models', 'ExpensePayment.ts'), 'utf8');
    if (!settlement.includes('assertCashTimeline')) {
      throw new Error('ExpensePayment.ts settles cash but never calls assertCashTimeline');
    }
  });

  it('each cash-affecting model and service file references assertCashTimeline', () => {
    const srcDir = path.join(__dirname, '..');
    const cashAffecting: Array<[string, string]> = [
      ['models', 'OwnerCapital.ts'],    // inflow create/edit/void
      ['models', 'OwnerWithdrawal.ts'], // outflow create/edit (moved-earlier dip)
      ['models', 'Payment.ts'],         // customer receipt create/delete/restore
      ['models', 'SupplierRefund.ts'],  // refund void
      ['models', 'Expense.ts'],         // expense GL post (Draft→Recorded) and edit
      ['services', 'SupplierPaymentService.ts'],   // supplier payout posts cash
      ['services', 'PaymentRecordingService.ts'],  // customer cash refund posts cash
      ['models', 'ExpensePayment.ts'],             // credit-expense settlement posts cash
    ];
    for (const [area, file] of cashAffecting) {
      const source = fs.readFileSync(path.join(srcDir, area, file), 'utf8');
      if (!source.includes('assertCashTimeline')) {
        throw new Error(
          `${area}/${file} mutates cash but never calls assertCashTimeline — ` +
          'add the chronological guard or justify an exemption here',
        );
      }
    }
  });
});
