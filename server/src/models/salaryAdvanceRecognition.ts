import type Database from 'better-sqlite3';
import AccountingService from '../services/accountingService';
import { toMinorUnits } from '../utils/currency';

export function recognizeSalaryAdvances(db: Database.Database, employeeId: number, salary: number, paymentId: number, date: string, userId: number | undefined): void {
  const period = date.slice(0, 7);
  const advances = db.prepare(`SELECT p.id,p.amount,COALESCE(SUM(r.amount_minor),0) AS recognized
    FROM salary_payments p LEFT JOIN salary_advance_recognitions r ON r.advance_id=p.id AND r.voided_at IS NULL
    WHERE p.employee_id=? AND p.pay_period=? AND p.payment_type='advance' AND p.parent_payment_id IS NOT NULL AND p.voided_at IS NULL
    GROUP BY p.id ORDER BY p.id`).all(employeeId, period) as Array<{ id: number; amount: number; recognized: number }>;
  let remaining = toMinorUnits(salary);
  for (const advance of advances) {
    const amount = Math.min(remaining, Math.max(0, toMinorUnits(advance.amount) - advance.recognized));
    remaining = Math.max(0, remaining - toMinorUnits(advance.amount));
    if (amount === 0) continue;
    const wages = AccountingService.getAccountByCode(db, '6100');
    const asset = AccountingService.getAccountByCode(db, '1310');
    if (!wages || !asset) throw new Error('Missing salary recognition accounts');
    AccountingService.postEntry(db, { entry_date: date, reference_type: 'SALARY_ADVANCE_EARNED', reference_id: paymentId,
      description: `Earned salary advance ${advance.id} for ${period}`, created_by: userId,
      lines: [{ account_id: wages.id, debit: amount / 100 }, { account_id: asset.id, credit: amount / 100 }] });
    db.prepare('INSERT INTO salary_advance_recognitions(advance_id,payment_id,amount_minor) VALUES(?,?,?)').run(advance.id, paymentId, amount);
  }
}
