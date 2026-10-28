import { spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { isProcessAlive } from '../utils/parentWatchdog';

describe('runtime path overrides for installed packages', () => {
  it('creates employee upload directories under UPLOADS_DIR', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-uploads-'));
    const previous = process.env.UPLOADS_DIR;
    process.env.UPLOADS_DIR = tmp;

    try {
      let docsDir = '';
      jest.isolateModules(() => {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const upload = require('../middleware/upload') as { employeeDocsDir: string };
        docsDir = upload.employeeDocsDir;
      });

      expect(docsDir).toBe(path.join(tmp, 'employees'));
      expect(fs.existsSync(docsDir)).toBe(true);
    } finally {
      if (previous === undefined) delete process.env.UPLOADS_DIR;
      else process.env.UPLOADS_DIR = previous;
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe('parent watchdog', () => {
  it('reports the current process as alive', () => {
    expect(isProcessAlive(process.pid)).toBe(true);
  });

  it('reports an exited process as not alive', () => {
    const child = spawnSync(process.execPath, ['-e', 'process.exit(0)']);
    expect(child.pid).toBeGreaterThan(0);
    expect(isProcessAlive(child.pid as number)).toBe(false);
  });
});
