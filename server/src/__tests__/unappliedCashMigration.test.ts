import fs from 'fs';
import path from 'path';
import type Database from 'better-sqlite3';
import singleton, { applyPendingMigrations } from '../config/database';
import {
  createFixtureDb, cleanupFixtureDbs, seedCustomers, seedHistoricalLedger,
} from './helpers/productionSchema';

const migrationName = '108_unapplied_customer_payments.sql';
const migrationPath = path.join(__dirname, '../migrations', migrationName);

afterAll(() => cleanupFixtureDbs());

function preFeatureDb(): Database.Database {
  const db = createFixtureDb({ reference: true });
  db.exec('DROP TABLE IF EXISTS credit_source_consumptions');
  db.exec('DROP TABLE IF EXISTS credit_applications');
  db.exec('DROP TABLE IF EXISTS customer_credit_sources');
  const columns = db.pragma('table_info(payments)');
  if (Array.isArray(columns) && columns.some(column => column.name === 'payment_kind')) {
    db.exec('ALTER TABLE payments DROP COLUMN payment_kind');
  }
  db.prepare("DELETE FROM chart_of_accounts WHERE code='2110'").run();
  return db;
}

function migrate(db: Database.Database): void {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  db.transaction(() => db.exec(sql))();
}

describe('unapplied cash migration and historical backfill', () => {
  it('creates the liability account with its numeric identity and text code', () => {
    const db = preFeatureDb();
    migrate(db);
    expect(db.prepare("SELECT code,type,normal_balance,text_code FROM chart_of_accounts WHERE code='2110'").get()).toEqual({
      code: '2110', type: 'liability', normal_balance: 'credit', text_code: 'unapplied_customer_payments',
    });
    expect(db.pragma('foreign_key_check')).toEqual([]);
  });

  it('backfills thirteen inert sources and allocates consumption FIFO per source', () => {
    const db = preFeatureDb();
    seedHistoricalLedger(db);
    migrate(db);
    const totals = db.prepare<[], {
      count: number; credited: number; consumed: number; remaining: number; refundable: number;
    }>(`SELECT COUNT(*) count, SUM(credited_amount) credited, SUM(consumed_amount) consumed,
        SUM(remaining_amount) remaining, SUM(refundable_cash_amount) refundable
        FROM customer_credit_sources`).get();
    expect(totals?.count).toBe(13);
    expect(totals?.credited).toBeCloseTo(8550.20, 2);
    expect(totals?.consumed).toBe(1800);
    expect(totals?.remaining).toBeCloseTo(6750.20, 2);
    expect(totals?.refundable).toBe(0);
    expect(db.prepare('SELECT credited_amount, consumed_amount, remaining_amount FROM customer_credit_sources WHERE customer_id=15 ORDER BY id').all()).toEqual([
      { credited_amount: 600, consumed_amount: 600, remaining_amount: 0 },
      { credited_amount: 600, consumed_amount: 600, remaining_amount: 0 },
      { credited_amount: 550, consumed_amount: 550, remaining_amount: 0 },
      { credited_amount: 550, consumed_amount: 50, remaining_amount: 500 },
    ]);
    expect(db.prepare("SELECT COUNT(*) count FROM customer_credit_sources WHERE kind='UNAPPLIED_CASH'").get()).toEqual({ count: 0 });
  });

  it('excludes voided and reversed grants and consumption', () => {
    const db = preFeatureDb();
    seedHistoricalLedger(db);
    db.exec(`INSERT INTO customer_ledger
      (customer_id,transaction_date,transaction_type,credit,debit,balance,voided)
      VALUES (1,'2026-09-01','RETURN',9999,0,0,1)`);
    db.exec(`INSERT INTO customer_ledger
      (customer_id,transaction_date,transaction_type,credit,debit,balance,reversed_by)
      VALUES (1,'2026-09-01','CREDIT_OFFSET',9999,0,0,1)`);
    migrate(db);
    expect(db.prepare('SELECT COUNT(*) count FROM customer_credit_sources').get()).toEqual({ count: 13 });
  });

  it('rejects consumption without any supporting grant and rolls back all DDL', () => {
    const db = preFeatureDb();
    seedCustomers(db);
    db.exec(`INSERT INTO customer_ledger
      (customer_id,transaction_date,transaction_type,credit,debit,balance)
      VALUES (1,'2026-09-01','CREDIT_OFFSET',100,0,-100)`);
    expect(() => migrate(db)).toThrow();
    expect(db.prepare("SELECT name FROM sqlite_master WHERE name='customer_credit_sources'").get()).toBeUndefined();
    expect(db.prepare("SELECT id FROM chart_of_accounts WHERE code='2110'").get()).toBeUndefined();
  });

  it('rejects per-customer overdraw even when other customers have surplus grants', () => {
    const db = preFeatureDb();
    seedHistoricalLedger(db);
    db.prepare("UPDATE customer_ledger SET credit=2000 WHERE transaction_type='CREDIT_OFFSET' AND reference_no='OFF-15-0'").run();
    expect(() => migrate(db)).toThrow();
  });

  it.each([
    ['asset', 'debit', 'wrong_code'],
    ['liability', 'debit', 'unapplied_customer_payments'],
    ['liability', 'credit', 'wrong_code'],
  ])('rejects an incompatible pre-existing 2110 (%s/%s/%s)', (type, normal, textCode) => {
    const db = preFeatureDb();
    db.prepare('INSERT INTO chart_of_accounts (code,name,type,normal_balance,text_code) VALUES (?,?,?,?,?)')
      .run('2110', 'Conflicting account', type, normal, textCode);
    expect(() => migrate(db)).toThrow();
    expect(db.prepare("SELECT name FROM sqlite_master WHERE name='customer_credit_sources'").get()).toBeUndefined();
  });

  it('rejects the required text code attached to another account', () => {
    const db = preFeatureDb();
    db.prepare('INSERT INTO chart_of_accounts (code,name,type,normal_balance,text_code) VALUES (?,?,?,?,?)')
      .run('2999', 'Conflicting identity', 'liability', 'credit', 'unapplied_customer_payments');
    expect(() => migrate(db)).toThrow();
  });

  it('allows full drain after apply and enforces generated columns and all source bounds', () => {
    const db = preFeatureDb();
    seedCustomers(db);
    migrate(db);
    db.exec(`INSERT INTO customer_credit_sources
      (customer_id,kind,credited_amount,refundable_cash_amount)
      VALUES (1,'UNAPPLIED_CASH',500,500)`);
    db.exec('UPDATE customer_credit_sources SET consumed_amount=400,refundable_cash_amount=100 WHERE id=1');
    db.exec('UPDATE customer_credit_sources SET refunded_amount=100,refundable_cash_amount=0 WHERE id=1');
    expect(db.prepare('SELECT remaining_amount FROM customer_credit_sources WHERE id=1').get()).toEqual({ remaining_amount: 0 });
    expect(() => db.exec('UPDATE customer_credit_sources SET remaining_amount=1')).toThrow(/generated/);
    for (const sql of [
      'UPDATE customer_credit_sources SET refunded_amount=501',
      'UPDATE customer_credit_sources SET consumed_amount=-1',
      'UPDATE customer_credit_sources SET refundable_cash_amount=-1',
      'UPDATE customer_credit_sources SET refundable_cash_amount=1',
    ]) expect(() => db.exec(sql)).toThrow(/CHECK/);
  });

  it('enforces scoped application keys and indexes the new relationship lookups', () => {
    const db = preFeatureDb();
    seedCustomers(db);
    migrate(db);
    const insert = db.prepare(`INSERT INTO credit_applications
      (application_key,customer_id,operation,total_amount) VALUES (?,?,'APPLY',100)`);
    insert.run('key', 1);
    expect(() => insert.run('key', 1)).toThrow(/UNIQUE/);
    expect(() => insert.run('key', 2)).not.toThrow();
    const indexes = db.prepare<[], { name: string }>(`SELECT name FROM sqlite_master
      WHERE type='index' AND tbl_name IN ('customer_credit_sources','credit_source_consumptions','credit_applications')`).all();
    expect(indexes.map(index => index.name)).toEqual(expect.arrayContaining([
      'idx_credit_sources_customer_live', 'idx_credit_consumptions_source_live',
      'idx_credit_consumptions_application', 'idx_credit_applications_key',
    ]));
  });

  it('is registered once and skipped by the actual migration runner on replay', () => {
    const before = singleton.prepare('SELECT * FROM schema_migrations WHERE filename=?').get(migrationName);
    expect(before).toBeDefined();
    applyPendingMigrations();
    expect(singleton.prepare('SELECT * FROM schema_migrations WHERE filename=?').get(migrationName)).toEqual(before);
    expect(singleton.prepare('SELECT COUNT(*) count FROM schema_migrations WHERE filename=?').get(migrationName)).toEqual({ count: 1 });
  });
});
