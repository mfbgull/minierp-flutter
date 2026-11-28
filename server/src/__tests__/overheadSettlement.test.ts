/**
 * D30 — Settle overhead (Gull's decision, 2026-11-27).
 *
 * Production capitalises the overhead typed into a run (labour tankhwa,
 * electricity, gas) into the stock batches and credits 2200 Accrued
 * Production Overhead. Nothing ever debited 2200, so the liability grew
 * forever even though Gull always pays the bill.
 *
 * D30 answered the three product questions:
 *   Q1 — Cash or Bank is chosen per payment.        (agreed)
 *   Q2 — the amount is free text.                   (agreed)
 *   Q3 — B: an over-payment is allowed. The accrued
 *        part clears 2200, the excess books as a
 *        normal expense (6000).
 *
 * The cost already sits inside the item's stock value, so the payment must
 * not book the whole amount as a new expense — that would count the same
 * electricity twice. The payment only removes the debt.
 *
 * Written FAILING-FIRST: before this feature no route debited 2200 at all.
 */
import request from 'supertest';
import { beforeAll, describe, expect, it } from '@jest/globals';
import app from '../app';
import db from '../config/database';
import AccountingService from '../services/accountingService';
import { IDEMPOTENCY_KEY_REQUIRED_MESSAGE } from '../utils/idempotency';
import { getAuthCookie } from './helpers/invoiceReturnSpec';

const SETTLE = '/api/accounting/overhead/settle';

let seq = 0;
function key(): string {
  seq += 1;
  return `d30-${Date.now()}-${seq}`;
}

