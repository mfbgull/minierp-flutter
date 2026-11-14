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
import { expectAllInvariantsHold } from './helpers/accountingInvariants';

let cookie: string;

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
  it('each cash-affecting model file references assertCashTimeline', () => {
    const modelsDir = path.join(__dirname, '..', 'models');
    const cashAffecting = [
      'OwnerCapital.ts',   // inflow create/edit/void
      'OwnerWithdrawal.ts', // outflow edit (moved-earlier dip)
      'Payment.ts',        // customer receipt delete/restore
      'SupplierRefund.ts', // refund void
      'Expense.ts',        // expense edit (moved-earlier dip)
    ];
    for (const file of cashAffecting) {
      const source = fs.readFileSync(path.join(modelsDir, file), 'utf8');
      if (!source.includes('assertCashTimeline')) {
        throw new Error(
          `${file} mutates cash but never calls assertCashTimeline — ` +
          'add the chronological guard or justify an exemption here',
        );
      }
    }
  });
});
