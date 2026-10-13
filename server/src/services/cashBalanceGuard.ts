import type Database from 'better-sqlite3';
import AccountingService from './accountingService';
import { BusinessRuleError } from '../utils/businessRuleError';

interface NegativeCashDay {
  readonly line_date: string;
  readonly balance: number;
}

export function assertCashTimeline(
  db: Database.Database,
  args: { readonly paymentMethod?: string | null; readonly fromDate: string },
): void {
  const code = AccountingService._cashOrBankAccountCode(args.paymentMethod ?? undefined);
  const account = AccountingService.getAccountByCode(db, code);
  if (!account) throw new BusinessRuleError(400, `Missing required account ${code}`);

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
    throw new BusinessRuleError(400,
      `Insufficient funds in ${account.name} on ${deficit.line_date}: ` +
      `balance would be ${(deficit.balance / 100).toFixed(2)}. Reverse the later spending first.`);
  }
}
