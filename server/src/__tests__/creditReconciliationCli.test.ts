import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { main } from '../../scripts/reconcile-customer-credits';
import { createFixtureDb, cleanupFixtureDbs, seedHistoricalLedger } from './helpers/productionSchema';

afterAll(() => cleanupFixtureDbs());
afterEach(() => jest.restoreAllMocks());

it('rejects missing arguments before creating a temporary snapshot', async () => {
  const temporary = jest.spyOn(fs, 'mkdtempSync');
  await expect(main([])).rejects.toThrow('Usage:');
  expect(temporary).not.toHaveBeenCalled();
});

it('rejects a nonexistent source and cleans its owned snapshot directory', async () => {
  const temporary = jest.spyOn(fs, 'mkdtempSync');
  const missing = path.join(process.env.DATABASE_PATH ?? '', 'missing-source.db');
  await expect(main([missing])).rejects.toMatchObject({ code: 'SQLITE_CANTOPEN' });
  expect(fs.existsSync(missing)).toBe(false);
  expect(temporary.mock.results).toHaveLength(1);
  expect(fs.existsSync(temporary.mock.results[0].value)).toBe(false);
});

it('reports real fixture reconciliation without changing source bytes and removes its snapshot', async () => {
  const db = createFixtureDb({ reference: true });
  seedHistoricalLedger(db);
  db.pragma('wal_checkpoint(TRUNCATE)');
  const source = db.name;
  db.close();
  const hash = () => crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex');
  const before = hash();
  const output = jest.spyOn(console, 'log').mockImplementation(() => undefined);
  const temporary = jest.spyOn(fs, 'mkdtempSync');
  await main([source]);
  expect(hash()).toBe(before);
  expect(output).toHaveBeenCalledTimes(1);
  const report = JSON.parse(String(output.mock.calls[0][0]));
  expect(report.sourceFingerprintsUnchanged).toBe(true);
  expect(report.sourceHash).toBe(before);
  expect(report.rows.map((row: { customerId: number }) => row.customerId)).toEqual([1, 12, 13, 14, 15]);
  expect(report.arBaseline).toEqual(expect.objectContaining({ difference: expect.any(Number) }));
  expect(fs.existsSync(temporary.mock.results[0].value)).toBe(false);
}, 60000);
