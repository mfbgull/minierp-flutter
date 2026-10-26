import { afterAll, describe, expect, it } from '@jest/globals';
import { spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { z } from 'zod';
import { mergeFallowCoverage } from '../../scripts/lib/merge-fallow-coverage.cjs';

const root = path.resolve(__dirname, '../../..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'minierp-coverage-merge-'));
afterAll(() => fs.rmSync(temporary, { recursive: true, force: true }));

const coverageSchema = z.record(z.string(), z.object({
  fnMap: z.record(z.string(), z.object({ name: z.string() })),
  f: z.record(z.string(), z.number()),
  s: z.record(z.string(), z.number()),
}));

describe('CLI coverage integration', () => {
  it('merges actual CLI execution and retains existing Istanbul hits', async () => {
    const raw = path.join(temporary, 'v8');
    const base = path.join(temporary, 'istanbul.json');
    const output = path.join(temporary, 'merged.json');
    const existing = path.join(temporary, 'already-covered.js');
    fs.writeFileSync(base, JSON.stringify({
      [existing]: {
        path: existing,
        statementMap: { 0: { start: { line: 1, column: 0 }, end: { line: 1, column: 1 } } },
        s: { 0: 7 }, fnMap: {}, f: {}, branchMap: {}, b: {},
      },
    }));
    const cli = path.join(root, 'scripts/openspec-archive-guard.js');
    const child = spawnSync(process.execPath, [cli], {
      cwd: root,
      env: { ...process.env, NODE_V8_COVERAGE: raw },
      encoding: 'utf8',
      timeout: 10000,
    });
    expect(child.error).toBeUndefined();
    expect(child.status).toBe(2);
    const summary = await mergeFallowCoverage(base, [raw], output);
    expect(summary.converted).toContain(cli);
    const merged = coverageSchema.parse(JSON.parse(fs.readFileSync(output, 'utf8')));
    expect(merged[existing].s['0']).toBe(7);
    const main = Object.entries(merged[cli].fnMap).find(([, fn]) => fn.name === 'main');
    expect(main).toBeDefined();
    if (!main) throw new Error('CLI main missing from converted coverage');
    expect(merged[cli].f[main[0]]).toBeGreaterThan(0);

    const repeatedOutput = path.join(temporary, 'retained-mappings.json');
    await mergeFallowCoverage(output, [raw], repeatedOutput);
    const repeated = coverageSchema.parse(JSON.parse(fs.readFileSync(repeatedOutput, 'utf8')));
    expect(repeated).toEqual(merged);

    for (const filename of fs.readdirSync(raw)) {
      fs.utimesSync(path.join(raw, filename), new Date(0), new Date(0));
    }
    const staleOutput = path.join(temporary, 'stale.json');
    const stale = await mergeFallowCoverage(base, [raw], staleOutput);
    expect(stale.stale).toContain(cli);
    const retained = coverageSchema.parse(JSON.parse(fs.readFileSync(staleOutput, 'utf8')));
    expect(Object.keys(retained)).toEqual([existing]);
    expect(retained[existing].s['0']).toBe(7);
  });
});
