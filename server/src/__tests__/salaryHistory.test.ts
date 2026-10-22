import { afterAll, describe, expect, it } from '@jest/globals';
import EmployeeModel from '../models/Employee';
import { createFixtureDb, cleanupFixtureDbs } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

describe('EmployeeModel.getSalaryHistory', () => {
  it('aggregates periods, statuses, advances, remaining and excludes voided rows', () => {
    const db = createFixtureDb();
    const employee = db.prepare(`
      INSERT INTO employees (employee_code, first_name, last_name, salary)
      VALUES ('SAL-HIST-1', 'Salary', 'History', 1000)
    `).run();
    const employeeId = Number(employee.lastInsertRowid);

    const insert = db.prepare(`
      INSERT INTO salary_payments
        (employee_id, amount, payment_date, pay_period, reference_no, voided_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `);

    insert.run(employeeId, 1000, '2026-09-05', '2026-09', null, null);
    insert.run(employeeId, 300, '2026-08-05', '2026-08', null, null);
    insert.run(employeeId, 200, '2026-07-05', '2026-07', 'ADV-2026-06', null);
    insert.run(employeeId, 0, '2026-06-05', '2026-06', null, null);
    insert.run(employeeId, 100, '2026-05-05', '2026-05', 'ADV-bad', null);
    insert.run(employeeId, 1000, '2026-04-05', '2026-04', null, '2026-04-06');

    const rows = EmployeeModel.getSalaryHistory(employeeId, db);
    expect(rows.map((r) => r.pay_period)).toEqual([
      '2026-09',
      '2026-08',
      '2026-07',
      '2026-06',
      '2026-05',
    ]);

    const byPeriod = new Map(rows.map((r) => [r.pay_period, r]));

    expect(byPeriod.get('2026-09')).toMatchObject({
      employee_salary: 1000,
      total_paid: 1000,
      remaining: 0,
      status: 'paid',
      payment_count: 1,
      advance_carryover: 0,
      advance_source_period: null,
      first_payment_date: '2026-09-05',
      last_payment_date: '2026-09-05',
    });

    expect(byPeriod.get('2026-08')).toMatchObject({
      employee_salary: 1000,
      total_paid: 300,
      remaining: 700,
      status: 'partial',
      payment_count: 1,
      advance_carryover: 0,
      advance_source_period: null,
    });

    expect(byPeriod.get('2026-07')).toMatchObject({
      total_paid: 200,
      remaining: 800,
      status: 'advance',
      payment_count: 1,
      advance_carryover: 200,
      advance_source_period: '2026-06',
    });

    expect(byPeriod.get('2026-06')).toMatchObject({
      total_paid: 0,
      remaining: 1000,
      status: 'advance',
      payment_count: 1,
      advance_carryover: 0,
      advance_source_period: null,
    });

    expect(byPeriod.get('2026-05')).toMatchObject({
      total_paid: 100,
      remaining: 900,
      status: 'advance',
      payment_count: 1,
      advance_carryover: 100,
      advance_source_period: null,
    });
  });
});
