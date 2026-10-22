import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import { localMonthCode } from '../utils/documentNumbering';
import { generateDocNo, generateReceiptBatchNo, getNextSequenceNumber } from '../utils/sequence';

describe('document numbering compatibility', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(':memory:');
    db.exec('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT)');
    jest.useFakeTimers().setSystemTime(new Date(2026, 11, 31, 12));
  });

  afterEach(() => {
    jest.useRealTimers();
    db.close();
  });

  it('formats local calendar dates in both existing orders', () => {
    expect(localMonthCode(new Date(2026, 0, 1))).toBe('0126');
    expect(localMonthCode(new Date(2026, 0, 1), 'YYMM')).toBe('2601');
    expect(localMonthCode(new Date('invalid'))).toBe('NaNaN');
  });

  it('shares the receipt counter across purchase and production, preserving existing rows', () => {
    db.prepare('INSERT INTO settings (key, value) VALUES (?, ?)').run('BATCH_last_no_1226', '41');
    expect(generateReceiptBatchNo(db, 'PUR')).toBe('BATCH-1226-PUR-00042');
    expect(generateReceiptBatchNo(db, 'PRD')).toBe('BATCH-1226-PRD-00043');
    expect(generateReceiptBatchNo(db, 'PUR')).toBe('BATCH-1226-PUR-00044');
  });

  it('starts a new month counter and retains document padding', () => {
    expect(generateDocNo(db, 'INV')).toBe('INV-1226-0001');
    expect(generateDocNo(db, 'INV', 5)).toBe('INV-1226-00002');
    jest.setSystemTime(new Date(2027, 0, 1, 12));
    expect(generateDocNo(db, 'INV')).toBe('INV-0127-0001');
    expect(generateReceiptBatchNo(db, 'PRD')).toBe('BATCH-0127-PRD-00001');
  });

  it('retains SQLite integer coercion for malformed legacy counter values', () => {
    db.prepare('INSERT INTO settings (key, value) VALUES (?, ?)').run('BATCH_TRF_last_no', '12suffix');
    db.prepare('INSERT INTO settings (key, value) VALUES (?, ?)').run('BATCH_EXP_last_no', 'invalid');
    expect(getNextSequenceNumber(db, 'BATCH_TRF_last_no')).toBe(13);
    expect(getNextSequenceNumber(db, 'BATCH_EXP_last_no')).toBe(1);
    expect(getNextSequenceNumber(db, 'BATCH_DAM_last_no')).toBe(1);
  });

  it('rolls back allocation with the enclosing receipt transaction', () => {
    const failedReceipt = db.transaction(() => {
      expect(generateReceiptBatchNo(db, 'PUR')).toBe('BATCH-1226-PUR-00001');
      throw new Error('receipt rejected');
    });
    expect(failedReceipt).toThrow('receipt rejected');
    expect(generateReceiptBatchNo(db, 'PRD')).toBe('BATCH-1226-PRD-00001');
    expect(generateReceiptBatchNo(db, 'PUR')).toBe('BATCH-1226-PUR-00002');
  });
});
