/**
 * Regression tests for the three latent defects that enabling strict mode
 * exposed. Each had no coverage, which is precisely why it survived: the
 * type system was the only thing looking at these paths.
 *
 * These pin behaviour, not types. If any of them fails, the underlying
 * defect is back.
 */
import type { Request, Response } from 'express';
import db from '../config/database';
import { log, flushLogs, ActionType } from '../services/activityLogger';

// ── 1. flush() returned falsy on success ────────────────────────────────
//
// flush() is declared `flush(): boolean` so callers can detect failure. The
// try block used to fall through to the end of the function, so a
// successful flush returned undefined — falsy, and indistinguishable from a
// failure to any caller testing the result.

describe('activityLogger.flush() return contract', () => {
  beforeEach(() => {
    // Drain anything a previous test queued so the assertion below is about
    // this test's own entry, not a leftover batch.
    flushLogs();
  });

  it('returns true after successfully writing queued entries', () => {
    log({
      userId: 1,
      action: ActionType.LOGIN,
      entityType: 'Auth',
      entityId: 1,
      description: 'flush-success-probe',
    });

    // The defect was `undefined` here. A truthy assertion would also have
    // passed on the old code only if the value were true, so pin it exactly.
    expect(flushLogs()).toBe(true);

    const row = db.prepare(
      'SELECT COUNT(*) AS n FROM activity_log WHERE description = ?'
    ).get('flush-success-probe') as { n: number };
    expect(row.n).toBe(1);
  });

  it('returns true when there is nothing queued', () => {
    expect(flushLogs()).toBe(true);
  });

  it('returns true on a repeated flush, so a caller cannot mistake a no-op for failure', () => {
    log({
      userId: 1,
      action: ActionType.LOGIN,
      entityType: 'Auth',
      entityId: 1,
      description: 'flush-repeat-probe',
    });
    expect(flushLogs()).toBe(true);
    // Second call has an empty queue; it must not report failure.
    expect(flushLogs()).toBe(true);
  });
});

// ── 2. getReceivablesSummary overwrote asOfDate ─────────────────────────
//
// The controller built its response as `{ asOfDate, ...summary }`, but the
// model result already carries asOfDate, so the spread silently replaced the
// query-derived value. They happened to be equal, which is why nothing broke
// visibly. The fix drops the redundant key.

describe('getReceivablesSummary response asOfDate', () => {
  // Minimal Response double capturing the JSON payload.
  function capture(): { statusCode: number; body: unknown; json: (p: unknown) => unknown } {
    const captured = {
      statusCode: 200,
      body: undefined as unknown,
      json(payload: unknown) {
        captured.body = payload;
        return captured;
      },
    };
    return captured;
  }

  it('echoes the requested asOfDate once, from the model result', async () => {
    const ReportsModel = (await import('../models/Reports')).default;
    const summary = ReportsModel.getReceivablesSummary(db, '2026-03-15');
    expect(summary.asOfDate).toBe('2026-03-15');

    // Drive the real controller: the response must carry exactly the date
    // that was requested. The defect was a spread that replaced this value
    // with the model's copy, which agreed by coincidence and so was never
    // observable — asserting the end-to-end value is what pins it.
    const controller = (await import('../controllers/reportsController')).default;
    const res = capture();
    const req = { query: { asOfDate: '2026-03-15' } } as unknown as Request;

    controller.getReceivablesSummary(req, res as unknown as Response);

    const body = res.body as { success: boolean; data: { asOfDate: string } };
    expect(body.success).toBe(true);
    expect(body.data.asOfDate).toBe('2026-03-15');
  });
});

// ── 3. Borrower merge read mergedLoans before assignment ────────────────
//
// The row count was assigned inside a db.transaction callback and read after
// it behind a non-null assertion that hid the definite-assignment error.
// The transaction now returns the count directly.

