import type Database from 'better-sqlite3';
import { BusinessRuleError } from '../utils/businessRuleError';

/**
 * cashTimeline — the chronological cash-balance guard (D2 / ACCT-013 / D21).
 *
 * This module is the shared home for the check that removing or moving a
 * cash movement cannot drive any later day's cash/bank balance negative.
 * It is deliberately a LEAF: it imports nothing from `accountingService`
 * or any other service, so `accountingService` can import it at the top
 * level without closing the cycle that previously forced the lazy
 * `require('./cashBalanceGuard')` inside `assertCashTimelineAfterOutflow`
 * (D21 — now removed).
 *
 * The method→account-code map lives here as the single source of truth;
 * `AccountingService._cashOrBankAccountCode` delegates to it. The list is
 * seeded by the add-cash-accounts migration; keep it in sync with
 * `cashService` normalization and the reconciliation report.
 */

export type CashOrBankCode = '1000' | '1010' | '1020' | '1030' | '1040';

export function cashOrBankAccountCode(paymentMethod?: string): CashOrBankCode {
  if (!paymentMethod) return '1000';
  const m = paymentMethod.toLowerCase().trim();
  if (m === 'cash') return '1000';
  if (m === 'easypaisa') return '1020';
  if (m === 'jazzcash') return '1030';
  if (m === 'upaisa') return '1040';
  return '1010';
}

/** Same lookup semantics as `AccountingService.getAccountByCode` (inlined
 * here so this module stays a leaf and the cycle stays broken). */
function getAccountByCode(db: Database.Database, code: string): { id: number; name: string } | undefined {
  return db.prepare(`SELECT * FROM chart_of_accounts WHERE code = ?`).get(code) as
    { id: number; name: string } | undefined;
}

interface NegativeCashDay {
  readonly line_date: string;
  readonly balance: number;
}

interface CashBlocker {
  readonly id: number;
  readonly date: string;
  readonly amount: number;
  readonly type: string;
}

export function assertCashTimeline(
  db: Database.Database,
  args: { readonly paymentMethod?: string | null; readonly fromDate: string },
): void {
  const code = cashOrBankAccountCode(args.paymentMethod ?? undefined);
  const account = getAccountByCode(db, code);
  if (!account) throw new BusinessRuleError(409, `Missing required account ${code}`);

  const deficit = db.prepare<[number, string], NegativeCashDay>(`
    WITH daily AS (
      SELECT line_date, SUM(ROUND(debit * 100) - ROUND(credit * 100)) AS movement
      FROM journal_lines WHERE account_id = ? AND voided = 0
      GROUP BY line_date
    ), balances AS (
      SELECT line_date, SUM(movement) OVER (ORDER BY line_date) AS balance FROM daily
    )
    SELECT line_date, balance FROM balances
    WHERE line_date >= ? AND balance < 0 ORDER BY line_date LIMIT 1
  `).get(account.id, args.fromDate);

  if (deficit) {
    // ACCT-013: the lines landing on the first deficit date, returned as
    // structured data so the client can show what must be reversed first.
    const blockers = db.prepare<[number, string], { id: number; date: string; amount_cents: number; type: string }>(`
      SELECT id, line_date AS date,
             ROUND(debit * 100) - ROUND(credit * 100) AS amount_cents,
             reference_type AS type
      FROM journal_lines
      WHERE account_id = ? AND voided = 0 AND line_date = ?
      ORDER BY id
    `).all(account.id, deficit.line_date).map((r): CashBlocker => ({
      id: r.id,
      date: r.date,
      amount: r.amount_cents / 100,
      type: r.type,
    }));
    throw new BusinessRuleError(409,
      `Insufficient funds in ${account.name} on ${deficit.line_date}: ` +
      `balance would be ${(deficit.balance / 100).toFixed(2)}. Reverse the later spending first.`,
      blockers);
  }
}
