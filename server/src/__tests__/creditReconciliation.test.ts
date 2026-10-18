import { reconcileCustomerCredits } from '../services/creditReconciliation';
import { createFixtureDb, cleanupFixtureDbs, seedHistoricalLedger } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());

describe('read-only customer credit reconciliation', () => {
  it('reports the five deterministic customer IDs and their unrepaired discrepancies', () => {
    const db = createFixtureDb({ reference: true });
    seedHistoricalLedger(db);
    const rows = reconcileCustomerCredits(db);
    expect(rows.map(row => [row.customerId, row.ledgerDerived])).toEqual([
      [1, 250.20], [12, 100], [13, 800], [14, 1200], [15, -50],
    ]);
    expect(rows.every(row => row.storedCreditBalance === 0 && !row.agrees)).toBe(true);
    expect(rows.map(row => row.ledgerRefunded)).toEqual([1200, 2300, 400, 0, 550]);
  });

  it('executes under query_only without modifying ledger or customer data', () => {
    const db = createFixtureDb();
    seedHistoricalLedger(db);
    const beforeCustomers = db.prepare('SELECT * FROM customers ORDER BY id').all();
    const beforeLedger = db.prepare('SELECT * FROM customer_ledger ORDER BY id').all();
    db.pragma('query_only = ON');
    expect(reconcileCustomerCredits(db)).toHaveLength(5);
    expect(db.prepare('SELECT * FROM customers ORDER BY id').all()).toEqual(beforeCustomers);
    expect(db.prepare('SELECT * FROM customer_ledger ORDER BY id').all()).toEqual(beforeLedger);
  });

  it('excludes voided and reversed grants, refunds and offsets', () => {
    const db = createFixtureDb();
    seedHistoricalLedger(db);
    const before = reconcileCustomerCredits(db);
    const insert = db.prepare(`INSERT INTO customer_ledger
      (customer_id,transaction_date,transaction_type,debit,credit,balance,voided,reversed_by)
      VALUES (1,'2026-09-01',?,?,?,0,?,?)`);
    for (const type of ['RETURN', 'REFUND', 'CREDIT_OFFSET']) {
      insert.run(type, 9999, 9999, 1, null);
      insert.run(type, 9999, 9999, 0, 1);
    }
    expect(reconcileCustomerCredits(db)).toEqual(before);
  });

  it('includes a stored-only balance and omits customers with no credit history', () => {
    const db = createFixtureDb();
    db.exec(`INSERT INTO customers (id,customer_code,customer_name,credit_balance)
      VALUES (1,'stored','Stored balance',42),(2,'empty','Empty history',0)`);
    expect(reconcileCustomerCredits(db)).toEqual([{
      customerId: 1, storedCreditBalance: 42, ledgerGranted: 0,
      ledgerRefunded: 0, ledgerConsumed: 0, ledgerDerived: 0, agrees: false,
    }]);
  });
});
