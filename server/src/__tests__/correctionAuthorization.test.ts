import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { assertCorrectionAuthorized, LIVE_DB_PATH } from '../../scripts/lib/correctionSafety';

class RefusedExit extends Error {
  constructor(readonly status: number) {
    super(`refused with exit ${status}`);
  }
}

describe('historical correction authorization', () => {
  const keys = ['CORRECTION_AUTHORIZED', 'DATABASE_PATH', 'CORRECTION_ALLOW_LIVE', 'CORRECTION_LIVE_SHA256'] as const;
  const savedEnvironment = new Map(keys.map(key => [key, process.env[key]]));
  const savedArgv = process.argv;
  const fixtureBytes = Buffer.from('synthetic correction fixture');
  const aliasMetadata = fs.statSync(__filename, { bigint: true });
  const unrelatedMetadata = fs.statSync(path.join(__dirname, '../../scripts/lib/correctionSafety.ts'), { bigint: true });

  beforeEach(() => {
    for (const key of keys) delete process.env[key];
    process.argv = ['node', 'correction'];
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    jest.spyOn(process, 'exit').mockImplementation(status => {
      throw new RefusedExit(Number(status));
    });
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'statSync').mockReturnValue(undefined);
    jest.spyOn(fs, 'readFileSync').mockReturnValue(fixtureBytes);
  });

  afterEach(() => {
    jest.restoreAllMocks();
    process.argv = savedArgv;
    for (const [key, value] of savedEnvironment) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  function authorizeIsolated(): void {
    process.env.CORRECTION_AUTHORIZED = 'CUSTOMER15-CORRECTION-AUTHORIZED';
    process.env.DATABASE_PATH = path.join(path.dirname(LIVE_DB_PATH), 'isolated-authorization-fixture');
  }

  function targetSyntheticLiveFile(): void {
    authorizeIsolated();
    process.env.DATABASE_PATH = path.dirname(LIVE_DB_PATH);
  }

  it.each([undefined, 'incorrect'])('refuses authorization token %s before reading files', token => {
    if (token !== undefined) process.env.CORRECTION_AUTHORIZED = token;
    process.env.DATABASE_PATH = path.dirname(LIVE_DB_PATH);
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.existsSync).not.toHaveBeenCalledWith(LIVE_DB_PATH);
    expect(fs.readFileSync).not.toHaveBeenCalledWith(LIVE_DB_PATH);
  });

  it('requires an explicit database directory', () => {
    process.env.CORRECTION_AUTHORIZED = 'CUSTOMER15-CORRECTION-AUTHORIZED';
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.existsSync).not.toHaveBeenCalled();
  });

  it('refuses a missing target file', () => {
    authorizeIsolated();
    jest.mocked(fs.existsSync).mockReturnValue(false);
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('refuses the live target without a separate override', () => {
    targetSyntheticLiveFile();
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('requires a measured checksum even with the live override', () => {
    targetSyntheticLiveFile();
    process.env.CORRECTION_ALLOW_LIVE = '1';
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('refuses a checksum mismatch', () => {
    targetSyntheticLiveFile();
    process.env.CORRECTION_ALLOW_LIVE = '1';
    process.env.CORRECTION_LIVE_SHA256 = 'outdated';
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.readFileSync).toHaveBeenCalledWith(LIVE_DB_PATH);
  });

  it('requires --apply for an authorized isolated target', () => {
    authorizeIsolated();
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(2));
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('accepts an authorized isolated target only with --apply', () => {
    authorizeIsolated();
    process.argv.push('--apply');
    expect(assertCorrectionAuthorized('fixture')).toEqual({
      dbPath: path.join(process.env.DATABASE_PATH ?? '', 'erp.db'),
      isLive: false,
    });
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('checks the synthetic live checksum and apply flag independently', () => {
    targetSyntheticLiveFile();
    process.env.CORRECTION_ALLOW_LIVE = '1';
    process.env.CORRECTION_LIVE_SHA256 = crypto.createHash('sha256').update(fixtureBytes).digest('hex');
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(2));
    process.argv.push('--apply');
    expect(assertCorrectionAuthorized('fixture')).toEqual({ dbPath: LIVE_DB_PATH, isLive: true });
  });

  it.each(['directory-symlink', 'hardlink'])('refuses a %s alias of the live file without its override', alias => {
    authorizeIsolated();
    process.env.DATABASE_PATH = path.join(path.dirname(LIVE_DB_PATH), alias);
    process.argv.push('--apply');
    jest.mocked(fs.statSync).mockReturnValue(aliasMetadata);
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });

  it('requires checksum and apply independently for the same physical file under another path', () => {
    authorizeIsolated();
    jest.mocked(fs.statSync).mockReturnValue(aliasMetadata);
    process.env.CORRECTION_ALLOW_LIVE = '1';
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    process.env.CORRECTION_LIVE_SHA256 = 'outdated';
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(1));
    process.env.CORRECTION_LIVE_SHA256 = crypto.createHash('sha256').update(fixtureBytes).digest('hex');
    expect(() => assertCorrectionAuthorized('fixture')).toThrow(new RefusedExit(2));
    process.argv.push('--apply');
    const dbPath = path.join(process.env.DATABASE_PATH ?? '', 'erp.db');
    expect(assertCorrectionAuthorized('fixture')).toEqual({ dbPath, isLive: true });
    expect(fs.readFileSync).toHaveBeenCalledWith(dbPath);
  });

  it('accepts a different physical file without requiring the live override', () => {
    authorizeIsolated();
    process.argv.push('--apply');
    jest.mocked(fs.statSync).mockReturnValueOnce(aliasMetadata).mockReturnValueOnce(unrelatedMetadata);
    expect(assertCorrectionAuthorized('fixture')).toEqual({
      dbPath: path.join(process.env.DATABASE_PATH ?? '', 'erp.db'), isLive: false,
    });
    expect(fs.readFileSync).not.toHaveBeenCalled();
  });
});

describe('correction entrypoint startup', () => {
  afterEach(() => {
    jest.dontMock('../../scripts/lib/correctionSafety');
    jest.dontMock('../config/database');
  });

  it.each(['apply-customer15-correction', 'rollback-customer15-correction'])(
    '%s authorizes before importing the database', script => {
      const refusal = new Error('authorization refused');
      const authorize = jest.fn<typeof assertCorrectionAuthorized>(() => { throw refusal; });
      const loadDatabase = jest.fn(() => { throw new Error('database imported before authorization'); });
      jest.isolateModules(() => {
        jest.doMock('../../scripts/lib/correctionSafety', () => ({ assertCorrectionAuthorized: authorize }));
        jest.doMock('../config/database', loadDatabase);
        expect(() => jest.requireActual<unknown>(`../../scripts/${script}`)).toThrow(refusal);
      });
      expect(authorize).toHaveBeenCalledWith(script);
      expect(loadDatabase).not.toHaveBeenCalled();
    },
  );
});
