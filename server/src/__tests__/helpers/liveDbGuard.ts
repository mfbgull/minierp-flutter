import fs from 'fs';
import path from 'path';
import type Database from 'better-sqlite3';

export class LiveDatabaseWriteError extends Error {
  constructor() {
    super('refused to open the canonical live database for writing');
    this.name = 'LiveDatabaseWriteError';
  }
}

export function resolveLiveDbPath(): string {
  return path.resolve(__dirname, '../../../database/erp.db');
}

function physicalPath(filename: string): string {
  const absolute = path.resolve(filename);
  const info = fs.lstatSync(absolute, { throwIfNoEntry: false });
  if (info?.isSymbolicLink()) {
    return physicalPath(path.resolve(path.dirname(absolute), fs.readlinkSync(absolute)));
  }
  if (info) return fs.realpathSync(absolute);
  return path.join(physicalPath(path.dirname(absolute)), path.basename(absolute));
}

export function protectDatabaseConstructor(
  Constructor: typeof Database,
  canonicalPath = resolveLiveDbPath(),
): typeof Database {
  return new Proxy(Constructor, {
    construct(target, args, newTarget) {
      const filename: unknown = args[0];
      const options: unknown = args[1];
      const readonly = typeof options === 'object' && options !== null
        && 'readonly' in options && options.readonly === true;
      if (typeof filename === 'string' && filename !== ':memory:' && !readonly) {
        const canonical = physicalPath(canonicalPath);
        const candidate = physicalPath(filename);
        const candidateInfo = fs.statSync(candidate, { throwIfNoEntry: false });
        const canonicalInfo = fs.statSync(canonical, { throwIfNoEntry: false });
        const sameFile = candidateInfo && canonicalInfo
          && candidateInfo.dev === canonicalInfo.dev && candidateInfo.ino === canonicalInfo.ino;
        if (candidate === canonical || sameFile) throw new LiveDatabaseWriteError();
      }
      return Reflect.construct(target, args, newTarget);
    },
  });
}