describe('borrower merge reports the reassigned loan count', () => {
  interface CapturedResponse {
    statusCode: number;
    body: { success?: boolean; data?: { merged_loans?: number; source_deactivated?: boolean } };
    status: (code: number) => CapturedResponse;
    json: (payload: unknown) => CapturedResponse;
  }

  function capture(): CapturedResponse {
    const captured: CapturedResponse = {
      statusCode: 200,
      body: {},
      status(code: number) {
        captured.statusCode = code;
        return captured;
      },
      json(payload: unknown) {
        captured.body = payload as CapturedResponse['body'];
        return captured;
      },
    };
    return captured;
  }

  /** Seed a borrower plus one loan attributed to them. */
  function seedBorrowerWithLoan(name: string): { sourceId: number; loanId: number } {
    const suffix = Math.random().toString(36).slice(2, 8);
    const borrowerName = `${name}-${suffix}`;

    // linked_type is CHECK'd to ('customer', 'supplier'); linked rows point
    // at a real customer so the UNIQUE(name, linked_type, linked_id) holds.
    const customer = db.prepare(
      `INSERT INTO customers (customer_code, customer_name) VALUES (?, ?)`
    ).run(`C-${suffix}`, borrowerName);
    const customerId = Number(customer.lastInsertRowid);

    const borrower = db.prepare(
      `INSERT INTO owner_personal_loan_borrowers (name, linked_type, linked_id, is_active)
       VALUES (?, 'customer', ?, 1)`
    ).run(borrowerName, customerId);
    const sourceId = Number(borrower.lastInsertRowid);

    const loan = db.prepare(
      `INSERT INTO owner_personal_loans
         (loan_no, borrower_id, borrower_name, borrower_type, amount, balance,
          loan_date, status, created_by)
       VALUES (?, ?, ?, 'customer', 1000, 1000, '2026-01-01', 'pending', 1)`
    ).run(`PL-TEST-${suffix}`, sourceId, borrowerName);
    const loanId = Number(loan.lastInsertRowid);

    return { sourceId, loanId };
  }

  it('returns a real count and deactivates the source borrower', async () => {
    const { sourceId, loanId } = seedBorrowerWithLoan('Src');

    const targetCustomer = db.prepare(
      `INSERT INTO customers (customer_code, customer_name) VALUES (?, ?)`
    ).run(`C-T-${sourceId}`, `Tgt-${sourceId}`);
    const target = db.prepare(
      `INSERT INTO owner_personal_loan_borrowers (name, linked_type, linked_id, is_active)
       VALUES (?, 'customer', ?, 1)`
    ).run(`Tgt-${sourceId}`, Number(targetCustomer.lastInsertRowid));
    const targetId = Number(target.lastInsertRowid);

    const controller = (await import('../controllers/ownerPersonalLoansController')).default;
    const res = capture();
    const req = {
      // The source borrower is the route param, not the request body.
      params: { id: String(sourceId) },
      body: { target_borrower_id: targetId },
      headers: {},
      user: { id: 1 },
      activityLogged: false,
    } as unknown as Request & { activityLogged?: boolean };

    controller.mergeBorrowers(
      req as Parameters<typeof controller.mergeBorrowers>[0],
      res as unknown as Response
    );

    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    // The defect surfaced as an unassigned value reaching this response.
    expect(typeof res.body.data?.merged_loans).toBe('number');
    expect(res.body.data?.merged_loans).toBe(1);
    expect(res.body.data?.source_deactivated).toBe(true);

    const loan = db.prepare(
      'SELECT borrower_id FROM owner_personal_loans WHERE id = ?'
    ).get(loanId) as { borrower_id: number };
    expect(loan.borrower_id).toBe(targetId);

    const source = db.prepare(
      'SELECT is_active FROM owner_personal_loan_borrowers WHERE id = ?'
    ).get(sourceId) as { is_active: number };
    expect(source.is_active).toBe(0);
  });
});