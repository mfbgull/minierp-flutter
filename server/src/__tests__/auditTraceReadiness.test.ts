import fs from 'fs';
import path from 'path';

it('never deletes a pre-existing directory and uses the canonical database bootstrap', () => {
  const originalPath = process.env.DATABASE_PATH;
  const remove = jest.spyOn(fs, 'rmSync').mockImplementation(() => undefined);
  jest.spyOn(fs, 'existsSync').mockReturnValue(true);
  jest.spyOn(fs, 'mkdirSync').mockReturnValue(undefined);
  jest.spyOn(fs, 'mkdtempSync').mockReturnValue('/owned/audit-trace-unique');
  jest.doMock('better-sqlite3', () => jest.fn(() => { throw new Error('direct database open'); }));
  jest.doMock('../config/database', () => { throw new Error('canonical bootstrap reached'); });
  jest.spyOn(console, 'log').mockImplementation(() => undefined);
  try {
    expect(() => jest.isolateModules(() => jest.requireActual('../../scripts/dev/audit-trace')))
      .toThrow('canonical bootstrap reached');
    expect(remove).not.toHaveBeenCalled();
    expect(process.env.DATABASE_PATH).toBe('/owned/audit-trace-unique');
    expect(path.basename(process.env.DATABASE_PATH ?? '')).not.toBe('audit-db');
  } finally {
    process.env.DATABASE_PATH = originalPath;
    jest.restoreAllMocks();
    jest.dontMock('better-sqlite3');
    jest.dontMock('../config/database');
  }
});
