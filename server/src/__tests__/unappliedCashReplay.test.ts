import Database from 'better-sqlite3';
import { afterAll, test, expect } from '@jest/globals';
import { createFixtureDb, cleanupFixtureDbs, seedCustomers } from './helpers/productionSchema';
import { UnappliedCashService } from '../services/unappliedCashService';
import { getReceiptReplay, saveReceiptReplay } from '../models/UnappliedCash';
import { hashRequestPayload } from '../utils/idempotency';

afterAll(cleanupFixtureDbs);

test('durable receipt replay survives reopen and has unique, non-cascading references', () => {
  const db = createFixtureDb({ reference: true });
  seedCustomers(db);
  const service = new UnappliedCashService(db);
  const receipt = service.receive({ customerId: 1, amount: 25, date: '2026-10-01', paymentMethod: 'Cash' });
  const hash = hashRequestPayload({ amount: 25 });
  saveReceiptReplay(db, 1, 'durable-reopen', hash, receipt.paymentId, receipt.amount);
  expect(() => saveReceiptReplay(db, 1, 'durable-reopen', hash, receipt.paymentId, 25)).toThrow();
  expect(() => saveReceiptReplay(db, 2, 'missing-payment', hash, 99999999, 25)).toThrow();
  expect(() => saveReceiptReplay(db, 99999999, 'missing-customer', hash, receipt.paymentId, 25)).toThrow();
  expect(() => db.prepare('DELETE FROM payments WHERE id=?').run(receipt.paymentId)).toThrow();
  expect(() => getReceiptReplay(db, 1, 'durable-reopen', 'different')).toThrow();
  expect(getReceiptReplay(db, 2, 'durable-reopen', hash)).toBeUndefined();
  const filename = db.name;
  db.close();
  const reopened = new Database(filename);
  try {
    expect(getReceiptReplay(reopened, 1, 'durable-reopen', hash)).toEqual({ request_hash: hash, payment_id: receipt.paymentId, amount: 25 });
  } finally {
    reopened.close();
  }
});
