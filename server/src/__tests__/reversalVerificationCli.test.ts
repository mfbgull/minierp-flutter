import { spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';

test('reversal verification CLI executes all 79 assertions before exiting successfully', () => {
  const serverRoot = path.resolve(__dirname, '../..');
  const temporaryRoot = fs.mkdtempSync(path.join(serverRoot, '.tmp-test/reversal-cli-'));
  try {
    const result = spawnSync('npm', ['run', 'verify:reversal-rules'], {
      cwd: serverRoot,
      env: { ...process.env, TMPDIR: temporaryRoot, TS_NODE_PROJECT: 'tsconfig.test.json' },
      encoding: 'utf8',
      timeout: 120_000,
      maxBuffer: 4 * 1024 * 1024,
    });
    expect({ error: result.error?.message, status: result.status, stderr: result.stderr })
      .toEqual({ error: undefined, status: 0, stderr: '' });
    const passingAssertions = result.stdout.split('\n').filter(line => /^\s+PASS\s+/.test(line));
    expect({ count: passingAssertions.length, output: result.stdout })
      .toEqual({ count: 79, output: expect.stringContaining('Result: 79 passed, 0 failed') });
    expect(result.stdout).not.toMatch(/^\s+FAIL\s+/m);
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}, 130_000);
