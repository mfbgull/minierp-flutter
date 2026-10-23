import Database from 'better-sqlite3';
import { afterAll, describe, expect, it } from '@jest/globals';
import EmployeeModel from '../models/Employee';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

/**
 * Fallow health remediation — `Employee.getAdvanceCarryover` (CRAP 90).
 * Covers missing/zero salary, full months above/at/below salary, partial
 * months below/at/above salary, full+advance months, voided rows, and rows
 * at/after the target pay period.
 */
function fixture(): { db: Database.Database; employeeId: number } {
  const db = createFixtureDb();
  const result = db.prepare(`
    INSERT INTO employees (employee_code, first_name, last_name, salary)
    VALUES ('EMP-CARRY', 'Carry', 'Over', 1000)
  `).run();
  return { db, employeeId: Number(result.lastInsertRowid) };
}

function pay(
  db: Database.Database,
  employeeId: number,
  payPeriod: string,
  amount: number,
  paymentType: 'full' | 'advance' | 'partial',
  voided = false,
): number {
  const id = EmployeeModel.addSalaryPayment(
    {
      employee_id: employeeId,
      amount,
      payment_date: `${payPeriod}-15`,
      payment_method: 'bank',
      pay_period: payPeriod,
      payment_type: paymentType,
    },
    db,
  );
  if (voided) {
    db.prepare(
      'UPDATE salary_payments SET voided_at = CURRENT_TIMESTAMP WHERE id = ?',
    ).run(id);
  }
  return id;
}

describe('Employee.getAdvanceCarryover', () => {
  it('returns zero for a missing employee and a non-positive salary', () => {
    const db = createFixtureDb();
    expect(EmployeeModel.getAdvanceCarryover(999999, '2026-08', db)).toBe(0);

    const zero = db.prepare(`
      INSERT INTO employees (employee_code, first_name, last_name, salary)
      VALUES ('EMP-ZERO', 'Zero', 'Salary', 0)
    `).run();
    expect(
      EmployeeModel.getAdvanceCarryover(Number(zero.lastInsertRowid), '2026-08', db),
    ).toBe(0);
    db.close();
  });

  it('sums excess from prior full and partial months only', () => {
    const { db, employeeId } = fixture();

    pay(db, employeeId, '2026-01', 1200, 'full'); // +200
    pay(db, employeeId, '2026-02', 1100, 'advance'); // +100
    pay(db, employeeId, '2026-03', 900, 'partial'); // under -> 0
    pay(db, employeeId, '2026-04', 800, 'full'); // under -> 0
    pay(db, employeeId, '2026-05', 1000, 'advance'); // exactly -> 0
    pay(db, employeeId, '2026-06', 800, 'full'); // full + advance -> +100
    pay(db, employeeId, '2026-06', 300, 'advance');
    pay(db, employeeId, '2026-07', 500, 'advance', true); // voided -> ignored
    pay(db, employeeId, '2026-09', 500, 'advance'); // at/after target -> ignored

    expect(
      EmployeeModel.getAdvanceCarryover(employeeId, '2026-08', db),
    ).toBe(400);
    db.close();
  });
});