/** Signed balance of 2200: it is a liability, so credits minus debits. */
function owedOverhead(): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(ROUND(jl.credit * 100) - ROUND(jl.debit * 100)), 0) AS cents
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = '2200' AND jl.voided = 0
  `).get() as { cents: number };
  return row.cents / 100;
}

/** Cash balance of one account as of a date, in currency units. */
function cashBalance(code: string, date: string): number {
  const row = db.prepare(`
    SELECT COALESCE(SUM(ROUND(jl.debit * 100) - ROUND(jl.credit * 100)), 0) AS cents
    FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE a.code = ? AND jl.voided = 0 AND jl.line_date <= ?
  `).get(code, date) as { cents: number };
  return row.cents / 100;
}

/** Top up Cash/Bank from Owner Capital so a test has money to pay with.
 *  The cash-timeline guard is under test in its own case, where the payment
 *  deliberately exceeds the balance; the other cases need funds to succeed. */
function fundAccount(code: string, amount: number, date: string): void {
  const cash = AccountingService.getAccountByCode(db, code);
  const capital = AccountingService.getAccountByCode(db, '3200');
  if (!cash || !capital) throw new Error(`${code} / 3200 Owner Capital missing from the chart`);
  AccountingService.postEntry(db, {
    entry_date: date,
    description: `D30 seed: owner contribution into ${code}`,
    reference_type: 'OWNER_CAPITAL',
    lines: [
      { account_id: cash.id, debit: amount, description: 'Cash in' },
      { account_id: capital.id, credit: amount, description: 'Owner capital' },
    ],
  });
}

/** Seed the accrual production posts: Dr production_clearing / Cr 2200. */
function accrueOverhead(amount: number, date: string): void {
  const payable = AccountingService.getAccountByTextCode(db, 'production_overhead_payable');
  const clearing = AccountingService.getAccountByTextCode(db, 'production_clearing');
  if (!payable || !clearing) throw new Error('2200 / production_clearing missing from the chart');
  AccountingService.postEntry(db, {
    entry_date: date,
    description: `Production D30 seed: overhead accrued unpaid (${amount.toFixed(2)})`,
    reference_type: 'production_overhead',
    lines: [
      { account_id: clearing.id, debit: amount, description: 'Overhead absorbed' },
      { account_id: payable.id, credit: amount, description: 'Overhead accrued unpaid' },
    ],
  });
}

interface SettleLine {
  code: string;
  account_name: string;
  debit: number;
  credit: number;
}

/** The journal lines of the settlement with the given id, ordered. */
function settleLines(settlementId: number): SettleLine[] {
  return db.prepare(`
    SELECT a.code, a.name AS account_name, jl.debit, jl.credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    JOIN chart_of_accounts a ON a.id = jl.account_id
    WHERE je.reference_type = 'OVERHEAD_SETTLEMENT' AND je.reference_id = ?
    ORDER BY jl.id
  `).all(settlementId) as SettleLine[];
}

function lineFor(lines: SettleLine[], code: string): SettleLine | undefined {
  return lines.find((l) => l.code === code);
}

/** Every block logs in once; the suite shares one seeded database. */
async function login(): Promise<string> {
  return getAuthCookie();
}

describe('D30 — Settle overhead: request validation', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await login();
  });

  it('rejects a keyless settlement with 400', async () => {
    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .send({ settlement_date: '2026-11-27', amount: 100, payment_method: 'Cash' });
    expect(res.status).toBe(400);
    expect((res.body as { error: string }).error).toMatch(IDEMPOTENCY_KEY_REQUIRED_MESSAGE);
  });

  it('rejects an invalid payment method with 400', async () => {
    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({ settlement_date: '2026-11-27', amount: 100, payment_method: 'Bitcoin' });
    expect(res.status).toBe(400);
    expect(JSON.stringify(res.body)).toMatch(/payment_method|payment method/i);
  });

  it('rejects a non-positive amount with 400', async () => {
    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({ settlement_date: '2026-11-27', amount: 0, payment_method: 'Cash' });
    expect(res.status).toBe(400);
  });
});

describe('D30 — Settle overhead: posting', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await login();
  });

  it('splits an over-payment: accrued clears 2200, the excess books as expense', async () => {
    accrueOverhead(4000, '2026-11-05');
    fundAccount('1000', 10000, '2026-11-06');
    const owed = owedOverhead();
    expect(owed).toBe(4000);

    // Gull's Q3 answer B: the real bill (5,000) is bigger than the estimate.
    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({
        settlement_date: '2026-11-27',
        amount: owed + 1000,
        payment_method: 'Cash',
        reference_note: 'K-Electric bill',
      });
    expect(res.status).toBe(201);

    const data = (res.body as { data: { id: number; accrued_amount: number; excess_amount: number } }).data;
    expect(data.accrued_amount).toBe(4000);
    expect(data.excess_amount).toBe(1000);

    const lines = settleLines(data.id);
    // Dr 2200 clears the box entirely; Dr 6000 carries the excess; cash pays all of it.
    expect(lineFor(lines, '2200')?.debit).toBe(4000);
    expect(lineFor(lines, '6000')?.debit).toBe(1000);
    expect(lineFor(lines, '1000')?.credit).toBe(5000);
    expect(lines).toHaveLength(3);

    expect(owedOverhead()).toBe(0);
  });

  it('posts a plain settlement as Dr 2200 / Cr cash with no expense line', async () => {
    accrueOverhead(4000, '2026-11-06');
    fundAccount('1010', 5000, '2026-11-07');
    const owed = owedOverhead();

    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({ settlement_date: '2026-11-27', amount: 1500, payment_method: 'Bank Transfer' });
    expect(res.status).toBe(201);

    const data = (res.body as { data: { id: number; accrued_amount: number; excess_amount: number } }).data;
    expect(data.accrued_amount).toBe(1500);
    expect(data.excess_amount).toBe(0);

    const lines = settleLines(data.id);
    expect(lineFor(lines, '2200')?.debit).toBe(1500);
    expect(lineFor(lines, '1010')?.credit).toBe(1500); // Bank Transfer → 1010
    expect(lineFor(lines, '6000')).toBeUndefined();
    expect(lines).toHaveLength(2);

    expect(owedOverhead()).toBe(owed - 1500);
  });
});

describe('D30 — Settle overhead: guard refusals', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await login();
  });

  it('refuses a settlement that would drive the cash balance negative', async () => {
    const date = '2026-11-28';
    const available = Math.max(cashBalance('1000', date), 0);

    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({ settlement_date: date, amount: available + 5000, payment_method: 'Cash' });
    expect(res.status).toBe(409);
    expect(JSON.stringify(res.body)).toMatch(/Insufficient funds/i);
  });

  it('refuses a settlement dated in a closed period', async () => {
    accrueOverhead(1000, '2026-11-08');
    db.prepare(`
      INSERT INTO accounting_periods (period_name, start_date, end_date, status)
      VALUES ('2026-09-d30-closed', '2026-09-01', '2026-09-30', 'open')
      ON CONFLICT(period_name) DO NOTHING
    `).run();
    db.prepare(`UPDATE accounting_periods SET status = 'closed' WHERE period_name = '2026-09-d30-closed'`).run();

    const res = await request(app)
      .post(SETTLE)
      .set('Cookie', authCookie)
      .set('Idempotency-Key', key())
      .send({ settlement_date: '2026-09-15', amount: 100, payment_method: 'Cash' });
    expect(res.status).toBe(409);
    expect(JSON.stringify(res.body)).toMatch(/closed/i);

    // Nothing was written into the closed period.
    const rows = db.prepare(`
      SELECT COUNT(*) n FROM journal_entries
      WHERE reference_type = 'OVERHEAD_SETTLEMENT' AND entry_date = '2026-09-15'
    `).get() as { n: number };
    expect(rows.n).toBe(0);
  });
});

describe('D30 — Settle overhead: idempotency', () => {
  let authCookie: string;

  beforeAll(async () => {
    authCookie = await login();
  });

  it('replays a keyed retry instead of paying twice', async () => {
    accrueOverhead(1000, '2026-11-07');
    fundAccount('1000', 1000, '2026-11-08');
    const owed = owedOverhead();
    const k = key();
    const body = { settlement_date: '2026-11-27', amount: 100, payment_method: 'Cash' };

    const first = await request(app).post(SETTLE).set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(first.status).toBe(201);
    const firstId = (first.body as { data: { id: number } }).data.id;

    const second = await request(app).post(SETTLE).set('Cookie', authCookie)
      .set('Idempotency-Key', k).send(body);
    expect(second.status).toBe(201);
    expect((second.body as { data: { id: number } }).data.id).toBe(firstId);

    // Exactly one settlement for this payment: three payments happened in
    // this suite before it (over-payment, plain settlement, this one).
    const count = db.prepare(`
      SELECT COUNT(*) n FROM overhead_settlements WHERE settlement_no LIKE 'OHS-%'
    `).get() as { n: number };
    expect(count.n).toBe(3);
    const one = db.prepare(`
      SELECT COUNT(*) n FROM journal_entries
      WHERE reference_type = 'OVERHEAD_SETTLEMENT' AND reference_id = ?
    `).get(firstId) as { n: number };
    expect(one.n).toBe(1);
    expect(owedOverhead()).toBe(owed - 100);
  });
});
