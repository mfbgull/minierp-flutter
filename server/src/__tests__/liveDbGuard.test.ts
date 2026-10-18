import Database from 'better-sqlite3';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { resolveLiveDbPath, protectDatabaseConstructor } from './helpers/liveDbGuard';

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-live-guard-'));

afterAll(() => fs.rmSync(temporary, { recursive: true, force: true }));

describe('live database write protection', () => {
  it('resolves the server database from the helper directory', () => {
    expect(resolveLiveDbPath()).toBe(path.resolve(__dirname, '../../database/erp.db'));
  });

  it('refuses canonical and relative writes through the intercepted import', () => {
    expect(() => new Database(resolveLiveDbPath())).toThrow(/refused/);
    expect(() => new Database(path.relative(process.cwd(), resolveLiveDbPath()))).toThrow(/refused/);
  });

  it('refuses symlink aliases through the intercepted import', () => {
    const alias = path.join(temporary, 'canonical-alias.db');
    fs.symlinkSync(resolveLiveDbPath(), alias);
    expect(() => new Database(alias)).toThrow(/refused/);
  });

  it('allows memory databases to persist and read an insert', () => {
    const db = new Database(':memory:');
    try {
      db.exec('CREATE TABLE probe (amount INTEGER); INSERT INTO probe VALUES (500)');
      expect(db.prepare<[], { amount: number }>('SELECT amount FROM probe').get()).toEqual({ amount: 500 });
    } finally {
      db.close();
    }
  });

  it('allows isolated files while preserving read-only enforcement', () => {
    const filename = path.join(temporary, 'isolated.db');
    const writer = new Database(filename);
    writer.exec('CREATE TABLE probe (amount INTEGER)');
    writer.close();
    const reader = new Database(filename, { readonly: true });
    try {
      expect(() => reader.exec('INSERT INTO probe VALUES (1)')).toThrow(/readonly/);
    } finally {
      reader.close();
    }
  });

  it('detects a hardlink without opening the real canonical database', () => {
    const filename = path.join(temporary, 'hardlink-source.db');
    const original = new Database(filename);
    original.close();
    const alias = path.join(temporary, 'hardlink-alias.db');
    fs.linkSync(filename, alias);
    const Protected = protectDatabaseConstructor(Database, filename);
    expect(() => new Protected(alias)).toThrow(/refused/);
  });

  it('refuses dangling symlinks to a missing canonical database', () => {
    const filename = path.join(temporary, 'missing', 'database', 'erp.db');
    const alias = path.join(temporary, 'dangling.db');
    fs.symlinkSync(filename, alias);
    const Protected = protectDatabaseConstructor(Database, filename);
    expect(() => new Protected(alias)).toThrow(/refused/);
    expect(fs.existsSync(filename)).toBe(false);
  });
});
